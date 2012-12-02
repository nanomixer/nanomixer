import numpy as np
from numpy import sin, cos, sinh
#import matplotlib.pyplot as plt
#from scipy.signal import freqz
from bitstring import BitArray

# Based on http://www.musicdsp.org/files/Audio-EQ-Cookbook.txt

Fs = 48000.
twoPiOverFs = 2*np.pi/Fs

def get_alpha(w0, **kw):
    if 'q' in kw:
        return sin(w0)/(2*kw['q'])
    elif 'bw' in kw:
        return sin(w0)*sinh(np.log(2)/2 * kw['bw'] * w0/sin(w0) )
    elif 's' in kw:
        A = kw['A']
        S = kw['s']
        return sin(w0)/2 * np.sqrt( (A + 1/A)*(1/S - 1) + 2 )
    else:
        raise ValueError("Should have gotten q, bw, or s.")

def get_pow(dBgain, is_shelving=False):
    return np.sqrt(np.power(10, dBgain/20.))

def normalize(b, a):
    b = map(float, b)
    a = map(float, a)
    return [b[0]/a[0], b[1]/a[0], b[2]/a[0]], [1.0, a[1]/a[0], a[2]/a[0]]

def lowpass(f0, dBgain, **kw):
    '''Pass either q, bw, or s.'''
    A = get_pow(dBgain)
    w0 = f0*twoPiOverFs
    alpha = get_alpha(w0, A=A, **kw)
    cosw0 = cos(w0)
    b = [(1-cosw0)/2,
         1-cosw0,
         (1-cosw0)/2]
    a = [1+alpha,
         -2*cosw0,
         1-alpha]
    return b, a

def peaking(f0, dBgain, **kw):
    A = get_pow(dBgain)
    w0 = f0*twoPiOverFs
    alpha = get_alpha(w0, A=A, **kw)
    cosw0 = cos(w0)
    b = [1+alpha*A,
         -2*cosw0,
         1-alpha*A]
    a = [1+alpha/A,
         -2*cosw0,
         1-alpha/A]
    return b, a

def to_fixedpt(x, bits):
    # Use 2 bits to the left of the binary point (1 of which is sign, i.e., the -2's place)
    if x >= 2 or x < -2:
        raise ValueError('Overflow!')
    shift = 1<<(bits-2)
    xx = int(x * shift)
    return xx

def plot_freqz(b, a, *args, **kw):
    f = np.logspace(1, np.log(Fs/2)/np.log(10), 512)
    w, h = freqz(b, a, f*twoPiOverFs)
    plt.loglog(f, np.abs(h), *args, **kw)

def plot_rounded_freqz(b, a, bits):
    plot_freqz(b, a, 'b')
    
    b, a = normalize(b, a)

    b = [round_coeff(x, bits) for x in b]
    a = [round_coeff(x, bits) for x in a]
    
    plot_freqz(b, a, 'r')

def round_coeff(x, bits):
    return to_fixedpt(x, bits) / (1<<(bits-2))

def biquad_to_param_mif(b, a, outfile):
    b, a = normalize(b, a)
    assert abs(a[0] - 1.0) < 1e-5
    biquad_to_param_mif_raw(b, a, outfile)

def biquad_to_param_mif_raw(b, a, outfile):
    arr = [b[0], b[1], b[2],
           -a[1], -a[2]]
    print >>outfile, "DEPTH = 256;"
    print >>outfile, "WIDTH = 36;"
    print >>outfile, "ADDRESS_RADIX = HEX;"
    print >>outfile, "DATA_RADIX = HEX;"
    print >>outfile, "CONTENT BEGIN"
    addr = 0
    for channel in range(2):
        for data in arr:
            print >>outfile, '{:02x} : {};'.format(addr, BitArray(int=to_fixedpt(data, 36), length=36).hex)
            addr += 1
    print >>outfile, "END;"

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
        self._setmem(40, gains.ravel())
    
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
        self.gains[channel,:] = data[0]
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
        freq = 20 * 2**(data[0]*5)
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

