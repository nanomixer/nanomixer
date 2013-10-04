@debug = console?.log.bind(console) ? ->
# Master disable scroll (seems hacky...)
window.addEventListener('touchmove', (e) -> e.preventDefault())


# Controllable value
controllableValue = (updateQueue, name, initial) ->
    uiVal = ko.observable initial
    serverVal = ko.observable null
    serverLastUpdate = ko.observable null

    cv = (newVal) ->
        if arguments.length
            uiVal(newVal)
            return cv
        return uiVal()

    _.extend cv, {uiVal, serverVal, serverLastUpdate}
    cv.subscribe = (args...) ->
        uiVal

    uiVal.subscribe (newVal) ->
        updateQueue[name] = newVal

    cv



winSize = {
    width: ko.observable()
    height: ko.observable()
}
winSize.rect = ko.computed ->
    {width: winSize.width(), height: winSize.height}

do ->
    updateWinSize = ->
        $window = $(window)
        winSize.width($window.width())
        winSize.height($window.height())
    updateWinSize()
    $(window).resize(_.throttle(updateWinSize, 100))
    return

cumSum = (arr) ->
    accum = 0
    for item in arr
        accum += item

MIN_FADER = -180

faderPositionToDb = d3.scale.linear()
    .range([MIN_FADER, -80, -60, -50, -40, -30, -20, -10, -5, 0, 5, 10])

faderDomain = (max=1) ->
    scale = max / 60
    (item * scale for item in cumSum([0, 1, 1.75, 3, 3, 6.75, 6.75, 7.4, 7.4, 7.5, 7.5, 7.6]))

faderLevelToText = (value) ->
    if value == MIN_FADER
        '-\u221e'
    else
        d3.round(value, 1)

ko.bindingHandlers.faderLevelText = {
    update: (element, valueAccessor) ->
        value = valueAccessor()
        text = faderLevelToText value()
        ko.bindingHandlers.text.update(element, -> text)
}

class Channel
    constructor: (@idx, @name, @eq) ->
        @signalLevel = ko.observable 0

class Bus
    constructor: (@channels, @faders) ->

class FaderView
    constructor: (@element, @model) ->
        @name = @model.channel.name
        @level = @model.level
        @posToDb = faderPositionToDb.copy().clamp(true).domain(faderDomain())
        @posToPixel = d3.scale.linear()
        @elt = d3.select(@element)
        @groove = @elt.select('.groove')
        @grip = @elt.select('.grip')

        @grooveHeight = ko.observable 20
        @gripHeight = ko.observable 20

        ctx = @elt.select('canvas').node().getContext('2d')
        ko.computed =>
            ctx.clearRect(0, 0, 1000, 1000)
            y = @posToPixel(@posToDb.invert(@model.channel.signalLevel()))
#            debug 'y=', y, 'signal=', @model.channel.signalLevel()
            gradient = ctx.createLinearGradient(0, 0, 20, @grooveHeight())
            gradient.addColorStop(0, 'rgba(255, 0, 0, .2)')
            gradient.addColorStop(.5, 'rgba(255, 255, 0, .2)')
            gradient.addColorStop(1, 'rgba(0, 255, 0, .2)')
            ctx.fillStyle = gradient
            ctx.fillRect(0, y, 1000, 1000)

        @level.subscribe @setPosition, this
        @setPosition(@level())

        @dragBehavior = d3.behavior.drag()
            .on('dragstart', -> d3.event.sourceEvent.stopPropagation()) # silence other listeners
            .on('drag', @drag)
            .origin( =>
                {x: 0, y: @posToPixel(@posToDb.invert(@level()))})
        @grip.call(@dragBehavior)

        @resize()
        winSize.rect.subscribe @resize, this

    drag: =>
        y = d3.event.y
        newVal = @posToDb(@posToPixel.invert(y))
        @level newVal

    resize: ->
        grooveHeight = $(@groove.node()).height()
        @grooveHeight grooveHeight
        gripHeight = $(@grip.node()).height()
        @gripHeight gripHeight
        @posToPixel
            .domain([0, 1])
            .range([grooveHeight+gripHeight/2, gripHeight/2])
        @setPosition @level()

        @elt.selectAll('svg.scale').remove()
        scale = @elt.append('svg').attr('class', 'scale')
            .attr('width', 20)
            .attr('height', grooveHeight + gripHeight)
            .append('g').attr('transform', 'translate(20, 0)')
        faderTicks = [MIN_FADER, -60, -50, -40, -30, -20, -10, -5, 0, 5, 10]
        faderLabels = ['\u221e', '60', '50', '40', '30', '20', '10', '5', 'U', '5', '10']

        for [dB, label] in _.zip(faderTicks, faderLabels)
            y = @posToPixel(@posToDb.invert(dB))
            scale.append('line')
                .attr('x1', -5).attr('x2', 0)
                .attr('y1', y).attr('y2', y)
            scale.append('text')
                .attr('dy', '.35em')
                .attr('text-anchor', 'end')
                .attr('x', -8)
                .attr('y', y)
                .text(label)

    gripTopForDb: (dB) ->
        Math.round(@posToPixel(@posToDb.invert(dB)) - @gripHeight()/2)

    setPosition: (dB) ->
        y = @gripTopForDb dB
        @grip.style('top', "#{y}px")


