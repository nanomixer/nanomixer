import numpy as np
from dsp_program import mixer
import logging
import time
import json
from datetime import datetime
from spi_channel import SPIChannel
from fpga_data_link import IOThread, SPI_BUF_SIZE_IN_WORDS
from logical_to_physical import (
    get_initial_state, logical_to_physical, metadata, physical_to_logical_bus_meters, num_physical_buses)
from util import OneStepMemoizer

logger = logging.getLogger(__name__)


class InvalidSnapshot(Exception):
    pass


class Controller(object):
    def __init__(self, io_thread, snapshot_base_dir='snapshots'):
        self.io_thread = io_thread

        self.snapshot_base_dir = snapshot_base_dir
        if not os.path.exists(self.snapshot_base_dir):
            os.makedirs(self.snapshot_base_dir)

        self.state = get_initial_state(metadata)
        self.memoizer = OneStepMemoizer()

        try:
            self.load_snapshot()
            print 'Snapshot loaded.'
        except IOError:
            print 'No snapshot found.'
        except InvalidSnapshot:
            print "Not loading an initial snapshot because it's invalid."

    def load_snapshot(self, name='latest'):
        with open(os.path.join(self.snapshot_base_dir, name), 'rb') as f:
            state = json.load(f)
            if state['metadata'] != self.state['metadata']:
                raise InvalidSnapshot
            self.state.update(state)
        # You probably want to dump_state_to_mixer now.

    def save_snapshot(self):
        now = datetime.now().isoformat()
        filename = os.path.join(self.snapshot_base_dir, now)
        with open(filename, 'wb') as f:
            json.dump(self.state, f)
        new_symlink_name = os.path.join(self.snapshot_base_dir, 'latest-next')
        latest_symlink_name = os.path.join(self.snapshot_base_dir, 'latest')
        if os.path.exists(new_symlink_name):
            os.unlink(new_symlink_name)
        os.symlink(now, new_symlink_name)
        os.rename(new_symlink_name, latest_symlink_name)

    def apply_update(self, control, value):
        """
        Apply a state update.

        Returns True iff the update was handled successfully.
        """
        if control not in self.state:
            return False
        self.state[control] = value
        self._update_state()
        return True

    def get_meter(self):
        raw = self.io_thread.get_meter()[1]
        return dict(
            c=raw[:metadata['num_channels']].tolist(),
            b=physical_to_logical_bus_meters(raw[metadata['num_busses']:].tolist()))

    def dump_state_to_mixer(self):
        self._update_state()

    def _update_state(self):
        desired_param_mem = self.io_thread.desired_param_mem
        def set_memory(core, addr, data):
            desired_param_mem[int(addr):int(addr)+len(data)] = data
        logical_to_physical(self.state, mixer, set_memory, self.memoizer)
        self.memoizer.advance()


class DummyController(Controller):
    def __init__(self, *a, **kw):
        super(DummyController, self).__init__(*a, **kw)
        self.meter_levels = np.zeros(metadata['num_channels'])

    def get_meter(self):
        core = 0
        downmix_matrix = np.array([
            [self.io_thread._param_mem_contents[addr] + 1e-6 for addr in mixer.downmixes[bus].gain[core]]
            for bus in range(num_physical_buses)])

        def abs_to_db(x): return 20. * np.log10(x)
        def db_to_abs(x): return 10. ** (x / 20.)

        # Fake input levels as based on bus 0 gains.
        channels = np.arange(metadata['num_channels'])
        channel_levels = downmix_matrix[0] + db_to_abs(np.sin(2 * np.pi * (time.time() + channels / 4.)))
        bus_levels = np.dot(downmix_matrix, channel_levels)
        return dict(
            c=abs_to_db(channel_levels).tolist(),
            b=physical_to_logical_bus_meters(abs_to_db(bus_levels).tolist()))



class DummySPIChannel(object):
    buf_size_in_words = SPI_BUF_SIZE_IN_WORDS

    def transfer(self, **kw):
        import time
        time.sleep(.1)


import os
SPI_DEVICE = '/dev/spidev4.0'
ON_TGT_HARDWARE = os.path.exists(SPI_DEVICE)
if ON_TGT_HARDWARE:
    import spidev
    spi_dev = spidev.SpiChannel(SPI_DEVICE, bits_per_word=20)
    spi_channel = SPIChannel(spi_dev, buf_size_in_words=SPI_BUF_SIZE_IN_WORDS)
    controller_class = Controller
else:
    spi_channel = DummySPIChannel()
    controller_class = DummyController

io_thread = IOThread(param_mem_size=1024, spi_channel=spi_channel)
controller = controller_class(io_thread)
controller.dump_state_to_mixer()

io_thread.start()
