## Views
class OSCServer(object):
    def __init__(self, controller, osc_port=7559):
        import OSC
        self.controller = controller
        self.osc_server = OSC.OSCServer(('0.0.0.0', osc_port), None, osc_port - 1)
        for channel in range(1, 6):
            self.osc_server.addMsgHandler('/4/gain/{}'.format(channel), self.setFiltGain)
        self.osc_server.addMsgHandler('/4/loslvfrq', self.setFreq)

        for channel in range(8):
            self.osc_server.addMsgHandler('/1/volume{}'.format(channel+1), self.setGain)


    def setGain(self, addr, tags, data, client_addr):
        # Ignore this if we'd just overwrite it in a moment
        # TODO: improve this logic!
        if self._data_ready():
            return
        channel = int(addr[-1])-1
        gain = data[0]
        self.controller.set_gain(0, 0, 0, channel, gain)

    def setFiltGain(self, addr, tags, data, client_addr):
        if self._data_ready():
            return
        channel = int(addr.rsplit('/', 1)[1]) - 1
        gain = 40*(data[0]-.5)
        self.controller.set_biquad_gain(0, channel, 0, gain)

    def setFreq(self, addr, tags, data, client_addr):
        if self._data_ready():
            return
        print addr
        freq = 20 * 2**(data[0]*10)
        channel = 0
        print freq
        self.controller.set_biquad_freq(0, channel, 0, freq)

    def _data_ready(self):
        self.osc_server.socket.setblocking(False)
        try:
            dataReady = self.osc_server.socket.recv(1, socket.MSG_PEEK)
        except:
            dataReady = False
        self.osc_server.socket.setblocking(True)
        return dataReady

    def serve_forever(self):
        try:
            self.osc_server.serve_forever()
        except:
            self.osc_server.socket.close()
            self.controller.memif_socket.close()
            raise
