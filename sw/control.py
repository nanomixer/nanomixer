import numpy as np
from bitstring import BitArray
from biquads import normalize, peaking
from util import to_fixedpt

def to_word(data):
    return BitArray(int=to_fixedpt(data, 36), length=36).hex


import socket
class Client(object):
    def __init__(self, host = 'localhost', port = 2540):
        self.s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.s.connect(( host,port))

    def set_biquad(self, channel, b, a):
        b, a = normalize(b, a)
        self.set_biquad_raw(channel, b, a)

    def set_biquad_raw(self, channel, b, a):
        arr = [b[0], b[1], b[2],
               -a[1], -a[2]]
        self._setmem(5*channel, arr)

    def set_gains(self, gains):
        self._setmem(40, gains.T.ravel())
    
    def _setmem(self, addr, content):
        content = ''.join(to_word(data) for data in reversed(content))
        self.s.send('{:<10d}{:<10d}{}'.format(addr, len(content), content))
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

        self.gains = np.zeros((8, 2))
        self.filt_gains = np.zeros(6)
        self.freqs = np.zeros(6)
        self.freqs[0] = 50

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

