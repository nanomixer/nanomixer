# Workaround stylus-brunch not defining the URL inclusion.
# from: https://github.com/KATT/stylus-brunch-issues-29/commit/b3c3de4571d0dbb6b4d32396445027f942924a7a
stylus = require './node_modules/stylus'

exports.config =
  # See http://brunch.readthedocs.org/en/latest/config.html for documentation.
  plugins:
    static_jade:
      extension: ".static.jade"
    stylus:
      defines:
        url: stylus.url()
      paths: [
        './app/assets/images'
      ]

  files:
    javascripts:
      joinTo:
        'js/app.js': /^app/
        'js/vendor.js': /^(bower_components|vendor)/
        'test/js/test.js': /^test(\/|\\)(?!vendor)/
        'test/js/test-vendor.js': /^test(\/|\\)(?=vendor)/
      order:
        before: []

    stylesheets:
      joinTo:
        'css/app.css': /^(app|vendor)/
        'test/css/test.css': /^test/
      order:
        before: []
        after: []

    # Ensure that our jade templates don't get compiled into our app JS.
    templates:
      joinTo: 'js/template.js'
  modules:
    nameCleaner: (path) ->
      path = path.replace(/^app\//, '')
      path = path.replace(/^javascripts\//, '')
