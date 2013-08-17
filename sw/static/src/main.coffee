@debug = console?.log.bind(console) ? ->

winSize = {
    width: ko.observable()
    height: ko.observable()
}
winSize.rect = ko.computed ->
    {width: winSize.width(), height: winSize.height}

$(window).resize(_.throttle(->
    $window = $(window)
    winSize.width($window.width())
    winSize.height($window.height())
, 100))


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

class FaderView
    constructor: (@element, @model) ->
        @level = @model.level
        @scale = d3.scale.linear().domain([0, 1])
        @elt = d3.select(@element)
        @groove = @elt.select('.groove')
        @grip = @elt.select('.grip')

        @level.subscribe @setPosition, this
        @setPosition(@level())

        @dragBehavior = d3.behavior.drag()
            .on('drag', @drag)
            .origin( =>
                y = @scale(faderLogToLinear(@level()))
                debug 'origin', y
                {x: 0, y: y})
        @grip.call(@dragBehavior)

        @resize()
        winSize.rect.subscribe @resize, this

    drag: =>
        y = d3.event.y
        console.log "y=#{y}"
        newVal = faderLogToLinear.invert(@scale.invert(y))
        console.log 'drag to', newVal
        @level newVal

    resize: ->
        @grooveHeight = $(@groove.node()).height()
        @gripHeight = $(@grip.node()).height()

        @scale.range [@grooveHeight-@gripHeight/2, @gripHeight/2]
        console.log 'scale range: ', @scale.range()
        @setPosition @level()

    setPosition: (val) ->
        console.log 'setPosition', val
        y = Math.round(@scale(faderLogToLinear(val)) - @gripHeight/2)
        @grip.style('top', "#{y}px")


class FaderSection
    constructor: (@containerSelection, @mixer) ->
        @activeSection = ko.observable 'master'
        @activeBus = ko.computed =>
            @mixer.buses[@activeSection()]

    setActiveFaders: ->
        faders = @activeBus().faders
        sel = d3.select(@containerSelection).selectAll('.fader').data(faders, (fader) -> ko.unwrap(fader.name))
        sel.enter().append('div').attr('class', 'fader').html(faderTemplate).each((fader, i) ->
            console.log 'before', this.__data__
            this.viewModel = new FaderView(this, fader)
            ko.applyBindings(this.viewModel, this)
            console.log 'after', this.__data__
        )
        sel.exit().transition().duration(500).style('opacity', 0).remove()
    # .each((d, i) -> ko.cleanNode(@))

faderTemplate = """
<div class="groove"></div>
<div class="grip" data-bind='roundedText: {value: level, digits: 2}'>
<input class="name" data-bind="value: name">
"""

faderSection = new FaderSection('#faders', mixer)
ko.applyBindings(faderSection)
