# Life Blood

A small action platformer with some roguelite elements (though not enough to be considered part of that genre).

The story and characters are loosely inspired by *Paradise Lost*. I had randomly been reading summaries and interpretations of the poem, and it fit well with the game jam's constraint, "become the villain". It plays with the idea that a villain and a hero are just different perspectives. Also, my first child was born two months ago, so the idea that a father would do anything for their daughter (perhaps even something villainous) plays a role here too.

## Play

Web builds are available as zips on the [Releases](../../releases) page. Download the version you want and serve it locally with any static web server:

```bash
python3 -m http.server -d build/web
```
### Controls

For keyboard and mouse:

| Action | Input |
|---|---|
| Move | A / D  or  LEFT / RIGHT |
| Jump | W  or  UP |
| Dash | SPACE |
| Quick Attack | J  or  LEFT CLICK |
| Secondary Scythe Attack | K  or  RIGHT CLICK |
| Summon Blood Scythe | R |
| Summon Blood Fangs | F |
| Pause | ESC |

Gamepad controls (recommended) are remappable.

## Build from Source

Requires [Odin](https://odin-lang.org/) and the [Emscripten SDK](https://emscripten.org/) at `~/emsdk`.

```bash
# Web (primary target) — outputs to build/web/
bash build_web.sh

# Desktop — outputs to build/desktop/
bash build_desktop.sh
```

## Bug Reports

Found a bug? Open an issue on the [Issues](../../issues) page with a description of what happened and steps to reproduce it. Screenshots or browser console logs are always helpful.

## Architecture

Odin + Raylib targeting WebAssembly (primary) and desktop. Virtual resolution is 640x360, rendered to an off-screen target then scaled to the window.

```
src/                    package "game" — all core game logic
  main_desktop/         desktop entry point (native game loop)
  main_web/             WASM entry point (exported procs called by JS)
dotmap/                 custom map file parser (independent library)
```

### Dotmap Format

Custom tile map format in `assets/maps/`. A grid of single-char symbols between `MAP_START`/`MAP_END`, followed by a metadata block defining each symbol's tiles, passability, and key-value properties (e.g., `spawn_point=player`). The game reads metadata to place entities and determine collision.
