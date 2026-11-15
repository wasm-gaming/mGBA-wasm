BIN := node_modules/.bin

PORT ?= 8030

.PHONY: build build-sdk build-lib build-specs build-app build-demo build-wasm build-wasm-ci build-wasm-docker \
	preview typecheck test smoke release-check i install clean help

SPECS := node_modules/@wasm-gaming/engine-specs

i: install
install: ## Install dev dependencies
	npm install

node_modules: package.json
	npm install
	@touch node_modules

build: build-wasm build-sdk ## Full build → dist/ (WASM first, then SDK/demo)

build-sdk: build-lib build-specs build-app build-demo ## The published SDK: TypeScript + the contract runtime + the app, and the demo page

build-lib: node_modules ## Compile SDK/options/manifest → dist/mgba/
	$(BIN)/tsc -p tsconfig.json

build-specs: build-lib ## Ship the contract runtime beside the SDK and import it relatively
	# The SDK extends the contract's base classes, so engine-specs is a runtime import.
	# Copied into dist/mgba/ (inside `files`) and the emitted imports rewritten to it:
	# the package loads from any static server, no import map.
	cp $(SPECS)/dist/engine-specs.js dist/mgba/engine-specs.js
	node scripts/localize-specs.mjs dist/mgba

build-app: ## The engine's own app (suspend points + pause menu) → dist/mgba/app/
	# Plain JS + CSS, mounted by hosts as <engine>/app/app.js (EngineApp); it imports
	# the SDK next to it relatively.
	rm -rf dist/mgba/app
	mkdir -p dist/mgba/app
	cp src/app/app.js src/app/app.css dist/mgba/app/

build-demo: build-lib ## The no-build demo page → dist/index.html
	cp src/demo/index.html dist/index.html

build-wasm: ## Build mGBA WASM artifacts via local Docker wrapper
	bash scripts/build-mgba-docker.sh

build-wasm-ci: ## Build mGBA WASM artifacts directly (for CI containers)
	bash scripts/build-mgba.sh

build-wasm-docker: build-wasm ## Alias: local Docker wrapper

typecheck: build-lib
	$(BIN)/tsc -p tsconfig.json --noEmit

smoke: ## Headless boot test (needs dist/mgba + roms/*.gba)
	node scripts/smoke-test.cjs

test: typecheck build-sdk ## Type-check, then run tests/ against the built package
	node --test tests/*.test.mjs

release-check: test
	npm config get registry
	npm pack --dry-run

preview: ## Serve dist/ with COOP/COEP headers
	@echo "Serving dist/ at http://localhost:$(PORT) (Ctrl+C to stop)"
	python3 scripts/preview-server.py --port $(PORT) --directory dist

clean: ## Remove build outputs
	@if [ -d dist ]; then find dist -mindepth 1 -delete; fi

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
