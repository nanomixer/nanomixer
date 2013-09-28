#cython: boundscheck=False
#cython: wraparound=False

import numpy as np
cimport numpy as np

def spi_to_fixeds(np.uint8_t[:] spi not None, np.uint64_t[:] result not None):
    cdef int n_words = spi.shape[0] / 8
    if result.shape[0] != n_words:
        raise ValueError("Bad dimensionality for fixed-point result array (should be %d)", n_words)
    cdef int start = 0
    cdef np.uint64_t hiword, loword
    for i in range(n_words):
        hiword = spi[start+2] & 0x03
        hiword <<= 8
        hiword |= spi[start+1]
        hiword <<= 8
        hiword |= spi[start]
        start += 4
        loword = spi[start+2] & 0x03
        loword <<= 8
        loword |= spi[start+1]
        loword <<= 8
        loword |= spi[start]
        result[i] = (hiword << 18 | loword)
        start += 4
    return result

def fixeds_to_spi(np.uint64_t[:] fixeds not None, np.uint8_t[:] spi not None):
    cdef int n_words = spi.shape[0] / 8
    if fixeds.shape[0] != n_words:
        raise ValueError("Bad dimensionality for fixed-point source array (should be %d)", n_words)
    cdef int start = 0
    cdef np.uint64_t hiword, loword
    for i in range(n_words):
        hiword = (fixeds[i] >> 18) & 0x03ffff
        loword =  fixeds[i]        & 0x03ffff

        # Pack hi word
        spi[start] = hiword & 0xff
        hiword >>= 8
        spi[start+1] = hiword & 0xff
        hiword >>= 8
        spi[start+2] = (hiword & 0xff) | 0x4 # prepend 2'b01
        spi[start+3] = 0
        start += 4

        # Pack lo word
        spi[start] = loword & 0xff
        loword >>= 8
        spi[start+1] = loword & 0xff
        loword >>= 8
        spi[start+2] = (loword & 0xff) | 0x8 # prepend 2'b10
        spi[start+3] = 0
        start += 4


def floats_to_fixeds(np.float64_t[::1] x not None, int fracbits, np.int64_t[::1] out=None):
    """Note that this function takes signed data, so use out.view(np.int64)."""
    if out is None:
        out = np.empty(len(x), dtype=np.int64)
    elif len(x) != len(out):
        raise ValueError("Input and output array sizes don't match.")
    cdef np.float64_t shift = 1 << fracbits
    cdef int i
    for i in range(len(x)):
        out[i] = <np.int64_t> (x[i] * shift)
    return out


def fixeds_to_floats(np.int64_t[::1] x, int fracbits, np.float64_t[::1] out=None):
    if out is None:
        out = np.empty(len(x), dtype=np.float64)
    elif len(x) != len(out):
        raise ValueError("Input and output array sizes don't match.")
    cdef np.float64_t shift = 1 << fracbits
    cdef int i
    for i in range(len(x)):
        out[i] = (<np.float64_t> x[i]) / shift
    return out
