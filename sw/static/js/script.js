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
    //socket.emit('ping', "Hello World!");
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

var app = {};
app.Filter = Backbone.Model.extend({
  defaults: {
    'freq': 440,
    'gain': 0,
    'Q': Math.sqrt(2)/2
  },
  sync: function(method, model, options) {
    console.log(this, 'sync', method, model, options);
  }
});

app.Filterbank = Backbone.Collection.extend({
  model: app.Filter,
  sync: function(method, model, options) {
    console.log(this, 'sync', method, model, options);
  }
});

app.formatGainAsTextCompact = d3.format('0.1f');

app.GainView = Backbone.View.extend({
  tagName: 'div',
  className: 'gainView',
  min: -12, max: 12,
  events: {
    'dblclick': 'zeroGain'
  },
  initialize: function() {
    var self = this; // hack
    this.listenTo(this.model, 'change', this.render);
    this.fader = $('<div>').attr('class', 'fader').appendTo(this.$el);
    this.lbl = $('<div>').attr('class', 'label').appendTo(this.fader);
    this.dragBehavior = d3.behavior.drag()
      .on('drag', function() {
        self.model.set('gain', self.pos2gain(d3.event.y));
      })
      .origin(function() { return {x: 0, y: self.gain2pos(self.model.get('gain'))}});
    d3.select(this.fader[0]).call(this.dragBehavior);
  },
  render: function() {
    //if (this.rendering) return;
    this.rendering = true;
    var gain = this.model.get('gain');
    this.fader.css('top', this.gain2pos(gain));
    this.lbl.text(app.formatGainAsTextCompact(gain));
    this.rendering = false;
    return this;
  },
  pos2gain: function(pos) {
    //console.log('pos2gain', pos);
    var totalHeight = this.$el.height(), faderHeight = this.fader.height();
    return clip(pos * (this.min - this.max) / (totalHeight - faderHeight) + this.max, this.min, this.max);
  },
  gain2pos: function(gain) {
    var totalHeight = this.$el.height(), faderHeight = this.fader.height(),
      clipGain = clip(gain, this.min, this.max);
    //console.log('gain2pos', gain, clipGain);
    return (clipGain - this.max) / (this.min - this.max) * (totalHeight - faderHeight);
  },
  zeroGain: function() {
    this.model.set('gain', 0);
  }
});

function clip(x, min, max) {
  return Math.min(Math.max(x, min), max);
}

$(function() {
  freqs = [];
  filters = [];
  views = [];
  var i;
  for (i=0; i<31; i++) {
    freqs.push(20*Math.pow(2, i/3.));
  }
  freqs.forEach(function(freq) {
    var filter, view;
    filters.push(filter = new app.Filter({freq: freq}));
    views.push(view = new app.GainView({model: filter}));
    view.$el.appendTo('#filterbank');
    setTimeout(function() {view.render();}, 10);
  })

  // Master disable scroll (seems hacky...)
  window.addEventListener('touchstart', function(e){ status('touchstart'); e.preventDefault(); });
});


