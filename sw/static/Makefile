JADE=./node_modules/jade/bin/jade
STYLUS=./node_modules/stylus/bin/stylus
COFFEE=./node_modules/coffee-script/bin/coffee

all: node_modules build html css js jslibs

node_modules:
	mkdir -p node_modules
	npm install jade
	npm install stylus
	npm install coffee-script

build: 
	mkdir -p build/js build/css

clean:
	rm -rf build

html: src/*.html
	cp "$<" build

css: src/*.styl
	$(STYLUS) -U -o build/css "$<"

js: src/*.coffee
	$(COFFEE) -b -o build/js "$<"

jslibs: lib/*
	cp -a lib/* build/js
