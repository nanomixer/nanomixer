@debug = console?.log.bind(console) ? ->
# Master disable scroll (seems hacky...)
window.addEventListener('touchmove', (e) -> e.preventDefault())

updateQueue = {}
checkpoint = false

# Extends an observable with the aspect of maintaining server state.
# FIXME: currently references the global update queue. Or maybe that's okay.
controllableValue = (name, initial) ->
    uiVal = ko.observable initial
    serverVal = ko.observable null
    serverLastUpdate = ko.observable null
    grabbed = ko.observable false
    sendInterlock = 0

    _.extend uiVal, {paramName: name, serverVal, serverLastUpdate, grabbed}
    uiVal.subscribe (newVal) ->
        return if sendInterlock
        debug 'update:', name, newVal
        updateQueue[name] = newVal
    uiVal.updateWithoutSending = (newVal) ->
        sendInterlock++
        uiVal newVal
        sendInterlock--
        uiVal
    grabbed.subscribe (newVal) ->
        if not newVal
            checkpoint = true
    uiVal


wrapModelObservable = (model, name) ->
    ko.computed {
        read: ->
            ko.unwrap(model()[name])
        write: (value) ->
            model()[name](value)
    }

wrapModelObservables = (viewModel, model, names) ->
    for name in names
        viewModel[name] = wrapModelObservable model, name


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
    constructor: (@channels, @faders, @masterFader, @name) ->

class BaseViewModel
    dispose: ->
        for observable in @_observables
            observable.dispose()
        ko.cleanNode(@element)

D = React.DOM

Meter = React.createClass
    componentDidMount: ->
        @paint()

    componentDidUpdate: ->
        @paint()

    paint: ->
        {posToPixel, posToDb, level, grooveHeight} = @props
        ctx = @getDOMNode().getContext('2d')
        ctx.clearRect(0, 0, 1000, 1000)
        y = posToPixel(posToDb.invert(level))
        gradient = ctx.createLinearGradient(0, 0, 20, grooveHeight)
        gradient.addColorStop(0, 'rgba(255, 0, 0, .2)')
        gradient.addColorStop(.5, 'rgba(255, 255, 0, .2)')
        gradient.addColorStop(1, 'rgba(0, 255, 0, .2)')
        ctx.fillStyle = gradient
        ctx.fillRect(0, y, 1000, 1000)

    render: ->
        {width, height} = @props
        D.canvas {className: 'meter', width, height}


class FaderView extends BaseViewModel
    constructor: (@element, @model) ->
        @_observables = wrapModelObservables @, @model, ['channel', 'level', 'pan']
        @name = @channel().name # FIXME: won't update for new channel maps.
        @posToDb = faderPositionToDb.copy().clamp(true).domain(faderDomain())
        @posToPixel = d3.scale.linear()
        @elt = d3.select(@element).select('.fader')
        @groove = @elt.select('.groove')
        @grip = @elt.select('.grip')

        @panToPixel = d3.scale.linear().domain([-.5, .5]).range([200, -200]).clamp(true)


        @grooveHeight = ko.observable 20
        @gripHeight = ko.observable 20

        ko.computed =>
            React.renderComponent(
                Meter({
                    width: 20, height: @grooveHeight() + @gripHeight()/2, level: @channel().signalLevel(),
                    posToPixel: @posToPixel,
                    posToDb: @posToDb,
                    grooveHeight: @grooveHeight()
                }),
                d3.select(@element).select('.meter-container').node()
            )

        @level.subscribe @setPosition, this
        @setPosition(@level())

        @dragBehavior = d3.behavior.drag()
            .on('dragstart', => d3.event.sourceEvent.stopPropagation()) # silence other listeners
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
        debug 'setPosition'
        y = @gripTopForDb dB
        @grip.style('top', "#{y}px")


