@debug = console?.log.bind(console) ? ->
# Master disable scroll (seems hacky...)
window.addEventListener('touchmove', (e) -> e.preventDefault())

updateQueue = {}
checkpoint = false

# TODO: port filt->filter back to the Python
stateNames =
    bus: 'b{bus}/{param}'
    channel: 'c{channel}/{param}'
    fader: 'b{bus}/c{channel}/{param}'
    channel_filter: 'c{channel}/f{filter}/{param}'
    bus_filter: 'b{bus}/f{filter}/{param}'

copyWith = (obj, args...) -> _.extend(_.clone(obj), args...)

class State
    constructor: ->
        @_client = {}
        @_server = {}
        @_grabbed = {}
        @metadata = null
        @_meters = null
        @_changeListeners = []

    format: (kind, params) ->
        getParam = (match, param) ->
            throw new Exception("Missing param in getParam(#{kind}, #{params}) (#{param})") unless params[param]?
            params[param]
        stateNames[kind].replace(/{(\w+)}/g, getParam)

    getClientValue: (name) ->
        throw new Exception("Missing state value: #{name}") unless @_client[name]?
        @_client[name]

    get: (name) -> @getClientValue(name)
    set: (name, value) ->
        @_client[name] = value
        updateQueue[name] = value
        @_changed()

    getParam: (kind, baseParams, param) -> @get(@format(kind, copyWith(baseParams, {param})))
    getFormat: (kind, params) -> @get(@format(kind, params))
    setFormat: (kind, params, value) -> @set(@format(kind, params), value)

    #setter: (name) ->
    #    (value) => @set(name, value)

    grab: (name) -> @_grabbed[name] = true
    release: (name) ->
        @_client[name] = @_server[name]
        delete @_grabbed[name]
        @_changed()

    getChannelMeter: (channel) -> @_meters.c[channel]

    handleUpdate: (msg) ->
        if msg.seq == 0
            @_client = _.clone(msg.state)
            @_server = _.clone(msg.state)
            @metadata = msg.state.metadata
        else
            for name, value of msg.state
                debug "Applying update", name, value
                @_server[name] = value
                @_client[name] = value unless @_grabbed[name]

        @_meters = msg.meter
        @_changed()

    onChange: (func) -> @_changeListeners.push(func)
    _changed: ->
        for listener in @_changeListeners
            listener()
        return


## State management
lastSeqSent = -1
lastSeqReceived = -1
window.state = state = new State()

socket = io.connect('');
socket.on 'connect', ->
    debug('connected!')
    lastSeqSent = -1
    sendUpdate()

socket.on 'msg', (msg) ->
    lastSeqReceived = msg.seq

    state.handleUpdate msg

    # ui.meterRev lastSeqReceived

    # Request another update.
    throttledSendUpdate()
    return


sendUpdate = ->
    lastSeqSent++
    socket.emit 'msg', {seq: lastSeqSent, state: updateQueue, snapshot: checkpoint}
    checkpoint = false
    updateQueue = {}

throttledSendUpdate = _.throttle sendUpdate, 1000/30




# winSize = {
#     width: ko.observable()
#     height: ko.observable()
# }
# winSize.rect = ko.computed ->
#     {width: winSize.width(), height: winSize.height}

# do ->
#     updateWinSize = ->
#         $window = $(window)
#         winSize.width($window.width())
#         winSize.height($window.height())
#     updateWinSize()
#     $(window).resize(_.throttle(updateWinSize, 100))
#     return

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


D = React.DOM

Meter = React.createClass
    componentDidMount: ->
        @paint()

    componentDidUpdate: ->
        @paint()

    paint: ->
        ctx = @getDOMNode().getContext('2d')
        ctx.clearRect(0, 0, 1000, 1000)
        y = posToPixel(posToDb.invert(@props.level))
        gradient = ctx.createLinearGradient(0, 0, 20, grooveHeight)
        gradient.addColorStop(0, 'rgba(255, 0, 0, .2)')
        gradient.addColorStop(.5, 'rgba(255, 255, 0, .2)')
        gradient.addColorStop(1, 'rgba(0, 255, 0, .2)')
        ctx.fillStyle = gradient
        ctx.fillRect(0, y, 1000, 1000)

    render: ->
        {width, height} = @props
        D.canvas {className: 'meter', width, height}


# class FaderView extends BaseViewModel
#     constructor: (@element, @model) ->
#         @_observables = wrapModelObservables @, @model, ['channel', 'level', 'pan']
#         @name = @channel().name # FIXME: won't update for new channel maps.
#         @elt = d3.select(@element).select('.fader')
#         @groove = @elt.select('.groove')
#         @grip = @elt.select('.grip')

