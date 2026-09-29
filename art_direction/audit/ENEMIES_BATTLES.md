# Enemies, animation, AI and battle design

Scope: the warpack (stalker, rifleman, brute), Varkas, their animation and
look, stealth perception polish. Verified with headless behaviour tests on real
physics in the real ravine (`tests/test_enemy_behavior.gd`), the automated
campaign bot (`tools/playtest_campaign.gd`, victory with zero deaths through
all three Varkas phases) and rendered frames (`tools/capture_enemies.gd`,
frames `art_direction/audit/en_*.png`).

## What was wrong

- Melee damage landed on the frame the Attack clip started (undodgeable), the
  rifle "shot" was a random roll with a bite animation, no cover, no pack
  coordination, one canned death clip, wolves that read as small dogs.
- Animation was a single AnimationPlayer with hard switches, no gait/speed
  matching, no head tracking.

## Combat

Everything lives in `scripts/enemy.gd` (state machine, brains, model, boss) plus
small helpers: `pack_director.gd` (attack tokens and roles), `enemy_nav.gd`
(runtime navigation mesh), `enemy_bullet.gd` (real rounds), `enemy_fx.gd`
(flash, tracers, dust, debris), `enemy_pose.gd` (skeleton modifier).

**Melee cycle** (stalker, brute): approach -> circle -> telegraph -> strike ->
recover. The Attack clip's crouch (first 0.25 s) is stretched over the
wind-up (stalker 0.5 s, brute 0.8 s, charge 1.0 s) and the clip resumes at the
strike so its head-lunge lands at the impact frame; damage is applied
`ATTACK_IMPACT_DELAY` (0.13 s) after the strike starts, only if the goat is
still inside reach and in front of the locked lunge line. The aim tracks the
goat until 0.18 s before the strike (0.25 s for a charge), then locks: a
sidestep beats it and emits `attack_dodged` (HUD "DODGED"). Wind-up tells:
crouch pose, eye flash, growl, dust. Stalkers feint 25% of the time (rock
forward, slip sideways) and circle at ring radius with random direction flips.
Brutes charge from 6.5-14 m on a clear lane at 9.2 m/s for up to 1.9 s; a miss
skids into a 1.3 s recovery, a wall hit staggers for 2 s with dust, camera
shake, yelp. Poise: brutes ignore light hits during a wind-up, everyone else's
wind-up is broken by a hit.

**Pack**: `PackDirector` caps simultaneous attackers (2 melee tokens, 2 ranged
tokens, self-expiring). On alert roles are assigned: nearest melee fighter =
rusher; others = flankers (swing wide to the goat's side before closing, then
wait for her to turn her back or the rusher to be spent); riflemen =
suppressors (marksman if alone). Howls still alert the pack within 20 m; boss
reinforcements still come only from `main.gd`. A wolverine at <=28% health
retreats once (to cover if it is a rifleman) for up to 4.5 s.

**Riflemen**: take a token, stop and crouch, aim for 0.75 s (0.95 marksman)
with a visible red laser that thickens as the shot commits, lock the line
0.22 s before firing, then fire a real 64 m/s round (`EnemyBullet`, 11-14
damage, dodgeable, stopped by walls) with a muzzle flash light + star, streak
and `rifle_crack`. Bursts of 2 (1 for suppressors), mag of 4, 2.4 s reload
(in cover if there is any). Accuracy = 0.3 + 0.12/s in sight, minus up to 0.32
when the goat moves, minus 0.12 crouched, minus range, minus 0.15 suppressors;
spread cone falls from 6.3 deg to 0.5 deg. The barrel must be in open air and
have a clear ray to the goat before it fires, so nothing shoots through walls
(the test puts a wall between them and also catches a barrel pressed into
stone). Cover: `_find_cover()` scans 30 ring samples for spots hidden from the
goat (raycast) with a lateral peek point that sees her again, claims them so
packmates do not share, then cycles cover -> peek -> aim -> burst -> cover.
Within 6 m of the goat a rifleman falls back; cornered, it uses a bayonet
wind-up.

**Hit reactions and death**: a hit shoves the wolverine away from the shot,
plays an upper-body flinch clip on the side it came from (one-shot filtered to
spine/neck/head so the gait continues) and slows, not freezes, the AI. Death
plays the Death clip with a knockback slide (`_corpse_physics`), a lean away
from the shot, a spreading blood pool, and physical props: the rifle and the
neck-bell become RigidBodies (the bell rings once when it lands). Corpses stay
34 s, then sink. Headshots, ambush kills and takedowns get a brief freeze-frame
(`_hitstop`, skipped headless). Takedown hauls the victim back onto the horn
(camera kick, spray) instead of the old canned clip.

