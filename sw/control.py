import numpy as np
import random
from biquads import normalize, filter_types
import wireformat
from dsp_program import (
    HARDWARE_PARAMS,
    mixer,
    constants, meter_filter_param_base, StateVarFilter)
import logging
import time
import json
from datetime import datetime

logger = logging.getLogger(__name__)

METERING_LPF_PARAMS = dict(
    Fc=7.5,
    Q=np.sqrt(2.)/2.,
    Fs=48000)

# Number formats
PARAM_WIDTH = 36
PARAM_INT_BITS = 5
PARAM_FRAC_BITS = 30
METER_WIDTH = 36
METER_FRAC_BITS = 30
METER_SIGN_BIT = 35
WORDS_PER_CORE = 1024 # FIXME !
MIN_FADER = -180.

def pack_biquad_coeffs(b, a):
    return [b[0], b[1], b[2], -a[1], -a[2]]

# Panning
PAN_LAW_DB = 3.
panning_exponent = PAN_LAW_DB / (20*np.log10(2.))


# Just using a class so that state_names.bus works.
class state_names(object):
    bus = 'b{bus}/{param}'
    channel = 'c{channel}/{param}'
    fader = 'b{bus}/c{channel}/{param}'
    channel_filter = 'c{channel}/f{filt}/{param}'
    bus_filter = 'b{bus}/f{filt}/{param}'


logical_bus_to_physical_bus_mapping = [
    [0, 1],
    [2],
    [3],
    [4],
    [5],
    [6],
    [7],
]


metadata = dict(
    num_busses=len(logical_bus_to_physical_bus_mapping),
    num_channels=HARDWARE_PARAMS['num_cores'] * HARDWARE_PARAMS['num_channels_per_core'],
    num_biquads_per_channel=HARDWARE_PARAMS['num_biquads_per_channel'],
    num_biquads_per_bus=HARDWARE_PARAMS['num_biquads_per_bus'])

METERING_CHANNELS = HARDWARE_PARAMS['num_channels_per_core'] + HARDWARE_PARAMS['num_busses_per_core']
METERING_PACKET_SIZE = METERING_CHANNELS
SPI_BUF_SIZE_IN_WORDS = METERING_PACKET_SIZE

initial_filter_frequencies = [250, 500, 1000, 6000, 12000]


class InvalidSnapshot(Exception):
    pass



def get_initial_state(metadata):
    state = {}

    def set_state_params(name_format, base_kv, **kw):
        for k, v in kw.iteritems():
            name = name_format.format(param=k, **base_kv)
            state[name] = v

    for bus in range(metadata['num_busses']):
        if bus == 0:
            name = "Master"
        else:
            name = "Aux {}".format(bus)
        # Masters
        set_state_params(state_names.bus, dict(bus=bus), name=name, lvl=0., pan=0.)

        # Downmix
        for channel in range(metadata['num_channels']):
            set_state_params(state_names.fader, dict(bus=bus, channel=channel), lvl=MIN_FADER, pan=0.)

        # Bus filters
        for filt, freq in enumerate(initial_filter_frequencies):
            assert metadata['num_biquads_per_bus'] == len(initial_filter_frequencies)
            if filt == 0:
                typ = 'lowshelf'
            elif filt == len(initial_filter_frequencies) - 1:
                typ = 'highshelf'
            else:
                typ = 'peaking'
            set_state_params(state_names.bus_filter, dict(bus=bus, filt=filt),
                type=typ, freq=freq, gain=0., q=np.sqrt(2.)/2)


    for channel in range(metadata['num_channels']):
        assert metadata['num_biquads_per_channel'] == len(initial_filter_frequencies)
        set_state_params(state_names.channel, dict(channel=channel), name="Ch{}".format(channel+1))

        for filt, freq in enumerate(initial_filter_frequencies):
            if filt == 0:
                typ = 'lowshelf'
            elif filt == len(initial_filter_frequencies) - 1:
                typ = 'highshelf'
            else:
                typ = 'peaking'
            set_state_params(state_names.channel_filter, dict(channel=channel, filt=filt),
                type=typ, freq=freq, gain=0., q=np.sqrt(2.)/2)

    state['metadata'] = metadata

    return state



