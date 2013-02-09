OPCODE_WIDTH = 6
SAMPLE_ADDR_WIDTH = 10
PARAM_ADDR_WIDTH = 10

def bin_(num, width):
    #s = bin(num)[2:]
    #assert len(s) <= width
    #return '0'*(width-len(s)) + s
    return '{:0{width}b}'.format(num, width=width)

class Instruction(object):
    def __init__(self, sample_addr, param_or_io_addr):
        self.sample_addr = sample_addr
        self.param_or_io_addr = param_or_io_addr
    def assemble(self):
        print self.__class__.__name__, self.sample_addr, self.param_or_io_addr
        return (
            bin_(self.opcode, OPCODE_WIDTH) +
            bin_(self.sample_addr, SAMPLE_ADDR_WIDTH) +
            bin_(self.param_or_io_addr, PARAM_ADDR_WIDTH))

class Nop(Instruction):
    opcode = 0
    def __init__(self):
        Instruction.__init__(self, sample_addr=0, param_or_io_addr=0)
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

def assemble(instructions, outfile):
    print >>outfile, "DEPTH = 512;"
    print >>outfile, "WIDTH = {};".format(OPCODE_WIDTH + SAMPLE_ADDR_WIDTH + PARAM_ADDR_WIDTH)
    print >>outfile, "ADDRESS_RADIX = HEX;"
    print >>outfile, "DATA_RADIX = BIN;"
    print >>outfile, "CONTENT BEGIN"
    for addr, inst in enumerate(instructions):
        print >>outfile, '{:02x} : {};'.format(addr, inst.assemble())
    print >>outfile, "END;"

def biquad_program(buf_base, param_base):
    # See http://www.earlevel.com/main/2003/02/28/biquads/ but note that it has A and B backwards.
    xn, xn1, xn2, yn, yn1, yn2 = [buf_base+n for n in range(6)]
    b0, b1, b2, a1, a2, gain = [param_base+n for n in range(6)]

    return [
        Mul(xn, b0),
        Mac(xn1, b1),
        Mac(xn2, b2),
        Mac(yn1, a1),
        Mac(yn2, a2),
        Store(yn)
        ]

num_channels = 8

# channel strip
num_biquads = 2
params_per_biquad = 5
total_biquad_params = num_biquads * params_per_biquad
mem_per_channel = (num_biquads+1)*3
params_per_channel = params_per_biquad*num_biquads
total_channel_params = params_per_channel * num_channels

# mixdown
num_cores = 1
num_busses_per_core = 2
mixdown_base_address = total_channel_params

HARDWARE_PARAMS = dict(
    num_cores=num_cores,
    num_busses_per_core=num_busses_per_core,
    num_channels_per_core=num_channels,
    num_biquads_per_channel=num_biquads)


def input_addr_for_biquad(biquad, channel):
    return mem_per_channel*channel + 3*biquad

def output_addr_for_biquad(biquad, channel):
    return input_addr_for_biquad(biquad+1, channel)

def parameter_base_addr_for_biquad(biquad, channel):
    return params_per_channel*channel + params_per_biquad*biquad

def address_for_mixdown_gain(channel, bus, core):
    '''returns the parameter memory address for the gain for channel on bus.'''
    num_mixdown_params_per_core = num_channels*num_busses_per_core
    return (mixdown_base_address
            + core * num_mixdown_params_per_core
            + num_channels * bus
            + channel)

program = []

# Read input into input for the zeroth biquad.
for channel in range(num_channels):
    program.append(In(io_addr=channel,
                      dest_sample_addr=input_addr_for_biquad(biquad=0, channel=channel)))

# Filter.
#
# Note that the read from the last channel will certainly be done by
# the time we start running its biquads.
#
# Also note that doing it this way makes sure we don't data-race
# against a store from the previous biquad.
for biquad in range(num_biquads):
    for channel in range(num_channels):
        program.extend(biquad_program(
                input_addr_for_biquad(biquad=biquad, channel=channel),
                parameter_base_addr_for_biquad(biquad=biquad, channel=channel)))

def sample_addr_post_channelstrip(channel):
    return output_addr_for_biquad(biquad=num_biquads-1, channel=channel)

# Downmix our channels.
#
# Again, the data will be ready by the time we need it.
for core in range(num_cores):
    for bus in range(num_busses_per_core):
        for channel in range(num_channels):
            if core == 0 and channel == 0:
                instr = Mul
            elif core != 0 and channel == 0:
                instr = RotMac
            else:
                instr = Mac
            program.append(
                instr(sample_addr_post_channelstrip(channel),
                      address_for_mixdown_gain(channel=channel, bus=bus, core=core)))
        program.append(Out(bus))


if __name__ == '__main__':
    print "Program length:", len(program)

    with open('instr.mif', 'w') as f:
        assemble(program, f)
