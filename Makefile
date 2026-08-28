.PHONY: all build release bundle run start reload open dev install stop clean

all: bundle

build:
	swift build

release:
	swift build -c release

bundle:
	./scripts/bundle.sh

# Recompiles, bundles, kills previous instance, and opens the app
run: bundle
	@killall AgentUsageLimits 2>/dev/null || true
	@open dist/AgentUsageLimits.app

# Quick launch without re-compiling (just kills previous instance and opens dist/AgentUsageLimits.app)
start:
	@killall AgentUsageLimits 2>/dev/null || true
	@open dist/AgentUsageLimits.app

reload: start
open: start

# Quick development mode: kills previous instance and runs directly with console output (Ctrl+C to quit)
dev:
	@killall AgentUsageLimits 2>/dev/null || true
	swift run AgentUsageLimits

# Stop any running instances of the app
stop:
	@killall AgentUsageLimits 2>/dev/null || true

install: bundle
	@killall AgentUsageLimits 2>/dev/null || true
	cp -R dist/AgentUsageLimits.app /Applications/

clean:
	@killall AgentUsageLimits 2>/dev/null || true
	swift package clean
	rm -rf dist resources/AppIcon.iconset resources/AppIcon.icns