def logical_to_physical(state, mixer, set_memory):

    def get_state_param(name_format, base_kv, param):
        assert isinstance(param, basestring)
        return state[name_format.format(param=param, **base_kv)]

    def get_state_params(name_format, base_kv, params):
        assert not isinstance(params, basestring)
        return [get_state_param(name_format, base_kv, param) for param in params]

    # Channel filters
    for channel, biquad_chain in enumerate(mixer.channel_biquads):
        for biquad_idx, biquad_params in enumerate(biquad_chain.params):
            typ, freq, gain, q = get_state_params(state_names.channel_filter, dict(channel=channel, filt=biquad_idx), ['type', 'freq', 'gain', 'q'])

            b, a = filter_types[typ](f0=freq, dBgain=gain, q=q)
            b, a = normalize(b, a)

            set_memory(
                core=0,  # hardcoded, until we can test multi-core and get the right abstraction.
                addr=biquad_params[0].addr,
                data=pack_biquad_coeffs(b, a))

    # Bus filters
    for bus, bus_strip in enumerate(mixer.bus_strips):
        for biquad_idx, biquad_params in enumerate(bus_strip.biquad_chain.params):
            typ, freq, gain, q = get_state_params(state_names.channel_filter, dict(bus=bus, filt=biquad_idx), ['type', 'freq', 'gain', 'q'])

            b, a = filter_types[typ](f0=freq, dBgain=gain, q=q)
            b, a = normalize(b, a)

            set_memory(
                core=0,  # hardcoded, until we can test multi-core and get the right abstraction.
                addr=biquad_params[0].addr,
                data=pack_biquad_coeffs(b, a))

    # Downmix buses
    num_downmix_channels = len(mixer.downmixes[0].gain)
    gain_for_physical_bus = np.zeros((len(mixer.downmixes), num_downmix_channels))

    for logical_bus, physical_buses in enumerate(logical_bus_to_physical_bus_mapping):
        for channel in xrange(gain_for_physical_bus):
            level = get_state_param(state_names.fader, dict(bus=logical_bus, channel=channel), 'lvl')
            bus_output_level = get_state_param(state_names.bus, dict(bus=logical_bus), 'lvl')
            absBusFaderLevel = 10. ** (bus_output_level / 20.)
            absLevel = 10. ** (level/20.) * absBusFaderLevel
            if len(physical_buses) == 1:
                # Mono.
                gain_for_physical_bus[physical_buses[0], channel] = absLevel
            else:
                # Stereo.
                pan = get_state_param(state_names.fader, dict(bus=logical_bus, channel=channel), 'pan')
                left, right = physical_buses
                gain_for_physical_bus[left , channel] = absLevel * (.5 - pan) ** panning_exponent
                gain_for_physical_bus[right, channel] = absLevel * (.5 + pan) ** panning_exponent

    for bus, downmix in enumerate(mixer.downmixes):
        for channel, gain_addr in enumerate(downmix.gain):
            set_memory(
                core=0,  # hardcoded, until we can test multi-core and get the right abstraction.
                addr=gain_addr,
                data=[gain_for_physical_bus[bus][channel]])



