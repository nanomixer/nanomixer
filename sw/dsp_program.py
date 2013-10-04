# Throughout, doing things in channel order makes sure that the data for every
# individual channel will be ready by the time we need it. If a core is ever
# processing just a single channel, NOTE that this may need to be revised.

from assembler import Nop, Mul, Mac, RotMac, Store, In, Out, Spin, AMac, AuxOut, assemble, Addr, assign_addresses
from util import flattened, roundrobin
from collections import namedtuple
import numpy as np


class Component(object):
    # Components have storage, params, and program.
    pass


class Constants(Component):
    def __init__(self, constants):
        self.constants = constants
        self.storage = []
        self.params = [Addr() for i in range(len(constants))]
        self.program = []
        self.base = self.params[0]

    def addr_for(self, constant):
        if constant in self.constants:
            return self.params[self.constants.index(constant)]
        else:
            # TODO: add it!
            raise ValueError("Constant %r not defined" % constant)


class Nops(Component):
    def __init__(self, n):
        self.storage = self.params = []
        self.program = [Nop()] * n

class Input(Component):
    def __init__(self, channel, dest):
        self.storage = self.params = []
        self.program = [In(io_addr=channel, dest_sample_addr=dest)]


class BiquadChain(Component):
    Storage = namedtuple('BiquadStorage', 'xn, xn1, xn2')
    Params = namedtuple('BiquadParams', 'b0, b1, b2, a1, a2')

    def __init__(self, n, params=None):
        # Params can be passed to share parameter memory.
        self.storage = [self.make_storage() for i in xrange(n + 1)]
        self.params = params or [self.make_params() for i in xrange(n)]
        self.input = self.storage[0].xn
        self.output = self.storage[-1].xn

        # See http://www.earlevel.com/main/2003/02/28/biquads/ but note that it has A and B backwards.
        # Also note that 'a' values are negative relative to the usual formulas.
        # Read the old values first, so that we basically never have to stall the pipeline to wait for xn.
        program = []
        for input_storage, output_storage, params in zip(self.storage[:-1], self.storage[1:], self.params):
            program.append([
                Mul(output_storage.xn2, params.a2),
                Mac(output_storage.xn1, params.a1),
                Mac(input_storage.xn2, params.b2),
                Mac(input_storage.xn1, params.b1),
                Mac(input_storage.xn, params.b0),
                Store(output_storage.xn)
            ])
        self.program = program

    @classmethod
    def make_storage(cls):
        return cls.Storage._make([Addr() for i in xrange(3)])

    @classmethod
    def make_params(cls):
        return cls.Params._make([Addr() for i in xrange(5)])


class SingleBiquad(Component):
    def __init__(self, params=None):
        self.chain = BiquadChain(1, params=None if params is None else [params])
        self.input = self.chain.input
        self.output = self.chain.output
        self.storage = self.chain.storage
        self.params = self.chain.params[0]
        self.program = self.chain.program


def Load(sample_addr):
    return Mul(sample_addr, constants.addr_for(1.))


class StateVarFilter(Component):
    Storage = namedtuple('SVStorage', 'xn, ln, ln1, bn, bn1')
    Params = namedtuple('SVParams', 'f, nf, oneminusfq')

    def __init__(self, params=None):
        # Based on http://www.earlevel.com/main/2003/03/02/the-digital-state-variable-filter/
        # See also https://ccrma.stanford.edu/~jos/svf/Digitization_Second_Order_Continuous_Time_Lowpass.html
        self.storage = storage = self.make_storage()
        self.params = params = self.make_params() if params is None else params
        self.input = self.storage.xn
        self.output = self.storage.ln

        self.program = [
            Load(storage.ln1),
            Mac(storage.bn1, params.f),
            Store(storage.ln),
            Nop(),
            Nop(),
            Mul(storage.bn1, params.oneminusfq),
            Mac(storage.xn, params.f),
            Mac(storage.ln, params.nf),
            Store(storage.bn)
        ]

    @classmethod
    def make_storage(cls):
        return cls.Storage._make([Addr() for i in xrange(5)])

    @classmethod
    def make_params(cls):
        return cls.Params._make([Addr() for i in xrange(3)])

    @classmethod
    def encode_params(cls, Fc, Q, Fs):
        """
        Encode filter parameters in the way we'll store them in memory.

        Fc = filter corner frequency
        Q = filter Q ("normally 0.5 to infinity")
        Fs = sampling rate
        """
        f = 2 * np.sin(np.pi * float(Fc) / Fs)
        q = 1. / Q
        return [f, -f, 1 - f * q]


