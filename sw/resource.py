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
        controller.handle_message(message, params)
        rev, meter = io_thread.get_meter()
        if rev > self.last_meter_sent:
            self.last_meter_sent = rev
            self.emit('meter', pack_meter_packet(meter))
