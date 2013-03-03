import numpy as np
from biquads import normalize, peaking
from util import encode_signed_fixedpt_as_hex
from assembler import HARDWARE_PARAMS, parameter_base_addr_for_biquad, address_for_mixdown_gain
import logging

logger = logging.getLogger(__name__)

MEMIF_SERVER_PORT = 2540

PARAM_WIDTH = 36
PARAM_FRAC_BITS = 30

core_param_mem_name = ['PM00', 'PM01']

# Channel name -> (core, channel)
channel_map = {
    '1': (0, 0),
    '2': (0, 1),
    '3': (0, 2),
    '4': (0, 3),
    '5': (0, 4),
    '6': (0, 5),
    '7': (0, 6),
    '8': (0, 7),
}

bus_map = {
    'L': (0, 0),
    'R': (0, 1)
}


def to_param_word_as_hex(x):
    return encode_signed_fixedpt_as_hex(
        x, width=PARAM_WIDTH, fracbits=PARAM_FRAC_BITS)


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
    def __init__(self, memory_interface):
        self.state = MixerState(**HARDWARE_PARAMS)
        self.memory_interface = memory_interface

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
        self._set_parameter_memory(
            core=channel_core,
            addr=address_for_mixdown_gain(
                core=(channel_core - bus_core - 1) % self.state.num_cores,
                channel=channel_idx,
                bus=bus_idx),
            data=[gain])

    def _update_biquad(self, core, channel, biquad):
        b, a = self.state.get_biquad_coefficients(core, channel, biquad)
        arr = [b[0], b[1], b[2],
               -a[1], -a[2]]
        self._set_parameter_memory(
            core=core,
            addr=parameter_base_addr_for_biquad(channel=channel, biquad=biquad),
            data=arr)

    def _set_parameter_memory(self, core, addr, data):
        self.memory_interface.set_mem(
            name=core_param_mem_name[core],
            addr=addr,
            data=data)

import socket
class MemoryInterface(object):
    def __init__(self, host='localhost', port=MEMIF_SERVER_PORT):
        self.s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.s.connect((host, port))

    def set_mem(self, name, addr, data):
        # Quartus strangely requests _words_ in _backwards_ order!
        content = list(reversed(data))
        content = ''.join(to_param_word_as_hex(data) for data in content)
        self.s.send(
            '{:4s}{:<10d}{:<10d}{}'.format(name, addr, len(content), content))
        # Wait for confirmation.
        self.s.recv(2)

    def close(self):
        self.s.close()
