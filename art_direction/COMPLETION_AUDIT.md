# The Last Bell — local completion audit

Verified on 2026-09-05 in the root Godot project on this Mac (Godot 4.7.2,
Metal Forward+, Apple M4 Max). This is the playable single-mission build.

## Requested work and evidence

| Request | Delivered | Evidence |
| --- | --- | --- |
| Finish the game | Deployment through three biomes, eight recovered bells, mother bell, gated courtyard, three boss phases, ninth-bell horn strike, ending and replay. Escape genuinely pauses enemy movement and attack timers. Six refuge entries and action-state recovery are checked. | `campaign/final-run.log`, `campaign/result.png`, `final_verification/`, `interface/` |
| Use Blender and Godot | Editable Blender sources and rebuild scripts for vegetation, rocks, all three landmarks, Varkas's animated body and new facial sculpt; imported assets used in the running Godot game. | `../art_source/`, `../tools/blender/`, `../assets/environment/`, `../assets/wolf/` |
| Improve three biomes and textures | Widowpine's frost pine and broken fold; Carrion Cut's dead timber, exposed red earth, shrine and remains; Iron Crown's pale occupied bell abbey, rough iron and ash. Scanned surface normals and roughness, irregular ground blending, original tree/rock kits, and continuous landmark visibility. | `widowpine/widowpine-ground-pass.png`, `carrion_cut/carrion-cut-ground-pass.png`, `iron_crown/iron-crown-ground-pass.png`, `traversal/`, `../assets/LICENSES.md` |
| Improve Varkas | Bespoke telegraphed swipe, fixed-lane charge and jumpable quake with recovery openings, convergence interruption, three unskippable phases, live reinforcements, reachable final horn strike and complete retry reset. Sculpted short muzzle, guard fur, scars, torn plates and hooked Red Horn. | `final_verification/varkas_combat.log`, `final_verification/varkas_encounter.log`, `campaign/final-run.log`, `iron_crown/varkas-sculpt-three-quarter.png` |
| Grittier story and a little gore | Nine individual memories, Orin as the protagonist's brother, a coherent tenth mother bell, grittier intro/chapter/ending text, brief dark blood on hits and deaths, and restrained old kill-sites. | `../scripts/story.gd`, `widowpine/carbine-hit-effects.png`, `final_verification/hit-effects.log`, `campaign/result.png` |

## Validation

All thirteen functional suites pass: controls, Remembrance, stealth/story,
runtime, Iron Crown environment, biome assets, boss combat, courtyard
counterplay, terrain orientation, biome traversal, checkpoint recovery,
campaign pickups, and pause/replay. Final suite logs contain no reported
warnings or errors. Graphical pause/replay additionally uses actual Escape
and mouse input and clicks the return button to create a fresh title scene.

The full graphical campaign uses real movement/collision, carbine shots,
normal resources, active AI, pickups and interactions. Final result: **nine
bells, mother bell rung, gate open, phases 1/2/3, active reinforcements, zero
retries, 42 shots, 68 health and 6/136 ammunition**. The pathfinder correction
and earlier progression regressions are described in `campaign/PLAYTEST.md`.

Rendered frames were inspected for all three biomes, Varkas's sculpt and
counterplay, blood effects, pause and the ending. README contains the repeat
commands. `git diff --check` passes.

## Local delivery and limits

Double-click `../Play The Last Bell.command` in Finder, or open
`../project.godot` in Godot and press Play. The launcher uses the Godot app
installed on this Mac; it is not a self-contained release export. Sources
and changes remain local and uncommitted.

The campaign is an accurate-aim automation proof, not a human playtest or a
playtime estimate. Human difficulty, story-reading pace, controller support
and performance on other hardware have not been established. Art is stylized;
the concept images are direction references rather than pixel-match promises.
Forcing the engine to quit immediately with `--quit-after 20` starts and exits
successfully but reports two audio objects retained at shutdown. Normal
capture/test cleanup and the ending's exit path allow the mixer to drain.
The launcher also completed the real main-scene Iron Crown capture and normal
shutdown with no warning (`final_verification/launcher-normal.log`).
