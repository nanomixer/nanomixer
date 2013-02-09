import numpy as np
from biquads import normalize, peaking
from util import encode_signed_fixedpt_as_hex
from assembler import HARDWARE_PARAMS, parameter_base_addr_for_biquad, address_for_mixdown_gain

PARAM_WIDTH = 5
PARAM_FRAC_BITS = 30

core_param_mem_name = ['PM00', 'PM01']

# Channel name -> (core, channel)
channel_map = {
    '1': (0, 0),
    '2': (0, 1),
    '3': (0, 2),
    '4': (0, 3),
    '5': (1, 0),
    '6': (1, 1),
    '7': (1, 2),
    '8': (1, 3),
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
        self.biquad_freq = np.zeros((num_cores, num_channels_per_core, num_biquads_per_channel))
        self.biquad_gain = np.zeros((num_cores, num_channels_per_core, num_biquads_per_channel))
        self.biquad_q = np.zeros((num_cores, num_channels_per_core, num_biquads_per_channel))

        # Mixdown parameters
        # (bus_core, bus, channel_core, channel)
        # channels are always named by the core they come in on.
        # busses are named by the core where they end up.
        self.mixdown_gains = np.zeros((num_cores, num_busses_per_core, num_cores, num_channels_per_core))

    def get_biquad_coefficients(self, core, channel, biquad):
        b, a = peaking(freq=self.state.biquad_freq[core, channel, biquad],
                       gain=self.state.biquad_gain[core, channel, biquad],
                       q=self.state.biquad_q[core, channel, biquad])
        b, a = normalize(b, a)
        return b, a


class Controler(object):
    def __init__(self, memif_socket):
        self.state = MixerState(**HARDWARE_PARAMS)
        self.memif_socket = memif_socket

    def set_biquad_freq(self, channel, biquad, freq):
        core, ch = channel_map[channel]
        self.state.biquad_freq[core, ch, biquad] = freq
        self._update_biquad(core, ch, biquad)

    def set_biquad_gain(self, channel, biquad, gain):
        core, ch = channel_map[channel]
        self.state.biquad_gain[core, ch, biquad] = gain
        self._update_biquad(core, ch, biquad)

    def set_biquad_q(self, channel, biquad, q):
        core, ch = channel_map[channel]
        self.state.biquad_q[core, channel, biquad] = q
        self._update_biquad(core, channel, biquad)

    def set_gain(self, bus, channel, gain):
        bus_core, b = bus_map[bus]
        channel_core, ch = channel_map[channel]
        self.state.mixdown_gains[bus_core, bus, channel_core, channel] = gain
        self._set_parameter_memory(
            core=channel_core,
            addr=address_for_mixdown_gain(
                core=(channel_core - bus_core - 1) % self.state.num_cores,
                channel=channel,
                bus=bus),
            data=[gain])

    def _update_biquad(self, core, channel, biquad):
        b, a = self.state.get_biquad_coefficients(core, channel, biquad)
        arr = [b[0], b[1], b[2],
               -a[1], -a[2]]
        self._set_parameter_memory(
            core=core,
            addr=parameter_base_addr_for_biquad(channel, biquad),
            data=arr)

    def _set_parameter_memory(self, core, addr, data):
        self.memory_interface.set_mem(
            name=core_param_mem_name[core],
            addr=addr,
            data=data)

import socket
class MemoryInterface(object):
    def __init__(self, host='localhost', port=2540):
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


## Views
class OSCServer(object):
    def __init__(self, controller, osc_port=7559):
        import OSC
        self.controller = controller
        self.osc_server = OSC.OSCServer(('0.0.0.0', osc_port), None, osc_port - 1)
        for channel in range(1, 6):
            self.osc_server.addMsgHandler('/4/gain/{}'.format(channel), self.setFiltGain)
        self.osc_server.addMsgHandler('/4/loslvfrq', self.setFreq)

        for channel in range(8):
            self.osc_server.addMsgHandler('/1/volume{}'.format(channel+1), self.setGain)


    def setGain(self, addr, tags, data, client_addr):
        # Ignore this if we'd just overwrite it in a moment
        # TODO: improve this logic!
        if self._data_ready():
            return
        channel = int(addr[-1])-1
        gain = data[0]
        self.controller.set_gain(0, 0, 0, channel, gain)

    def setFiltGain(self, addr, tags, data, client_addr):
        if self._data_ready():
            return
        channel = int(addr.rsplit('/', 1)[1]) - 1
        gain = 40*(data[0]-.5)
        self.controller.set_biquad_gain(0, channel, 0, gain)

    def setFreq(self, addr, tags, data, client_addr):
        if self._data_ready():
            return
        print addr
        freq = 20 * 2**(data[0]*10)
        channel = 0
        print freq
        self.controller.set_biquad_freq(0, channel, 0, freq)

    def _data_ready(self):
        self.osc_server.socket.setblocking(False)
        try:
            dataReady = self.osc_server.socket.recv(1, socket.MSG_PEEK)
        except:
            dataReady = False
        self.osc_server.socket.setblocking(True)
        return dataReady

    def serve_forever(self):
        try:
            self.osc_server.serve_forever()
        except:
            self.osc_server.socket.close()
            self.controller.memif_socket.close()
            raise
