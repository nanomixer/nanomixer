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

_.extend exports, {Filter, Eq}
