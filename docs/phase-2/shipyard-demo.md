# Phase 2 — Four-ship 3D demo

The shipyard now presents one detailed stylized model per class in a shared, interactive viewer. This is a browser demo only: no vessel definitions, playable roster, game GLBs, engine settings, or release files were changed by this work.

## Run and controls

```sh
cd shipyard-gallery
npm run preview
# Open http://127.0.0.1:8765
```

The preview serves local files on loopback. Three.js 0.180.0, OrbitControls, geometry, and the generated smoke texture are local; no CDN, backend, texture download, or new package is needed. Existing dependencies can be restored with `npm ci` if absent.

Select Sloop, Brig, Frigate, or Galleon. Drag to orbit; scroll/pinch or use +/− to zoom. With the canvas focused, arrow keys orbit, +/− zoom, and R resets the view. Class changes clear smoke and reset the camera. Wind, ship heading, speed, and motion remain adjustable.

**Fire cannons** fires every mounted gun. Three soft white sprites originate at each transformed muzzle, expand and drift outward/upward, then disappear after four seconds. Firing has a one-second cooldown. Smoke fades with ship motion disabled. The reusable pool is capped at 480 sprites; sustained Galleon firing uses 384.

**Download GLB** exports only the selected ship, with named rig pivots and muzzle markers. The status reports a download request, since browser saving is handled by the browser. The original variant definitions remain in source, while the visible demo uses Sunfish Runner, Crown & Compass, Resolute, and Galleon.

## Models and footprint

| Class | Total guns | Per side | Meshes | Triangles | GLB bytes |
|---|---:|---:|---:|---:|---:|
| Sloop | 8 | 4 | 178 | 26,682 | 1,199,532 |
| Brig | 12 | 6 | 271 | 38,254 | 1,851,592 |
| Frigate | 16 | 8 | 324 | 45,214 | 2,225,464 |
| Galleon | 32 | 16 | 466 | 56,978 | 2,957,700 |

Runtime JavaScript and vendored Three.js files total 993,615 bytes (excluding retained unused concept images). The four verified GLBs are also packaged locally in `build/phase-2/shipyard-demo/ship-models.zip` (1,439,004 bytes); this ignored build artifact does not affect game exports.

Galleon has eight guns on each of two decks per side, a raised forecastle, stepped sterncastle, chestnut/crimson/gold materials, square-rigged fore/main masts, and a lateen mizzen. Its overall bounds are 1.294× Frigate's length, 1.350× its beam, and 1.251× its height.

All ships retain planking, deck fittings, anchors, helm, hatches, capstan, stitched sails, and rigging. Gunports follow the hull at their own elevation, cannon mouths have dark bores, and hull/deck triangle winding was corrected for exterior visibility. Shared materials and geometries are disposed once when replacing a model. One renderer survives class changes, and rendering pauses while hidden.

`createShipModel(type, variantIndex = 0)` retains its existing fields and adds `cannons: [{ side, barrel, muzzle }]` plus dimensions. Existing primary IDs, sail pivots, and muzzle names/order remain compatible with the unchanged game exporter. The new generator affects game assets only if an explicit future game export is run.

## Verification record — 2026-10-02

Host: macOS arm64. Rendered checks used the Codex in-app browser at 1280×900 and responsive overrides. These are browser-demo observations, not Godot game verification or a hardware-floor benchmark.

Automated checks run:

```sh
npm test --prefix shipyard-gallery
node --check shipyard-gallery/dist/app.js
node --check shipyard-gallery/dist/ship-models.js
git diff --check -- shipyard-gallery
```

**Result: 8 tests passed, 0 failed, 0 skipped.** The model/effect suite covers exact cannon counts, balanced sides, unique marker names, barrel-tip alignment, outward muzzle directions, finite geometry, valid indices, exterior normals, independent sail pivots, Galleon proportions/castles/lateen rig, and all retained variants. GLTFLoader reads all four exported GLBs back and checks geometry and marker positions; no smoke, scenery, lights, or image textures are exported. Smoke checks cover transformed origins, cooldown, expansion, opacity, four-second cleanup, repeated-fire capacity/reuse, clearing and disposal. A shared-framing check projects each model at headings 0/90/180/270 into desktop and two narrow viewports.

Vendored OrbitControls and its MIT license were byte-compared with the installed Three.js 0.180.0 files. All three existing game GLB SHA-256 hashes match the pre-work snapshot. No Godot tests were run because this work does not change the game or its assets.

### Initial rendered observations (before the detail refinement)

