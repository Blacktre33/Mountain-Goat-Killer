# Continuation checkpoint — 2026-09-05

## Final: playable local build and completion audit

The requested single-mission game work is complete. See `COMPLETION_AUDIT.md`
for scope, evidence and limits. The local Finder launcher is
`../Play The Last Bell.command`, using the installed Godot application.

The final campaign playback reaches nine bells, the rung mother bell, open
Iron Crown, all three Varkas phases, active reinforcements and the ending:
42 shots, 68 health, 6/136 ammunition, zero retries. The actual gameplay run
is preserved in `campaign/final-run.log` and `campaign/result.png`.

Final vegetation has irregular live boughs, forked needle sprays, wind gaps
and broken dead branches. The rebuilt assets were imported, bounds checked
and all three biome ground views rendered and inspected. The actual carbine
hit capture shows the restrained brief spray and stain.

Escape now pauses the encounter, not merely the overlay. Click or Escape
resumes without firing. The pause screen hides the crosshair. Ending buttons
sit above the victory veil; Return to Title creates a fresh mission, and
Leave the Mountain allows audio cleanup before exiting. The ascent objective
now directs the player to the gate after eight recovered bells.

All thirteen functional suites pass with clean saved logs. Graphical
pause/replay verifies real key/mouse events, frozen enemy movement/timers and
a click returning to the fresh title. It was rerun after final UI adjustments.
Runtime smoke and story checks also pass after the final changes.
`final_verification/` preserves the logs. `git diff --check` passes.

The initial final-run bot stalled against a terrace: its flat grid connected
floor samples across a height discontinuity. The probe now builds a 3D graph
with neighbor height limits and checks horizontal progress; the successful
repeat uses normal player collision throughout. No world collider was removed.

Human difficulty and story-reading pace remain unmeasured. This is a local
Godot build, not a standalone release export or a hardware performance claim.
A forced immediate `--quit-after 20` exit emits a two-object audio cleanup
warning; normal test/capture cleanup has clean logs. Nothing was committed,
pushed or published. Earlier entries below are historical checkpoints.

## Latest: joined Varkas face, fur and metal review

Varkas's visible spherical cheek/jaw pieces are replaced by a joined Blender
facial sculpt with a short muzzle, uneven cheek markings, 7,924 polygons of
tapered guard-fur ribbons, and a small surface-following healed cheek scar.
The sculpt has 11,265 vertices; the separate game GLB is about 1.1 MB.
Source: `art_source/characters/varkas_head.blend`, rebuilt by
`tools/blender/build_varkas_head.py`. The original animated body and its
animation set remain intact, and the new face follows the existing death shell.

The imported sculpt uses the existing original guard-fur swatch. Body fibre
scale is finer, cheek colour is irregular, the fangs point downward, and the
eye lights no longer wash out the face. The Red Horn has a stronger hook,
textured rough iron and restrained emission. The carried bells now have
tarnished surface detail instead of smooth bright gold. Four-sample MSAA
smooths fine fur and other geometry edges.

Rendered and inspected: `iron_crown/varkas-sculpt-three-quarter.png`,
`varkas-sculpt-close-red-horn.png`, and `varkas-sculpt-scar-side.png`. Standard
phase-one, phase-three and execution captures were also refreshed. The earlier
face is preserved at `iron_crown/archive/varkas-before-sculpt.png`.

Verification: runtime smoke, Varkas combat, and real courtyard encounter
checks pass. The graphical terrain regression still draws 38,400 samples with
either culling mode. Full graphical campaign playback with the sculpt and
MSAA reaches 9/9, all phases and reinforcements, with 42 shots, 43 health and
no retry (`campaign/sculpt-run.log`). Final tarnish refinement was inspected
in refreshed rendered captures; it does not alter gameplay.

The intermittent eight-object traversal-test warning was traced to generated
WAV streams and pending playbacks during rapid same-frame chapter changes.
The test now lets an audio mix occur, retains weak references to its generated
streams/playbacks, and verifies their release after teardown with a bounded
wait. Five diagnostic runs and three runs of the final saved test exit cleanly.
This is explicit fixture cleanup, not a change to the game's audio engine.

Remaining full-goal work: final vegetation review/refinement and the final
completion audit. Human difficulty and story-reading pace remain unmeasured;
the automatic campaign is an accurate-aim progression probe. No commit or
publication was made.

## Latest: complete campaign playback and pickup placement

