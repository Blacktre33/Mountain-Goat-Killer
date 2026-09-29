# Surfaces, architecture and props pass

Frames: `art_direction/audit/surfaces/before/` (base commit) and
`art_direction/audit/surfaces/final/` (this branch), 53 player-height views along
z = 44 .. -112, captured by `tools/surface_capture.gd`; `sheet_NN.png` in each
folder are 2x3 contact sheets. Same view names in both folders.

## Problems catalogued in `before/`

| Problem | Where | Cause | Fix |
| --- | --- | --- | --- |
| Salmon flat box + white-outlined grey box near the trail | a04-a06, c01 (log stack, sign) | Kenney kit materials are flat pastel swatches (`wood` = #ffc5a7), the colormap atlas is unfiltered squares | `SurfaceLibrary.PROP_TABLE` swaps every Kenney swatch for the shared scanned timber/bark/slate/iron; log stack and fallen log rebuilt as swept-tube meshes (`_log_pile`, `_fallen_log`) with ringed sawn ends |
| Flat salmon/pink boxes, white slab, pink cone stump (Carrion) | c01, c04 | siege catapult and tree trunks from the same kit | catapult replaced by a generated `siege_wreck` prop; trunk swatches textured |
| Red spikes / daggers, red sphere trees | b05, b06, d-series | flat `Dried bellthorn red` + `leaf_blade` cones + ico-sphere clusters | primitives removed from the Blender scripts; generated `kill_stakes`, `bellthorn_tree`, `bellthorn_shrub` props placed in `_build_hero_props` |
| Lego masonry | fold walls, shrine steps/piers, terraces | identical bevelled boxes | `hewn_block()` in `tools/blender/build_biome_hero_slices.py` and the same in `build_iron_crown_blockout.py`: jittered corners, subdivided + noise-chipped faces, angle-limited chipped bevels, per-block colour in a `Col` vertex attribute, uneven quoin widths per course, dark rubble core so joints read as mortar |
| Flat/nearly black abbey ("Black granite" ~ 0.05) | d03, e-series | albedo tint far below the scan | `SurfaceLibrary` remaps every GLB material by name to the triplanar shader with a readable, desaturated albedo; abbey limestone uses the generated scorched-masonry set |
| Black smudge decals on snow | a07, b11, d-series | alpha planes of near-black colour | all baked patch meshes and `_build_patch_layer` removed. Baked GLB blood/shadow patches use `stain.gdshader` (noise-dissolved alpha); route dressing is now real `Decal` nodes (boots, paws, blood splat + drag, scorch, dirty snow, glossy ice sheen) with alpha PNG + normal maps |
| Wind-crust ridges ending in hard polygons | a-series | opaque ribbon | `snow_drift.gdshader`, alpha fades across both flanks |
| Terrain tiling and dark band | c01, e-series | single scale, fixed colours, dark red carrion floor | `ravine_terrain.gdshader` rewritten (below) |
| Lantern was pole + box; bell pickup orange cone/prism | a03, pickups | primitives | lantern is a swept iron/timber post with crook and four-post iron cage; bell/pouch pickups are generated `neck_bell` / `ammo_pouch` GLBs (`WorldBuilder.pickup_node`) |
| Mother bell a capped cone (flat underside) | b07 | primitive cone | lathe-turned `cast_bell()` with flared lip, waisted shoulder, open mouth, generated bronze PBR |
| Ember particles hard squares | a11, b-series | opaque quad | soft radial sprite, additive |

Not reproduced: black smudges in the moon-lit Crown ash scars after the fix were
re-checked in d/e frames; z-fighting and floating props were not observed in
`before/` beyond the items above (props are height-field snapped, verified by
`test_campaign_pickups` and the per-view frames).

## New assets

- `assets/materials/architecture.gdshader`: triplanar PBR with per-plane two-scale
  anti-tiling, vertex-colour block tint, dirty-snow settling on up-facing faces,
  biome shift (Carrion red / Crown ash) by world z.
- `assets/materials/ravine_terrain.gdshader`: 2-scale anti-tiled sampling for every
  layer, biome soils (forest_ground_04 / cracked_red_ground / burned_ground_01),
  triplanar cliff, height-blended snow cover so drifts follow the relief, dirty
  snow along the trail, slush wetness (low roughness) and sparse view-dependent
  ice glints.
- `assets/materials/generated/` (Higgsfield gpt_image_2_5): frost slate, carrion
  sandstone, iron plate, abbey masonry, banner cloth, cracked ice, dirty snow, iron-bound
  timber, bell bronze; made seamless and given Sobel normal + roughness by
  `tools/build_surface_textures.gd`.
- `assets/materials/decals/` and `tools/build_decals.gd`.
- `assets/environment/props/` (Higgsfield image -> Tripo H3.1 3D): kill_stakes,
  iron_cage, war_banner, neck_bell, ammo_pouch, bellthorn_tree, bellthorn_shrub,
  siege_wreck. Verified in `tools/preview_glb.gd` and in game frames before use.
- `scripts/surface_library.gd`: material presets + GLB/kit remapping.
- Polyhaven CC0 additions: snow_02, forest_ground_04, cracked_red_ground,
  burned_ground_01, rock_face_03, sandstone_cracks (recorded in `assets/LICENSES.md`).

## Verification

Tests run (all pass): test_biome_assets, test_iron_crown_environment,
test_biome_traversal, test_terrain_surface, test_campaign_pickups,
test_runtime_smoke, test_checkpoint_recovery, test_varkas_encounter,
test_stealth, test_pause_replay. `test_iron_crown_environment` no longer requires
`BellthornAbbey_trunk` (bellthorn is now a generated prop placed by world.gd).
Frame rate in the capture harness stays 45-53 fps on this Mac across the route,
dipping to 10-30 only on the first frames after teleporting into a new area
(shader/texture streaming), which the harness's 34-frame settle absorbs.

## Known remaining

- Kenney castle/nature meshes still used for stumps, signs and campfire stones
  (now textured by the shared family, still low-poly silhouettes).
- The bronze on the Crown's nine bells and cast-iron throat bars only receive the
  shared materials; they were not re-modelled.
- Terrace masonry fronts are dressed; terrace tops and the fortress interior walls
  remain single slabs textured triplanar.
