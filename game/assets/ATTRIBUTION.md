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
hand-written 24×24 SVG glyphs. No third-party or probe assets are used. Reef Glass water is
original procedural shader art in `view/reef_glass.gdshader`, adapted from the project's
approved browser study (AI-assisted, 2026-09-30; same project license). It uses no image
textures or third-party assets. Shallows, coast, and buoys are drawn procedurally in
`view/arena_view.gd`; 3D ship staging, wind trim, reefing, and gentle motion are implemented
in `view/ship_3d_view.gd`.

The original vector condition/hit overlays in `view/arena_view.gd` are by the Tortuga
project (AI-assisted, 2026-10-01), dedicated to the public domain under CC0-1.0
(`assets/audio/LICENSE.txt`). The four audio files are generated locally by
`tools/generate_audio.py` at 22050 Hz mono16 PCM: seeded white noise and an .08
low-pass; cannon combines 65 Hz and noise with `exp(-9*t)` (seed 707), impact
combines 170/310 Hz and noise with `exp(-22*t)` (708), splash uses high-passed
noise times `sin(pi*u)^2` (709), and sea uses modulated low-pass noise, 8.25s
generated and .25s end-to-head crossfaded for an 8s loop (710). DC is removed,
one-shots have 5ms endpoint fades, peaks normalize to .8 (sea .25).

| Sound | SHA-256 |
|-------|--------|
| `assets/audio/cannon.wav` | `ccdbc97759a2604614eb27b899a1023dc3a95ad0245280adba10eb7e7f401460` |
| `assets/audio/impact.wav` | `26ab7d35a34d5fd76ec7e6af3b8a240fc36a03ac3c9a564b03781aa7b2fff3b6` |
| `assets/audio/splash.wav` | `8e01a605881a087ce2779dac05f0258bb5ea533bd0fae09f30afa4c2cce8c918` |
| `assets/audio/sea.wav` | `6b3727e2ba8d43525f9b65829f061f60f84230dfb73364992dce68c531581d26` |

## Engine notice

The game is built with Godot Engine (MIT license). Distributions (plan 08) must preserve the
Godot Engine copyright and license notice, together with its third-party notices.