`tools/playtest_campaign.gd` now drives the entire real route with player
movement/collision, accurate carbine aim, normal ammunition, active enemy AI,
pickups and interaction prompts. The final verified run reaches 9/9 bells,
mother bell rung, gate open, all three Varkas phases and active reinforcements,
then the close horn-strike ending: 42 shots, 34 health, 6/136 rounds, no retries.
It does not warp, grant resources, directly damage targets or set mission
progress. Its 63.7-second direct run is not a human pacing/difficulty estimate.

The first run stalled at a bell buried under the mother-bell dais. Drop and
bobbing height now come from real collision surfaces. The shrine patrol now
uses the clear east side; the ascent brute starts before TerraceTwo instead
of inside it. `tests/test_campaign_pickups.gd` reproduces the buried drop and
checks every enemy's initial capsule against world collision. All twelve
headless suites pass; the traversal exit emitted eight ObjectDB leaks in both
parallel and isolated runs, so do not claim verification was warning-free.

Read `campaign/PLAYTEST.md`, `campaign/verified-run.log` and the captured
`campaign/result.png` for the authoritative proof and its limits. The graphical
runtime is required for scripted player input. Native UI inspection was
unavailable because macOS was locked, but the graphical Godot playback and
its viewport captures completed and were inspected directly.

Remaining full-goal work: vegetation and close material naturalism, Varkas's
overly smooth facial silhouette/close framing, traversal-test shutdown cleanup,
and a final completion audit.
The full progression route is now verified; human difficulty and story pacing
remain unmeasured. No commit or publication was made.

## Latest: continuous landmarks and clean checkpoint actions

Removed biome-driven hiding of entire architectural roots. The mother-bell
shrine now remains visible from the fold, and the abbey appears along its
authored ascent rather than suddenly at z=-76. Local weather still follows
the existing zone selection. Physics and authored meshes are unchanged.

`tests/test_biome_traversal.gd` first reproduced disappearing roots across
forward and backward crossings, then passed after the fix. Optional
`--capture-traversal` saves real player-height views in `traversal/`, including
both sides of the shrine and gate boundaries. These were rendered and
visually inspected. Gate-boundary draw calls are now 856/855 instead of
471/855; the forest/shrine approach costs more (1242 versus 654), since its
previous view omitted distant architecture. These are draw-call counts,
not a frame-time or minimum-hardware performance guarantee.

All six checkpoint entries settle onto real collision safely. Surviving
enemies already return to their homes in the current code; that older review
concern was no longer current. A new recovery test did reproduce a pending
reload locking the fresh life and later changing its ammunition, plus held
aim/Remembrance state surviving death. Death and respawn now clear transient
actions and invalidate old reload callbacks. A fresh reload still works and
spends the correct ammunition.

All **eleven** README suites pass with no reported warnings, and
`git diff --check` passes. Logs: `/tmp/mgk-continuation-*.log`.
The checkpoint test freezes enemies while checking refuge collision; it is
not a full campaign balance test. Remaining full-goal work: uninterrupted
campaign validation with reinforcements, vegetation/material naturalism,
Varkas's smooth facial silhouette, and final completion audit. No commit or
publication was made.

## Latest: visible terrain and distinct biome surfaces

The surface audit found that all **18,720 terrain triangles were wound away
from the player**. Height-map collision still worked, but ordinary culling
hid nearly the entire ground. Broad flat blue regions in earlier captures
were largely background, so those frames did not prove working terrain
materials. The original isolated rendering probe counted 215 visible terrain
samples versus 46,976 with culling disabled. Correct winding made both modes
draw 46,976 samples. The persistent GPU regression checks a lower screen area
and passes at 38,400 samples in both modes.

The terrain now uses `assets/materials/ravine_terrain.gdshader`: packed forest
snow, iron-red exposed earth, and charcoal ash blend through irregular snow
coverage and drift boundaries. Existing CC0 snow/rock scans drive albedo,
normal and roughness detail; there are no new third-party dependencies.
The snow is toned down from its initially overbright restored appearance.
A subtle lower HUD veil keeps text readable over the newly visible snow.

Restoring the terrain also exposed a buried charge-warning plane. Red Horn's
warning is now a segmented ribbon sampled against the height field; the
combat test checks that its vertices remain above ground. The refreshed
rendered warning, walking dodge, and reachable ending all pass after this fix.

`tools/capture_biomes.gd` captures player-height views **inside each actual
gameplay biome**, using ordinary zone and atmosphere selection. These are the
current surface review frames:

- `widowpine/widowpine-ground-pass.png` — trailhead / whitewood
- `carrion_cut/carrion-cut-ground-pass.png` — shrine / carrion_cut
- `iron_crown/iron-crown-ground-pass.png` — gate / iron_crown

