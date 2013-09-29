import numpy as np
from wireformat import fixeds_to_spi, spi_to_fixeds

SPI_BYTES_PER_WORD = 8


class SPIChannel(object):
    def __init__(self, dev, buf_size_in_words):
        self.dev = dev
        self.buf_size_in_words = buf_size_in_words
        # Account for the two address words at the beginning of each transmission.
        self.write_buf = np.empty((buf_size_in_words + 2) * SPI_BYTES_PER_WORD, dtype=np.uint8)
        self.read_buf = np.empty((buf_size_in_words + 2) * SPI_BYTES_PER_WORD, dtype=np.uint8)
        self._addresses = np.empty(2, dtype=np.uint64)

    def transfer(self, read_addr, read_data, write_addr, write_data):
        buf_len_words = len(write_data)
        if len(read_data) != buf_len_words:
            raise ValueError("Read and write buffer sizes must match.")
        buf_len_bytes = SPI_BYTES_PER_WORD * buf_len_words
        address_offset_bytes = 2 * SPI_BYTES_PER_WORD

        # Build the data packet: read addr, write addr, data.
        write_buf = self.write_buf[:address_offset_bytes + buf_len_bytes]
        read_buf = self.read_buf[:address_offset_bytes + buf_len_bytes]
        self._addresses[0] = read_addr
        self._addresses[1] = write_addr
        fixeds_to_spi(self._addresses, self.write_buf[:address_offset_bytes])
        fixeds_to_spi(write_data, write_buf[address_offset_bytes:])

        # Do transfer.
        self.dev.transfer(write_buf, read_buf)

        # Unpack results
        spi_to_fixeds(read_buf[address_offset_bytes:], read_data)
