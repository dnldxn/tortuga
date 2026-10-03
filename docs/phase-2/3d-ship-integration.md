# Phase 2 — Detailed 3D ship integration

The base game now renders the simulation vessel classes with the procedural shipyard models:

| Simulation class | Integrated model | Source asset |
|---|---|---|
| Sloop | Sunfish Runner | `assets/ships/3d/sloop.glb` |
| Brig | Crown & Compass | `assets/ships/3d/brig.glb` |
| Frigate | Resolute | `assets/ships/3d/frigate.glb` |
| Galleon | Crimson-and-gold two-deck Galleon | `assets/ships/3d/galleon.glb` |

The deterministic naval simulation remains 2D. Each ship is presented by a `Node2D` adapter
containing a transparent 416×432 `SubViewport`, an orthographic camera, and its imported GLB.
The focus ship is viewed from 70 degrees above horizontal. Other ships smoothly blend toward
30 degrees over 800 world units from the focus ship (50 degrees at 400 units). Spectating uses
the spectated ship as the focus. This is a presentation effect, with no change to movement or
collision coordinates. Projection compensation keeps the bow aligned with its simulation
heading, and the hull origin anchored to its world position as the angle changes.

The default camera zoom is doubled: initial zoom 2.0, auto-fit range 1.5–2.2 instead of
0.75–1.1. Existing player-follow smoothing and off-screen opponent indicators remain active.
Higher viewport resolution and additional vertical framing preserve the model scale while
keeping the tall rigs inside their textures during end-on turns.

Sail pivots rotate from the relative wind direction. Reefing shortens the cloth upward while
keeping its head attached to the yard, gaff, or stay, and attached seams and reef points follow
the cloth. Speed drives a sub-degree roll, pitch, and heave. Hull and sail condition remain
presentation-only color changes. Hull and deck materials explicitly enable imported vertex
colors: Godot 4.7.2 retains the procedural plank colors but does not enable the material flag.
Per-instance material overrides leave the imported resource untouched.

All four classes are selectable in the base game: 8/12/16/32 guns, respectively. The Galleon
has two rows of eight guns per side; indexes 0–7 are the lower deck and 8–15 the upper deck.
Each pair shares a longitudinal position in the 2D simulation, while visual effects use its
own projected 3D muzzle. The wire catalog appends Galleon as ID 3, preserving existing IDs.
Galleon starting tuning is speed 55.08, turn rate 0.45, hull/sails/crew 360/190/220, radius
55.25, and base reload 11 seconds. These are initial tuning values, not a balance certification.
The original three classes' simulation tuning is unchanged.

The reusable exporter is `shipyard-gallery/scripts/export-game-models.mjs`:

```bash
cd shipyard-gallery
npm run export:game
```

It normalizes the selected gallery variants, retains named sail pivots/surfaces, and batches
compatible static geometry within rig-safe scopes. Current imported source sizes and renderable
counts are:

| Asset | GLB size | Renderables | Triangles | Muzzle markers |
|---|---:|---:|---:|---:|
| Sloop | 1,024,976 bytes | 26 | 26,682 | 8 |
| Brig | 1,584,932 bytes | 49 | 38,254 | 12 |
| Frigate | 1,899,680 bytes | 55 | 45,214 | 16 |
| Galleon | 2,483,544 bytes | 52 | 56,978 | 32 |
| **Total** | **6,993,132 bytes** | — | — | **68** |

Godot model imports disable animation, tangent generation, shadow meshes, and light baking;
generated LODs remain enabled.

## Verification record, 2026-10-02 — detailed models, Galleon and depth

Host: macOS, Apple M5. Pinned engine: `4.7.2.stable.official.ed1daf0bf`, Compatibility
renderer (`OpenGL API 4.1 Metal`). The game used a disposable profile under
`/tmp/tortuga-game-model-integration/profile`; the player's settings were not changed.

### Automated checks

