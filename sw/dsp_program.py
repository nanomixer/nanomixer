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

from assembler import Nop, Mul, Mac, RotMac, Store, In, Out, Spin, AMac, assemble

def biquad_program(buf_base, param_base):
    # See http://www.earlevel.com/main/2003/02/28/biquads/ but note that it has A and B backwards.
    xn, xn1, xn2, yn, yn1, yn2 = [buf_base+n for n in range(6)]
    b0, b1, b2, a1, a2, gain = [param_base+n for n in range(6)]

    # Read the old values first, so that we basically never have to stall the pipeline to wait for xn.
    return [
        Mul(yn2, a2),
        Mac(yn1, a1),
        Mac(xn2, b2),
        Mac(xn1, b1),
        Mac(xn, b0),
        Store(yn)
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


def input_addr_for_biquad(biquad, channel):
    # Each biquad stores the current and two previous input sample values.
    # Outputs, and delayed outputs, are considered to belong to the following biquad in sequence.
    return mem_per_channel*channel + 3*biquad

def output_addr_for_biquad(biquad, channel):
    # Outputs, and delayed outputs, are considered to belong to the following biquad in sequence.
    return input_addr_for_biquad(biquad+1, channel)

def parameter_base_addr_for_biquad(biquad, channel):
    return params_per_channel*channel + params_per_biquad*biquad

def address_for_mixdown_gain(channel, bus, core):
    '''returns the parameter memory address for the gain for channel on bus.'''
    return (mixdown_base_address
            + core * num_mixdown_params_per_core
            + num_channels * bus
            + channel)


# metering params
meter_biquad_param_base = mixdown_base_address + num_mixdown_params
num_meter_biquad_params = 6

# metering storage
metering_storage_base = num_channels * mem_per_channel + num_busses_per_core * sample_mem_per_bus
def input_addr_for_channel_metering_biquad(channel):
    num_biquad_storage_addresses = 6
    return metering_storage_base + num_biquad_storage_addresses*channel

def output_addr_for_channel_metering_biquad(channel):
    return input_addr_for_channel_metering_biquad(channel) + 3

# metering output
meter_out_base = 1024
def meter_out_addr_for_input_channel(channel):
    return meter_out_base + channel

def meter_out_addr_for_output_bus(bus):
    return meter_out_base + num_channels + bus


constants_base = meter_biquad_param_base + num_meter_biquad_params
def addr_for_constant(constant):
    if constant in constants:
        return constants_base + constants.index(constant)
    else:
        raise ValueError("Constant %r not defined" % constant)

program = []

# Read input into input for the zeroth biquad.
for channel in range(num_channels):
    program.append(In(io_addr=channel,
                      dest_sample_addr=input_addr_for_biquad(biquad=0, channel=channel)))

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

# Meter.
for channel in range(num_channels):
    # square the channel value
    channel_value_addr = input_addr_for_biquad(biquad=0, channel=channel)
    squared_value_addr = input_addr_for_channel_metering_biquad(channel)
    program.extend([
        Mul(channel_value_addr, addr_for_constant(2**-8)), # shift down to give room for squaring not to overflow.
        Mul(0, addr_for_constant(0)), # HACK to clear the accumulator. First arg doesn't matter.
        AMac(channel_value_addr),
        Store(squared_value_addr)
        ])
    program.extend(biquad_program(
        squared_value_addr,
        meter_biquad_param_base))
    # biquad ends with Store(yn), which preserves the accumulator, which currently contains the filtered squared value.
    program.append(Out(meter_out_addr_for_input_channel(channel)))


# Rotate sample memory by one (positive spins shift *data* to higher addresses)
program.append(Spin(1))

if __name__ == '__main__':
    with open('instr.mif', 'w') as f:
        assemble(program, f)

    print "Program length:", len(program)