class RoundRobin(Component):
    def __init__(self, components):
        self.params = pluck('params', components)
        self.storage = pluck('storage', components)
        program_parts = pluck('program', components)
        self.program = list(roundrobin(*program_parts))


class Downmix(object):
    storage = []

    def __init__(self, channel_samples):
        self.gain = [
            [[Addr() for channel in range(num_channels)]
             for bus in range(num_busses_per_core)]
            for core in range(num_cores)]
        self.params = self.gain
        program = []
        # FIXME: I think bus needs to be the outer loop.
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
                        instr(channel_samples[channel],
                              self.gain[core][bus][channel]))
                program.append(Out(bus))
        self.program = program


class Meter(object):
    def __init__(self, input, output, params):
        self.filter = StateVarFilter(params=params)
        self.storage = self.filter.storage
        self.params = self.filter.params
        self.output = output
        self.program = [
            Mul(input, constants.addr_for(2**-2)), # shift down to give room for squaring not to overflow.
            Mul(0, constants.addr_for(0)), # HACK to clear the accumulator. First arg doesn't matter.
            AMac(input),
            Store(self.filter.input)
        ] + self.filter.program + [
            Load(self.filter.output),
            AuxOut(self.output)
        ]


num_channels = 8

# channel strip
num_biquads = 5

# mixdown
num_cores = 1
num_busses_per_core = 8
sample_mem_per_bus = 0 # for now.

HARDWARE_PARAMS = dict(
    num_cores=num_cores,
    num_busses_per_core=num_busses_per_core,
    num_channels_per_core=num_channels,
    num_biquads_per_channel=num_biquads)

meter_outputs = [Addr() for channel in range(num_channels)]
assign_addresses(meter_outputs, start_address=512)

constants = Constants([0., 1., 2**-2])

class Mixer(Component):
    def __init__(self):
        biquads = self.biquads = [BiquadChain(num_biquads) for channel in range(num_channels)]
        inputs = self.inputs = [Input(channel, biquads[channel].input) for channel in range(num_channels)]

        # FIXME: will probably become by bus.
        downmix = self.downmix = Downmix([biquads[channel].output for channel in range(num_channels)])

        # Meter.
        meter_filter_params = self.meter_filter_params = StateVarFilter.make_params()
        meters = self.meters = [Meter(biquads[channel].input, meter_outputs[channel], meter_filter_params) for channel in range(num_channels)]

        components = [inputs, Nops(3), RoundRobin(biquads), downmix, meters, constants]
        flat_components = list(flattened(components))

        self.program = list(flattened(pluck('program', flat_components)))
        # Rotate sample memory by one (positive spins shift *data* to higher addresses)
        self.program.append(Spin(1))
        self.params = pluck('params', flat_components)
        self.storage = pluck('storage', flat_components)


def pluck(attr, lst):
    return [getattr(item, attr) for item in lst]


mixer = Mixer()

next_param_addr = assign_addresses(mixer.params, 0)
next_sample_addr = assign_addresses(mixer.storage, 0)


##
## Exports
##
def parameter_base_addr_for_biquad(channel, biquad):
    return mixer.biquads[channel].params[biquad][0].addr

def address_for_mixdown_gain(core, channel, bus):
    return mixer.downmix.gain[core][bus][channel].addr

constants_base = constants.base
meter_filter_param_base = mixer.meter_filter_params[0].addr


if __name__ == '__main__':
    with open('instr.mif', 'w') as f:
        assemble(mixer.program, f)

    print "Program length:", len(mixer.program)
    print "Used", next_param_addr, "params and", next_sample_addr, "sample memory addresses."