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
    formatParam: (kind, baseParams, param) -> @format(kind, copyWith(baseParams, {param}))

    getClientValue: (name) ->
        throw new Exception("Missing state value: #{name}") unless @_client[name]?
        @_client[name]

    get: (name) -> @getClientValue(name)
    set: (name, value) ->
        @_client[name] = value
        updateQueue[name] = value
        @_changed()

    getParam: (kind, baseParams, param) -> @get(@formatParam(kind, baseParams, param))
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
    getBusMeter: (bus) -> @_meters.b[bus]

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
        gradient.addColorStop(0, 'rgba(255, 0, 0, .5)')
        gradient.addColorStop(.5, 'rgba(255, 255, 0, .5)')
        gradient.addColorStop(1, 'rgba(0, 255, 0, .5)')
        ctx.fillStyle = gradient
        ctx.fillRect(0, y, 1000, 1000)

    render: ->
        {width, height} = @props
        D.canvas {className: 'meter', width, height}



faderTicks = [MIN_FADER, -60, -50, -40, -30, -20, -10, -5, 0, 5, 10]
faderLabels = ['\u221e', '60', '50', '40', '30', '20', '10', '5', 'U', '5', '10']

SVGText = React.createClass
  _setAttrs: ->
    {textAnchor, dy} = @props
    @getDOMNode().setAttribute('text-anchor', textAnchor) if textAnchor?
    @getDOMNode().setAttribute('dy', dy) if dy?

  componentDidMount: ->
    @_setAttrs()

  componentDidUpdate: ->
    @_setAttrs()

  render: ->
    {x, y, baseline, fontSize, children} = @props
    if baseline == 'middle'
      dy = '.35em'
    else if baseline == 'top'
      dy = '.71em'
    else
      dy = false
    D.text {x, y, dy, style: {fontSize}, children}


ScaleView = React.createClass
    shouldComponentUpdate: -> false

    render: ->
        lines = []
        labels = []
        for [dB, label] in _.zip(faderTicks, faderLabels)
            y = posToPixel(posToDb.invert(dB))
            lines.push D.line({x1: -5, x2: 0, y1: y, y2: y})
            labels.push SVGText({dy: '.35em', textAnchor: 'end', x: -8, y: y}, label)

        D.svg {className: 'scale', width: 20, height: grooveHeight + gripHeight},
            D.g {transform: 'translate(20, 0)'}, lines, labels



faderWidth = 60
grooveHeight = 400
grooveWidth = 4
gripWidth = 35
gripHeight = gripWidth * 2
posToDb = faderPositionToDb.copy().clamp(true).domain(faderDomain())
posToPixel = d3.scale.linear().domain([0, 1]).range([grooveHeight+gripHeight/2, gripHeight/2])
panToPixel = d3.scale.linear().domain([-.5, .5]).range([200, -200]).clamp(true)

StateToggleButton = React.createClass
    render: ->
        {state, name, className, children} = @props
        enabled = state.get name
        className = className + " enabled" if enabled
        D.button {className, onClick: @handleClick}, children

    handleClick: ->
        {state, name} = @props
        enabled = state.get name
        state.set name, !enabled

