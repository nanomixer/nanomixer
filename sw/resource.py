from socketio.namespace import BaseNamespace
from socketio.mixins import BroadcastMixin
from control import controller, io_thread
import traceback
import numpy as np
from pprint import pprint

class Resource(BaseNamespace, BroadcastMixin):
    def initialize(self):
        # Called after socketio has initialized the namespace.
        self.last_meter_sent = -1

    def disconnect(self, *a, **kw):
        super(Resource, self).disconnect(*a, **kw)

    def on_control(self, commands):
        if commands:
            pprint(commands)
        try:
            for cmd, args in commands:
                if cmd == 'set_gain':
                    bus, channel, gain = args
                    controller.set_gain(bus, channel, gain)
                elif cmd == 'set_biquad':
                    #channel, biquad, freq, gain, q = args
                    controller.set_biquad(*args)
                else:
                    print 'Unknown command', cmd

            response = dict()#seq=params['seq'])
            rev, meter = io_thread.get_meter()
            if rev > self.last_meter_sent:
                response['levels'] = meter[:8].tolist()
                self.last_meter_sent = rev
            self.emit('meter', response)

        except Exception as e:
            traceback.print_exc()