#         @panToPixel = d3.scale.linear().domain([-.5, .5]).range([200, -200]).clamp(true)


#         @grooveHeight = ko.observable 20
#         @gripHeight = ko.observable 20

#         ko.computed =>
#             React.renderComponent(
#                 Meter({
#                     width: 20, height: @grooveHeight() + @gripHeight()/2, level: @channel().signalLevel(),
#                     posToPixel: @posToPixel,
#                     posToDb: @posToDb,
#                     grooveHeight: @grooveHeight()
#                 }),
#                 d3.select(@element).select('.meter-container').node()
#             )

#         @level.subscribe @setPosition, this
#         @setPosition(@level())

#         @dragBehavior = d3.behavior.drag()
#             .on('dragstart', => d3.event.sourceEvent.stopPropagation()) # silence other listeners
#             .on('drag', @drag)
#             .origin( =>
#                 {x: 0, y: @posToPixel(@posToDb.invert(@level()))})
#         @grip.call(@dragBehavior)

#         @resize()
#         winSize.rect.subscribe @resize, this

#     drag: =>
#         y = d3.event.y
#         newVal = @posToDb(@posToPixel.invert(y))
#         @level newVal

#     resize: ->
#         grooveHeight = $(@groove.node()).height()
#         @grooveHeight grooveHeight
#         gripHeight = $(@grip.node()).height()
#         @gripHeight gripHeight

#         @setPosition @level()

#         @elt.selectAll('svg.scale').remove()
#         scale = @elt.append('svg').attr('class', 'scale')
#             .attr('width', 20)
#             .attr('height', grooveHeight + gripHeight)
#             .append('g').attr('transform', 'translate(20, 0)')
#         faderTicks = [MIN_FADER, -60, -50, -40, -30, -20, -10, -5, 0, 5, 10]
#         faderLabels = ['\u221e', '60', '50', '40', '30', '20', '10', '5', 'U', '5', '10']

#         for [dB, label] in _.zip(faderTicks, faderLabels)
#             y = @posToPixel(@posToDb.invert(dB))
#             scale.append('line')
#                 .attr('x1', -5).attr('x2', 0)
#                 .attr('y1', y).attr('y2', y)
#             scale.append('text')
#                 .attr('dy', '.35em')
#                 .attr('text-anchor', 'end')
#                 .attr('x', -8)
#                 .attr('y', y)
#                 .text(label)

#     gripTopForDb: (dB) ->
#         Math.round(@posToPixel(@posToDb.invert(dB)) - @gripHeight()/2)

#     setPosition: (dB) ->
#         debug 'setPosition'
#         y = @gripTopForDb dB
#         @grip.style('top', "#{y}px")


grooveHeight = 100
gripWidth = 35
gripHeight = gripWidth * 2
posToDb = faderPositionToDb.copy().clamp(true).domain(faderDomain())
posToPixel = d3.scale.linear().domain([0, 1]).range([grooveHeight+gripHeight/2, gripHeight/2])

ChannelViewInMix = React.createClass
    render: ->
        {state, bus, channel} = @props

        D.div {className: 'channel-view-in-mix'},
            Meter({width: 20, height: grooveHeight, level: state.getChannelMeter(channel)})
            D.div {className: 'name'}, state.getParam('channel', {channel}, 'name')

MixerView = React.createClass
    render: ->
        {state, bus} = @props
        D.div {},
            for channel in [0...state.metadata.num_channels]
                ChannelViewInMix({state, bus, channel})



# # Hacking in constants for the groove
# faderTemplate = """
# <div class="fader">
# <div class="meter-container"></div>
# <div class="groove"></div>
# <div class="grip"></div>
# </div>
# <input class="name" data-bind="value: name">
# <div class="pan" data-bind="dragToAdjust: {value: pan, scale: panToPixel}"></div>
# """

###### Channel View
{Filter, Eq} = require 'eq'


freqToPixel = d3.scale.log().range([0, 300]).domain([20000, 20]).clamp(true)
gainToPixel = d3.scale.linear().domain([-20, 20]).range([200, -200]).clamp(true)
qToPixel = d3.scale.log().domain([.3, 3]).range([200, -200]).clamp(true)





