from flask import Flask, request, send_file
from socketio import socketio_manage
from socketio.namespace import BaseNamespace
import logging
import numpy as np
import os
import traceback

STATIC_FILES_AT = os.path.join(os.path.dirname(__file__), 'static', 'build')
NUM_CHANNELS = 16

class Resource(BaseNamespace):
    def initialize(self):
        # Called after socketio has initialized the namespace.
        self.meter_levels = np.zeros(NUM_CHANNELS)

    def disconnect(self, *a, **kw):
        super(Resource, self).disconnect(*a, **kw)

    def on_control(self, commands):
        try:
            for cmd, args in commands:
                if cmd == 'set_gain':
                    bus, channel, gain = args
                    self.meter_levels[channel] = gain

            self.emit('meter', dict(
                levels=self.meter_levels.tolist()))
        except Exception as e:
            traceback.print_exc()

# Flask routes
app = Flask(__name__)

@app.route('/')
def index():
    return send_file(os.path.join(STATIC_FILES_AT, 'index.html'))

@app.route("/socket.io/<path:path>")
def run_socketio(path):
    return socketio_manage(request.environ, {'': Resource})

if __name__ == '__main__':
    logging.basicConfig(level=logging.DEBUG)
    print 'Listening on http://localhost:8080'
    app.debug = True
    import os
    from werkzeug.wsgi import SharedDataMiddleware
    app = SharedDataMiddleware(app, {
        '/': STATIC_FILES_AT
        })
    from socketio.server import SocketIOServer
    SocketIOServer(('0.0.0.0', 8080), app,
        namespace="socket.io", policy_server=False).serve_forever()
