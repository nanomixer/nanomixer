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