class Controller(object):
    def __init__(self, io_thread, snapshot_base_dir='snapshots'):
        self.io_thread = io_thread

        self.snapshot_base_dir = snapshot_base_dir
        if not os.path.exists(self.snapshot_base_dir):
            os.makedirs(self.snapshot_base_dir)

        self.state = get_initial_state(metadata)

        try:
            self.load_snapshot()
            print 'Snapshot loaded.'
        except IOError:
            print 'No snapshot found.'
        except InvalidSnapshot:
            print "Not loading an initial snapshot because it's invalid."

    def load_snapshot(self, name='latest'):
        with open(os.path.join(self.snapshot_base_dir, name), 'rb') as f:
            state = json.load(f)
            if state['metadata'] != self.state['metadata']:
                raise InvalidSnapshot
            self.state.update(state)
        # You probably want to dump_state_to_mixer now.

    def save_snapshot(self):
        now = datetime.now().isoformat()
        filename = os.path.join(self.snapshot_base_dir, now)
        with open(filename, 'wb') as f:
            json.dump(self.state, f)
        new_symlink_name = os.path.join(self.snapshot_base_dir, 'latest-next')
        latest_symlink_name = os.path.join(self.snapshot_base_dir, 'latest')
        if os.path.exists(new_symlink_name):
            os.unlink(new_symlink_name)
        os.symlink(now, new_symlink_name)
        os.rename(new_symlink_name, latest_symlink_name)

    def apply_update(self, control, value):
        """
        Apply a state update.

        Returns True iff the update was handled successfully.
        """
        if control not in self.state:
            return False
        self.state[control] = value
        logical_to_physical(self.state, mixer, self._set_parameter_memory)
        return True

    def get_meter(self):
        raw = self.io_thread.get_meter()[1]
        return dict(
            c=raw[:metadata['num_channels']].tolist(),
            b=raw[metadata['num_channels']:].tolist())

    def dump_state_to_mixer(self):
        for core in xrange(HARDWARE_PARAMS['num_cores']):
            # Set constants.
            self._set_parameter_memory(
                core=core,
                addr=constants.base,
                data=constants.constants)

            # Special metering filter.
            self._set_parameter_memory(core=core, addr=meter_filter_param_base,
                data=self.get_metering_filter_params())

        for control, value in self.state.iteritems():
            if control == 'metadata':
                continue
            handled = self.apply_update(control, value)
            if not handled:
                raise NameError("Unhandled name: {}".format(control))

    def get_metering_filter_params(self):
        return StateVarFilter.encode_params(**METERING_LPF_PARAMS)

    def _set_parameter_memory(self, core, addr, data):
        start = core * WORDS_PER_CORE + int(addr)
        self.io_thread[start:start+len(data)] = data


class DummyController(Controller):
    def __init__(self, *a, **kw):
        super(DummyController, self).__init__(*a, **kw)
        self.meter_levels = np.zeros(metadata['num_channels'])

    def get_meter(self):
        offsets = np.array([np.sin(2*np.pi*(time.time() + chan / 4.)) for chan in xrange(metadata['num_channels'])])
        return dict(
            c=(self.meter_levels + offsets).tolist(),
            b=[np.logaddexp.reduce(self.meter_levels).tolist()]*HARDWARE_PARAMS['num_busses_per_core'])

    def set_gain(self, bus, channel, gain):
        super(DummyController, self).set_gain(bus, channel, gain)
        self.meter_levels[channel] = 20 * np.log10(gain)


