
from nanolang import * # Inputs, Outputs, DelayLine, Param, subscribe, saturate, ...
from biquads import normalize, peaking

# Parametrize mixer:
num_channels = 8

# Create an object with all the IO that we can import into the assembler, simulator, controller, etc.
# We can then get all the info we need about the code, bindings, etc. from the output monads.
mixerIO = {}

mixerIO.adat_in   = Inputs(range(0, num_channels))
mixerIO.adat_out  = Outputs(range(0, num_channels))
mixerIO.meter_out = Outputs(range(256, num_channels + 256)) # Look, memory mapping!

# Here's a simple multi-channel biquad:
for chan in range(num_channels):
    x = DelayLine(3)
    y = DelayLine(3)

    x[0] = mixerIO.adat_in[chan]

    # Parameters:
    @subscribe('c{}/f0/*'.format(chan))
    def compute_biquad_coeffs(state):
        b, a = peaking(
                f0     = state['c{}/f0/freq'.format(chan)], 
                dBgain = state['c{}/f0/gain'.format(chan)], 
                q      = state['c{}/f0/q'.format(chan)])
        b, a = normalize(b, a)
        return Param(b), Param(a)

    b, a = compute_biquad_coeffs()

    # DSP code:
    A  = y[2] * a[2] # could also write as A = Mul(y[2], a[2])
    A += y[1] * a[1] # could also write as A = Mac(y[1], a[1], A)
    A += x[2] * b[2]
    A += x[1] * b[1]
    A += x[0] * b[0]
    y[0] = saturate(A)

    mixerIO.adat_out = output(A)


# We can also package code into functions:
def biquad(input_sample, chan, filt):
    x = DelayLine(3)
    y = DelayLine(3)

    x[0] = input_sample

    # ...

    return y[0]
