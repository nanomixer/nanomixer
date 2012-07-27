# dest addr always goes first

# halt
# load:   reg addr
# store:  reg addr
# mul:    rd, rs, rt
# mulacc: rd, rs, rt # accumulator is both rd and rd+1

def bin_(num):
    return bin(num)[2:]

def zero_extend(num, width):
    assert len(num) <= width
    return '0'*(width-len(num)) + num

class Instruction(object):
    def __init__(self, data=''):
        self.opcode = opcode_for_inst[self.__class__]
        self.data = data
    def assemble(self):
        return zero_extend(bin_(self.opcode), 3) + self.data + '0'*(16-3-len(self.data))
class Halt(Instruction): pass
class Load(Instruction):
    def __init__(self, reg, addr):
        super(Load, self).__init__(Reg(reg) + Mem(addr))
class Store(Instruction):
    def __init__(self, reg, addr):
        super(Store, self).__init__(Reg(reg) + Mem(addr))
class Mul(Instruction):
    def __init__(self, rs, rt, rd):
        super(Mul, self).__init__(Reg(rd) + Reg(rs) + Reg(rt))
class MulAcc(Instruction):
    def __init__(self, rd, rs, rt):
        super(MulAcc, self).__init__(Reg(rd) + Reg(rs) + Reg(rt))

opcodes = [Halt, Load, Store, Mul, MulAcc]
opcode_for_inst = dict((inst, opcode) for opcode, inst in enumerate(opcodes))

def assemble(instructions):
    for inst in instructions:
        print inst.assemble()

# See http://www.earlevel.com/main/2003/02/28/biquads/ but note that it has A and B backwards.

# Biquad memory layout
mem = range(14)
zero, noise, xn, xn1, xn2, yn, yn1, yn2 = mem[0:8]
b0, b1, b2, a1, a2, gain = mem[8:14]

# registers
r0, r1, r2, r3 = range(4)

biquad = [
    Load(r0, zero),
    Load(r1, noise),
    Load(r2, xn),
    Load(r3, b0),
    MulAcc(r0, r2, r3),
    Load(r2, xn1),
    Load(r3, b1),
    MulAcc(r0, r2, r3),
    Load(r2, xn2),
    Load(r3, b2),
    MulAcc(r0, r2, r3),
    Load(r2, yn1),
    Load(r3, a1),
    MulAcc(r0, r2, r3),
    Load(r2, yn2),
    Load(r3, a2),
    MulAcc(r0, r2, r3),
    Store(r1, noise),
    Load(r3, gain),
    Mul(r2, r0, r3),
    Halt()]

assemble(biquad)
    


# biquad = [
#     Copy(zero, accMSB),
#     Copy(zero, accLSB),
#     MulAcc(xn, b0, accMSB),
#     MulAcc(xn1, b1, accMSB),
#     MulAcc(xn2, b2, accMSB),
#     MulAcc(yn1, a1, accMSB),
#     Mul(accMSB, gain, yn)]

def segmented_address(segment, offset):
    return (segment << OFFSET_WIDTH) | offset

def reg(n):
    return segmented_address(0, n)

def io(n):
    return segmented_address(1, n)

def param(n):
    return segmented_address(2, n)

zero, xn, xn1, xn2, yn, yn1, yn2 = [reg(n) for n in range(6)]
# Segment 1: inputs/outputs
ch1 = io(0)
# Segment 2: parameter memory
b0, b1, b2, a1, a2, gain = [param(n) for n in range(6)]

# Instructions read from A and optionally B, and write to W.
biquad = [
    # Zero the accumulator.
    AToHi(zero), # register 0 is zero
    AToLo(zero),
    # Set up registers: move existing values
    AToW(xn2, xn1),
    AToW(xn1, xn),
    AToW(yn2, yn1),
    AToW(yn1, yn),
    # Read input
    AToW(xn, ch1),
    # Run biquad
    MulAcc(xn, b0),
    MulAcc(xn1, b1),
    MulAcc(xn2, b2),
    MulAcc(yn1, a1),
    MulAcc(yn2, a2),
    HiToReg(yn),
    MulToReg(yn, yn, gain),
    # Write output
    AToW(ch1, yn)
    ]

# Instructions
# 0: nop
# 1: Mul
# 2: MulAcc
# 3: MulToW
# 4: AToHi
# 5: AToLo
# 6: HiToW
# 7: LoToW
# 8: AToW
