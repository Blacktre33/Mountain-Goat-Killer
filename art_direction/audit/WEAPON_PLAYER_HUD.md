# Weapon, hands, player feel and HUD

Frames in this folder were rendered in a real window by `tools/weapon_capture.gd`
(`CAPTURE_ONLY=<step>` renders one) and viewed one by one. `tools/weapon_preview.gd`
is a turntable of the rig outside the game.

## Viewmodel: the Herdkeeper and gloved hands

- Reference art from Higgsfield `gpt_image_2_5` (`art_source/weapon/carbine_ref_*.png`,
  `glove_ref_*.png`). Image-to-3D: Hunyuan3D v3 (11 credits) and Meshy 7 with PBR
  (38 credits) both ran on the carbine; Meshy won (faithful silhouette, worn blued
  steel, brass, wood grain, real metal/rough/normal maps, 30k triangles). The glove
  is Hunyuan3D v3 (11 credits), decimated from 500k to 27k triangles. Total 61.25
  credits including the images.
- `tools/blender/build_herdkeeper_viewmodel.py` rotates the muzzle to -Z, scales to a
  1.06 m carbine, mirrors the generated left-side bolt handle to the right, splits
  `Body`, `Bolt`, `Bell` (charm) and a modelled `Magazine`, caps the holes the split
  leaves, drops the bolt handle so its knob clears the sight picture, stretches and
  slims the jacket sleeve, and exports `assets/weapon/herdkeeper.glb` and `glove.glb`.
  Empties mark the muzzle, ejection port and sights.
- `scripts/weapon_view.gd` is the rig: gun, two gloves, flash quads, smoke, a private
  fill light on its own visual layer, and every animation (all procedural).
  Poses: hip, ADS (rear sight top on the optical axis, front blade on the crosshair),
  sprint-lowered, crouch, wall-lowered. Layers: idle breath, walk bob (x, y, z, roll,
  yaw), movement lean, look inertia springs, recoil springs (z and pitch), landing dip,
  bell swing. Gestures: bolt cycle after every shot, multi-phase reload (tilt, hand to
  well, magazine out and dropped, fresh magazine up, seat, rack bolt) timed to
  `RELOAD_SECONDS`, dry fire, hang a round (F tap), horn strike, stone throw with the
  release delayed to the hand, equip.
- Springs sub-step at 8 ms so a hitched frame cannot fling the weapon.

## Shooting feedback

`scripts/combat_fx.gd`, all pooled: impact bursts per surface (snow puff, rock chips
+ dust + sparks, wood splinters, metal sparks, flesh), shallow bullet-hole decals in a
36-decal round-robin pool, brass casings and dropped magazines with manual gravity and
bounces. Muzzle flash is three billboarded star quads, a smoke wisp pool and a light
that only lights the world. Hit markers (hit, headshot, kill), damage direction arcs,
red vignette with desaturation and a heartbeat pulse, and tuned shake live in
`scripts/hud_widgets.gd` and `scripts/player.gd`.

Known limit: `world.gd` gives rocks, signs and props box colliders fitted to their
bounds, so an impact puff appears on the invisible box and a decal does not touch the
mesh. Terrain hits (snow, cliff) decal correctly. Trimesh colliders in world.gd would
fix it; `CombatFX.surface_of` already reads a `surface` metadata string if the world
owner adds one.

## Movement (`scripts/player.gd`, `tests/test_player_feel.gd`)

Snappy ground response (walk speed in 7 frames, full stop in 7 frames and 0.27 m),
harder braking when reversing, slower sprint ramp and stop so both read; variable
jump height (release early to cut the rise), jump buffer, coyote time, heavier fall;
step-up over ledges up to 0.42 m (never over steep slopes or walls) with the eye
riding the step; floor snap, constant speed and stop-on-slope for stable slopes;
landing camera dip proportional to fall speed; footfalls by distance travelled
(sprint 0.35 s, walk 0.41 s, crouch 0.62 s) with a surface probe; bob that fades out
smoothly; crouch stand-up refused under a ceiling by a shape cast and retried every
frame; pitch clamped; mouse-look smoothing off by default with a pause-menu toggle.

## HUD

Theme with outlined labels and slate/brass buttons; drawn widgets (compass with
objective diamond and distance, dynamic crosshair, ammo pips with reload sweep, will
bar with second-wind mark, Remembrance slots); circular radar with view cones and
bell pips replacing the black square; stealth plate with a high-contrast state word;
objective stack that wraps instead of colliding; chapter card lowered below the
compass and given a backdrop and rule; themed pause, death and ending screens.

## Frames

`weapon_hip`, `weapon_ads`, `weapon_sprint`, `weapon_reload_1..3`, `weapon_fire`,
`weapon_bolt_open`, `weapon_lowhealth`, `gesture_hang`, `gesture_throw_*`,
`gesture_takedown_*`, `gesture_wall`, `fx_impact_snow|wood|rock`, `fx_decals_snow`,
`hud_hitmarker_*`, `hud_pause`, `hud_chapter`, `hud_death`, `hud_ending`.
