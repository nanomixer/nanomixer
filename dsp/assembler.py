OFFSET_WIDTH = 7

def bin_(num, width):
    #s = bin(num)[2:]
    #assert len(s) <= width
    #return '0'*(width-len(s)) + s
    return '{:0{width}b}'.format(num, width=width)

class Instruction(object):
    def __init__(self, w, a, b):
        self.w = w
        self.a = a
        self.b = b
    def assemble(self):
        return (
            bin_(self.opcode, 6) +
            bin_(self.w, 10) +
            bin_(self.a, 10) +
            bin_(self.b, 10))

class Nop(Instruction):
    opcode = 0
    def __init__(self):
        Instruction.__init__(self, w=0, a=0, b=0)
class _MulInstruction(Instruction):
    def __init__(self, a, b):
        Instruction.__init__(self, w=0, a=a, b=b)
class Mul(_MulInstruction):
    opcode = 1
class MulAcc(_MulInstruction):
    opcode = 2
class MulToW(Instruction):
    opcode = 3
class AToHi(Instruction):
    opcode = 4
    def __init__(self, a):
        Instruction.__init__(self, w=0, a=a, b=0)
class AToLo(Instruction):
    opcode = 5
    def __init__(self, a):
        Instruction.__init__(self, w=0, a=a, b=0)
class HiToW(Instruction):
    opcode = 6
    def __init__(self, w):
        Instruction.__init__(self, w=w, a=0, b=0)
class LoToW(Instruction):
    opcode = 7
    def __init__(self, w):
        Instruction.__init__(self, w=w, a=0, b=0)
class AToW(Instruction):
    opcode = 8
    def __init__(self, w, a):
        Instruction.__init__(self, w=w, a=a, b=0)

def assemble(instructions, outfile):
    print >>outfile, "DEPTH = 512;"
    print >>outfile, "WIDTH = 36;"
    print >>outfile, "ADDRESS_RADIX = HEX;"
    print >>outfile, "DATA_RADIX = BIN;"
    print >>outfile, "CONTENT BEGIN"
    for addr, inst in enumerate(instructions):
        print >>outfile, '{:02x} : {};'.format(addr, inst.assemble())
    print >>outfile, "END;"

def segmented_address(segment, offset):
    return (segment << OFFSET_WIDTH) | offset

def reg(n):
    return segmented_address(0, n)

def io(n):
    return segmented_address(1, n)

def param(n):
    return segmented_address(2, n)

def biquad(in_addr, buf_base, param_base, out_addr):
    # See http://www.earlevel.com/main/2003/02/28/biquads/ but note that it has A and B backwards.
    zero = reg(0)  # register 0 is always zero
    xn, xn1, xn2, yn, yn1, yn2 = [buf_base+n for n in range(6)]
    b0, b1, b2, a1, a2, gain = [param_base+n for n in range(6)]

    return [
        # Zero the accumulator.
        AToHi(zero),
        AToLo(zero),
        # Set up registers: move existing values
        AToW(xn2, xn1),
        AToW(xn1, xn),
        AToW(yn2, yn1),
        AToW(yn1, yn),
        # Read input
        AToW(xn, in_addr),
        # Run biquad
        MulAcc(xn, b0),
        MulAcc(xn1, b1),
        MulAcc(xn2, b2),
        MulAcc(yn1, a1),
        MulAcc(yn2, a2),
        HiToW(yn),
        MulToW(yn, yn, gain),
        # Write output
        AToW(out_addr, yn)
        ]

program = []
for channel in range(8):
    program.extend(
        biquad(io(channel), reg(6*channel+1), param(6*channel), io(channel)))

print "Program length:", len(program)

with open('../fpga/instr.mif', 'w') as f:
    assemble(program, f)
