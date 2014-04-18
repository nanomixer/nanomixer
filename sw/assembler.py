from __future__ import print_function

OPCODE_WIDTH = 6
SAMPLE_ADDR_WIDTH = 10
PARAM_ADDR_WIDTH = 10

def bin_(num, width):
    #s = bin(num)[2:]
    #assert len(s) <= width
    #return '0'*(width-len(s)) + s
    s = '{:0{width}b}'.format(num, width=width)
    if len(s) != width:
        raise ValueError("Number too wide: %r can't fit in %s bits" % (num, width))
    return s

class Addr(object):
    def __init__(self):
        self.addr = None
    def __repr__(self):
        return str(self.addr)
    def __index__(self):
        assert self.addr is not None
        return self.addr
    def __int__(self):
        assert self.addr is not None
        return self.addr


def assign_addresses(seq, start_address):
    if hasattr(seq, 'addr'):
        # Base case: single Addr object.
        if seq.addr is None:
            seq.addr = start_address
            return start_address + 1
        else:
            # already assigned.
            return start_address
    if hasattr(seq, 'values'):
        seq = seq.values()
    for item in seq:
        start_address = assign_addresses(item, start_address)
    return start_address

def get_addr(addr):
    return getattr(addr, 'addr', addr)

class Instruction(object):
    def __init__(self, sample_addr, param_or_io_addr):
        self.sample_addr = sample_addr
        self.param_or_io_addr = param_or_io_addr
    def __repr__(self):
        return '{}({}, {})'.format(self.__class__.__name__, self.sample_addr, self.param_or_io_addr)
    def assemble(self):
        print(repr(self))
        return (
            bin_(self.opcode, OPCODE_WIDTH) +
            bin_(get_addr(self.sample_addr), SAMPLE_ADDR_WIDTH) +
            bin_(get_addr(self.param_or_io_addr), PARAM_ADDR_WIDTH))

class Nop(Instruction):
    opcode = 0
    def __init__(self):
        Instruction.__init__(self, sample_addr=0, param_or_io_addr=0)
    def __repr__(self): return '{}()'.format(self.__class__.__name__)
class Mul(Instruction):
    opcode = 1
class Mac(Instruction):
    opcode = 2
class RotMac(Instruction):
    opcode = 3
class Store(Instruction):
    opcode = 4
    def __init__(self, dest_sample_addr):
        Instruction.__init__(
            self, sample_addr=dest_sample_addr, param_or_io_addr=0)
    def __repr__(self): return '{}({})'.format(self.__class__.__name__, self.sample_addr)
class In(Instruction):
    opcode = 5
    def __init__(self, dest_sample_addr, io_addr):
        Instruction.__init__(
            self, sample_addr=dest_sample_addr, param_or_io_addr=io_addr)
class Out(Instruction):
    opcode = 6
    def __init__(self, dest_io_addr):
        Instruction.__init__(
            self, sample_addr=0, param_or_io_addr=dest_io_addr)
    def __repr__(self): return '{}({})'.format(self.__class__.__name__, self.param_or_io_addr)
class Spin(Instruction):
    opcode = 7
    def __init__(self, spin_amount):
        Instruction.__init__(
            self, sample_addr=spin_amount, param_or_io_addr=0)
    def __repr__(self): return '{}({})'.format(self.__class__.__name__, self.sample_addr)
class AMac(Instruction):
    opcode = 8
    def __init__(self, sample_addr):
        Instruction.__init__(
            self, sample_addr=sample_addr, param_or_io_addr=0)
    def __repr__(self): return '{}({})'.format(self.__class__.__name__, self.sample_addr)
class AuxOut(Out):
    opcode = 9

def assemble(instructions, outfile):
    print("DEPTH = 2048;", file=outfile)
    print("WIDTH = {};".format(OPCODE_WIDTH + SAMPLE_ADDR_WIDTH + PARAM_ADDR_WIDTH), file=outfile)
    print("ADDRESS_RADIX = HEX;", file=outfile)
    print("DATA_RADIX = BIN;", file=outfile)
    print("CONTENT BEGIN", file=outfile)
    for addr, inst in enumerate(instructions):
        print('{:02x} : {};'.format(addr, inst.assemble()), file=outfile)
    print("END;", file=outfile)
