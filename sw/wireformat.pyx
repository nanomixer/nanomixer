import numpy as np
cimport numpy as np

def spi_to_fixeds(np.uint8_t[:] spi):
    cdef int n_words = len(spi) / 8
    cdef np.ndarray[np.uint64_t, ndim=1] result = np.empty(n_words, dtype=np.uint64)
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