class FaderSection
    constructor: (@containerSelection, @mixer) ->
        @activeBusIdx = ko.observable "0"
        @activeBus = ko.computed =>
            @mixer.buses[+@activeBusIdx()]
        @busNames = ko.computed =>
            (bus.name() for bus in @mixer.buses)
        @elts = []

    setActiveFaders: ->
        ko.computed =>
            faders = @activeBus().faders

            sel = d3.select(@containerSelection).select('.faders').selectAll('.fader-strip').data(faders, (fader) -> ko.unwrap(fader.channel.idx))
            sel.each((d) -> @viewModel.model(d))
            sel.enter().append('div').attr('class', 'fader-strip').html(faderTemplate).each((fader) ->
                model = ko.observable fader
                @viewModel = new FaderView(this, model)
                ko.applyBindings(@viewModel, this)
            )
            sel.exit().each((d) -> @viewModel.dispose()).transition().duration(500).style('opacity', 0).remove()

            sel = d3.select(@containerSelection).select('.master-fader').selectAll('.fader-strip').data([@activeBus().masterFader], (d) -> 'MASTER')
            sel.each((d) -> @viewModel.model(d))
            sel.enter().append('div').attr('class', 'fader-strip').html(faderTemplate).each((fader) ->
                model = ko.observable fader
                @viewModel = new FaderView(this, model)
                ko.applyBindings(@viewModel, this)
            )


# Hacking in constants for the groove
faderTemplate = """
<div class="fader">
<div class="meter-container"></div>
<div class="groove"></div>
<div class="grip"></div>
</div>
<input class="name" data-bind="value: name">
<div class="pan" data-bind="dragToAdjust: {value: pan, scale: panToPixel}"></div>
"""

###### Channel View
{Filter, Eq} = require 'eq'

ko.bindingHandlers.dragToAdjust = {
    init: (element, valueAccesor) ->
        {value, scale} = valueAccesor()

        dragBehavior = d3.behavior.drag()
            .on('dragstart', ->
                d3.event.sourceEvent.stopPropagation() # silence other listeners
                d3.select(element).classed("adjusting", true)
                if value.grabbed?
                    value.grabbed true
            ).on('drag', =>
                value scale.invert(d3.event.y)
            ).on('dragend', ->
                d3.select(element).classed("adjusting", false)
                if value.grabbed?
                    value.grabbed false
            ).origin( =>
                {x: 0, y: scale(value())})
        d3.select(element).call(dragBehavior)

    update: (element, valueAccessor) ->
        {value} = valueAccessor()
        text = d3.round(value(), 2)
        ko.bindingHandlers.text.update(element, -> text)
}

class FilterView
    constructor: (@element, @model) ->
        @_observables = wrapModelObservables @, @model, ['freq', 'gain', 'q']
        @freqElt = d3.select(@element).select('.freq')
        @freqToPixel = d3.scale.log().range([0, 300]).domain([20000, 20]).clamp(true)
        @gainToPixel = d3.scale.linear().domain([-20, 20]).range([200, -200]).clamp(true)
        @qToPixel = d3.scale.log().domain([.3, 3]).range([200, -200]).clamp(true)

    dispose: ->
        for observable in @_observables
            observable.dispose()
        ko.cleanNode(@element)

FilterVis = React.createClass
    render: ->
        {width, height, magnitudes} = @props

        xScale = d3.scale.linear().domain([0, magnitudes.length - 1]).range([0, 500])
        yScale = d3.scale.linear().domain([0, 5]).range([height, 0]) # lower range is higher on screen

        line = d3.svg.line()
            .x((d, i) -> xScale(i))
            .y((d) -> yScale(d))

        D.svg {width, height},
            D.path {d: line(magnitudes)}

ChannelOrBusChooser = React.createClass
    render: ->
        name = 'ChannelOrBusChooser'
        changed = (type, num) => @props.changed(type, num)
        channels = for channel, i in @props.channels
            D.label {},
                D.input {name, type: 'radio', onChange: changed.bind(this, 'channel', i)}
                channel.name()
        buses = for bus, i in @props.buses
            D.label {},
                D.input {name, type: 'radio', onChange: changed.bind(this, 'bus', i)}
                bus.name()
        D.div {},
            D.div {},
                "Channels:",
                channels,
            D.div {},
                "Buses:",
                buses

