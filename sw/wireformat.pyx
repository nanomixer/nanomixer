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
