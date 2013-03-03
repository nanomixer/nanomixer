from socketio.namespace import BaseNamespace
from socketio.mixins import BroadcastMixin
from control import controller

class Resource(BaseNamespace, BroadcastMixin):
    def initialize(self):
        # Called after socketio has initialized the namespace.
        pass

    def disconnect(self, *a, **kw):
        super(Resource, self).disconnect(*a, **kw)

    def on_control(self, message, params):
        controller.handle_message(message, params)
