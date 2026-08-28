.PHONY: all build release bundle run install clean

all: bundle

build:
	swift build

release:
	swift build -c release

bundle:
	./scripts/bundle.sh

run: bundle
	open dist/AgentUsageLimits.app

install: bundle
	cp -R dist/AgentUsageLimits.app /Applications/

clean:
	swift package clean
	rm -rf dist resources/AppIcon.iconset resources/AppIcon.icns
