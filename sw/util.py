import bitstring

def encode_signed_fixedpt(x, intbits, fracbits):
    shift = 1 << fracbits
    as_int = int(x * shift)
    total_num_bits = intbits + fracbits + 1 # sign bit
    try:
        return bitstring.BitArray(int=as_int, length=total_num_bits).hex
    except bitstring.CreationError:
        raise ValueError("Overflow! %s doesn't fit in a Q%d.%d",
                         x, intbits, fracbits)
