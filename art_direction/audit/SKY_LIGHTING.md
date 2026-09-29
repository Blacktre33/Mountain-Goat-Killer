# Sky, moon, lighting and atmosphere pass

Frames: `art_direction/audit/sky/before_*.png` (base commit) and `after_*.png`
(this branch), captured at player height by `tools/sky_capture.gd`
(`Godot --path . --script res://tools/sky_capture.gd -- after [view-prefix] [hud]`).

## What changed

- **Moon**: a real sky object. `assets/materials/night_sky.gdshader` draws an
  orthographic patch of a generated lunar photo (`moon_surface.png`) with limb
  shading, a gibbous terminator, a soft halo, a faint 22 degree ring in
  Widowpine, and crepuscular rays that trees and crags draw over. Its direction
  is `WorldBuilder.moon_direction()`, the same vector as the Moonlight node, so
  the disc, shadows and rim light agree (asserted by `tests/test_sky_atmosphere.gd`).
  The depth-test-disabled Sprite3D is gone; the moon can never draw over
  anything.
- **Sky**: the shader replaces the 0.085-energy panorama. It has a luminous
  horizon band (glow strongest toward the moon), zenith gradient, drifting cloud
  bands with a moon-side silver lining, a two-layer hashed star field hidden by
  cloud and glare, and a faint aurora in Widowpine only. The CC0 HDRI is kept
  as tonal structure. Stars/aurora/moon halo are procedural; the old star dome
  and aurora mesh were removed.
- **Crags**: `distant_crag.gdshader` renders the skyline as near-black
  silhouettes with haze pooled at their base and a thin moon rim, tinted per
  biome, so they read against the bright sky instead of as lit blue blobs.
- **Biomes**: `WorldBuilder.ATMOSPHERES` holds one profile per biome (sky, fog,
  volumetric fog, ambient, exposure, glow, saturation/contrast, moon and fill
  light, snow and ash amounts). `set_biome` now tweens between profiles over
  5 s (interrupt-safe); `set_biome(built, biome, true)` snaps for captures.
  Widowpine is cold blue with aurora and a sharp moon; Carrion Cut is ochre
  dusk with ash drift and a smoke-dimmed moon; Iron Crown is slate sky with an
  ember horizon, colder moon, ash and embers.
- **Post**: AgX tonemapper, per-biome saturation/contrast, forward-scattering
  volumetric fog (anisotropy 0.55), debanding on, and a `GradeOverlay` canvas
  layer (vignette plus fine dithering grain) between the 3D view and the HUD.
- **Lights**: `_build_atmosphere_lights` adds three unshadowed fills so the boss
  court is no longer black (cold moon spill, ember bounce, red uplight at
  Varkas' feet). `main.gd::_update_lights` gives lanterns a candle wobble and
  turns real shadows on for only the two nearest lit flames (dual-paraboloid).
  Moon shadow cascades blend and soften.
- **Particles**: new `AshDrift` (charcoal flakes plus HDR embers, soft round
  sprites) child of the snowfall so it follows the player; amounts per biome.

## Performance

Measured with `RenderingServer.force_draw` (not vsync-throttled) at 2x 3D
scale (2560x1440), M4 Max, per-frame renderer time:

| Biome view | before | after |
| --- | --- | --- |
| Widowpine | 9.9 ms | 10.4 ms |
| Carrion Cut | 5.4 ms | 5.5 ms |
| Iron Crown | 5.3 ms | 6.1 ms |

At the native 1280x720 the game stays locked to 60 fps with about 1 ms CPU
render time. The Iron Crown delta is the extra fills plus lantern shadows.

## Known remaining problems (outside this lane)

- The abbey's "Black granite" material (glb `EnvironmentVisuals`) is nearly
  black; looking back at the gate from the court (view `i4`) is still pitch dark
  because the surface reflects almost no light. It needs a lighter albedo or
  roughness in the architecture pass.
- Foreground terrain in Carrion Cut renders as a flat dark band (view `c3`);
  that is the terrain shader, not lighting.
- Sprint/hit-flash post effects (damage vignette, low-health desaturation) are
  not implemented; the grade overlay shader has room for them.
