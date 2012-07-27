import numpy as np
from numpy import sin, cos, sinh
import matplotlib.pyplot as plt
from scipy.signal import freqz

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
    return [b[0]/a[0], b[1]/a[0], b[2]/a[0]], [1, a[1]/a[0], a[2]/a[0]]

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
    # Use 2 bits to the left of the binary point (1 of which is sign)
    if x >= 2 or x < -2:
        raise ValueError('Overflow!')
    shift = (2**(bits-2))
    xx = x * shift
    return np.round(xx)/shift
