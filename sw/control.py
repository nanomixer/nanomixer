import numpy as np
from biquads import normalize, peaking
from util import encode_signed_fixedpt_as_hex
from assembler import HARDWARE_PARAMS, parameter_base_addr_for_biquad, address_for_mixdown_gain

PARAM_WIDTH = 5
PARAM_FRAC_BITS = 30
DEFAULT_FREQS = [150., 300., 2000., 5000.]

core_param_mem_name = ['PM00', 'PM01']

def to_param_word_as_hex(x):
    return encode_signed_fixedpt_as_hex(
        x, width=PARAM_WIDTH, fracbits=PARAM_FRAC_BITS)

class PeakingBiquad(object):
    def __init__(self, freq, gain, q):
        self.freq = float(freq)
        self.gain = float(gain)
        self.q = float(q)

    def get_coefficients(self):
        b, a = peaking(freq=self.freq, gain=self.gain, q=self.q)
        b, a = normalize(b, a)
        return b, a

class MixerState(object):
    def __init__(self, num_cores, num_busses_per_core,
                 num_channels_per_core, num_biquads_per_channel):
        self.num_cores = num_cores
        self.num_busses_per_core = num_busses_per_core
        self.num_channels_per_core = num_channels_per_core
        self.num_biquads_per_channel = num_biquads_per_channel

        # Biquads parameters
        self.biquads = np.empty((num_cores, num_channels_per_core, num_biquads_per_channel), dtype=np.object)
        for core, channel, biquad in np.nditer(self.biquads.shape):
            self.biquads[core, channel, biquad] = PeakingBiquad(freq=DEFAULT_FREQS[biquad], gain=0., q=1.)

        # Mixdown parameters
        # (bus_core, bus, channel_core, channel)
        # channels are always named by the core they come in on.
        # busses are named by the core where they end up.
        self.mixdown_gains = np.zeros((num_cores, num_busses_per_core, num_cores, num_channels_per_core))


class Controler(object):
    def __init__(self, memif_socket):
        self.state = MixerState(**HARDWARE_PARAMS)
        self.memif_socket = memif_socket

    def set_biquad_freq(self, core, channel, biquad, freq):
        self.state.biquads[core, channel, biquad].freq = freq
        self._update_biquad(core, channel, biquad)

    def set_biquad_gain(self, core, channel, biquad, gain):
        self.state.biquads[core, channel, biquad].gain = gain
        self._update_biquad(core, channel, biquad)

    def set_biquad_q(self, core, channel, biquad, q):
        self.state.biquads[core, channel, biquad].q = q
        self._update_biquad(core, channel, biquad)

    def set_gain(self, bus_core, bus, channel_core, channel, gain):
        self.state.mixdown_gains[bus_core, bus, channel_core, channel] = gain
        self._set_parameter_memory(
            core=channel_core,
            addr=address_for_mixdown_gain(
                core=(channel_core - bus_core - 1) % self.state.num_cores,
                channel=channel,
                bus=bus),
            data=[gain])

    def _update_biquad(self, core, channel, biquad):
        b, a = self.state.biquads[core, channel, biquad].get_coefficients()
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
    def __init__(self, host = 'localhost', port = 2540):
        self.s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.s.connect(( host,port))

    def set_mem(self, name, addr, data):
        # Quartus strangely requests _words_ in _backwards_ order!
        content = list(reversed(data))
        content = ''.join(to_param_word_as_hex(data) for data in content)
        self.s.send(
            '{:4s}{:<10d}{:<10d}{}'.format(name, addr, len(content), content))
        # Wait for confirmation.
        self.s.recv(2)


class OSCServer(object):
    def __init__(self, client=None, port=7559):
        import OSC
        if client is None:
            client = Client()

        self.client = client
        self.server = OSC.OSCServer(('0.0.0.0', port), None, port-1)
        for channel in range(1,6):
            self.server.addMsgHandler('/4/gain/{}'.format(channel), self.setFiltGain)
        self.server.addMsgHandler('/4/loslvfrq', self.setFreq)

        for channel in range(8):
            self.server.addMsgHandler('/1/volume{}'.format(channel+1), self.setGain)


    def setGain(self, addr, tags, data, client_addr):
        channel = int(addr[-1])-1
        self.gains[channel,channel % 2] = data[0]
        print self.gains
        if not self._data_ready():
            self.client.set_gains(self.gains)

    def setFiltGain(self, addr, tags, data, client_addr):
        channel = int(addr.rsplit('/', 1)[1]) - 1
        gain = 40*(data[0]-.5)
        self.filt_gains[channel] = gain
        self._send_filt()

    def setFreq(self, addr, tags, data, client_addr):
        print addr
        freq = 20 * 2**(data[0]*10)
        print freq
        self.freqs[0] = freq
        self._send_filt()

    def _data_ready(self):
        self.server.socket.setblocking(False)
        try:
            dataReady = self.server.socket.recv(1, socket.MSG_PEEK)
        except:
            dataReady = False
        self.server.socket.setblocking(True)
        return dataReady

    def _send_filt(self):
        dataReady = self._data_ready()
        if not dataReady:
            gain = self.filt_gains[0]
            print gain, self.freqs[0]
            self.client.set_biquad(*peaking(self.freqs[0], gain, bw=1./2))


    def serve_forever(self):
        try:
            self.server.serve_forever()
        except:
            self.server.socket.close()
            self.client.s.close()
            raise