| Command / gate | Result |
|---|---|
| `npm run export:game --prefix shipyard-gallery` | Four batched GLBs generated; gun-tip mapping validated before export |
| `npm test --prefix shipyard-gallery` | **8 tests passed**, including finite geometry, 8/12/16/32 cannons, GLB readback, size ratios and smoke lifecycle |
| `GODOT=<pinned absolute binary> bash game/tests/run_settings_checks.sh` | **6,536 checks, 0 failures** across all 30 registered suites; six isolated settings probes passed; exit 0 |
| Same wrapper with `--self-test-failure` | **6,537 checks, 1 deliberate failure**, exit 1 as required |
| `--headless --path game --quit-after 30` | Main-scene smoke run, exit 0 |
| `--headless --path game --script res://tests/presentation_demo.gd -- --case=ship-depth --smoke` | **16 snapshots, 0 failures**, exit 0 |
| `git diff --check` | Clean |

View tests cover 30/50/70-degree bounds with cardinal headings and three wind directions,
negative/near/intermediate/far distances, the focus and spectated ships, diagonal heading
alignment, fixed hull-origin anchoring, colored planks, reefing and projected muzzle positions.
Weapon tests cover all 32 Galleon guns, paired deck stations, gun order and reload rejection;
snapshot round trips include Galleon's 32 load values. Gallery bounds measure Galleon at
1.294× Frigate length, 1.350× beam and 1.251× height.

The exporter emits its existing `LineBasicMaterial` advisory for seam/rigging lines. They
survive export and native inspection. Direct sandboxed headless smoke commands also emit a
macOS system-CA lookup warning; they exit 0. The full wrapper and native play finish without
script errors. Automated runs establish state and geometry, not native visual quality.

### Native display inspection

The real main scene was inspected at 1280×720. The `ship-depth` fixture places three copies
of each class at 0/250/500 units from the focus, yielding 70°/60.72°/42.66°. It holds the
production zoom floor of 1.5 to compare the ships and freezes simulation advancement.
All four classes were inspected at headings 0°, 90°, 180°, and −90°: rigging stays attached,
hulls and sails remain within their viewports, and distant models visibly show more side profile.
Edge-on sails remain thin at appropriate wind/heading combinations.

Separately, native play through the normal selection screens verified that Galleon is selectable,
sails under normal simulation, reefs with W, and fires with Q/E: both readiness counters drop
from 16/16 to 0/16. Pause remains functional. Muzzle attachment and smoke lifecycle are covered
by automated checks; this pass does not claim frame-by-frame native smoke timing.

Representative display samples during the three-ship fixture (with other checks running):

| Three copies of | Displayed FPS range | Draw calls | Primitives |
|---|---:|---:|---:|
| Sloop | 107–121 | 337 | 98,856–98,860 |
| Brig | 82–107 | 414 | 132,740–132,744 |
| Frigate | 68–98 | 440–470 | 148,499–152,363 |
| Galleon | 76–95 | 463–469 | 155,469–155,512 |

These include water, HUD and all three models. They are local observations, not a controlled
benchmark or proof of the Intel UHD performance floor. Native Linux/Windows, low-end GPUs,
remote multiplayer interoperability and long-session soak testing remain unverified here.
No release was published.

Evidence: [ship selection](evidence/game-ship-depth/selection.png),
[Sloop](evidence/game-ship-depth/sloop.png), [Brig](evidence/game-ship-depth/brig.png),
[Frigate](evidence/game-ship-depth/frigate.png),
[Galleon depth comparison](evidence/game-ship-depth/galleon-stern.png).

To repeat the native angle inspection:

```bash
"$GODOT" --path game --resolution 1280x720 \
  --script res://tests/presentation_demo.gd -- --case=ship-depth
```

Use **Next snapshot** (or hold Space briefly) to advance through the 16 views.

## Verification record, 2026-10-01

Historical record for the original three-model, fixed-30-degree implementation:

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