All **nine** README test suites pass, as does the graphical terrain-culling
regression. The previous environment and boss proof captures have been
refreshed against this exact rendered surface state; the rendered encounter
also passes. Physics geometry and
the underlying height function were not changed.

Remaining full-goal work: uninterrupted campaign validation, landmark
visibility when crossing biome boundaries, closer material and vegetation
naturalism, Varkas's smooth facial shapes, and a final completion audit. The
full game is not yet claimed complete.

## Latest: boss counterplay and personal bell memories

Replaced Varkas's overlapping normal-enemy attacks and special moves with one
boss attack timeline. Red Horn now warns for 0.95 seconds, marks a fixed lane,
charges straight, and leaves a recovery opening. Iron Jaw warns before its
close attack. Bellquake warns for 1.2 seconds and can be jumped or escaped.
Converged Remembrance rounds interrupt the charge. Phase changes, execution,
and retries clear pending attacks without delayed damage callbacks.

The hero collider now reaches his visible muzzle. Retries restore first-phase
speed, reach, and damage, which previously remained at Red Horn values. Debug
shortcut 4 restores a dead player before setting up another arena attempt.

Recovered bells reveal a brief personal memory; Orin is established as the
Herdkeeper's younger brother. The gate acknowledges eight recovered names and
one still held by Varkas. The retry wording now names the actual refuge
checkpoint. Chapter fades cancel the preceding fade, and memory text fits
clear of the minimap without a duplicate notification.

Current verification: all **eight** README suites pass. Runtime smoke was
rerun after the final memory-layout adjustment. The new focused combat check
first reproduced immediate charge motion, homing after a sidestep, and damage
during a transition; all are now fixed. The full courtyard encounter test
verifies a 2.70 m walking sidestep at **100 health**, a recovery opening, a jump
that avoids Bellquake, one 18-point hit while grounded, and the final horn
strike from a collision-reachable position returning the ninth bell.

Rendered and inspected proofs:

- `iron_crown/iron-crown-varkas-charge-warning.png`
- `iron_crown/iron-crown-varkas-charge-dodged.png`
- `iron_crown/iron-crown-varkas-reachable-ending.png`
- `widowpine/widowpine-bell-memory.png`

The encounter proof drives real Godot physics in the real courtyard at fixed
steps, with other enemies disabled to isolate counterplay. It does not prove
the difficulty of the entire fight with reinforcements active or the full
campaign. Full-route pacing/ammunition/recovery testing, biome texture and
ground-transition refinement, and a less smooth character silhouette remain
outstanding. The full user goal remains active; nothing has been committed or
pushed.

## Earlier: interrupted fur pass

Continued the interrupted Varkas surface pass from the task "Finish game story
and biomes" in the root Godot project.

## Completed this pass

- Recovered the fur image generated in the previous task and preserved it as
  `assets/materials/original/varkas_guard_fur.png`, with provenance in the asset
  ledger.
- Added a reproducible UV unwrap to the Blender hero build. Rebuilt the blend
  and GLB while retaining the source skeleton and animations.
- Applied guard-fur detail to Varkas and corrected the phase colors that were
  multiplying the new texture into near-black. Kept the warpack materials.
- Made debug shortcut 4 restore a dead player before preparing the arena.
- Refreshed the Iron Hide, Red Horn, and execution proof frames in `iron_crown/`.

## Verification

All six README Godot suites passed: controls, Remembrance, stealth, runtime,
Iron Crown environment, and biome assets. Runtime smoke was rerun after the
final material and debug-retry changes and passed. The phase-one, phase-three,
and execution captures exited successfully without reported warnings or errors.
`git diff --check` passed.

Live Godot UI checks reached Iron Hide, Call the Warpack, and Red Horn with the
debug shortcuts. A live defeat displayed the R retry prompt; R returned to the
gate checkpoint and reset the encounter. The final horn-strike ending was
verified by the deterministic rendered capture and runtime test, both using
the real interaction handler. The live keyboard attempt did not complete the
ending before another defeat.

## Still to verify and improve

- Play the complete three-biome route at ordinary health without debug warps:
  pacing, ammunition, checkpoint fairness, and combat readability remain
  unproven by this audit.
- Review camera obstruction during Varkas's closest attacks. At contact range,
  his body can occupy most of the frame; the test does not establish whether
  ordinary movement and dodge timing make this acceptable.
- Fur detail is clearer, but Varkas's smooth added facial shapes and the wider
  environment still fall short of the reference artwork's realism.

Changes remain local and uncommitted on the existing working branch.