import threading
import collections
from spi_channel import SPIChannel
class IOThread(threading.Thread):
    def __init__(self, param_mem_size, spi_channel):
        threading.Thread.__init__(self, name='IOThread')
        self.daemon = True
        self._shutdown = False
        self.spi_channel = spi_channel
        self.spi_words = spi_channel.buf_size_in_words
        self._param_mem_contents = np.zeros(param_mem_size, dtype=np.float64)
        self._param_mem_dirty = np.zeros(param_mem_size, dtype=np.uint8)
        self._meter_revision = -1
        self._meter_mem_contents = (
            self._meter_revision, np.zeros(METERING_PACKET_SIZE, dtype=np.float64))
        self._write_queue = collections.deque()

        # Buffers in terms of words.
        self._write_buf = np.empty(self.spi_words, dtype=np.uint64)
        self._read_buf = np.empty(self.spi_words, dtype=np.uint64)

    def __setitem__(self, addr, data):
        # TODO: de-dupe / only keep the latest thing to write, and don't write things that are the same as what's already there.
        self._write_queue.append((addr, data))

    def get_meter(self):
        return self._meter_mem_contents

    def shutdown(self):
        self._shutdown = True

    def handle_queued_memory_mods(self):
        while True:
            try:
                item = self._write_queue.popleft()
            except IndexError:
                break
            addr, data = item
            self._param_mem_contents[addr] = data
            self._param_mem_dirty[addr] = 1

    def dump_to_mif(self, outfile):
        self.handle_queued_memory_mods()
        write_buf = np.empty(len(self._param_mem_contents), dtype=np.uint64)
        wireformat.floats_to_fixeds(self._param_mem_contents, PARAM_INT_BITS, PARAM_FRAC_BITS, write_buf.view(np.int64))
        print >>outfile, "DEPTH = {};".format(len(write_buf))
        print >>outfile, "WIDTH = {};".format(36)
        print >>outfile, "ADDRESS_RADIX = HEX;"
        print >>outfile, "DATA_RADIX = HEX;"
        print >>outfile, "CONTENT BEGIN"
        for addr, val in enumerate(write_buf):
            fmt_val = '{:09x}'.format(val)
            # But if it was negative, it's too wide.
            fmt_val = fmt_val[-9:]
            print >>outfile, '{:02x} : {};'.format(addr, fmt_val)
        print >>outfile, "END;"


    def do_send_recvs(self):
        meter_packet = np.zeros(METERING_PACKET_SIZE, dtype=np.float64)
        first_meter_index_needed = 0
        while True:
            dirty = self._param_mem_dirty.nonzero()[0]
            meter_words_desired = METERING_PACKET_SIZE - first_meter_index_needed
            if len(dirty) == 0:
                if meter_words_desired <= 0:
                    # All sending and receiving this time is complete.
                    break
                # Otherwise, pick a random address to start from
                first_param_send_index = random.randrange(max(0, len(self._param_mem_contents) - self.spi_words))
            else:
                first_param_send_index = dirty[0]
            param_data_to_send = self._param_mem_contents[first_param_send_index:]
            if len(param_data_to_send) > self.spi_words:
                param_data_to_send = param_data_to_send[:self.spi_words]
            words_in_transfer = len(param_data_to_send)

            read_buf = self._read_buf[:words_in_transfer]

            # Unpack floats into fixed point in the write buffer.
            write_buf = self._write_buf[:words_in_transfer]
            wireformat.floats_to_fixeds(param_data_to_send, PARAM_INT_BITS, PARAM_FRAC_BITS, write_buf.view(np.int64))

            #print '{} @ rd: {} wr: {}'.format(words_in_transfer, first_meter_index_needed, first_param_send_index)
            self.spi_channel.transfer(
                read_addr=first_meter_index_needed,
                read_data=read_buf,
                write_addr=first_param_send_index,
                write_data=write_buf)

            # Mark param memory segment not dirty.
            self._param_mem_dirty[first_param_send_index:first_param_send_index+words_in_transfer] = 0

            # Extract the metering data we got.
            meter_vals_read = read_buf[:meter_words_desired]
            wireformat.sign_extend(meter_vals_read, METER_SIGN_BIT)
            wireformat.fixeds_to_floats(
                meter_vals_read.view(np.int64),
                METER_FRAC_BITS,
                meter_packet[first_meter_index_needed:first_meter_index_needed+len(meter_vals_read)])
            # TODO: wraparound, since the meter data at the beginning of the packet is going to be newer.
            first_meter_index_needed += words_in_transfer
            break # FIXME.

        self._meter_revision += 1

        np.maximum(2**-METER_FRAC_BITS, meter_packet, out=meter_packet)
        # meter packet contains LPF of square of signal value right-shifted by 2 bits.
        # So: correct for the shift, correct for the crest factor, sqrt, and convert to dB.
        meter_values = 20 * np.log10(np.sqrt(meter_packet * 2**2 * 2))
        self._meter_mem_contents = (self._meter_revision, meter_values)


    def run(self):
        logger.info('IO thread started')
        while True:
            if self._shutdown:
                return

            # Handle queued memory modifications
            self.handle_queued_memory_mods()

            # Do SPI send-recv's
            self.do_send_recvs()



class DummySPIChannel(object):
    buf_size_in_words = SPI_BUF_SIZE_IN_WORDS


import os
SPI_DEVICE = '/dev/spidev4.0'
ON_TGT_HARDWARE = os.path.exists(SPI_DEVICE)
if ON_TGT_HARDWARE:
    import spidev
    spi_dev = spidev.SpiChannel(SPI_DEVICE, bits_per_word=20)
    spi_channel = SPIChannel(spi_dev, buf_size_in_words=SPI_BUF_SIZE_IN_WORDS)
    controller_class = Controller
else:
    spi_channel = DummySPIChannel()
    controller_class = DummyController

io_thread = IOThread(param_mem_size=1024, spi_channel=spi_channel)
controller = controller_class(io_thread)
controller.dump_state_to_mixer()

if ON_TGT_HARDWARE:
    io_thread.start()
else:
    print "Not on target hardware, not starting IO thread."
