# Mountain Goat Killer — The Last Bell

A first-person alpine stealth-revenge shooter built in Godot 4.7. Open
`project.godot` in Godot and press Play. On this Mac, you can also double-click
`Play The Last Bell.command` in Finder to launch directly using the installed
Godot application. The ending offers a return to the title or an exit.

## The story

The Ironhorn herd wore nine named neck-bells. A tenth, the great mother bell,
called the whole valley home. Varkas, the Iron Wolverine, butchered the herd in
the blue hour, gave eight bells to his warpack, and kept Orin's bell at his own
throat. One kid survived beneath the ice trough: the Herdkeeper. Ten winters
later, you return with Maren's carbine to take every name back.

Each recovered neck-bell reveals a brief memory of the person who wore it:
the builder whose trough hid you, the healer who had nobody left to save her,
Maren's last instruction, and Orin, your younger brother. The final climb takes
eight names into the abbey; Varkas still carries the ninth.

The climb is now a complete three-act journey through three distinct biomes:

- **Widowpine** — living frost pine and the broken family fold. Recover four
  bells from Varkas' camp before the shrine will answer.
- **The Carrion Cut** — sparse dead timber, rust-red stone, old kill-sites, the
  mother-bell shrine, and the exposed Black Ravine. Ringing the bell releases
  every hung Remembrance round and wakes the mountain; recover all eight bells
  carried by the warpack to open the Iron Crown.
- **The Iron Crown** — the herd's pale nine-bell abbey, now mutilated with
  Varkas' black iron, cages, scaffold forts, and slaughter courtyard. Its
  founding bell hangs in a scarred central gable above eight smaller name
  bells; the widened inner court gives the final charge a clean dodge lane.
  Varkas guards Orin's ninth bell through three unskippable phases: Iron Hide,
  Call the Warpack, and Red Horn, ending with a close-range horn strike.

Varkas announces each attack before impact. Back away from Iron Jaw; jump the
Bellquake pulse or leave its ring; sidestep Red Horn's marked, fixed charge
lane. Every attack leaves a recovery opening. Two converging Remembrance
rounds can interrupt the charge. His normal warpack bite and random ranged
damage do not run underneath these attacks. A failed attempt restores his
first-phase movement and clears every pending attack.

## Controls

| Key | Action |
| --- | --- |
| WASD / Shift / Space | Move, sprint, jump (with coyote time) |
| C | Crouch: quieter, slower, harder to see |
| Mouse / RMB | Aim / focus |
| LMB / R | Fire / reload |
| G | Throw a stone; wolverines investigate where it lands |
| E | Interact: horn-strike an unaware wolverine from behind, snuff a lantern, ring the mother bell |
| F (tap / hold) | Remembrance: hang a live round where you stand / release every hung round at once |
| Esc | Pause the encounter; click or press Esc to resume. R after death returns to the last refuge; R after victory returns to the title |

## Stealth

Wolverines hunt with three senses, and the HUD shows what they know.

- **Sight.** They need line of sight and you inside their view cone. Darkness
  shortens their range; lantern and fire light stretches it. Crouching cuts
  how fast you are noticed. Snuff lanterns to own the dark.
- **Hearing.** Every action has a noise radius: crouch-walking is nearly
  silent, walking carries, sprinting carries far, a landing thumps, a gunshot
  wakes the whole camp. Hanging a Remembrance round is silent; releasing the
  volley is not. A thrown stone pulls a patrol toward where it lands.
- **Scent.** The wind drifts around the compass and carries your scent
  downwind. Keep the wind in your face and a wolverine cannot smell you; stand
  upwind of one and it will find you without ever seeing you. The HUD reads
  the wind relative to your facing and whether your scent is carried away or
  toward the nearest hunter.

The minimap (top right) is centred on you with north up: the valley floor
and walls, lit lanterns and fires, dropped bells and pouches, hung Remembrance
rounds with their beams, wolverines within earshot coloured by what they know,
the wind, and the current objective pinned to the edge when it is off the map.

Each wolverine runs a patrol / suspicious / alert / search loop. Its eyes tell
you what it knows: cold blue, amber when suspicious, red when hunting. An
alert wolverine howls and brings the pack within earshot. Shots into an
unaware wolverine are ambushes and hit harder; getting behind one lets you
finish it silently with a horn strike.

## Remembrance

Tap F to spend one round and leave it hanging at your muzzle, frozen on your
aim line. Leave up to six across the ravine. Hold F and they all fire at once
from where they were left, each nudged onto an enemy near its line. Two rounds
converging on one target stagger it and hit harder. Hung rounds flare when an
enemy crosses their beam, so a round left covering a flank is also a tripwire.

## Systems

- `scripts/stealth.gd` — pure perception math (noise radii, wind and scent,
  sight rate, hearing, the detection meter, takedown rules).
- `scripts/story.gd` — the storyline: bell names, intro, chapters, objectives.
- `scripts/remembrance.gd` — pure Remembrance logic.
- `scripts/world.gd` — builds all three biomes: upward-facing terrain with
  height-map collision and scanned dirty-snow/dark-rock normals. The shared
  `assets/materials/ravine_terrain.gdshader` blends snow coverage, exposed red
  earth and ash using irregular drift boundaries rather than colour alone, with
  shallow wind-crust geometry that gives the opening path player-scale relief;
  custom Blender pine and dead-tree bands;
  a custom PBR ravine-rock family; the Widowpine broken fold, Carrion Cut
  mother-bell shrine, Iron Crown bell-abbey, restrained environmental remains,
  procedural crag skyline, lanterns, fires, volumetric fog, snow, and ash,
  beneath a CC0 overcast-night HDR panorama. Forward+ SSAO and indirect-light
  contact shading are tuned for desktop play. Modular Blender sources are
  preserved for editing, while their static game exports are material-batched
  and remain visible along the continuous ravine as local weather changes.
