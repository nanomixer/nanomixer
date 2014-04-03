import numpy as np
import random
import wireformat
import threading
import collections

from dsp_program import HARDWARE_PARAMS


import logging
logger = logging.getLogger(__name__)


# Number formats
PARAM_WIDTH = 36
PARAM_INT_BITS = 5
PARAM_FRAC_BITS = 30
METER_WIDTH = 36
METER_FRAC_BITS = 30
METER_SIGN_BIT = 35


METERING_CHANNELS = HARDWARE_PARAMS['num_channels_per_core'] + HARDWARE_PARAMS['num_busses_per_core']
METERING_PACKET_SIZE = METERING_CHANNELS
SPI_BUF_SIZE_IN_WORDS = METERING_PACKET_SIZE


class IOThread(threading.Thread):
    def __init__(self, param_mem_size, spi_channel):
        threading.Thread.__init__(self, name='IOThread')
        self.daemon = True
        self._shutdown = False
        self.spi_channel = spi_channel
        self.spi_words = spi_channel.buf_size_in_words
        self._param_mem_contents = np.zeros(param_mem_size, dtype=np.float64)
        self._param_mem_dirty = np.zeros(param_mem_size, dtype=np.uint8)
        self._meter_revision = -1
        self._meter_mem_contents = (
            self._meter_revision, np.zeros(METERING_PACKET_SIZE, dtype=np.float64))
        self._write_queue = collections.deque()

        # Buffers in terms of words.
        self._write_buf = np.empty(self.spi_words, dtype=np.uint64)
        self._read_buf = np.empty(self.spi_words, dtype=np.uint64)

    def __setitem__(self, addr, data):
        # TODO: de-dupe / only keep the latest thing to write, and don't write things that are the same as what's already there.
        self._write_queue.append((addr, data))

    def get_meter(self):
        return self._meter_mem_contents

    def shutdown(self):
        self._shutdown = True

    def handle_queued_memory_mods(self):
        while True:
            try:
                item = self._write_queue.popleft()
            except IndexError:
                break
            addr, data = item
            self._param_mem_contents[addr] = data
            self._param_mem_dirty[addr] = 1

    def dump_to_mif(self, outfile):
        self.handle_queued_memory_mods()
        write_buf = np.empty(len(self._param_mem_contents), dtype=np.uint64)
        wireformat.floats_to_fixeds(self._param_mem_contents, PARAM_INT_BITS, PARAM_FRAC_BITS, write_buf.view(np.int64))
        print >>outfile, "DEPTH = {};".format(len(write_buf))
        print >>outfile, "WIDTH = {};".format(36)
        print >>outfile, "ADDRESS_RADIX = HEX;"
        print >>outfile, "DATA_RADIX = HEX;"
        print >>outfile, "CONTENT BEGIN"
        for addr, val in enumerate(write_buf):
            fmt_val = '{:09x}'.format(val)
            # But if it was negative, it's too wide.
            fmt_val = fmt_val[-9:]
            print >>outfile, '{:02x} : {};'.format(addr, fmt_val)
        print >>outfile, "END;"


    def do_send_recvs(self):
        meter_packet = np.zeros(METERING_PACKET_SIZE, dtype=np.float64)
        first_meter_index_needed = 0
        while True:
            dirty = self._param_mem_dirty.nonzero()[0]
            meter_words_desired = METERING_PACKET_SIZE - first_meter_index_needed
            if len(dirty) == 0:
                if meter_words_desired <= 0:
                    # All sending and receiving this time is complete.
                    break
                # Otherwise, pick a random address to start from
                first_param_send_index = random.randrange(max(0, len(self._param_mem_contents) - self.spi_words))
            else:
                first_param_send_index = dirty[0]
            param_data_to_send = self._param_mem_contents[first_param_send_index:]
            if len(param_data_to_send) > self.spi_words:
                param_data_to_send = param_data_to_send[:self.spi_words]
            words_in_transfer = len(param_data_to_send)

            read_buf = self._read_buf[:words_in_transfer]

            # Unpack floats into fixed point in the write buffer.
            write_buf = self._write_buf[:words_in_transfer]
            wireformat.floats_to_fixeds(param_data_to_send, PARAM_INT_BITS, PARAM_FRAC_BITS, write_buf.view(np.int64))

            #print '{} @ rd: {} wr: {}'.format(words_in_transfer, first_meter_index_needed, first_param_send_index)
            self.spi_channel.transfer(
                read_addr=first_meter_index_needed,
                read_data=read_buf,
                write_addr=first_param_send_index,
                write_data=write_buf)

            # Mark param memory segment not dirty.
            self._param_mem_dirty[first_param_send_index:first_param_send_index+words_in_transfer] = 0

            # Extract the metering data we got.
            meter_vals_read = read_buf[:meter_words_desired]
            wireformat.sign_extend(meter_vals_read, METER_SIGN_BIT)
            wireformat.fixeds_to_floats(
                meter_vals_read.view(np.int64),
                METER_FRAC_BITS,
                meter_packet[first_meter_index_needed:first_meter_index_needed+len(meter_vals_read)])
            # TODO: wraparound, since the meter data at the beginning of the packet is going to be newer.
            first_meter_index_needed += words_in_transfer
            break # FIXME.

        self._meter_revision += 1

        np.maximum(2**-METER_FRAC_BITS, meter_packet, out=meter_packet)
        # meter packet contains LPF of square of signal value right-shifted by 2 bits.
        # So: correct for the shift, correct for the crest factor, sqrt, and convert to dB.
        meter_values = 20 * np.log10(np.sqrt(meter_packet * 2**2 * 2))
        self._meter_mem_contents = (self._meter_revision, meter_values)


    def run(self):
        logger.info('IO thread started')
        while True:
            if self._shutdown:
                return

            # Handle queued memory modifications
            self.handle_queued_memory_mods()

            # Do SPI send-recv's
            self.do_send_recvs()

