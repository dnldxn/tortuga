# Tortuga water samples

Open `index.html` directly in a browser. It is a standalone, dependency-free WebGL
app: no install, asset downloads, external fonts, or build step.

Three original procedural studies inspired by the supplied reference:

- **Reef glass (selected):** turquoise shallows, stationary reef patches,
  refracted caustics, gentler swells, and shorter whitecap fades.
- **Painted passage:** soft blue-green swells with a quieter painted surface.
- **Storybook sea:** simplified color bands and brighter illustrated crests.

Wind direction controls the direction of travel, in screen coordinates:
0° east, 90° south, 180° west, 270° north. The default is 315° northeast.
Surface texture, swell phases, and whitecaps advect downwind; the seabed stays
fixed. Seeded whitecap lifetimes fade to zero before changing location.
Sun glitter follows surface normals, with gentle independent twinkling.

Controls include pause, speed, wind, foam, glitter, ship visibility, and fullscreen
where supported. Reduced-motion preference starts paused. Hidden tabs stop
advancing. Rendering is capped at 1.6 million pixels and 1.5 device pixel ratio.

## Existing Tailscale preview

The active preview server watches:

`.superpowers/brainstorm/321219-1790801335/content/`

An identical copy is published as `water-reference-studies.html`. The server
recorded the new page and later updates. Its recorded address is:

<http://100.67.211.123:52099>

The root displays the newest HTML study. The older `water-studies.html` is
preserved. HTTP and desktop/mobile Chromium checks now pass from this host.
Access from another Tailscale device has not been independently checked.

For a persistent independent endpoint, the standalone directory can also be
served with Tailscale Serve from an unrestricted owner shell:

```sh
tailscale serve --bg --set-path=/tortuga-water /home/ddixon/projects/tortuga/tools/water-preview
```

This optional command was **not run**. Consult
[Tailscale Serve documentation](https://tailscale.com/docs/reference/tailscale-cli/serve)
and inspect existing Serve configuration before setting up a new endpoint.

These are browser art-selection samples, not Godot captures. No gameplay,
simulation, assets, or release files were modified. See
`docs/phase-2/water-reference-studies-verification.md` for verification limits.
