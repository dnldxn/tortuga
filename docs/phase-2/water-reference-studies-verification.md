# Reference-inspired water studies — verification

Date: 2026-09-30.

## Delivered

`tools/water-preview/index.html` contains three animated procedural water samples
and their comparison controls. It is about 18 KB with no external dependencies.
The visual design gives the water most of the viewport with compact sample
selectors and shared controls. A matching HTML copy was added to the existing
Tailscale preview server's watched content directory; its log confirms detection
and subsequent updates. The pre-existing study was preserved.

This is a presentation prototype for choosing a water style. It does not replace
the game's current sea drawing or change the simulation.

## Automated and offscreen checks

- JavaScript parses with Node's `vm.Script`.
- 21 assertions passed using a stubbed DOM/WebGL host: initial state, time
  advance, pause, three sample selections, selection accessibility state, wind
  labels/vector and advection, effect toggles, ship visibility, speed label,
  hidden-tab behavior, reduced-motion startup, and identical published files.
- The actual embedded vertex and fragment shaders compiled and linked in an
  OpenGL ES 2 EGL surfaceless context using Mesa llvmpipe (software rendering).
- Seven 1200×720 images rendered without GL errors: each style, a later frame,
  foam off, glitter off, and a changed wind direction.
- Pixel comparisons confirmed distinct styles, time evolution, and visible
  changes from foam, glitter, and wind controls.
- Rendered images were inspected for the water appearance. This is shader
  evidence, not a browser layout screenshot or proof of native GPU performance.
- `git diff --check` passed.

Session verification helpers and renders are under `/tmp/tortuga-water-*`.
Commands used:

```sh
node /tmp/tortuga-water-controls.cjs
gcc /tmp/tortuga-water-render.c -o /tmp/tortuga-water-render -lEGL -lGLESv2 -lm
LIBGL_ALWAYS_SOFTWARE=1 XDG_CACHE_HOME=/tmp/tortuga-water-cache \
  /tmp/tortuga-water-render tools/water-preview/index.html \
  /tmp/tortuga-water-reef.ppm 0 6 315 1 1
git diff --check
```

Render arguments after the output path: style (0–2), time in seconds, wind
degrees, foam enabled, glitter enabled. Helpers in /tmp are temporary.

## Initial environment limits

- Chromium and Chromium Headless Shell could not start: sandbox socket calls
  returned `Operation not permitted`. Actual browser layout, controls,
  fullscreen, mobile rendering, and WebGL context recovery need a real browser.
- The sandbox also denied local HTTP binding, HTTP connections, and access to
  the Tailscale daemon socket. The existing server's state records
  `http://100.67.211.123:52099`, and its live log detected the published page,
  but remote HTTP reachability was not independently tested.
- Context7 documentation lookup failed with `fetch failed`; this session cannot
  run outside the sandbox. Tailscale CLI help and official web documentation
  were consulted for the optional persistent hosting command.
- RTK was unavailable on PATH, so verification commands ran directly.
- No macOS/native-game test, Godot integration, export, or release was performed.

## Reef Glass refinement — 2026-09-30

The owner selected Reef Glass and requested gentler swells and faster whitecap
fades. Its broad swell weight changed from 0.58 to 0.34 (41% lower), intermediate
wave weight from 0.24 to 0.16, and fine ripples from 0.075 to 0.060. Whitecap
lifetimes changed from 6–12 to 4–8 animation seconds, shortening both fades by
one third. Smooth opacity envelopes and the wind direction are retained.
The other two comparison samples are unchanged.

With the session's sandbox restrictions removed:

- HTTP GET to the existing Tailscale address returned 200.
- Chromium loaded the served page and compiled/rendered its actual WebGL shader.
  The default headless graphics backend lost its context; explicit SwiftShader
  software rendering worked without page errors.
- Actual browser checks passed for reduced-motion startup, play/time advance,
  pause, wind labels, effect and ship toggles, and all three sample selectors.
- Desktop (1440×1000) and mobile (390×844) screenshots were captured and inspected;
  the mobile page has no horizontal overflow. The mobile wind label was moved
  below the playback buttons to remove an overlap; browser geometry checks pass.
- The 21 existing stubbed control assertions passed again, including identical
  standalone and published copies.
- The refined shader also compiled and rendered via EGL; this run reported the
  NVIDIA RTX 2070 renderer, despite the software-preference environment variable.
- `git diff --check` passed.

Screenshots: `/tmp/tortuga-reef-gentle-desktop.png` and
`/tmp/tortuga-reef-gentle-mobile.png`. These browser checks supersede the initial
browser and host-HTTP verification limitations above. Access from a separate
Tailscale device, native mobile hardware, fullscreen, WebGL context recovery,
and Godot/macOS integration remain untested.
