# Asset attribution

| Path | Author | Date | License |
|------|--------|------|---------|
| `assets/ships/sloop.svg` | Tortuga project (AI-assisted), original work | 2026-09-30 | Same as the Tortuga project license (not yet chosen; TBD) |
| `assets/ships/brig.svg` | Tortuga project (AI-assisted), original work | 2026-09-30 | Same as the Tortuga project license (not yet chosen; TBD) |
| `assets/ships/frigate.svg` | Tortuga project (AI-assisted), original work | 2026-09-30 | Same as the Tortuga project license (not yet chosen; TBD) |
| `assets/ships/3d/{sloop,brig,frigate}.glb` | Tortuga project (AI-assisted), original procedural models | 2026-10-01 | Same as the Tortuga project license (not yet chosen; TBD) |
| `assets/ui/{hull,sails,crew,speed,cannon,distance}.svg` | Tortuga project (AI-assisted), original work | 2026-09-30 | Same as the Tortuga project license (not yet chosen; TBD) |
| `assets/audio/cannon.wav` | Tortuga project (AI-assisted), original procedural sound | 2026-10-01 | CC0-1.0 (`assets/audio/LICENSE.txt`) |
| `assets/audio/impact.wav` | Tortuga project (AI-assisted), original procedural sound | 2026-10-01 | CC0-1.0 (`assets/audio/LICENSE.txt`) |
| `assets/audio/splash.wav` | Tortuga project (AI-assisted), original procedural sound | 2026-10-01 | CC0-1.0 (`assets/audio/LICENSE.txt`) |
| `assets/audio/sea.wav` | Tortuga project (AI-assisted), original procedural sound | 2026-10-01 | CC0-1.0 (`assets/audio/LICENSE.txt`) |

The legacy ship sprites are hand-written top-down SVGs (bow toward +X, canvases 64×32,
80×40, 96×48). Their in-game replacements are original, texture-free procedural GLBs:
Sunfish Runner (sloop), Crown & Compass (brig), and Resolute (frigate). The HUD icons are
hand-written 24×24 SVG glyphs. These ship models and HUD icons use no third-party or probe assets; licensed
heading font provenance is recorded below. Reef Glass water is
original procedural shader art in `view/reef_glass.gdshader`, adapted from the project's
approved browser study (AI-assisted, 2026-09-30; same project license). It uses no image
textures or third-party assets. Shallows, coast, and buoys are drawn procedurally in
`view/arena_view.gd`; 3D ship staging, wind trim, reefing, and gentle motion are implemented
in `view/ship_3d_view.gd`.

The original vector condition/hit overlays in `view/arena_view.gd` are by the Tortuga
project (AI-assisted, 2026-10-01), dedicated to the public domain under CC0-1.0
(`assets/audio/LICENSE.txt`). The four audio files are generated locally by
`tools/generate_audio.py` at 22050 Hz mono16 PCM. Cannon uses the seed-707
ignition/pressure/resonance/reflection synthesis described below. Impact combines 170/310 Hz and noise with `exp(-22*t)` (708), splash uses high-passed
noise times `sin(pi*u)^2` (709), and sea uses modulated low-pass noise, 8.25s
generated and .25s end-to-head crossfaded for an 8s loop (710). DC is removed,
one-shots have 5ms endpoint fades, peaks normalize to .8 (sea .25).

| Sound | SHA-256 |
|-------|--------|
| `assets/audio/cannon.wav` | `28b3ac6569e93d77fd9a420f5d5191be34877dd011991f3fa685cc4f06cc0223` |
| `assets/audio/impact.wav` | `26ab7d35a34d5fd76ec7e6af3b8a240fc36a03ac3c9a564b03781aa7b2fff3b6` |
| `assets/audio/splash.wav` | `8e01a605881a087ce2779dac05f0258bb5ea533bd0fae09f30afa4c2cce8c918` |
| `assets/audio/sea.wav` | `6b3727e2ba8d43525f9b65829f061f60f84230dfb73364992dce68c531581d26` |

## Engine notice

The game is built with Godot Engine (MIT license). Distributions (plan 08) must preserve the
Godot Engine copyright and license notice, together with its third-party notices.

## Nautical menu headings

`fonts/DejaVuSerif-headings.ttf` is a compact Latin subset of DejaVu Serif,
from the DejaVu fonts distributed with Matplotlib 3.11.1. DejaVu changes are
public domain; original Bitstream Vera/Arev permissions and notices are in
`fonts/LICENSE_DEJAVU.txt`; the full license is also embedded in the font’s
name ID 13 so its copyright, trademark and permission notices survive resource export. Source: https://dejavu-fonts.github.io/. Subset
contains basic Latin, middle dot, en/em dashes; body text keeps Godot's
readable default font. Brass borders and restrained corner details are
original procedural drawing in this project; no reference image assets used.

## Representative ship batteries (2026-10-02)

Original AI-assisted procedural source is `shipyard-gallery/dist/ship-models.js`;
`shipyard-gallery/scripts/export-game-models.mjs` generates the three texture-free GLBs
using the existing Three.js exporter. Representative batteries have 4/6/8 barrels
per side indexed bow to stern, brass collars and reinforced sills, a continuous
battery wale and contrasting cargo-hatch coamings. Empty `Muzzle_<side>_<index>`
transforms preserve barrel tips through static geometry batching. Other gallery
variants retain their existing geometry. License remains the Tortuga project license
(not yet chosen; TBD); no additional third-party assets or runtime dependencies.

### Per-cannon report refinement (presentation task 3)

`audio/cannon.wav` is original deterministic synthesis authored for Tortuga; no
recording or third-party sample is used. Reproduce with
`python3 game/tools/generate_audio.py`; verify without writes using `--check`.
Seed707, mono16-bit PCM at22050Hz, .65seconds (28,708bytes). The source combines
broadband ignition crack, low-pass turbulent pressure/rumble, falling resonances,
and short diffuse reflections. Cannon DC removal precedes endpoint fades, with
peak normalization to0.8. Existing impact/splash/sea synthesis and samples are unchanged.

Presentation pitch varies deterministically by projectile ID by at most2.5%,
level by at most0.6dB; no simulation random state is consumed. Sixty-four native
voices at at most-40dB cover32 simultaneous shots and overlapping tails.
`game/tests/test_generate_audio.py` checks deterministic regeneration, waveform
attack/decay, silence endpoint and conservative mono constructive mix headroom.
Native rendering/mix capture and physical listening are separate verification;
waveform tests alone do not establish convincing sound on speakers.
