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

        ctx = @elt.select('canvas').node().getContext('2d')
        ko.computed =>
            ctx.clearRect(0, 0, 1000, 1000)
            y = @posToPixel(@posToDb.invert(@channel().signalLevel()))
            gradient = ctx.createLinearGradient(0, 0, 20, @grooveHeight())
            gradient.addColorStop(0, 'rgba(255, 0, 0, .2)')
            gradient.addColorStop(.5, 'rgba(255, 255, 0, .2)')
            gradient.addColorStop(1, 'rgba(0, 255, 0, .2)')
            ctx.fillStyle = gradient
            ctx.fillRect(0, y, 1000, 1000)

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
<canvas class="meter" width="20" data-bind="attr: {height: grooveHeight() + gripHeight()/2 }"></canvas>
<div class="groove"></div>
<div class="grip"></div>
</div>
<input class="name" data-bind="value: name">
<div class="pan" data-bind="dragToAdjust: {value: pan, scale: panToPixel}"></div>
"""

###### Channel View
fSamp = 48000
twoPiOverFs = 2 * Math.PI / fSamp

class Eq
    constructor: (@filters) ->
        @freq = [0..100].map (i) -> 20 * Math.pow(2, i/10)
        @magnitudes = ko.computed =>
            @filters.reduce (agg, cur) =>
                magnitude = @computeMagnitudes(cur.coefficients())
                agg.multiply(magnitude)
            , new Magnitudes(@freq.map (i) -> 1)

    computeMagnitudes: (coefficients)->
        c = coefficients.map (real) -> new ComplexNumber(real, 0)
        new Magnitudes(@freq.map (frequency) ->
            w0 = frequency * twoPiOverFs
            z = new ComplexNumber(Math.cos(w0), Math.sin(w0))
            numerator = c.b0.add(c.b1.add(c.b2.multiply(z)).multiply(z)) # b0 + (b1 + b2 * z) * z
            denominator = new ComplexNumber(1, 0).add(c.a1.add(c.a2.multiply(z)).multiply(z)) # c(1, 0) + (a1 + a2 * z) * z
            response = numerator.divide(denominator)
            Math.abs(response.real)
        )

    class Magnitudes
        constructor: (@values) ->

        multiply: (other) ->
            new Magnitudes(_.zip(@values, other.values).map (values) ->
                [mag1, mag2] = values
                mag1 * mag2
            )

    class ComplexNumber
        constructor: (@real, @imaginary) ->

        add: (other) =>
            new ComplexNumber(@real + other.real, @imaginary + other.imaginary)

        multiply: (other) =>
            new ComplexNumber(@real * other.real - @imaginary * other.imaginary,
                @real * other.imaginary + @imaginary * other.real)

        conjugate: =>
            new ComplexNumber(@real, -@imaginary)

        divide: (denominator) =>
            # division: (a + bi)/(c + di) => (a + bi)(c - di)/(c + di)(c - di)
            newNumerator = @multiply(denominator.conjugate())
            newDenominator = denominator.multiply(denominator.conjugate())

            # newDominator only has a real component
            new ComplexNumber(
                newNumerator.real / newDenominator.real,
                newNumerator.imaginary / newDenominator.real
            )

class Filter
    constructor: (@freq, @gain, @q) ->
        @coefficients = ko.computed =>
            @computePeakingParams(@freq(), @gain(), @q())

    class FilterCoefficients
        constructor : (@b0, @b1, @b2, @a0, @a1, @a2) ->

        normalize: =>
            a0Inverse = 1 / @a0
            new FilterCoefficients(@b0 * a0Inverse, @b1 * a0Inverse, @b2 * a0Inverse, @a0, @a1 * a0Inverse, @a2 * a0Inverse)

        map: (transform) =>
            new FilterCoefficients(
                transform(@b0), transform(@b1), transform(@b2),
                transform(@a0), transform(@a1), transform(@a2))

    ## Peaking params computation
    computePeakingParams: (freq, gain, q) =>
        w0 = freq * twoPiOverFs

        a = Math.pow(10.0, gain / 40)

        alpha = Math.sin(w0) / (2 * q)
        cosw0 = Math.cos(w0)

        b0 = 1 + alpha * a
        b1 = -2 * cosw0
        b2 = 1 - alpha * a
        a0 = 1 + alpha / a
        a1 = -2 * cosw0
        a2 = 1 - alpha / a

        new FilterCoefficients(b0, b1, b2, a0, a1, a2).normalize()


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

            @rebindFilterVisualization()
            return

    rebindFilterVisualization: =>
        ko.computed =>
            channel = @activeChannel()
            return unless channel?
            eq = channel.eq

            eqElt = d3.select(@containerSelection).select('#eq')
            eqElt.selectAll('svg').remove()
            width = 500
            height = 200
            svg = eqElt.append('svg')
                .attr('width', width)
                .attr('height', height)

            xScale = d3.scale.linear().range([0, 500]).domain([0, eq.freq.length - 1])
            yScale = d3.scale.linear().domain([0, 5]).range([height, 0]) # lower range is higher on screen
            line = d3.svg.line()
                .x((d, i) -> return xScale(i))
                .y((d) -> return yScale(d))

            svg.select('path').remove()
            path = svg.append('path').attr('d', line(eq.magnitudes().values))
            return

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
        @activeSection = ko.observable 'faders'
        @faderSection = new FaderSection('#faders', @mixer)
        @channelSection = new ChannelSection('#channel', @mixer)
        @meterRev = ko.observable 0

        ko.applyBindings this
        @faderSection.setActiveFaders()
        @channelSection.activeChannelIdx 0

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
