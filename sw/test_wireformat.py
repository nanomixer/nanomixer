import numpy as np
import bitstring
import wireformat


def fixeds_to_spi(x):
    hiwords = ((x >> 18) & 0x03ffff) | 0x40000  # prepend 2'b01
    lowords = (x & 0x03ffff) | 0x80000  # prepend 2'b10
    n_words = len(x)
    result = np.empty(8 * n_words, dtype=np.uint8)
    start = 0
    for i in xrange(n_words):
        result[start  :start+4] = np.fromstring(
            bitstring.Bits(uintle=hiwords[i], length=32).bytes, dtype=np.uint8)
        result[start+4:start+8] = np.fromstring(
            bitstring.Bits(uintle=lowords[i], length=32).bytes, dtype=np.uint8)
        start += 8
    return result


def spi_to_fixeds(x):
    n_words = len(x) / 8
    result = np.empty(n_words, dtype=np.uint64)
    start = 0
    for i in xrange(n_words):
        result[i] = (
            ((bitstring.Bits(bytes=x[start  :start+4]).uintle & 0x03ffff) << 18) +
             (bitstring.Bits(bytes=x[start+4:start+8]).uintle & 0x03ffff))
        start += 8
    return result


def test_spi_roundtrip(n=1000, reps=100):
    for i in xrange(reps):
        # Encode ref, decode ref
        fixeds = np.random.randint(2**36-1, size=n).astype(np.uint64)
        ref_spi = fixeds_to_spi(fixeds)
        ref_roundtrip_result = spi_to_fixeds(ref_spi)
        assert np.all(fixeds==ref_roundtrip_result)

        # Encode ref, decode cython
        fixed_buf = np.empty(n, dtype=np.uint64)
        wireformat.spi_to_fixeds(ref_spi, fixed_buf)
        assert np.all(fixeds == fixed_buf)

        # Encode cython, decode ref
        spi_buf = np.empty(n * 8, dtype=np.uint8)
        wireformat.fixeds_to_spi(ref_roundtrip_result, spi_buf)
        assert np.all(spi_buf == ref_spi)
        assert np.all(fixeds == spi_to_fixeds(spi_buf))

        # Encode cython, decode cython
        wireformat.fixeds_to_spi(fixeds, spi_buf)
        wireformat.spi_to_fixeds(spi_buf, fixed_buf)
        assert np.all(fixeds == fixed_buf)
