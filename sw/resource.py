from socketio.namespace import BaseNamespace
from socketio.mixins import BroadcastMixin
from control import controller, io_thread, pack_meter_packet


class Resource(BaseNamespace, BroadcastMixin):
    def initialize(self):
        # Called after socketio has initialized the namespace.
        self.last_meter_sent = -1

    def disconnect(self, *a, **kw):
        super(Resource, self).disconnect(*a, **kw)

    def on_control(self, message, params):
        for cmd, args in params['commands']:
            controller.handle_message(cmd, args)

        response = dict(seq=params['seq'])
        rev, meter = io_thread.get_meter()
        if rev > self.last_meter_sent:
            response['meter'] = pack_meter_packet(rev, meter)
            self.last_meter_sent = rev
        self.emit('response', response)