ChannelViewInMix = React.createClass
    levelParamName: ->
        {state, bus, channel} = @props
        if channel is 'master'
            state.format 'bus', {bus, param: 'lvl'}
        else
            state.format 'fader', {bus, channel, param: 'lvl'}

    componentDidMount: ->
        {state, bus, channel} = @props

        grip = @refs.grip.getDOMNode()

        dragBehavior = d3.behavior.drag()
            .on('dragstart', =>
                d3.event.sourceEvent.stopPropagation() # silence other listeners
                state.grab(@levelParamName())
                )
            .on('drag', @drag)
            .on('dragend', => state.release(@levelParamName()))
            .origin( =>
                {x: 0, y: posToPixel(posToDb.invert(@getLevel()))})
        d3.select(grip).call(dragBehavior)

    getLevel: ->
        {state, bus, channel} = @props
        state.get @levelParamName()

    drag: ->
        {state, bus, channel} = @props
        y = d3.event.y
        newVal = posToDb(posToPixel.invert(y))
        state.set @levelParamName(), newVal

    render: ->
        {state, bus, channel} = @props

        gripTop = Math.round(posToPixel(posToDb.invert(@getLevel())) - gripHeight/2)
        if channel is 'master'
            channelName = state.getParam('bus', {bus}, 'name')
            signalLevel = state.getBusMeter(bus)
            panner = false
            muteButton = false
            pflButton = false
        else
            channelName = state.getParam('channel', {channel}, 'name')
            signalLevel = state.getChannelMeter(channel)
            panner = DragToAdjustText({state, name: state.format('fader', {bus, channel, param: 'pan'}), scale: panToPixel})
            muteButton = StateToggleButton {state, className: 'mute-button', name: state.format 'channel', {channel, param: 'mute'}}, "mute"
            pflButton = StateToggleButton {state, className: 'pfl-button', name: state.format 'channel', {channel, param: 'pfl'}}, "PFL"

        D.div {className: 'channel-view-in-mix'},
            D.div {className: 'fader', style: {height: grooveHeight + gripHeight}},
                D.div {
                    className: 'groove',
                    style: {height: grooveHeight, top: gripHeight / 2, width: grooveWidth, left: (faderWidth - grooveWidth) / 2}}
                Meter({width: 20, height: grooveHeight + gripHeight / 2, level: signalLevel})
                ScaleView({})
                D.div {
                    className: 'grip', ref: 'grip',
                    style: {top: gripTop, left: (faderWidth - gripWidth) / 2, width: gripWidth, height: gripHeight}
                }
            pflButton
            muteButton
            D.div {className: 'name'}, channelName
            panner

MixerView = React.createClass
    render: ->
        {state, bus} = @props
        D.div {},
            for channel in [0...state.metadata.num_channels]
                ChannelViewInMix({state, bus, channel})
            D.div {className: "master-fader"},
                ChannelViewInMix({state, bus, channel: 'master'})



###### Channel View
{Filter, Eq} = require 'eq'


freqToPixel = d3.scale.log().range([0, 300]).domain([20000, 20]).clamp(true)
gainToPixel = d3.scale.linear().domain([-20, 20]).range([200, -200]).clamp(true)
qToPixel = d3.scale.log().domain([.3, 3]).range([200, -200]).clamp(true)





defaultFormat = d3.format(',.1f')

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
            ).on('drag', @dragged
            ).on('dragend', ->
                d3node.classed("adjusting", false)
                state.release(name)
            ).origin( =>
                {x: 0, y: scale(state.get(name))})
        d3node.call(dragBehavior)

    dragged: ->
        {state, name, scale} = @props
        state.set name, scale.invert(d3.event.y)

    componentWillUnmount: ->
        d3.select(@getDOMNode()).on('.drag', null)


    render: ->
        {state, name, format} = @props
        format = defaultFormat unless format?
        @transferPropsTo(D.div({}, format(state.get(name))))


FilterView = React.createClass
    render: ->
        {state, nameFormat, which} = @props
        freq = state.format(nameFormat, copyWith(which, {param: 'freq'}))
        gain = state.format(nameFormat, copyWith(which, {param: 'gain'}))
        q = state.format(nameFormat, copyWith(which, {param: 'q'}))
        D.div {className: 'filter'},
            state.getFormat nameFormat, copyWith(which, {param: 'type'})
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
            D.div {className: 'type'}, "Type"
            D.div {className: "freq"}, "Freq"
            D.div {className: "gain"}, "Gain"
            D.div {className: "q"}, "Q"


        D.div {className: 'filterbank'},
            labels,
            for filter in [0...numFilters]
                FilterView({state, nameFormat, which: copyWith(which, {filter})})

ChannelStripView = React.createClass
    getInitialState: -> @getTypeDependentState(@props)
    componentWillReceiveProps: (props) -> @setState @getTypeDependentState(props)
    getTypeDependentState: (props) ->
        {state, stripType, idx} = props
        switch stripType
            when 'channel'
                typeName = "Channel"
                nameParam = state.formatParam('channel', {channel: idx}, 'name')
            when 'bus'
                typeName = "Bus"
                nameParam = state.formatParam('bus', {bus: idx}, 'name')
            else
                throw new Exception("Unknown strip type #{stripType}")
        {typeName, nameParam, name: state.get(nameParam)}

    render: ->
        {state, stripType, idx} = @props
        {typeName, name} = @state

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
            D.button {onClick: @rename}, "Rename"
            FilterBankView({state, nameFormat, which, numFilters})

    rename: ->
        {state} = @props
        {nameParam} = @state
        prevName = state.get nameParam
        newName = prompt "New name?", prevName
        if newName.length > 0
            state.set nameParam, newName

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