class ChannelSection
    constructor: (@containerSelection, @mixer) ->
        @activeStripType = ko.observable null
        @activeStripIdx = ko.observable null
        @activeStrip = ko.computed =>
            return unless @activeStripType()? and @activeStripIdx()?
            if @activeStripType() is 'channel'
                @mixer.channels[@activeStripIdx()]
            else
                @mixer.buses[@activeStripIdx()]

        @title = ko.computed =>
            return 'No channel' unless @activeStrip()?
            typeName = if @activeStripType() is 'channel' then "Channel" else "Bus"
            "#{typeName} #{@activeStripIdx()+1} (#{@activeStrip().name()})"
        eq = ko.computed => @activeStrip()?.eq

        elt = d3.select(@containerSelection)

        ko.computed =>
            changed = (type, num) =>
                @activeStripType type
                @activeStripIdx num
                return
            React.renderComponent(
                ChannelOrBusChooser(channels: @mixer.channels, buses: @mixer.buses, changed: changed),
                elt.select('.chooser').node()
            )

        ko.computed =>
            return unless eq()?
            React.renderComponent(
                FilterVis({width: 500, height: 200, magnitudes: eq().magnitudes().values})
                d3.select(@containerSelection).select('.filtervis').node()
            )
            return

        ko.computed =>
            return unless eq()?
            filters = eq().filters

            sel = d3.select(@containerSelection).select('#eq').selectAll('.filter').data(filters)
            sel.each((d) -> @viewModel.model(d))
            sel.enter().append('div').attr('class', 'filter').html(filterTemplate).each((filter) ->
                model = ko.observable filter
                @viewModel = new FilterView(this, model)
                ko.applyBindings(@viewModel, this)
            )
            sel.exit().each((d) -> @viewModel.dispose()).transition().duration(500).style('opacity', 0).remove()
            return

filterTemplate = """
<div class="freq" data-bind="dragToAdjust: {value: freq, scale: freqToPixel}"></div>
<div class="gain" data-bind="dragToAdjust: {value: gain, scale: gainToPixel}"></div>
<div class="q" data-bind="dragToAdjust: {value: q, scale: qToPixel}"></div>
"""


class UIView
    constructor: (@mixer) ->
        @activeSection = ko.observable 'faders'
        @faderSection = new FaderSection('#faders', @mixer)
        @channelSection = new ChannelSection('#channel', @mixer)
        @meterRev = ko.observable 0

        ko.applyBindings this
        @faderSection.setActiveFaders()
        @channelSection.activeStripType 'channel'
        @channelSection.activeStripIdx 0

    snapshot: ->
        checkpoint = true

    goMix: -> @activeSection 'faders'
    goChan: -> @activeSection 'channel'


updateMeters = (meterPacket) ->
    for level, channelIdx in meterPacket.c
        mixer.channels[channelIdx].signalLevel level
    # FIXME: physical to logical level map
    for busIdx in [0...metadata.num_busses]
        level = meterPacket.b[2*busIdx]
        mixer.buses[busIdx].masterFader.channel.signalLevel level

## State management
lastSeqSent = -1
lastSeqReceived = -1
stateFromServer = {}
controllableValues = {}

socket = io.connect('');
socket.on 'connect', ->
    debug('connected!')
    lastSeqSent = -1
    sendUpdate()

socket.on 'msg', (msg) ->
    lastSeqReceived = msg.seq

    if msg.seq == 0
        initializeMixerState(msg.state)
    else
        for name, value of msg.state
            stateFromServer[name] = value
            cv = controllableValues[name]
            unless cv?
                debug("Got a state update we weren't expecting! #{name}")
                continue
            debug "Applying update", name, value
            cv.serverVal value
            cv.serverLastUpdate lastSeqReceived
            # FIXME...
            cv.updateWithoutSending value

    updateMeters(msg.meter)

    ui.meterRev lastSeqReceived

    # Request another update.
    throttledSendUpdate()
    return

# Spy globals
metadata = null
mixer = null
ui = null

initializeMixerState = (state) ->
    debug 'state', state
    _.extend stateFromServer, state
    metadata = state.metadata
    getCv = (name) ->
        val = state[name]
        unless val?
            alert "Missing state value: #{name}!"
            return
        if controllableValues[name]?
            debug "Duplicate state name: #{name}!"
            return controllableValues[name]
        cv = controllableValue name, val
        controllableValues[name] = cv
        cv

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
                pan: getCv("b#{bus}/c#{chan}/pan")
            }
        busName = getCv("b#{bus}/name")
        masterFader = {
            channel: new Channel(null, busName, null)
            level: getCv("b#{bus}/lvl")
            pan: getCv("b#{bus}/pan")
        }
        new Bus(channels, faders, masterFader, busName)
    mixer = {channels, buses}
    ui = new UIView(mixer)


sendUpdate = ->
    lastSeqSent++
    socket.emit 'msg', {seq: lastSeqSent, state: updateQueue, snapshot: checkpoint}
    checkpoint = false
    updateQueue = {}

throttledSendUpdate = _.throttle sendUpdate, 1000/30
