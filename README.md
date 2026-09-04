# Mountain Goat Killer — The Last Bell

A first-person alpine stealth-revenge shooter built in Godot 4.7. Open
`project.godot` in Godot and press Play.

## The story

The Ironhorn herd wore nine named neck-bells. A tenth, the great mother bell,
called the whole valley home. Varkas, the Iron Wolverine, butchered the herd in
the blue hour, gave eight bells to his warpack, and kept Orin's bell at his own
throat. One kid survived beneath the ice trough: the Herdkeeper. Ten winters
later, you return with Maren's carbine to take every name back.

The climb is now a complete three-act journey through three distinct biomes:

- **Whitewood** — living frost pine and the broken family fold. Recover four
  bells from Varkas' camp before the shrine will answer.
- **The Carrion Cut** — sparse dead timber, rust-red stone, old kill-sites, the
  mother-bell shrine, and the exposed Black Ravine. Ringing the bell releases
  every hung Remembrance round and wakes the mountain; recover all eight bells
  carried by the warpack to open the Iron Crown.
- **The Iron Crown** — an ash-dark siege fortress and slaughter courtyard.
  Varkas guards Orin's ninth bell through three unskippable phases: Iron Hide,
  Call the Warpack, and Red Horn, ending with a close-range horn strike.

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
| Esc | Release the mouse; click to re-enter. R after death returns you to the last checkpoint |

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
- `scripts/world.gd` — builds all three biomes: z-blended frost/red-earth/ash
  terrain with height-map collision; living, dead, and burned forest bands;
  restrained environmental remains; the homestead, shrine, ravine, fortress,
  courtyard, lanterns, fires, star dome, aurora, fog shifts, snow, and ash.
- `scripts/enemy.gd` — the Quaternius wolf re-tinted and armed as Varkas'
  wolverines, with animation, bone-attached bells, rifles, restrained hit/death
  blood, and Varkas' breakable iron plates, bellquake, charge, and phase gates.
- `scripts/player.gd` — movement, crouch, noise, decoys, takedowns, carbine,
  second-wind regen, Remembrance embers, beams, and pooled tracers.
- `scripts/main.gd` — gated mission flow, biome atmosphere, HUD, checkpoints,
  mother bell, name-locked gate, Varkas phase cards/bar, and reinforcements.
- `scripts/minimap.gd` — the top-down map drawn each frame from the game state.
- `scripts/audio.gd` — sound: Kenney's CC0 snow footsteps and impact clips, plus
  everything else synthesised at startup (carbine, hits, howls, growls, huffs,
  yelps, the mother bell, wind, the gate, chapter stings), played through
  pooled 2D and positional voices.

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
```

For fast visual QA in a debug run, number keys warp through the authored beats:
`1` Whitewood, `2` Carrion Cut, `3` Iron Crown, `4` the Varkas arena, then `5`
and `6` advance Varkas to his second and third phases. Press `6` once more to
break him and `7` to frame the final horn strike. These shortcuts are guarded
by `OS.is_debug_build()` and are unavailable in a release export.
