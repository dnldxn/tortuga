# Asset attribution

| Path | Author | Date | License |
|------|--------|------|---------|
| `assets/ships/sloop.svg` | Tortuga project (AI-assisted), original work | 2026-09-30 | Same as the Tortuga project license (not yet chosen; TBD) |
| `assets/ships/brig.svg` | Tortuga project (AI-assisted), original work | 2026-09-30 | Same as the Tortuga project license (not yet chosen; TBD) |
| `assets/ships/frigate.svg` | Tortuga project (AI-assisted), original work | 2026-09-30 | Same as the Tortuga project license (not yet chosen; TBD) |
| `assets/ships/3d/{sloop,brig,frigate}.glb` | Tortuga project (AI-assisted), original procedural models | 2026-10-01 | Same as the Tortuga project license (not yet chosen; TBD) |
| `assets/ui/{hull,sails,crew,speed,cannon,distance}.svg` | Tortuga project (AI-assisted), original work | 2026-09-30 | Same as the Tortuga project license (not yet chosen; TBD) |

The legacy ship sprites are hand-written top-down SVGs (bow toward +X, canvases 64×32,
80×40, 96×48). Their in-game replacements are original, texture-free procedural GLBs:
Sunfish Runner (sloop), Crown & Compass (brig), and Resolute (frigate). The HUD icons are
hand-written 24×24 SVG glyphs. No third-party or probe assets are used. Reef Glass water is
original procedural shader art in `view/reef_glass.gdshader`, adapted from the project's
approved browser study (AI-assisted, 2026-09-30; same project license). It uses no image
textures or third-party assets. Shallows, coast, and buoys are drawn procedurally in
`view/arena_view.gd`; 3D ship staging, wind trim, reefing, and gentle motion are implemented
in `view/ship_3d_view.gd`.

## Engine notice

The game is built with Godot Engine (MIT license). Distributions (plan 08) must preserve the
Godot Engine copyright and license notice, together with its third-party notices.
