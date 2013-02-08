import bitstring

def encode_signed_fixedpt_as_hex(x, width, fracbits):
    shift = 1 << fracbits
    as_int = int(x * shift)
    try:
        return bitstring.BitArray(int=as_int, length=width).hex
    except bitstring.CreationError:
        raise ValueError("Overflow! %s doesn't fit into %d bits with %d frac bits",
                         x, width, fracbits)