DragToAdjustText = React.createClass
    displayName: "DragToAdjustText"

    componentDidMount: ->
        {state, name, scale} = @props
        node = @getDOMNode()
        d3node = d3.select(node)

        dragBehavior = d3.behavior.drag()
            .on('dragstart', ->
                d3.event.sourceEvent.stopPropagation() # silence other listeners
                d3node.classed("adjusting", true)
                state.grab(name)
            ).on('drag', =>
                state.set name, scale.invert(d3.event.y)
            ).on('dragend', ->
                d3node.classed("adjusting", false)
                state.release(name)
            ).origin( =>
                {x: 0, y: scale(state.get(name))})
        d3node.call(dragBehavior)

    render: ->
        {state, name} = @props
        @transferPropsTo(D.div({}, d3.round(state.get(name), 2)))


FilterView = React.createClass
    render: ->
        {state, nameFormat, which} = @props
        freq = state.format(nameFormat, copyWith(which, {param: 'freq'}))
        gain = state.format(nameFormat, copyWith(which, {param: 'gain'}))
        q = state.format(nameFormat, copyWith(which, {param: 'q'}))
        D.div {className: 'filter'},
            DragToAdjustText {className: 'freq', state, name: freq, scale: freqToPixel}
            DragToAdjustText {className: 'gain', state, name: gain, scale: gainToPixel}
            DragToAdjustText {className: 'q', state, name: q, scale: qToPixel}

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


FilterBankView = React.createClass
    render: ->
        {state, nameFormat, which, numFilters} = @props
        labels = D.div {className: "labels"},
            D.div {className: "freq"}, "Freq"
            D.div {className: "gain"}, "Gain"
            D.div {className: "q"}, "Q"


        D.div {className: 'filterbank'},
            labels,
            for filter in [0...numFilters]
                FilterView({state, nameFormat, which: copyWith(which, {filter})})

ChannelStripView = React.createClass
    render: ->
        {state, stripType, idx} = @props

        switch stripType
            when 'channel'
                typeName = "Channel"
                name = state.getParam('channel', {channel: idx}, 'name')
            when 'bus'
                typeName = "Bus"
                name = state.getParam('bus', {bus: idx}, 'name')
            else
                throw new Exception("Unknown strip type #{stripType}")

        title = "#{name} (#{typeName} #{idx+1})"

        # FilterVis({width: 500, height: 200, magnitudes: eq().magnitudes().values})

        switch stripType
            when 'channel'
                nameFormat = 'channel_filter'
                which = {channel: idx}
                numFilters = state.metadata.num_biquads_per_channel
            when 'bus'
                nameFormat = 'bus_filter'
                which = {bus: idx}
                numFilters = state.metadata.num_biquads_per_bus

        D.div {},
            D.h1 {}, title
            FilterBankView({state, nameFormat, which, numFilters})


Nav = React.createClass
    saveSnapshot: ->
        checkpoint = true

    shouldComponentUpdate: (nextProps, nextState) ->
        props = ['section', 'idx', 'busNames', 'channelNames']
        not _.isEqual(
            _.pick(nextProps, props...)
            _.pick(@props, props...))

    render: ->
        {section, idx} = @props
        itemNames = switch section
            when 'mix' then @props.busNames
            when 'channel' then @props.channelNames
            when 'bus' then @props.busNames

        items = for item, i in itemNames
            D.label {},
                D.input {type: 'radio', onChange: @props.itemChanged.bind(this, i), checked: idx is i}
                item


        D.div {className: 'nav'},
            D.div {className: "mode-picker"},
                D.button {onClick: @props.kindChanged.bind(this, 'mix')}, "Mix"
                D.button {onClick: @props.kindChanged.bind(this, 'channel')}, "Channel"
                D.button {onClick: @props.kindChanged.bind(this, 'bus')}, "Bus"
            D.div {className: "item-picker"}, items
            D.button {onClick: @saveSnapshot}, 'Save'

UI = React.createClass
    getInitialState: -> {
        section: 'mix'
        idx: 0
    }

    render: ->
        {state} = @props

        return D.div {}, "Waiting for server..." unless state.metadata?

        {section, idx} = @state

        kindChanged = (section) => @setState {section}
        itemChanged = (idx) => @setState {idx}

        channelNames = (state.getParam('channel', {channel}, 'name') for channel in [0...state.metadata.num_channels])
        busNames = (state.getParam('bus', {bus}, 'name') for bus in [0...state.metadata.num_busses])

        D.div {},
            Nav({section, idx, channelNames, busNames, itemChanged, kindChanged})
            switch section
                when 'mix' then MixerView({state, bus: idx})
                when 'channel' then ChannelStripView({state, stripType: 'channel', idx})
                when 'bus' then ChannelStripView({state, stripType: 'bus', idx})


ui = React.renderComponent(UI({state}), document.body)
state.onChange -> ui.setProps({state})
