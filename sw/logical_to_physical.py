import numpy as np
from biquads import normalize, filter_types
from dsp_program import (
    HARDWARE_PARAMS,
    constants, meter_filter_param_base, StateVarFilter)

METERING_LPF_PARAMS = dict(
    Fc=7.5,
    Q=np.sqrt(2.)/2.,
    Fs=48000)

WORDS_PER_CORE = 1024 # FIXME !
MIN_FADER = -180.

def pack_biquad_coeffs(b, a):
    return [b[0], b[1], b[2], -a[1], -a[2]]

# Panning
PAN_LAW_DB = 3.
panning_exponent = PAN_LAW_DB / (20*np.log10(2.))


# Just using a class so that state_names.bus works.
class state_names(object):
    bus = 'b{bus}/{param}'
    channel = 'c{channel}/{param}'
    fader = 'b{bus}/c{channel}/{param}'
    channel_filter = 'c{channel}/f{filt}/{param}'
    bus_filter = 'b{bus}/f{filt}/{param}'


logical_bus_to_physical_bus_mapping = [
    [0, 1],
    [2],
    [3],
    [4],
    [5],
    [6],
    [7],
]


def invert_mapping(logical_bus_to_physical_bus_mapping, num_physical_buses):
    logical_bus_for_physical_bus = [None] * num_physical_buses
    for logical_bus, physical_buses in enumerate(logical_bus_to_physical_bus_mapping):
        for physical_bus in physical_buses:
            logical_bus_for_physical_bus[physical_bus] = logical_bus
    return logical_bus_for_physical_bus

num_physical_buses = HARDWARE_PARAMS['num_busses_per_core'] * HARDWARE_PARAMS['num_cores']

logical_bus_for_physical_bus = invert_mapping(logical_bus_to_physical_bus_mapping, num_physical_buses)


metadata = dict(
    num_busses=len(logical_bus_to_physical_bus_mapping),
    num_channels=HARDWARE_PARAMS['num_cores'] * HARDWARE_PARAMS['num_channels_per_core'],
    num_biquads_per_channel=HARDWARE_PARAMS['num_biquads_per_channel'],
    num_biquads_per_bus=HARDWARE_PARAMS['num_biquads_per_bus'])

initial_filter_frequencies = [250, 500, 1000, 6000, 12000]
solo_bus_index = len(logical_bus_to_physical_bus_mapping) - 1


def get_initial_state(metadata):
    state = {}

    def set_state_params(name_format, base_kv, **kw):
        for k, v in kw.iteritems():
            name = name_format.format(param=k, **base_kv)
            state[name] = v

    for bus in range(metadata['num_busses']):
        if bus == 0:
            name = "Master"
        elif bus == solo_bus_index:
            name = "Solo"
        else:
            name = "Aux {}".format(bus)
        # Masters
        set_state_params(state_names.bus, dict(bus=bus), name=name, lvl=0., pan=0.)

        # Downmix
        for channel in range(metadata['num_channels']):
            set_state_params(state_names.fader, dict(bus=bus, channel=channel), lvl=MIN_FADER, pan=0.)

        # Bus filters
        for filt, freq in enumerate(initial_filter_frequencies):
            assert metadata['num_biquads_per_bus'] == len(initial_filter_frequencies)
            if filt == 0:
                typ = 'lowshelf'
            elif filt == len(initial_filter_frequencies) - 1:
                typ = 'highshelf'
            else:
                typ = 'peaking'
            set_state_params(state_names.bus_filter, dict(bus=bus, filt=filt),
                type=typ, freq=freq, gain=0., q=np.sqrt(2.)/2)


    for channel in range(metadata['num_channels']):
        assert metadata['num_biquads_per_channel'] == len(initial_filter_frequencies)
        set_state_params(state_names.channel, dict(channel=channel), name="Ch{}".format(channel+1), mute=True, pfl=False)

        for filt, freq in enumerate(initial_filter_frequencies):
            if filt == 0:
                typ = 'lowshelf'
            elif filt == len(initial_filter_frequencies) - 1:
                typ = 'highshelf'
            else:
                typ = 'peaking'
            set_state_params(state_names.channel_filter, dict(channel=channel, filt=filt),
                type=typ, freq=freq, gain=0., q=np.sqrt(2.)/2)

    state['metadata'] = metadata

    return state


