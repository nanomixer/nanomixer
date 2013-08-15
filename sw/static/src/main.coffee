d = console.log

meterLogToLinear = d3.scale.log()
    .domain([-60, -50, -40, -30, -20, -15, -10, -6,  -1, 0])
    .range([   0, .05,  .1,  .2,   0,  .5,  .7, .8, .95, 1])
    .clamp(true)

faderLogToLinear = meterLogToLinear
# faderLogToLinear = d3.scale.log()
#     .domain([-60, -10, 0])
#     .range([0, .8, 1])
#     .clamp(true)

ko.bindingHandlers.roundedText = {
    update: (element, valueAccessor) ->
        {value, digits} = valueAccessor()
        ko.bindingHandlers.text.update(element, -> d3.round(value(), digits))
}

# A fader, using the d3 fader scale.
ko.bindingHandlers.fader = {
    init: (element, valueAccessor, allBindingsAccessor, viewModel, bindingContext) ->
        d 'fader init'
        value = valueAccessor()
        scale = d3.scale.linear().domain([0, 1])
        grip = grooveHeight = gripHeight = null
        setPosition = (val) ->
            d 'setPosition', val
            y = Math.round(scale(faderLogToLinear(val)) - gripHeight/2)
            grip.style('top', "#{y}px")
        _.defer =>
            elt = d3.select(element)
            groove = elt.select('.groove')
            grip = elt.select('.grip')
            grooveHeight = groove.node().getBoundingClientRect().height
            gripHeight = grip.node().getBoundingClientRect().height
            d 'grooveHeight', grooveHeight
            scale.range([grooveHeight-gripHeight/2, gripHeight/2])
            d 'scale range: ', scale.range()
            dragBehavior = d3.behavior.drag()
                .on('drag', =>
                    [x, y] = d3.mouse(groove.node())
                    d "y=#{y}"
                    newVal = faderLogToLinear.invert(scale.invert(y))
                    d 'drag to', newVal
                    value newVal
                ).origin( -> {x: 0, y: scale(faderLogToLinear(value()))})
            elt.select('.grip').call(dragBehavior)
            setPosition value()
        value.subscribe setPosition
}

class Channel
    constructor: (@name) ->
        @curLevel = ko.observable Math.random()

class Bus
    constructor: (@channels) ->
        @faders = ({
            name: channel.name
            channel: channel
            level: ko.observable(0)
            pan: ko.observable(0)
            } for channel in channels)

channels = (new Channel(ko.observable('Ch'+(i+1))) for i in [0...16])
buses = {
    master: new Bus(channels)
}
mixer = {channels, buses}

class FaderSection
    constructor: (@mixer) ->
        @activeSection = ko.observable 'master'
        @activeBus = ko.computed =>
            @mixer.buses[@activeSection()]

faders = new FaderSection(mixer)
ko.applyBindings(faders)