class FaderSection
    constructor: (@containerSelection, @mixer) ->
        @activeBusIdx = ko.observable 0
        @activeBus = ko.computed =>
            @mixer.buses[@activeBusIdx()]

    setActiveFaders: ->
        faders = @activeBus().faders
        sel = d3.select(@containerSelection).selectAll('.fader').data(faders, (fader) -> ko.unwrap(fader.channel.idx))
        sel.enter().append('div').attr('class', 'fader').html(faderTemplate).each((fader) ->
            @viewModel = new FaderView(this, fader)
            ko.applyBindings(@viewModel, this)
        )
        sel.exit().transition().duration(500).style('opacity', 0).remove()
    # .each((d, i) -> ko.cleanNode(@))

# Hacking in constants for the groove
faderTemplate = """
<canvas class="meter" width="20" data-bind="attr: {height: grooveHeight() + gripHeight()/2 }"></canvas>
<div class="groove"></div>
<div class="grip"></div>
<input class="name" data-bind="value: name">
"""

###### Channel View
class Eq
    constructor: (@filters) ->

class Filter
    constructor: (@freq, @gain, @q) ->

ko.bindingHandlers.dragToAdjust = {
    init: (element, valueAccesor) ->
        {value, scale} = valueAccesor()

        dragBehavior = d3.behavior.drag()
            .on('dragstart', ->
                d3.event.sourceEvent.stopPropagation() # silence other listeners
                d3.select(element).classed("adjusting", true)
            ).on('drag', =>
                value scale.invert(d3.event.y)
            ).on('dragend', ->
                d3.select(element).classed("adjusting", false)
            ).origin( =>
                {x: 0, y: scale(value())})
        d3.select(element).call(dragBehavior)

    update: (element, valueAccessor) ->
        {value} = valueAccessor()
        text = d3.round(value(), 2)
        ko.bindingHandlers.text.update(element, -> text)
}

wrapModelObservable = (model, name) ->
    ko.computed {
        read: ->
            model()[name]()
        write: (value) ->
            model()[name](value)
    }

wrapModelObservables = (viewModel, model, names) ->
    for name in names
        viewModel[name] = wrapModelObservable model, name

class FilterView
    constructor: (@element, @model) ->
        debug 'new FilterView'
        @_observables = wrapModelObservables @, @model, ['freq', 'gain', 'q']
        @freqElt = d3.select(@element).select('.freq')
        @freqToPixel = d3.scale.log().range([0, 300]).domain([20000, 20]).clamp(true)
        @gainToPixel = d3.scale.linear().domain([-20, 20]).range([200, -200]).clamp(true)
        @qToPixel = d3.scale.log().domain([.3, 3]).range([200, -200]).clamp(true)

    dispose: ->
        for observable in @_observables
            observable.dispose()
        ko.cleanNode(@element)


