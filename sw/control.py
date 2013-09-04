import numpy as np
from biquads import normalize, peaking, lowpass
from util import fixeds_to_spi, spi_to_fixeds, fixeds_to_floats, floats_to_fixeds
from dsp_program import (
    HARDWARE_PARAMS, parameter_base_addr_for_biquad, address_for_mixdown_gain,
    constants_base, constants, meter_biquad_param_base)
import logging

logger = logging.getLogger(__name__)

METERING_LPF_PARAMS = dict(
    f0=10.,
    q=np.sqrt(2.)/2.)

# Number formats
PARAM_WIDTH = 36
PARAM_FRAC_BITS = 30
METER_WIDTH = 24
METER_WIDTH_NIBBLES = METER_WIDTH / 4
METER_FRAC_BITS = 20
WORDS_PER_CORE = 1024 # FIXME !

# I don't think these are used.
METERING_CHANNELS = 8
METERING_PACKET_SIZE = METERING_CHANNELS * METER_WIDTH_NIBBLES

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

    def set_biquad_freq(self, channel, biquad, freq):
        core, ch = channel_map[channel]
        self.state.biquad_freq[core, ch, biquad] = freq
        self._update_biquad(core, ch, biquad)

    def set_biquad_gain(self, channel, biquad, gain):
        core, ch = channel_map[channel]
        self.state.biquad_gain[core, ch, biquad] = gain
        self._update_biquad(core, ch, biquad)

    def set_biquad_q(self, channel, biquad, q):
        core, channel_idx = channel_map[channel]
        self.state.biquad_q[core, channel_idx, biquad] = q
        self._update_biquad(core, channel_idx, biquad)

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
                addr=constants_base,
                data=constants)

            # Update all biquads
            for channel in xrange(HARDWARE_PARAMS['num_channels_per_core']):
                for biquad in xrange(HARDWARE_PARAMS['num_biquads_per_channel']):
                    self._update_biquad(core, channel, biquad)

            # Special metering biquad.
            self._set_parameter_memory(core=core, addr=meter_biquad_param_base,
                data=pack_biquad_coeffs(*self.get_metering_biquad_coef()))
            # Update all gains.
            for bus_core in xrange(HARDWARE_PARAMS['num_cores']):
                for bus_idx in xrange(HARDWARE_PARAMS['num_busses_per_core']):
                    for channel_idx in xrange(HARDWARE_PARAMS['num_channels_per_core']):
                        self._update_gain(bus_core, bus_idx, core, channel_idx)

    def get_metering_biquad_coef(self):
        return normalize(*lowpass(**METERING_LPF_PARAMS))

    def _set_parameter_memory(self, core, addr, data):
        self.io_thread.memories[core * WORDS_PER_CORE + addr] = data


import threading
import collections
import spidev
class IOThread(threading.Thread):
    def __init__(self, param_mem_size, spi_device):
        threading.Thread.__init__(self, name='IOThread')
        self._param_mem_contents = np.zeros(param_mem_size, np.float64)
        self._write_queue = collections.deque()
        self._spi = spidev.SpiChannel(spi_device, bits_per_word=20)

    def __setitem__(self, addr, data):
        self._write_queue.append((addr, data))

    def get_meter(self):
        return self._meter_mem_contents

    def run(self):
        logger.info('IO thread started')
        while True:
            # Handle queued memory modifications
            while True:
                try:
                    item = self._write_queue.popleft()
                except IndexError:
                    continue
                else:
                    addr, data = item
                    self._param_mem_contents[addr] = data

            # Do an SPI send-recv.
            data = fixeds_to_spi(floats_to_fixeds(self._param_mem_contents, PARAM_FRAC_BITS))
            meter = self._spi.transfer(data)
            self._meter_revision += 1

            self._meter_mem_contents = (
                self._meter_revision, fixeds_to_floats(spi_to_fixeds(meter), METER_FRAC_BITS))

            # self.meter_values = 20 * np.log10(np.sqrt(decoded * 2**8))

iothread = IOThread(param_mem_size=2048)
iothread.start()
controller = Controller(iothread)
