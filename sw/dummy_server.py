from flask import Flask, request, send_file
from socketio import socketio_manage
from socketio.namespace import BaseNamespace
import time
import logging
import numpy as np
import os
import traceback
import control

STATIC_FILES_AT = os.path.join(os.path.dirname(__file__), 'static', 'build')

import re
fader_re = re.compile(r'^b(?P<bus>\d+)/c(?P<chan>\d+)/(?P<param>lvl|pan)$')
filter_re = re.compile(r'^c(?P<chan>\d+)/f(?P<filt>\d+)/(?P<param>freq|gain|q)$')

class DummyController(object):
    def __init__(self):
        self.full_state = {}
        hwparams = control.HARDWARE_PARAMS
        self.full_state['metadata'] = metadata = dict(
            num_busses=hwparams['num_cores'] * hwparams['num_busses_per_core'],
            num_channels=hwparams['num_cores'] * hwparams['num_channels_per_core'],
            num_biquads_per_channel=hwparams['num_biquads_per_channel'])
        for bus in range(metadata['num_busses']):
            for channel in range(metadata['num_channels']):
                self.full_state['b{bus}/c{chan}/lvl'.format(bus=bus, chan=channel)] = 0.
                self.full_state['b{bus}/c{chan}/pan'.format(bus=bus, chan=channel)] = 0.
        for channel in range(metadata['num_channels']):
            assert metadata['num_biquads_per_channel'] == 5
            for filt, freq in enumerate([250, 500, 1000, 6000, 12000]):
                for param, val in [('freq', freq), ('gain', 0.), ('q', np.sqrt(2.)/2)]:
                    self.full_state['c{chan}/f{filt}/{param}'.format(chan=channel, filt=filt, param=param)] = val
            self.full_state["c{chan}/name".format(chan=channel)] = "Ch{}".format(channel+1)
        self.routes = [
            [fader_re, self.set_fader],
            [filter_re, self.set_filter]]

        self.meter_levels = np.zeros(metadata['num_channels'])

    def apply_update(self, control, value):
        """
        Apply a state update.

        Returns True iff the update was handled successfully.
        """
        for pattern, func in self.routes:
            match = pattern.match(control)
            if match is None:
                continue
            func(val=value, **match.groupdict())
            self.full_state[control] = value
            return True
        # No match.
        return False

    def set_fader(self, bus, chan, param, val):
        bus = int(bus)
        chan = int(chan)
        if param == 'lvl':
            print 'set_fader', bus, chan, param, val
            #absVal = np.pow(10., val/20.)
            self.meter_levels[chan] = val
        elif param == 'pan':
            print 'pan'

    def set_filter(self, chan, filt, param, val):
        chan = int(chan)
        filt = int(filt)
        print 'filt', chan, filt, param, val


controller = DummyController()


class Resource(BaseNamespace):
    def __init__(self, *a, **kw):
        super(Resource, self).__init__(*a, **kw)
        self.session['response_state'] = dict(controller.full_state)

    def disconnect(self, *a, **kw):
        super(Resource, self).disconnect(*a, **kw)

    def set_all_response_states(self, control, value):
        # This feels hacky, but it's how https://github.com/abourget/gevent-socketio/blob/master/socketio/mixins.py does it.
        for sessid, socket in self.socket.server.sockets.iteritems():
            response_state = socket.session.get('response_state', None)
            if response_state is None:
                continue
            response_state[control] = value

    def on_msg(self, msg):
        try:
            seq = msg['seq']
            for control, value in msg['state'].iteritems():
                handled = controller.apply_update(control, value)
                if handled:
                    self.set_all_response_states(control, value)
                else:
                    print "Oops, couldn't handle", control, value



            self.emit('msg', dict(
                seq=seq,
                state=self.session['response_state'],
                meter=(controller.meter_levels + np.sin(2*np.pi*time.time())).tolist()))
            self.session['response_state'] = {}
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
