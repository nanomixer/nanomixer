import os
from gevent import monkey; monkey.patch_socket()
from flask import Flask, request, send_file
from socketio import socketio_manage
from resource import Resource
import logging

STATIC_FILES_AT = os.path.join(os.path.dirname(__file__), 'static', 'public')

# Flask routes
app = Flask(__name__)

@app.route('/')
def index():
    return send_file(os.path.join(STATIC_FILES_AT, 'index.html'))

@app.route("/socket.io/<path:path>")
def run_socketio(path):
    socketio_manage(request.environ, {'': Resource})
    return 'out'

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
