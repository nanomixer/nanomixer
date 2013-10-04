from flask import Flask, request, send_file
from socketio import socketio_manage
from socketio.namespace import BaseNamespace
import time
import logging
import numpy as np
import os
import traceback

STATIC_FILES_AT = os.path.join(os.path.dirname(__file__), 'static', 'build')
NUM_CHANNELS = 16

class Resource(BaseNamespace):
    def __init__(self, *a, **kw):
        BaseNamespace.__init__(self, *a, **kw)
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
                levels=(self.meter_levels + np.sin(2*np.pi*time.time())).tolist()))
        except Exception as e:
            traceback.print_exc()

    def on_filter(self, values):
        try:
            freq, q, gain = values
            coefficients = self.compute_peaking_params(freq, q, gain)

            self.emit('filter', dict(coefficients=list(coefficients)))
        except Exception as e:
            traceback.print_exc()

    def compute_peaking_params(self, freq, q, gain):
        clipped_freq = max(0.0, min(freq, 1.0))
        clipped_q = max(0.0, q)

        a = math.pow(10.0, gain / 40)

        if 0 < clipped_freq < 1:
            if clipped_q > 0:
                w0 = math.pi * clipped_freq
                alpha = math.sin(w0) / (2 * clipped_q)
                k = cos(w0)

                b0 = 1 + alpha * a
                b1 = -2 * k
                b2 = 1 - alpha * a
                a0 = 1 + alpha / a
                a1 = -2 * k
                a2 = 1 - alpha / a

                return self.normalize_coefficients((b0, b1, b2, a0, a1, a2))
            else:
                return self.normalize_coefficients((a * a, 0, 0, 1, 0, 0))
        else:
            return self.normalize_coefficients((1, 0, 0, 1, 0, 0))

    def normalize_coefficients(self, coefficients):
        _, _, _, a0, _, _ = coefficients
        a0_inverse = 1 / a0
        return tuple(c * a0_inverse for c in coefficients)

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
