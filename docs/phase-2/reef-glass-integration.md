# Reef Glass game integration

Date: 2026-09-30. Engine: Godot 4.7.2 stable, Compatibility renderer.

## Implementation

The owner selected the Reef Glass browser sample, requested gentler swells and
faster whitecap fades, then approved integrating that refinement into the game.

- `game/view/reef_glass.gdshader` ports the approved procedural water into a
  canvas-item shader. It retains turquoise/jade colors, refracted reef patches,
  caustics, wind-driven swells, seeded whitecaps, and subtle sun glitter.
- `game/view/reef_glass.gd` owns one world-sized draw rectangle and one material.
  It renders behind ArenaView, so ships, projectiles, arcs, coast, navigation
  hatching, buoys, and UI keep their existing draw order.
- `arena_view.gd` replaces the flat sea and static chevron wave marks with the
  water node. The shallows tint is translucent, leaving the water visible below
  the existing safety hatch and boundary markings.
- Reef detail uses world coordinates at 144 world pixels per shader unit.
  Camera movement/zoom does not drag or rescale the underlying world texture.
  Depth patches extend across the 6000×4200 arena and become shallower near the
  borders; the preview's single-screen diagonal depth gradient was unsuitable
  for that full arena. These decorative reefs do not create collision obstacles.
- Wind comes from the current `main.sim.wind_heading`, with the same
  clockwise/Y-down convention as the HUD. The shader converts that to the
  browser study's Y-up coordinates. Surface drift accumulates, including after
  a wind change; the bottom stays anchored.
- Time/drift advance once per fixed gameplay tick. Explicit uniforms are used
  instead of shader `TIME`, so pause/result screens freeze the water and restart
  resets it. Returning to selection reads the newly replaced simulation.
- Presentation tuning is centralized in `Definitions.WATER`: animation speed
  0.75, drift speed 0.1, swell weights (0.34, 0.16, 0.060), whitecap lifetimes
  4–8 animation seconds. The approved gentler/faster settings are retained.

No simulation mechanics, dependencies, raster textures, network imports, or
release presets were added. The new water script and shader total 7,216 bytes
before packaging. Existing user files and the browser samples are preserved.

## Verification

Baseline: 1,465 checks passed before changes.

The new registered `test_water.gd` suite first failed because Reef Glass was
absent, then passed after integration. It checks the real scene's water node,
material/layering, arena coverage, fixed timing, wind/drift direction, camera
independence, simulation immutability, pause/resume, restart, actual combat result
flow, simulation replacement, and node reuse.

Commands use the repository's pinned engine and isolated XDG directories:

```sh
export P="$HOME/.cache/tortuga-godot-4.7.2"
export XDG_DATA_HOME="$P/xdg/data" XDG_CONFIG_HOME="$P/xdg/config" XDG_CACHE_HOME="$P/xdg/cache"
export GODOT="$P/bin/Godot_v4.7.2-stable_linux.x86_64"
"$GODOT" --headless --path game --import
"$GODOT" --headless --path game --script res://tests/run_tests.gd
"$GODOT" --headless --path game --script res://tests/run_tests.gd -- --self-test-failure
"$GODOT" --headless --path game --quit-after 30
git diff --check
```

- Import: exit 0.
- Full suite: **1,493 checks, 0 failures**; only deliberate invalid-ID errors.
- Runner sanity: **1,494 checks, 1 intentional failure**, exit 1.
- Main-scene headless smoke: exit 0, no script/shader errors.
- Whitespace check: passed.

### Actual engine rendering

A temporary copy of `game/` was exported with the same pinned engine to Web,
single-threaded, and served on localhost for Chromium/SwiftShader inspection.
The real main scene rendered under Godot's Compatibility/WebGL2 renderer,
including the refined shader, ships, targeting cues, menus, and HUD. Keyboard
input entered practice and opened pause. Menu, practice, and pause screenshots
were inspected.

The WebGL backend emitted buffer-binding/bufferSubData warnings. A diagnostic
export with the water shader unbound reproduced those warnings, so they are not
specific to Reef Glass. There were no shader compilation, JavaScript, or Godot
script errors. This does not establish that the WebGL warnings are harmless
everywhere.

Temporary evidence:

- `/tmp/tortuga-water-tests.log`
- `/tmp/tortuga-water-runner-sanity.log`
- `/tmp/tortuga-water-smoke.log`
- `/tmp/tortuga-water-web-export.log`
- `/tmp/tortuga-water-browser.log`
- `/tmp/tortuga-water-browser-control.log`
- `/tmp/tortuga-reef-game-{menu,play,pause}.png`

Screenshots and final test/render logs were also saved under the gitignored
`build/phase-2/reef-glass/` directory (`menu.png`, `practice.png`, `paused.png`,
`tests.log`, `web-render.log`). The temporary localhost verification server was
stopped afterward; the existing Tailscale art-study server was not changed.

Native macOS appearance, integrated-GPU performance, and a real-display playtest
remain unverified. The temporary Web export is a verification artifact, not a
release; no macOS build or rolling GitHub release was produced.

API references checked with Context7 against the Godot 4.7 documentation:
[CanvasItem shaders](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/canvas_item_shader.html),
[Web export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html).
