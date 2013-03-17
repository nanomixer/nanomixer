#
# Sample Memory Layout:
#
# [[channel biquad state] * num_biquads] * num_channels + [metering biquad state]
#
# Param Memory Layout:
# [[channel biquad params] * num_channels] [[mixdown gains]] [metering biquad params] [constants]
#
constants = [
    0.,
    2**-8
]

from assembler import Nop, Mul, Mac, RotMac, Store, In, Out, Spin, AMac, assemble, Addr, assign_addresses
from collections import namedtuple

BiquadStorage = namedtuple('BiquadStorage', 'xn, xn1, xn2')
BiquadParams = namedtuple('BiquadParams', 'b0, b1, b2, a1, a2')

def make_biquad_storage():
    return BiquadStorage._make([Addr() for i in xrange(3)])

def make_biquad_params():
    return BiquadParams._make([Addr() for i in xrange(5)])

def n_addrs(n):
    return [Addr() for i in xrange(n)]

def biquad_program(input_storage, output_storage, params):
    # See http://www.earlevel.com/main/2003/02/28/biquads/ but note that it has A and B backwards.
    # Read the old values first, so that we basically never have to stall the pipeline to wait for xn.
    return [
        Mul(output_storage.xn2, params.a2),
        Mac(output_storage.xn1, params.a1),
        Mac(input_storage.xn2, params.b2),
        Mac(input_storage.xn1, params.b1),
        Mac(input_storage.xn, params.b0),
        Store(output_storage.xn)
        ]

num_channels = 8

# channel strip
num_biquads = 2
params_per_biquad = 5
total_biquad_params = num_biquads * params_per_biquad
# Each biquad only stores its own input sample values. To leave space for the outputs,
# we need additional storage for the output sample and its two delayed values.
mem_per_channel = 3*num_biquads + 3
params_per_channel = params_per_biquad*num_biquads
total_channel_params = params_per_channel * num_channels

# mixdown
num_cores = 1
num_busses_per_core = 2
mixdown_base_address = total_channel_params
num_mixdown_params_per_core = num_channels*num_busses_per_core
num_mixdown_params = num_cores * num_mixdown_params_per_core
sample_mem_per_bus = 0 # for now.

HARDWARE_PARAMS = dict(
    num_cores=num_cores,
    num_busses_per_core=num_busses_per_core,
    num_channels_per_core=num_channels,
    num_biquads_per_channel=num_biquads)

meter_outputs = [Addr() for channel in range(num_channels)]
assign_addresses(meter_outputs, start_address=512)

ParamMem = namedtuple('ParamMem', 'biquad mixdown_gain meter_biquad constant')
SampleMem = namedtuple('SampleMem', 'biquad meter_biquad')

def make_mems():
    param = ParamMem(
        biquad=[
            [make_biquad_params() for biquad in range(num_biquads)]
            for channel in range(num_channels)],
        mixdown_gain=[
            [[Addr() for channel in range(num_channels)]
             for bus in range(num_busses_per_core)]
            for core in range(num_cores)],
        meter_biquad=make_biquad_params(),
        constant=[Addr() for i in range(len(constants))])
    assign_addresses(param, 0)

    sample = SampleMem(
        biquad=[
            [make_biquad_storage() for biquad in range(num_biquads+1)] # extra biquad for the final output
            for channel in range(num_channels)],
        meter_biquad=[[make_biquad_storage() for biquad in range(2)] for channel in range(num_channels)])
    assign_addresses(sample, 0)

    return param, sample

param, sample = make_mems()


##
## Exports
##
def parameter_base_addr_for_biquad(channel, biquad):
    return param.biquad[channel][biquad][0].addr

def address_for_mixdown_gain(core, channel, bus):
    return param.mixdown_gain[core][channel][bus].addr

constants_base = param.constant[0].addr
meter_biquad_param_base = param.meter_biquad[0].addr

def addr_for_constant(constant):
    if constant in constants:
        return param.constant[constants.index(constant)]
    else:
        raise ValueError("Constant %r not defined" % constant)

program = []

# Read input into input for the zeroth biquad.
for channel in range(num_channels):
    program.append(In(io_addr=channel,
                      dest_sample_addr=sample.biquad[channel][0].xn))

# Note that with the current pipelining, the read from the first channel may not be done by
# the time we start running the first channel's biquads; so, let's add a few NOPs for now.
program.extend([Nop()]*3)

# Filter.
#
# Note that doing the biquads in channel-order makes sure we don't data-race
# against a store from the previous biquad in a given channel.
for biquad in range(num_biquads):
    for channel in range(num_channels):
        program.extend(biquad_program(
            input_storage=sample.biquad[channel][biquad],
            output_storage=sample.biquad[channel][biquad+1],
            params=param.biquad[channel][biquad]))

def sample_addr_post_channelstrip(channel):
    return sample.biquad[channel][-1].xn

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
                      param.mixdown_gain[core][bus][channel]))
        program.append(Out(bus))

# Meter.
for channel in range(num_channels):
    # square the channel value
    channel_value_addr = sample.biquad[channel][0].xn
    squared_value_addr = sample.meter_biquad[channel][0].xn
    program.extend([
        Mul(channel_value_addr, addr_for_constant(2**-8)), # shift down to give room for squaring not to overflow.
        Mul(0, addr_for_constant(0)), # HACK to clear the accumulator. First arg doesn't matter.
        AMac(channel_value_addr),
        Store(squared_value_addr)
        ])
    program.extend(biquad_program(
        input_storage=sample.meter_biquad[channel][0],
        output_storage=sample.meter_biquad[channel][1],
        params=param.meter_biquad))
    # biquad ends with Store(yn), which preserves the accumulator, which currently contains the filtered squared value.
    program.append(Out(meter_outputs[channel]))


# Rotate sample memory by one (positive spins shift *data* to higher addresses)
program.append(Spin(1))

if __name__ == '__main__':
    with open('instr.mif', 'w') as f:
        assemble(program, f)

    print "Program length:", len(program)
