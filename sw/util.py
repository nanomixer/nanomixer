
def to_fixedpt(x, bits):
    # Use 2 bits to the left of the binary point (1 of which is sign, i.e., the -2's place)
    if x >= 2 or x < -2:
        raise ValueError('Overflow!')
    shift = 1<<(bits-2)
    xx = int(x * shift)
    return xx
