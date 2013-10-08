Functional Reactive DSP Parameter State
=======================================

Desiderata
----------

* The structure of the parameter memory mirrors the structure of the DSP program, so the two should be structured the same.
* The parameter memory state must be a function of the current control state, never dependent on the state history or the particular way that the state update may have happened.

Allocating Memory
-----------------

The value(s) in each location or range in parameter memory is a function of [a small part of] the control state. When a component requests a block of parameter memory, it provides the corresponding function. e.g., for a biquad:

    def channel_biquad_coeffs(channel, biquad, state):
        type, freq, gain, q = get_biquad_params(channel, biquad, state)
        return packed_biquad_coeffs(type, freq, gain, q)

    def get_biquad_params(channel, biquad, state):
        type = state.get(biquad_param_name(channel, biquad, 'type'), initial_type(biquad))
        freq = state.get(biquad_param_name(channel, biquad, 'freq'), initial_freq(biquad))
        gain = state.get(biquad_param_name(channel, biquad, 'gain'), 0.)
        q = state.get(biquad_param_name(channel, biquad, 'q'), INITIAL_Q)
        return type, freq, gain, q

    def channel_biquad(channel, biquad):
        params = get_block_of_param_memory('b0, b1, b2, a1, a2', partial(channel_biquad_coeffs, channel, biquad))
        ...
        program = [Mul(storage.xn2, params.a2), ...]
        return params, storage, program

As the code suggests, the `get` method of the `state` object takes an initial value for that state. I'm unsure if this is a great idea or if initial state should be specified elsewhere.

A memory block is represented as:

    size
    value_function: the function of control state that returns the current value
    addresses


Handling Updates
----------------

When a state update happens, we need to be able to efficiently update the part of the parameter memory that must change.
So we maintain a table of parameter memory blocks that are dependent on eaach control state:

    "c0/f1/gain": [<the channel biquad memory block>]
    "c0/name": []
    "b1/c0/pan": [<the mixdown gain memory block>]

This structure is constructed by the first run through the DSP program, by a special hook in the `state.get` method.

When a state update comes in, the parameter memory addresses are updated with the value_function of the new state.
