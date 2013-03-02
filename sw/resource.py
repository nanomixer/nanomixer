from socketio.namespace import BaseNamespace
from socketio.mixins import BroadcastMixin

class Resource(BaseNamespace, BroadcastMixin):
    def initialize(self):
        # Called after socketio has initialized the namespace.
        pass

    def disconnect(self, *a, **kw):
        super(Resource, self).disconnect(*a, **kw)

    def on_ping(self, param):
        self.emit('pong', param)
