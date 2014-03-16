import numpy as np
from numpy import sin, cos, sinh

# Based on http://www.musicdsp.org/files/Audio-EQ-Cookbook.txt

Fs = 48000.
twoPiOverFs = 2*np.pi/Fs

def get_common_coeffs(f0, dBgain=None, q=None, bw=None, s=None):
    if (q, bw, s).count(None) != 2:
        raise TypeError("Exactly one bandwidth-type keyword (q, bw, s) must be specified")
    elif s and (dBgain is None):
        raise TypeError("Gain (dBgain) cannot be left unassigned if slope (s) is specified")

    w0 = f0*twoPiOverFs
    A = np.sqrt(np.power(10, dBgain/20.)) if dBgain else None

    if q:
        alpha = sin(w0)/(2*q)
    elif bw:
        alpha = sin(w0)*sinh(np.log(2)/2 * bw * w0/sin(w0) )
    elif s:
        alpha = sin(w0)/2 * np.sqrt( (A + 1/A)*(1/s - 1) + 2 )
    else:
        raise TypeError("Invalid combination of keyword arguments")

    return alpha, cos(w0), A

def normalize(b, a):
    b = map(float, b)
    a = map(float, a)
    return [b[0]/a[0], b[1]/a[0], b[2]/a[0]], [1.0, a[1]/a[0], a[2]/a[0]]

def lowpass(f0, q):
    alpha, cosw0, _ = get_common_coeffs(f0, q=q)
    b = [(1-cosw0)/2,
         1-cosw0,
         (1-cosw0)/2]
    a = [1+alpha,
         -2*cosw0,
         1-alpha]
    return b, a

def highpass(f0, q):
    # May yield unstable biquads when quantization is considered
    alpha, cosw0, _ = get_common_coeffs(f0, q=q)
    b = [(1+cosw0)/2,
         -(1+cosw0),
         (1+cosw0)/2]
    a = [1+alpha,
         -2*cosw0,
         1-alpha]
    return b, a

def bandpass(f0, bw):
    alpha, cosw0, _ = get_common_coeffs(f0, bw=bw)
    b = [alpha,
         0,
         -alpha]
    a = [1+alpha,
         -2*cosw0,
         1-alpha]
    return b, a

def notch(f0, q=None, bw=None):
    alpha, cosw0, _ = get_common_coeffs(f0, q=q, bw=bw)
    b = [1,
         -2*cosw0,
         1]
    a = [1+alpha,
         -2*cosw0,
         1-alpha]
    return b, a

def allpass(f0, q=None, bw=None):
    alpha, cosw0, _ = get_common_coeffs(f0, q=q, bw=bw)
    b = [1-alpha,
         -2*cosw0,
         1+alpha]
    a = [1+alpha,
         -2*cosw0,
         1-alpha]
    return b, a

def peaking(f0, dBgain, q=None, bw=None):
    alpha, cosw0, A = get_common_coeffs(f0, dBgain=dBgain, q=q, bw=bw)
    b = [1+alpha*A,
         -2*cosw0,
         1-alpha*A]
    a = [1+alpha/A,
         -2*cosw0,
         1-alpha/A]
    return b, a

def lowshelf(f0, dBgain, **kw):
    alpha, cosw0, A = get_common_coeffs(f0, dBgain=dBgain, **kw)
    twoRootAAlpha = 2*np.sqrt(A)*alpha
    b = [A*((A+1) - (A-1)*cosw0 + twoRootAAlpha),
         2*A*((A-1) - (A+1)*cosw0),
         A*((A+1) - (A-1)*cosw0 - twoRootAAlpha)]
    a = [(A+1) + (A-1)*cosw0 + twoRootAAlpha,
         -2*((A-1) + (A+1)*cosw0),
         (A+1) + (A-1)*cosw0 - twoRootAAlpha]
    return b, a

def highshelf(f0, dBgain, **kw):
    alpha, cosw0, A = get_common_coeffs(f0, dBgain=dBgain, **kw)
    twoRootAAlpha = 2*np.sqrt(A)*alpha
    b = [A*((A+1) + (A-1)*cosw0 + twoRootAAlpha),
         -2*A*((A-1) + (A+1)*cosw0),
         A*((A+1) + (A-1)*cosw0 - twoRootAAlpha)]
    a = [(A+1) - (A-1)*cosw0 + twoRootAAlpha,
         2*((A-1) - (A+1)*cosw0),
         (A+1) - (A-1)*cosw0 - twoRootAAlpha]
    return b, a

def plot_freqz(b, a, *args, **kw):
    import matplotlib.pyplot as plt
    from scipy.signal import freqz
    f = np.logspace(1, np.log(Fs/2)/np.log(10), 512)
    w, h = freqz(b, a, f*twoPiOverFs)
    plt.loglog(f, np.abs(h), *args, **kw)
