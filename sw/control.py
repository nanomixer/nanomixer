import numpy as np
import random
from biquads import normalize, peaking
import wireformat
from dsp_program import (
    HARDWARE_PARAMS, parameter_base_addr_for_biquad, address_for_mixdown_gain,
    constants, meter_filter_param_base, StateVarFilter)
import logging

logger = logging.getLogger(__name__)

METERING_LPF_PARAMS = dict(
    Fc=10.,
    Q=np.sqrt(2.)/2.,
    Fs=48000)

# Number formats
PARAM_WIDTH = 36
PARAM_INT_BITS = 5
PARAM_FRAC_BITS = 30
METER_WIDTH = 24
METER_WIDTH_NIBBLES = METER_WIDTH / 4
METER_FRAC_BITS = 20
METER_SIGN_BIT = 23
WORDS_PER_CORE = 1024 # FIXME !

METERING_CHANNELS = 8
METERING_PACKET_SIZE = METERING_CHANNELS

# Channel name -> (core, channel)
channel_map = {
    0: (0, 0),
    1: (0, 1),
    2: (0, 2),
    3: (0, 3),
    4: (0, 4),
    5: (0, 5),
    6: (0, 6),
    7: (0, 7),
}

bus_map = {
    0: (0, 0),
    1: (0, 1)
}

def pack_biquad_coeffs(b, a):
    return [b[0], b[1], b[2], -a[1], -a[2]]

class MixerState(object):
    def __init__(self, num_cores, num_busses_per_core,
                 num_channels_per_core, num_biquads_per_channel):
        self.num_cores = num_cores
        self.num_busses_per_core = num_busses_per_core
        self.num_channels_per_core = num_channels_per_core
        self.num_biquads_per_channel = num_biquads_per_channel

        # Biquad parameters
        self.biquad_freq = np.zeros((num_cores, num_channels_per_core, num_biquads_per_channel)) + 1000.
        self.biquad_gain = np.zeros((num_cores, num_channels_per_core, num_biquads_per_channel))
        self.biquad_q = np.zeros((num_cores, num_channels_per_core, num_biquads_per_channel)) + 1.

        # Mixdown parameters
        # (bus_core, bus, channel_core, channel)
        # channels are always named by the core they come in on.
        # busses are named by the core where they end up.
        self.mixdown_gains = np.zeros((num_cores, num_busses_per_core, num_cores, num_channels_per_core))

    def get_biquad_coefficients(self, core, channel, biquad):
        b, a = peaking(f0=self.biquad_freq[core, channel, biquad],
                       dBgain=self.biquad_gain[core, channel, biquad],
                       q=self.biquad_q[core, channel, biquad])
        b, a = normalize(b, a)
        return b, a


class Controller(object):
    def __init__(self, io_thread):
        self.state = MixerState(**HARDWARE_PARAMS)
        self.io_thread = io_thread

    def handle_message(self, message, args):
        logger.info('handle_message(%r, %r)', message, args)
        getattr(self, message)(**args)

    def set_biquad(self, channel, biquad, freq, gain, q):
        core, ch = channel_map[channel]
        self.state.biquad_freq[core, ch, biquad] = freq
        self.state.biquad_gain[core, ch, biquad] = gain
        self.state.biquad_q[core, ch, biquad] = q
        self._update_biquad(core, ch, biquad)

    def set_gain(self, bus, channel, gain):
        bus_core, bus_idx = bus_map[bus]
        channel_core, channel_idx = channel_map[channel]
        self.state.mixdown_gains[bus_core, bus_idx, channel_core, channel_idx] = gain
        self._update_gain(bus_core, bus_idx, channel_core, channel_idx)

    def _update_gain(self, bus_core, bus_idx, channel_core, channel_idx):
        gain = self.state.mixdown_gains[bus_core, bus_idx, channel_core, channel_idx]
        self._set_parameter_memory(
            core=channel_core,
            addr=address_for_mixdown_gain(
                core=(channel_core - bus_core - 1) % self.state.num_cores,
                channel=channel_idx,
                bus=bus_idx),
            data=[gain])

    def _update_biquad(self, core, channel, biquad):
        b, a = self.state.get_biquad_coefficients(core, channel, biquad)
        self._set_parameter_memory(
            core=core,
            addr=parameter_base_addr_for_biquad(channel=channel, biquad=biquad),
            data=pack_biquad_coeffs(b, a))

    def dump_state_to_mixer(self):
        for core in xrange(HARDWARE_PARAMS['num_cores']):
            # Set constants.
            self._set_parameter_memory(
                core=core,
                addr=constants.base,
                data=constants.constants)

            # Update all biquads
            for channel in xrange(HARDWARE_PARAMS['num_channels_per_core']):
                for biquad in xrange(HARDWARE_PARAMS['num_biquads_per_channel']):
                    self._update_biquad(core, channel, biquad)

            # Special metering filter.
            self._set_parameter_memory(core=core, addr=meter_filter_param_base,
                data=self.get_metering_filter_params())

            # Update all gains.
            for bus_core in xrange(HARDWARE_PARAMS['num_cores']):
                for bus_idx in xrange(HARDWARE_PARAMS['num_busses_per_core']):
                    for channel_idx in xrange(HARDWARE_PARAMS['num_channels_per_core']):
                        self._update_gain(bus_core, bus_idx, core, channel_idx)

    def get_metering_filter_params(self):
        return StateVarFilter.encode_params(**METERING_LPF_PARAMS)

    def _set_parameter_memory(self, core, addr, data):
        start = core * WORDS_PER_CORE + int(addr)
        self.io_thread[start:start+len(data)] = data


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
            meter_vals_read = read_buf[:meter_words_desired].view(np.int64)
            wireformat.sign_extend(meter_vals_read, METER_SIGN_BIT)
            wireformat.fixeds_to_floats(
                meter_vals_read,
                METER_FRAC_BITS,
                meter_packet[first_meter_index_needed:first_meter_index_needed+len(meter_vals_read)])
            # TODO: wraparound, since the meter data at the beginning of the packet is going to be newer.
            first_meter_index_needed += words_in_transfer
            break # FIXME.

        self._meter_revision += 1

        np.maximum(2**-METER_FRAC_BITS, meter_packet, out=meter_packet)
        meter_values = 20 * np.log10(np.sqrt(meter_packet * 2**8))
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



def pack_meter_packet(rev, meter_data):
    return dict(
        channels=meter_data[:METERING_CHANNELS].tolist(),
        rev=rev)


import os
SPI_DEVICE = '/dev/spidev4.0'
ON_TGT_HARDWARE = os.path.exists(SPI_DEVICE)
if ON_TGT_HARDWARE:
    import spidev
    spi_dev = spidev.SpiChannel(SPI_DEVICE, bits_per_word=20)
    spi_channel = SPIChannel(spi_dev, buf_size_in_words=64)
else:
    class DummySPIChannel(object):
        buf_size_in_words = 64

    spi_channel = DummySPIChannel()
io_thread = IOThread(param_mem_size=1024, spi_channel=spi_channel)

if ON_TGT_HARDWARE:
    io_thread.start()
else:
    print "Not on target hardware, not starting IO thread."

controller = Controller(io_thread)
controller.dump_state_to_mixer()