**Navigation**: a NavigationMesh is baked once at runtime from the world's
static colliders (~25 ms), enemies follow paths with a 1.2 s refresh, whisker
rays (3 low rays) steer around what the mesh does not know, and a stuck
detector side-steps after 0.7 s without progress. Boss uses direct steering
(his capsule is far larger than the mesh's agent). The test spawns eight
stalkers across the map (trailhead to the ascent) and requires all of them to
reach biting range.

## Animation and look

- **AnimationTree** (built in code on the 12 Quaternius clips): idle-variant
  transition (Idle, Idle_2, Idle_2_HeadLow), walk/gallop blend space, foot-slide
  fix (clip time-scale = ground speed / measured stride speed of the IK foot
  bones: walk 2.3 rig units/s, gallop 6.9), turn-in-place (walk cycle at a pace
  matching the yaw rate), full-body attack one-shot with a time-scale node for
  the held crouch, filtered upper-body hit one-shot.
- **`EnemyPose`** (SkeletonModifier3D, runs after the tree): bone scaling for
  bulk (forequarters, neck, stubby legs, short tail; scales set against rest
  scale because the rig has a 100x skeleton), head/neck look-at composed on
  global bone bases (bone +Y is forward, so the same orthonormalised-basis rule
  as the `riders` applies), and a wind-up/aim crouch. Procedural lean into
  accel, turns and strafes; bell swing.
- **Perception body language**: patrols pause at posts with idle variants and a
  slow head sweep and turn toward the next leg before setting off; suspicion
  walks to the noise with the head on it, sniffs (head-low idle) and sweeps;
  search picks fresh points near the last known position with a sweeping
  brow beam (shadowless SpotLight, only while hunting and near); return to the
  nearest post.
- **Look**: the wolverine head is a Higgsfield generation (snarling, scarred,
  spiked collar) mounted rigidly on the Head bone with the wolf skull
  collapsed; a custom head shader finds the baked eyes by colour and lights
  them cold blue / amber / red by detection. Fur is a triplanar shader over
  two generated fur swatches with a pale flank band, a per-animal war-paint
  claw mask, scars and rime; armor is a Blender-made gear kit (harness rifle
  with scope and bayonet, forged pauldrons, spine plates, bell) on a generated
  worn-iron plate texture. Size varies +-10% per animal.
- **Rigged replacement**: not adopted. A Higgsfield rigged wolverine would come
  with its own (humanoid-biased) clip library and no Attack/Death/HitReact
  set matching the game's telegraph contract; keeping the Quaternius rig and
  replacing head, fur and gear got the read without losing animation.

## Varkas

Contract kept and tested (`test_varkas_combat.gd`, `test_varkas_encounter.gd`):
every attack is announced, has a recovery, retry resets everything. New:

- Phase break is a beat: he rears (0.5 s), roars as the plates the phase
  discards are torn off as RigidBody debris with sparks, an arena light flash
  and shockwave ring fire, Red Horn's horn grows from nothing, then he drops
  with a slam (dust ring, ring, camera 0.5) - the lock still rejects damage.
- Attack poses match the tell: Iron Jaw rears half up and slams; Bellquake rears
  fully (camera rumble during the tell) and slams on release; Red Horn drops to
  a crouch with dust and a marked lane.
- Recovery is visibly open (head hung, Orin's bell glows); a sidestepped attack
  emits `dodged`; **Red Horn into a pillar or wall stuns him for 3 s**
  (`wall_stun`), so the arena is the answer to the charge.
- Execution: he kneels, bell pulses gold, arena flash, freeze-frame on the
  strike, remaining plates burst off.
- Rear-up is a rigid pitch of skinned mesh and hero shell about the hind paws
  (the shell is not skinned), so the boss has no head look-at.

## Frames (art_direction/audit/)

`en_look_stalker_front`, `en_look_brute_side` (the new build), `en_patrol_2`,
`en_search_1` (brow beam), `en_hit_1` (flinch), `en_strike_windup_1`,
`en_strike_impact`, `en_brute_windup`, `en_brute_charge`, `en_rifle_aim`
(laser), `en_rifle_fire` (flash and round), `en_death_1`,
`en_boss_transition_2` (armor flying, ring, embers), `en_boss_bellquake_1`
(rear-up), `en_boss_phase3_1`, `en_boss_broken`. Regenerate with
`Godot --path . --resolution 1280x720 --script res://tools/capture_enemies.gd`
(optionally `-- boss` etc.).

## Tests added or extended

- `tests/test_enemy_behavior.gd` (new): nav across the map, telegraph before
  damage, dodge, tokens/roles, rifle beam and rounds, wall blocks rifle, brute
  charge and wall stagger, retreat, cover, death, corpse and body discovery.
- `tests/test_varkas_combat.gd`: dodge feedback, Bellquake rear/slam, phase
  break beat (rear, shed plates, debris, horn growth, retry restores).
- `tests/test_stealth.gd`: body sight rules, lantern notice range.

## Hooks in other files

`scripts/main.gd` (a few lines): connect `attack_dodged` -> `_on_enemy_dodged`
("DODGED" notice) in `_spawn_enemies` and `_spawn_reinforcement`; new boss
attack names `wall_stun` (notice) in `_on_boss_attack` (`dodged` and
`phase_slam` are emitted but need no UI); lantern snuff calls
`enemy.notice_dark(lantern.position)` for every enemy.

## Sound names the audio agent should supply

`rifle_crack` (falls back to `shot`), `whiz` (near-miss, falls back to
`footstep`), `reload` (falls back to `click`), `aim_charge` (falls back to
`click`), `roar` (brute/boss, falls back to `growl`), `wall_slam` (falls back
to `thud`), `whoosh` (dodged swipe, falls back to `growl`). Existing names in
use: growl, bite, howl, huff, yelp, death, bell, bell_strike, rock_hit.

## Higgsfield credits

About 12.5: 6 gpt_image_2_5 images (fur x2, iron plate, war-paint mask, head
concept x2 = 1.5) and one hunyuan3d_v3_image_to_3d head (11).

## Known remaining problems

- Hit direction and head hits are inferred (player passes no hit point:
  direction = away from the goat, headshot = stagger >= 0.5), and the takedown
  lunge on the player side needs a `player.gd` hook (the enemy side is pulled).
- The nav mesh is baked with the iron gate closed; beyond the gate and around
  props added after the bake, whisker steering takes over.
- Circling uses the forward walk clip plus lean (no strafe clips exist).
- Varkas' own face/eyes are unchanged (hero shell); only his beats, poses,
  armor break and finisher changed.
- `art_source/characters/wolverine_head_higgsfield_raw.glb` (33 MB raw
  generation) is intentionally untracked.
