from socketio.namespace import BaseNamespace
from control import controller
import traceback

class Resource(BaseNamespace):
    def __init__(self, *a, **kw):
        super(Resource, self).__init__(*a, **kw)
        self.session['response_state'] = dict(controller.state)

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

            result = dict(seq=seq, state=self.session['response_state'])

            if msg.get('snapshot', False):
                controller.save_snapshot()
                result['snapshot_saved'] = True

            result['meter'] = controller.get_meter()

            self.emit('msg', result)
            self.session['response_state'] = {}
        except Exception as e:
            traceback.print_exc()
