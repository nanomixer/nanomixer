#
# SPI testing utility (using spidev driver)
#
# Copyright (c) 2007  MontaVista Software, Inc.
# Copyright (c) 2007  Anton Vorontsov <avorontsov@ru.mvista.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License.
#
# Cross-compile with cross-gcc -I/path/to/cross-kernel/include
#

from cpython.string cimport PyString_FromStringAndSize
from libc.stdlib cimport malloc, free
from libc.string cimport memset
from os import open, close, O_RDWR
from posix.ioctl cimport ioctl

cdef extern from "linux/spi/spidev.h":
    struct spi_ioc_transfer:
        char *tx_buf
        char *rx_buf
        int len
        int speed_hz
        int delay_usecs
        int bits_per_word
        int cs_change
        int pad
    int SPI_IOC_MESSAGE(int num)
    int SPI_IOC_WR_MODE, SPI_IOC_RD_MODE
    int SPI_IOC_RD_MAX_SPEED_HZ, SPI_IOC_WR_MAX_SPEED_HZ
    int SPI_IOC_WR_BITS_PER_WORD, SPI_IOC_RD_BITS_PER_WORD
    int SPI_IOC_RD_LSB_FIRST, SPI_IOC_WR_LSB_FIRST

cdef class SpiChannel:
    cdef int fd, mode, bits, speed, delay, lsb_first

    def transfer(self, write_buf):
        cdef int ret
        cdef int buflen = len(write_buf)

        cdef char *_read_buf = <char *> malloc(buflen)
        read_buf = <bytes> _read_buf[:buflen] #PyString_FromStringAndSize(None, len(write_buf))
        free(_read_buf)
        cdef spi_ioc_transfer tr
        memset(&tr, 0, sizeof(tr))
        tr.tx_buf = write_buf
        tr.rx_buf = read_buf
        tr.len = len(write_buf)
        tr.delay_usecs = self.delay
        tr.speed_hz = self.speed
        tr.bits_per_word = self.bits

        ret = ioctl(self.fd, SPI_IOC_MESSAGE(1), &tr);
        if ret < 1:
            raise IOError("can't send spi message")

        return read_buf

    def __init__(self, char *device, mode=0, bits_per_word=8, speed=500000, delay=0, lsb_first=0):
        self.fd = open(device, O_RDWR)
        if self.fd < 0:
            raise IOError("can't open device")

        self.set_spi_mode(mode)
        self.set_bits_per_word(bits_per_word)
        self.set_max_speed_hz(speed)
        self.set_lsb_first(lsb_first)
        self.delay = 0

        print 'SPI mode:', self.get_spi_mode()
        print 'Bits per word:', self.get_bits_per_word()
        print 'Max speed: {} Hz ({} kHz)'.format(speed, speed/1000.)

    def set_spi_mode(self, int mode):
        self.mode = mode
        ret = ioctl(self.fd, SPI_IOC_WR_MODE, &self.mode)
        if ret == -1:
            raise IOError("can't set spi mode")

    def get_spi_mode(self):
        ret = ioctl(self.fd, SPI_IOC_RD_MODE, &self.mode)
        if ret == -1:
            raise IOError("can't get spi mode")
        return self.mode

    def close(self):
        close(self.fd)

    def set_bits_per_word(self, int bits):
        self.bits = bits
        ret = ioctl(self.fd, SPI_IOC_WR_BITS_PER_WORD, &self.bits)
        if ret == -1:
            raise IOError("can't set bits per word")

    def get_bits_per_word(self):
        ret = ioctl(self.fd, SPI_IOC_RD_BITS_PER_WORD, &self.bits)
        if ret == -1:
            raise IOError("can't get bits per word");
        return self.bits

    def set_max_speed_hz(self, speed):
        self.speed = speed
        ret = ioctl(self.fd, SPI_IOC_WR_MAX_SPEED_HZ, &self.speed)
        if ret == -1:
            raise IOError("can't set max speed hz")

    def get_max_speed_hz(self):
        ret = ioctl(self.fd, SPI_IOC_RD_MAX_SPEED_HZ, &self.speed)
        if ret == -1:
            raise IOError("can't get max speed hz")
        return self.speed

    def get_lsb_first(self):
        ret = ioctl(self.fd, SPI_IOC_RD_LSB_FIRST, &self.lsb_first)
        if ret == -1:
             raise IOError("can't get lsb-first flag")
        return self.lsb_first

    def set_lsb_first(self, lsb_first):
        self.lsb_first = lsb_first
        ret = ioctl(self.fd, SPI_IOC_WR_LSB_FIRST, &self.lsb_first)
        if ret == -1:
            raise IOError("can't set lsb-first flag")

