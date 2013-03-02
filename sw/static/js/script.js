function status(x) {
  console.log('status', x);
  $('#status').text(x);
}

$(document).ready(function() {

  status('connecting...');
  WEB_SOCKET_DEBUG = true;
  socket = io.connect("");

  socket.on('connect', function() {
    status('connected');
    socket.emit('ping', "Hello World!");
  });
  socket.on('reconnect', function () {
    status('reconnected');
  });
  socket.on('reconnecting', function (msec) {
    status('reconnecting in '+(msec/1000)+'sec ... ');
    $("#status").append($('<a href="#">').text("Try now").click(function(evt) {
      evt.preventDefault();
      socket.socket.reconnect();
    }));
  });
  socket.on('connect_failed', function() { status('Connect failed.'); });
  socket.on('reconnect_failed', function() { status('Reconnect failed.'); });
  socket.on('error', function (e) { status('Error: '+ e); });

  socket.on('pong', function(arg) {
    status("Pong! "+arg);
  });

});
