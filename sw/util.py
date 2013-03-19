import itertools
import bitstring


def encode_signed_fixedpt_as_hex(x, width, fracbits):
    shift = 1 << fracbits
    as_int = int(x * shift)
    try:
        return bitstring.BitArray(int=as_int, length=width).hex
    except bitstring.CreationError:
        raise ValueError("Overflow! %s doesn't fit into %d bits with %d frac bits",
                         x, width, fracbits)


def decode_signed_fixedpt_from_hex(x, fracbits):
    shift = 1 << fracbits
    return float(bitstring.BitArray(hex=x).int) / shift


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
