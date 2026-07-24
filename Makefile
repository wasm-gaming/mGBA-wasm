BIN := node_modules/.bin

PORT ?= 8030

.PHONY: build build-sdk build-lib build-manifest build-demo build-wasm build-wasm-ci build-wasm-docker \
	preview typecheck test smoke release-check i install clean help

i: install
install: ## Install dev dependencies
	npm install

node_modules: package.json
	npm install
	@touch node_modules

build: build-wasm build-sdk ## Full build → dist/ (WASM first, then SDK/demo)

build-sdk: build-lib build-manifest build-demo ## TypeScript + manifest + demo shell

build-lib: node_modules ## Compile SDK/options/manifest → dist/mgba/
	$(BIN)/tsc -p tsconfig.json

build-manifest: build-lib ## Serialize typed manifest → dist/manifest.json
	node scripts/emit-manifest.mjs

DEMO_SRC := node_modules/@wasm-gaming/engine-specs/demo

build-demo: build-lib ## Assemble the themable engine-specs demo shell + GBA skin
	@rm -f dist/index.html dist/main.js
	cp -R $(DEMO_SRC)/. dist/
	rm -f dist/README.md
	cp src/demo/index.html dist/index.html
	cp src/demo/mgba.css dist/mgba.css

build-wasm: ## Build mGBA WASM artifacts via local Docker wrapper
	bash scripts/build-mgba-docker.sh

build-wasm-ci: ## Build mGBA WASM artifacts directly (for CI containers)
	bash scripts/build-mgba.sh

build-wasm-docker: build-wasm ## Alias: local Docker wrapper

typecheck: build-lib
	$(BIN)/tsc -p tsconfig.json --noEmit

smoke: ## Headless boot test (needs dist/mgba + roms/*.gba)
	node scripts/smoke-test.cjs

test: typecheck

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
