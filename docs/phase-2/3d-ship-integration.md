# Phase 2 — Detailed 3D ship integration

The base game now renders the simulation vessel classes with the procedural shipyard models:

| Simulation class | Integrated model | Source asset |
|---|---|---|
| Sloop | Sunfish Runner | `assets/ships/3d/sloop.glb` |
| Brig | Crown & Compass | `assets/ships/3d/brig.glb` |
| Frigate | Resolute | `assets/ships/3d/frigate.glb` |

The deterministic naval simulation remains 2D. Each ship is presented by a `Node2D` adapter
containing a small transparent `SubViewport`, a fixed orthographic camera 30 degrees above
horizontal, and its imported GLB. The outer node stays in simulation coordinates while the 3D
model yaws inside the viewport. Projection compensation keeps the rendered bow aligned with
the simulation heading at every turn.

Sail pivots rotate from the relative wind direction. Reefing shortens the cloth upward while
keeping its head attached to the yard, gaff, or stay, and attached seams and reef points follow
the cloth. Speed drives a sub-degree roll, pitch, and heave. Hull and sail condition remain
presentation-only color changes.

The reusable exporter is `shipyard-gallery/scripts/export-game-models.mjs`:

```bash
cd shipyard-gallery
npm run export:game
```

It normalizes the selected gallery variants, retains named sail pivots/surfaces, and batches
compatible static geometry within rig-safe scopes. Current imported source sizes and renderable
counts are:

| Asset | GLB size | Renderables |
|---|---:|---:|
| Sloop | 301,868 bytes | 26 |
| Brig | 452,992 bytes | 47 |
| Frigate | 585,588 bytes | 52 |
| **Total** | **1,340,448 bytes** | — |

Godot model imports disable animation, tangent generation, shadow meshes, and light baking;
generated LODs remain enabled.

## Verification record, 2026-10-01

Host: macOS on Apple M5. Engine: Godot `4.7.2.stable.official.ed1daf0bf`, Compatibility
renderer (`OpenGL API 4.1 Metal`).

| Gate | Result |
|---|---|
| `--headless --path game --import` | exit 0; all GLBs imported without errors |
| `run_tests.gd` | **2,630 checks, 0 failures**, exit 0; only the two expected invalid-ID `ERROR` lines |
| `run_tests.gd -- --self-test-failure` | 2,631 checks, 1 deliberate failure, exit **1** as required |
| `--headless --path game --quit-after 30` | exit 0; real main scene smoke-run clean |
| Native visual check | all three models render through transparent viewports; full and reefed rigs remain attached and unclipped |
| Native representative scene | 243 draw calls, 34,787 primitives, 114 displayed FPS, 0.010214 s process time at 1280×720 |
| `git diff --check` | clean |

The native performance sample is a regression signal for this Apple M5 host, not the Phase 2
Intel UHD performance-floor result. Native Linux/Windows rendering and Intel UHD remain
unverified.
