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
        '-∞'
    else 
        d3.round(value, 1)

ko.bindingHandlers.faderLevelText = {
    update: (element, valueAccessor) ->
        value = valueAccessor()
        text = faderLevelToText value()
        ko.bindingHandlers.text.update(element, -> text)
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
        @name = @model.name
        @level = @model.level
        @posToDb = faderPositionToDb.copy().clamp(true).domain(faderDomain(@grooveHeight))
        @posToPixel = d3.scale.linear()
        @elt = d3.select(@element)
        @groove = @elt.select('.groove')
        @grip = @elt.select('.grip')

        @level.subscribe @setPosition, this
        @setPosition(@level())

        @dragBehavior = d3.behavior.drag()
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
        @grooveHeight = $(@groove.node()).height()
        @gripHeight = $(@grip.node()).height()
        @posToPixel
            .domain([0, 1])
            .range([@grooveHeight+@gripHeight/2, @gripHeight/2])
        @setPosition @level()

        @elt.selectAll('svg.scale').remove()
        scale = @elt.append('svg').attr('class', 'scale')
            .attr('width', 20)
            .attr('height', @grooveHeight + @gripHeight)
            .append('g').attr('transform', 'translate(20, 0)')
        faderTicks = [MIN_FADER, -60, -50, -40, -30, -20, -10, -5, 0, 5, 10]
        faderLabels = ['∞', '60', '50', '40', '30', '20', '10', '5', 'U', '5', '10']

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
        Math.round(@posToPixel(@posToDb.invert(dB)) - @gripHeight/2)

    setPosition: (dB) ->
        y = @gripTopForDb dB
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
<div class="grip"></div>
<input class="name" data-bind="value: name">
"""

faderSection = new FaderSection('#faders', mixer)
ko.applyBindings(faderSection)
faderSection.setActiveFaders()