class ChannelSection
    constructor: (@containerSelection, @mixer) ->
        @activeChannelIdx = ko.observable null
        @activeChannel = ko.computed =>
            return unless @activeChannelIdx()?
            @mixer.channels[@activeChannelIdx()]

        @title = ko.computed =>
            return 'No channel' unless @activeChannel()?
            "Channel #{@activeChannelIdx()+1} (#{@activeChannel().name()})"

        @hasPrevChannel = ko.computed => @activeChannelIdx() > 0
        @hasNextChannel = ko.computed => @activeChannelIdx() < @mixer.channels.length - 1

        ko.computed =>
            channel = @activeChannel()
            return unless channel?
            filters = channel.eq.filters

            sel = d3.select(@containerSelection).select('#eq').selectAll('.filter').data(filters)
            sel.each((d) -> @viewModel.model(d))
            sel.enter().append('div').attr('class', 'filter').html(filterTemplate).each((filter) ->
                model = ko.observable filter
                @viewModel = new FilterView(this, model)
                ko.applyBindings(@viewModel, this)
            )
            sel.exit().each((d) -> @viewModel.dispose()).transition().duration(500).style('opacity', 0).remove()

    prevChannel: ->
        if @hasPrevChannel()
            @activeChannelIdx @activeChannelIdx() - 1

    nextChannel: ->
        if @hasNextChannel()
            @activeChannelIdx @activeChannelIdx() + 1

filterTemplate = """
<div class="freq" data-bind="dragToAdjust: {value: freq, scale: freqToPixel}"></div>
<div class="gain" data-bind="dragToAdjust: {value: gain, scale: gainToPixel}"></div>
<div class="q" data-bind="dragToAdjust: {value: q, scale: qToPixel}"></div>
"""


class UIView
    constructor: (@mixer) ->
        @activeSection = ko.computed =>
            if winSize.width() > winSize.height()
                # Landscape
                'faders'
            else
                # portrait
                'channel'
        @faderSection = new FaderSection('#faders', @mixer)
        @channelSection = new ChannelSection('#channel', @mixer)
        @meterRev = ko.observable 0

        ko.applyBindings this
        @faderSection.setActiveFaders()
        @channelSection.activeChannelIdx 0

## State management
lastSeqSent = -1
lastSeqReceived = -1
updateQueue = {}
stateFromServer = {}

socket = io.connect('');
socket.on 'connect', ->
    debug('connected!')
    lastSeqSent = -1
    sendUpdate()

socket.on 'msg', (msg) ->
    lastSeqReceived = msg.seq
    _.extend stateFromServer, msg.state
    if msg.seq == 0
        initializeMixerState(msg.state)

    for level, channelIdx in msg.meter
        mixer.channels[channelIdx].signalLevel level

    # Request another update.
    sendUpdate()
    return

# Spy globals
metadata = null
mixer = null
ui = null

initializeMixerState = (state) ->
    debug 'state', state
    metadata = state.metadata
    getCv = (name) ->
        val = state[name]
        unless val?
            alert "Missing state value: #{name}!"
            return
        controllableValue updateQueue, name, val

    channels = for chan in [0...metadata.num_channels]
        filters = for filt in [0...metadata.num_biquads_per_channel]
            new Filter(
                getCv("c#{chan}/f#{filt}/freq"),
                getCv("c#{chan}/f#{filt}/gain"),
                getCv("c#{chan}/f#{filt}/q"))
        eq = new Eq(filters)
        new Channel(chan, getCv("c#{chan}/name"), eq)
    buses = for bus in [0...metadata.num_busses]
        faders = for chan in [0...metadata.num_channels]
            {
                channel: channels[chan]
                level: getCv("b#{bus}/c#{chan}/lvl")
                pan: getCv("b#{bus}/c#{chan}/lvl")
            }
        new Bus(channels, faders)
    mixer = {channels, buses}
    ui = new UIView(mixer)


sendUpdate = ->
    socket.emit 'msg', {seq: ++lastSeqSent, state: updateQueue}
    updateQueue = {}