def compute_biquad_param_mem(typ, **kw):
    b, a = filter_types[typ](**kw)
    b, a = normalize(b, a)
    return pack_biquad_coeffs(b, a)


def logical_to_physical(state, mixer, set_memory, memoizer):
    """
    State comes in as logical, here we figure out how to set_memory in the physical mixer to match.
    """

    def get_state_param(name_format, base_kv, param):
        assert isinstance(param, basestring)
        return state[name_format.format(param=param, **base_kv)]

    def get_state_params(name_format, base_kv, params):
        assert not isinstance(params, basestring)
        return [get_state_param(name_format, base_kv, param) for param in params]

    # TODO: grab this from metadata?
    num_physical_buses = len(mixer.downmixes)

    # Channel filters
    for channel, biquad_chain in enumerate(mixer.channel_biquads):
        for biquad_idx, biquad_params in enumerate(biquad_chain.params):
            typ, freq, gain, q = get_state_params(state_names.channel_filter, dict(channel=channel, filt=biquad_idx), ['type', 'freq', 'gain', 'q'])

            set_memory(
                core=0,  # hardcoded, until we can test multi-core and get the right abstraction.
                addr=biquad_params[0].addr,
                data=memoizer.get(compute_biquad_param_mem, typ=typ, f0=freq, dBgain=gain, q=q))

    # Bus filters
    for physical_bus, bus_strip in enumerate(mixer.bus_strips):
        for biquad_idx, biquad_params in enumerate(bus_strip.biquad_chain.params):
            logical_bus = logical_bus_for_physical_bus[physical_bus]
            typ, freq, gain, q = get_state_params(state_names.bus_filter, dict(bus=logical_bus, filt=biquad_idx), ['type', 'freq', 'gain', 'q'])

            set_memory(
                core=0,  # hardcoded, until we can test multi-core and get the right abstraction.
                addr=biquad_params[0].addr,
                data=memoizer.get(compute_biquad_param_mem, typ=typ, f0=freq, dBgain=gain, q=q))

    # Downmix buses
    num_downmix_channels = len(mixer.downmixes[0].gain[0]) # FIXME: hardcoded core 0.
    gain_for_physical_bus = np.zeros((num_physical_buses, num_downmix_channels))

    for logical_bus, physical_buses in enumerate(logical_bus_to_physical_bus_mapping):
        bus_output_level = get_state_param(state_names.bus, dict(bus=logical_bus), 'lvl')
        absBusFaderLevel = 10. ** (bus_output_level / 20.)
        for channel in xrange(num_downmix_channels):
            if logical_bus == solo_bus_index:
                # Solo bus is entirely controlled by PFLs. Notably, independent of muting.
                absLevel = 1. if get_state_param(state_names.channel, dict(channel=channel), 'pfl') else 0
            elif get_state_param(state_names.channel, dict(channel=channel), 'mute'):
                absLevel = 0
            else:
                # Combine the effect of the bus fader with the channel fader to get the gain matrix entry.
                level = get_state_param(state_names.fader, dict(bus=logical_bus, channel=channel), 'lvl')
                absLevel = 10. ** (level/20.) * absBusFaderLevel
            if len(physical_buses) == 1:
                # Mono.
                gain_for_physical_bus[physical_buses[0], channel] = absLevel
            else:
                # Stereo: compute panning (0 = center).
                pan = get_state_param(state_names.fader, dict(bus=logical_bus, channel=channel), 'pan')
                left, right = physical_buses
                gain_for_physical_bus[left , channel] = absLevel * (.5 - pan) ** panning_exponent
                gain_for_physical_bus[right, channel] = absLevel * (.5 + pan) ** panning_exponent

    for bus, downmix in enumerate(mixer.downmixes):
        gain_addresses = downmix.gain[0] #  FIXME: hardcoded core 0
        for channel, gain_addr in enumerate(gain_addresses):
            set_memory(
                core=0,  # hardcoded, until we can test multi-core and get the right abstraction.
                addr=gain_addr,
                data=[gain_for_physical_bus[bus, channel]])


    for core in xrange(HARDWARE_PARAMS['num_cores']):
        # Set constants.
        set_memory(
            core=core,
            addr=constants.base,
            data=constants.constants)

        # Special metering filter.
    set_memory(core=core, addr=meter_filter_param_base, data=StateVarFilter.encode_params(**METERING_LPF_PARAMS))