- `scripts/enemy.gd` — the Quaternius wolf re-tinted and armed as Varkas'
  wolverines, with animation, bone-attached bells, rifles, restrained hit/death
  blood, and a separate smooth-subdivided Blender hero mesh for Varkas. His
  inherited skull is rebuilt into a low, broad, short-muzzled wolverine with
  round ears, an original guard-fur texture with animation-following UVs,
  phase tints that preserve its detail, a joined Blender facial sculpt with
  short guard-fur geometry, uneven cheek markings, a healed scar, and small
  downward fangs; the hero silhouette also carries weathered torn iron plates, a scarred
  phase-three Red Horn, embers and underlight,
  bellquake, charge, and unskippable phase gates.
- `scripts/player.gd` — movement, crouch, noise, decoys, takedowns, carbine,
  second-wind regen, Remembrance embers, beams, pooled tracers, and restrained
  impact trauma for Varkas' phase breaks and set-piece attacks.
- `scripts/main.gd` — gated mission flow, biome atmosphere, HUD, checkpoints,
  mother bell, name-locked gate, Varkas phase cards/bar, reinforcements, and a
  complete Iron Hide retry reset after a failed climax.
- `scripts/minimap.gd` — the top-down map drawn each frame from the game state.
- `scripts/audio.gd` — the mixer and sound bank: about 200 offline-rendered
  44.1 kHz clips (`tools/audio/`, registry in `scripts/audio_bank.gd`) plus
  Kenney's CC0 footsteps and impacts, routed through Music / SFX / Ambience /
  Voice / UI buses with a canyon reverb send, distance air absorption,
  line-of-sight occlusion, ducking and a master limiter. Volumes persist in
  `user://audio.cfg`. `scripts/music.gd` is the adaptive score (biome themes,
  three boss phases, victory, death), `scripts/ambience.gd` the wind and
  positional bed events, `scripts/voice.gd` and `scripts/subtitles.gd` the
  Higgsfield-generated narration, Varkas taunts and pack barks with subtitles,
  and `scripts/audio_watch.gd` drives all of it from the campaign state.
- `scripts/weapon_view.gd`, `scripts/combat_fx.gd`, `scripts/hud_widgets.gd` —
  the first-person carbine and gloved hands with procedural hip / aim / sprint /
  reload / bolt / gesture animation, muzzle flash, casings, per-surface impacts
  and bullet-hole decals, hit markers, damage arcs, and the HUD widgets.
- `scripts/pack_director.gd`, `scripts/enemy_nav.gd`, `scripts/enemy_bullet.gd`,
  `scripts/enemy_fx.gd`, `scripts/enemy_pose.gd` — pack roles and attack tokens,
  a runtime navigation mesh with whisker steering, rifleman rounds, and the
  enemy effect and animation helpers used by `scripts/enemy.gd`.
- `scripts/surface_library.gd` — triplanar PBR surface presets that remap the
  imported architecture onto the generated and scanned texture sets.

Third-party assets are public domain (CC0); see `assets/LICENSES.md`.

## Automated checks

The first command refreshes Godot's class cache and imports after scripts or
assets are added:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_controls.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_remembrance.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_stealth.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_runtime_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_iron_crown_environment.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_biome_assets.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_varkas_combat.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_varkas_encounter.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_terrain_surface.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_biome_traversal.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_checkpoint_recovery.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_campaign_pickups.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_pause_replay.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_player_feel.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_enemy_behavior.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_sky_atmosphere.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_audio_registry.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_audio_watch.gd
```

The custom Blender sources are reproducible with:

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/blender/build_widowpine_tree_kit.py
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/blender/build_ravine_rock_kit.py
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/blender/build_biome_hero_slices.py
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/blender/build_iron_crown_blockout.py
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/blender/build_varkas_wolverine.py
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/blender/build_varkas_head.py
```

`tools/audit_capture.gd` renders player-height frames of every biome and the
enemies (run without `--headless`); output goes to `art_direction/audit/final/`.

Repeatable live proof frames use Godot's user-argument separator:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --capture-widowpine-live
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --capture-carrion-live
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --capture-iron-crown-approach
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --capture-varkas-phase1
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --capture-varkas-phase3
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --capture-varkas-execution
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tests/test_varkas_encounter.gd -- --capture-varkas-combat
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tests/test_terrain_surface.gd -- --render-terrain-proof
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tools/capture_biomes.gd
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tests/test_biome_traversal.gd -- --capture-traversal
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tools/capture_varkas_portrait.gd
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tools/capture_hit_effects.gd
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tests/test_pause_replay.gd
/Applications/Godot.app/Contents/MacOS/Godot --path . --resolution 960x540 --fixed-fps 60 --script res://tools/playtest_campaign.gd
```

For fast visual QA in a debug run, number keys warp through the authored beats:
`1` Widowpine, `2` Carrion Cut, `3` Iron Crown, `4` the Varkas arena, then `5`
and `6` advance Varkas to his second and third phases. Press `6` once more to
break him and `7` to frame the final horn strike. These shortcuts are guarded
by `OS.is_debug_build()` and are unavailable in a release export.