| Model | Sample FPS | Render calls | Rendered triangles |
|---|---:|---:|---:|
| Sloop | 60.0 | 156 | 10,006 |
| Brig | 60.0 | 270 | 13,750 |
| Frigate | 59.0 | 336 | 16,242 |
| Galleon | 59.0 | 473 | 20,182 |

These are brief one-second samples, with ship motion off, not sustained benchmark claims. A single Galleon volley showed 96 active smoke sprites, 569 render calls, 20,374 triangles, and 60.0 FPS. After fading, active smoke returned to zero and rendering returned to 473 calls / 20,182 triangles, with motion still off.

Pointer orbit, wheel zoom, zoom buttons, keyboard orbit, reset, smoke emission/fade, and switching ships during smoke were exercised through the actual UI. Smoke returned to zero after switching to Sloop. Responsive layouts at 390×844 and 320×800 had no horizontal overflow. Screenshots cover bow, stern, both broadsides (default and port), and above views for every ship. The final camera correction was visually rechecked from both ends, including Galleon at 320px width. It fits the largest model’s projected bounds at the current heading while preserving a common scale across classes; heading changes retain inspection zoom and orbit. Independent implementation review and focused framing review both passed with no actionable findings. Evidence is in [evidence/shipyard-demo](evidence/shipyard-demo/), including [Galleon firing](evidence/shipyard-demo/galleon-smoke-expanded.jpg).

### Limits

- Physical touchscreen orbit/pinch has not been exercised; touch is configured through the vendored OrbitControls. Responsive browser widths are checked separately from physical-device testing.
- The embedded browser did not report a saved download event. GLB generation and independent readback are verified; native browser file saving remains unverified.
- Three.js emits its existing LineBasicMaterial export advisory for rigging/outline materials. All mesh/triangle counts and muzzle positions survive readback. The vendor exporter was not patched to hide the advisory.
- No Godot rendering, native game platform, release, or low-end GPU verification is claimed.


## Detail refinement — 2026-10-02

The requested increase in detail keeps all four silhouettes, relative dimensions, gun totals, named muzzle transforms, and sail pivots intact. The models now include seven hull plank courses with staggered joints and treenails, denser deck boards and rail posts, framed and divided windows, paneled bulkheads and doors, grated hatches, quarterdeck stairs, castle deck planking, caged lanterns, cannon carriages/trucks/trunnions, port hinges, barrel staves, capstan handles, anchor tackle, belaying pins, paired deadeyes/lanyards, fourteen ratlines per shroud, yard footropes, and denser sail stitching visible from both faces.

| Class | Original triangles | Refined triangles | Ratio | Sample FPS | Render calls |
|---|---:|---:|---:|---:|---:|
| Sloop | 10,006 | 26,682 | 2.67× | 59 | 200 |
| Brig | 13,750 | 38,254 | 2.78× | 59 | 326 |
| Frigate | 16,242 | 45,214 | 2.78× | 59 | 397 |
| Galleon | 20,182 | 56,978 | 2.82× | 58 | 533 |

Triangle counts quantify added geometry, not an objective visual-quality score. Small fixed fittings are merged into seven shared-material meshes per model. The installed Three.js 0.180.0 `BufferGeometryUtils.js` is vendored locally and byte-compared with the package; its existing MIT license applies. There are still no downloaded textures or additional npm dependencies.

Verification: `npm test --prefix shipyard-gallery` passes all **8 tests**, including all four GLB export/readback checks and the existing smoke/rig/framing checks. The model checks also enforce at least 2× and under 3× the original triangle totals and at most eight batches for the new fittings. `node --check shipyard-gallery/dist/ship-models.js` and scoped `git diff --check` pass. All four generated GLBs were repackaged into the ignored ZIP above and ZIP integrity verified. Existing game GLBs and gameplay code were not changed by this refinement.

Rendered checks inspected all four models in close broadside and overhead/opposite-side views, the Galleon stern, and the Galleon at 390px width. Evidence is in [evidence/shipyard-demo/detail-pass](evidence/shipyard-demo/detail-pass/); close-up captures use inspection zoom and therefore are not comparative-scale images. The FPS figures are brief browser samples during this pass, not sustained benchmarks. Later idle Galleon samples in the embedded browser fell to 9–12 FPS; switching models restored 58–60 FPS, including the Galleon with motion on. The cause of that intermittent slowdown was not isolated, so sustained frame rate is not claimed. Galleon firing showed 96 white sprites, 629 render calls, 57,170 triangles and 60 FPS with motion off; all smoke subsequently disappeared. Physical touchscreen testing and native browser download saving retain the limitations listed above.
