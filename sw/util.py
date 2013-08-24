import itertools
import bitstring
import numpy as np


def floats_to_fixeds(x, fracbits):
    """Takes a numpy float array and returns a numpy int array of them
    in fixed point.

    NB: This does not check for overflow!
    """
    shift = 1 << fracbits
    return (x * shift).astype(np.uint64)


def fixeds_to_floats(x, fracbits):
    shift = 1 << fracbits
    return x.astype(np.float64) / shift


def fixeds_to_spi(x):
    hiwords = (x >> 18) & 0x03ff
    lowords = x & 0x03ff
    n_words = len(x)
    result = np.empty(8 * n_words, dtype=np.uint8)
    start = 0
    for i in xrange(n_words):
        result[start  :start+4] = bitstring.Bits(uintle=hiwords[i], length=32).bytes
        result[start+4:start+8] = bitstring.Bits(uintle=lowords[i], length=32).bytes
        start += 8
    return result


def spi_to_fixeds(x):
    n_words = len(x) / 8
    result = np.empty(n_words, dtype=np.uint64)
    start = 0
    for i in xrange(n_words):
        result[i] = (
            ((bitstring.Bits(bytes=x[start  :start+4]).uintle & 0x03ff) << 18) +
             (bitstring.Bits(bytes=x[start+4:start+8]).uintle & 0x03ff))
        start += 8
    return result


def flattened(iterable):
    iterable = iter(iterable)
    while True:
        item = iterable.next()
        try:
            iterable = itertools.chain(iter(item), iterable)
        except TypeError:
            yield item


# From http://docs.python.org/2/library/itertools.html
def roundrobin(*iterables):
    "roundrobin('ABC', 'D', 'EF') --> A D E B F C"
    # Recipe credited to George Sakkis
    pending = len(iterables)
    nexts = itertools.cycle(iter(it).next for it in iterables)
    while pending:
        try:
            for next in nexts:
                yield next()
        except StopIteration:
            pending -= 1
            nexts = itertools.cycle(itertools.islice(nexts, pending))
