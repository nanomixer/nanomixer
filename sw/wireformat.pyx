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
        raise ValueError("Bad dimensionality for fixed-point source array (should be %d)" % n_words)
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


def floats_to_fixeds(np.float64_t[::1] x not None, int intbits, int fracbits, np.int64_t[::1] out):
    """Note that this function takes signed data, so use out.view(np.int64)."""
    if len(x) != len(out):
        raise ValueError("Input and output array sizes don't match.")
    cdef np.float64_t shift = 1 << fracbits
    cdef int i
    cdef np.float64_t cur_x
    cdef int overflow = 0
    cdef np.float64_t max_possible = 2.**intbits - 2.**-fracbits
    cdef np.float64_t min_possible = -2.**intbits
    for i in range(len(x)):
        cur_x = x[i]
        if cur_x > max_possible:
            cur_x = max_possible
            overflow = 1
        elif cur_x < min_possible:
            cur_x = min_possible
            overflow = 1
        out[i] = <np.int64_t> (cur_x * shift)
    return overflow != 0


def fixeds_to_floats(np.int64_t[::1] x, int fracbits, np.float64_t[::1] out):
    if len(x) != len(out):
        raise ValueError("Input and output array sizes don't match.")
    cdef np.float64_t shift = 1 << fracbits
    cdef int i
    for i in range(len(x)):
        out[i] = (<np.float64_t> x[i]) / shift

def sign_extend(np.uint64_t[::1] x, int sign_bit):
    """
    Sign-extends the given array in-place.

    sign_bit is the (zero-based) index of the sign bit.
    e.g., if sign_bit is 3, the minimum number that could be represented is 'b1000,
    which is -8, but we'll see it coming in as +8.
    """
    cdef np.uint64_t sign_bit_value = 1
    sign_bit_value <<= sign_bit
    cdef np.uint64_t min_neg = <np.uint64_t> -2**sign_bit
    cdef int i
    for i in range(x.shape[0]):
        if x[i] & sign_bit_value:
            x[i] |= min_neg
