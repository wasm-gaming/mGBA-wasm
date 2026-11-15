# @wasm-gaming/mgba-wasm

[mGBA](https://github.com/mgba-emu/mgba) — the accuracy-focused **Game Boy
Advance** emulator, which also runs **Game Boy** and **Game Boy Color** —
compiled to WebAssembly via Emscripten and packaged as a wasm-gaming engine SDK.

It conforms to the [`@wasm-gaming/engine-specs`](https://github.com/wasm-gaming/engine-specs)
**1.0 contract** (`MgbaSDK` / `MgbaPlay` on the contract's base classes), the same shape as
snes9x-wasm, blastem-wasm and fbneo-wasm: save-state slots, owner-aware pause, and the
wasm-gaming engine app (`./app`). The built SDK is self-contained ESM — `engine-specs.js` ships
beside it — so it loads from any static server, with no bundler or import map.

mGBA ships several frontends (`qt/`, `sdl/`, `libretro/`); none of them suit a
browser, so this package supplies its own
([scripts/shim/mgba_shim.c](scripts/shim/mgba_shim.c)) instead of an Emscripten
SDL layer: **no ASYNCIFY, no SDL, no emulated GL**. Because mGBA already
publishes `struct mCore` — a frontend-facing vtable that is identical for both
its cores — the shim is a thin flat-C ABI over it rather than a reimplemented
port. The JS SDK drives one `core->runFrame()` per frame, blits the framebuffer
to a 2D canvas, and streams audio through an `AudioWorklet` ring buffer.
Emulation is **audio-clocked**: frames are produced to keep ~90 ms of audio
queued.

## ROM format

Pass the cartridge image as the `rom` asset: `.gba`, `.gb`, `.gbc` or `.sgb`.
**Zipped dumps work too** — the archive is opened in JS
([src/mgba.zip.ts](src/mgba.zip.ts)) with `DecompressionStream`, since this
build carries no libzip.

The right core is chosen from the image itself, so a Game Boy ROM and a GBA ROM
both just work; force it with `options.system` for headerless or mislabelled
files.

### BIOS

**Optional.** mGBA has a high-level BIOS replacement that runs virtually every
commercial title, so the `bios` asset is only needed for the boot animation and
the handful of games that read the BIOS directly. Supply a 16 KiB GBA BIOS dump
as `assets.bios` if you want it; without one, `skipBios` is forced on and drops
out of the settings menu, because there is no intro to skip.

## Contract surface

```js
import MgbaSDK from '@wasm-gaming/mgba-wasm';

const play = await new MgbaSDK()
  .options({ system: 'auto', aspect: 'native' })
  .assets({ rom: () => file.arrayBuffer() /*, bios: biosBytes */ })
  .storage({ namespace: 'minish-cap' })        // OPFS mgba/minish-cap/
  .on('saves', ({ detail }) => console.log(detail.files))
  .mount(document.querySelector('#stage'))     // an element (the SDK adds a canvas) or a canvas
  .start();

play.system;                                   // 'gba' | 'gb' — which core booted
play.pause('menu'); play.resume('menu');       // the first owner holds the pause
await play.restart();                          // power cycle
await play.destroy();                          // battery RAM flushed, loop stopped, audio closed
```

### Save states

```js
await play.states.save(0, { thumbnail: await play.snapshot() });
play.states.load(0);           // true when mGBA took it (false: another game's state)
play.states.list();            // slots 0-3: { slot, savedAt, thumbnail, locked }
await play.states.copy(9, 1); await play.states.lock(1, true); await play.states.remove(0);
```

Slots 0–3 are the player's, 9 is the engine app's suspend point. Per slot, OPFS
`mgba/<namespace>/` holds `slot_N.state` (mGBA's own snapshot: 388 KiB on GBA, 70 KiB on Game
Boy), `slot_N.png` (its frame) and `slot_N.lock`; battery RAM is `sram.bin`, flushed every 15 s,
on pause and on destroy. The slots are read into memory at start, so listing them is
synchronous; every change is written through.

## The engine app

`@wasm-gaming/mgba-wasm/app` is the wasm-gaming engine app, the same as BlastEm's, FBNeo's and
snes9x's: suspend points on start, Select+Start / Escape / the touch pad's pause button open the
pause menu with the four slots in it (Cargar focused), Reiniciar, Volver al lanzador. The slot
frames take the picture's shape (3:2 on GBA, 10:9 on Game Boy).

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `system` | `auto` | Which core boots the ROM: `auto` (sniffed from the image), `gba`, or `gb`. **Needs reset.** |
| `gbModel` | `auto` | Game Boy hardware: `auto` (from the header), `dmg`, `sgb`, `cgb`, `agb`. Ignored on GBA. **Needs reset.** |
| `idleOptimization` | `remove` | How the GBA core treats busy-wait loops. `remove` is where nearly all the speed comes from; `ignore` emulates them cycle for cycle. |
| `skipBios` | `true` | Skip the boot animation. Forced on, and hidden, when no BIOS image was supplied. **Needs reset.** |
| `allowOpposingDirections` | `false` | Let the D-pad report left+right at once. Real hardware cannot. |
| `renderFilter` | `pixelated` | Canvas scaling filter (`pixelated` or `smooth`). |
| `aspect` | `native` | `native` is square pixels — 3:2 on GBA, 10:9 on Game Boy; `4:3` fills a TV-shaped frame. |
| `interframeBlending` | `false` | Blend consecutive frames, approximating the ghosting of the original unlit LCD. Restores transparency effects games drew by flickering sprites. |
| `volume` | `1.0` | Master audio volume (0–1). |
| `gamepads` | `true` | Poll connected gamepads (standard mapping) each frame. |
| `logLevel` | `error` | Core messages printed to the console (`off`, `error`, `debug`). |

## Live settings

`play.settings` writes apply to the running game: mGBA re-reads its `mCoreConfig` when the
frontend calls `reloadConfigOption()`, which is how its own Qt frontend applies a settings
change mid-play. The ones the core consumes while mapping the cartridge — `system`, `gbModel`,
`skipBios` — are **needs reset** (`live: false` in `MGBA_SPEC`), and `play.restart()` re-maps
it (battery RAM is carried across).

```js
play.settings.write('interframeBlending', true);
play.settings.read('idleOptimization');            // 'remove'
```

- Writes are remembered per storage namespace in `localStorage` and re-applied on the next
  start; options the host passes still win.
- Settings the loaded `mgba.wasm` cannot apply — a build predating one of the shim's setters —
  are omitted rather than erroring.
- mGBA draws no settings overlay of its own; `toEscMenuGroups(play.settings.values())` gives a
  host the rows to draw one.

Every knob is declared once in [src/mgba.options.ts](src/mgba.options.ts); `MGBA_SPEC`, the
defaults and the rows are all derived from that catalog.

### Sizing the canvas

Mounted on an element, the SDK sizes its canvas to fit it at the picture's ratio — 3:2 on GBA,
10:9 on Game Boy, 8:7 once a Super Game Boy border appears, 4:3 with `aspect: '4:3'` — and
refits when the geometry or the option changes. Mounted on a canvas of yours, the core still
publishes the ratio on it as `aspect-ratio` and `--mgba-aspect`:

```css
canvas { width: min(100%, calc(100% * var(--mgba-aspect))); height: auto; }
```

### Default controls

| Control | Key | Standard gamepad |
|---------|-----|------------------|
| D-pad | Arrow keys | 12–15 / left stick |
| A / B | X / Z | 0 / 1 |
| L / R | A / S | 4 / 5 |
| Start | Enter | 9 |
| Select | Right Shift | 8 |

Every connected gamepad plays (`options.gamepads`), so a physical pad and the engine-specs
touch pad — which exposes itself as a standard gamepad — work together. Keys and buttons are
released whenever the game pauses.

## Build

```sh
make build        # Full build: WASM (Docker/Emscripten) + TypeScript SDK
make build-sdk    # SDK + contract runtime + engine app + demo page (no WASM)
make test         # Type-check, then the tests against the built package
make build-wasm   # mGBA WASM only (via Docker)
make preview      # Serve dist/ at :8030 with COOP/COEP headers
make smoke        # Headless boot test (needs a ROM in roms/)
```

The WASM build clones a pinned mGBA revision and builds it with its own CMake —
`DISABLE_FRONTENDS` plus `DISABLE_DEPS` is exactly the "just the emulator"
configuration this needs, and it generates `version.c` and `flags.h` along the
way — then links the shim against the resulting `libmgba.a`. No upstream
patching.

## WASM artifacts

| File | Description |
|------|-------------|
| `mgba.js` | Emscripten module loader (`createMgbaModule`). |
| `mgba.wasm` | Compiled mGBA core + shim (~790 KB). |

No SharedArrayBuffer or COOP/COEP headers are required at runtime (the preview
server sets them anyway for parity with sibling engines).

See [CORE.md](CORE.md) for the mapping between upstream mGBA capabilities and
what this wrapper exposes, and for the Emscripten-specific build traps.

## License

The SDK and shim are MPL-2.0, matching mGBA.
