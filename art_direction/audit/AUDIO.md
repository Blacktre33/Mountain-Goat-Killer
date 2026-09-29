# Audio, music and voice

Everything below is implemented in `scripts/audio.gd` (mixer + sound bank),
`scripts/music.gd`, `scripts/ambience.gd`, `scripts/voice.gd`, `scripts/subtitles.gd`,
`scripts/audio_watch.gd`, `scripts/audio_settings.gd` and the generated
`scripts/audio_bank.gd`. Assets are rendered offline by `tools/audio/` (numpy, ffmpeg,
deterministic seeds) into `assets/audio/generated/` (44.1 kHz) and `assets/audio/voice/`.

## What changed

* The old 22 kHz mono sine/noise synthesis is gone. 93 sound names (about 200 clips,
  25 MB) are real sound design: layered carbine shot with canyon slap echoes, distinct
  marksman rifle, bolt/magazine/reload stages, brass casings, material impacts,
  source-filter wolverine voices (growl, snarl, howl, yelp, death, breath), paw crunch,
  armour, Varkas' roar, charge, bellquake and armour break, a 16-partial mother bell,
  Remembrance choir bells, pickups, interface, heartbeat, tinnitus and scattered ambient events.
* Buses `Master <- Music, SFX, Ambience, Voice, UI`, `SFX <- Room, Canyon` with a compressor
  and hard limiter on Master, a large cold canyon reverb, distance air absorption, line-of-sight
  occlusion, ducking, pause/title mixing and a saved volume API.
* Adaptive score: 3 biomes x 4 stems, 3 boss phases x 2 stems, victory, death.
* 43 spoken lines from Higgsfield `seed_audio` (Herdkeeper narration, Varkas, pack barks) with subtitles.
* Everything is wired **without edits to main.gd/player.gd/enemy.gd**: `GoatWatch` follows the
  campaign state (see "Automatic behaviour"). The hooks listed at the end only add finer cues.

## Buses

| Bus | Send | Effects | Carries |
| --- | --- | --- | --- |
| Master | (device) | Compressor (-14 dB, 3:1, 15 ms / 240 ms, +4 dB) then HardLimiter (-1 dB ceiling) | everything |
| Music | Master | low-pass (idle; closes to 650 Hz when paused) | score stems, victory, death |
| SFX | Master | low-pass (idle; closes to 700 Hz on `stun()`) | dry effects (gunfire has its tail baked in) |
| Room | SFX | Reverb (small, wet 0.08) | foley: footsteps, impacts, casings, bites, growls |
| Canyon | SFX | Reverb (room 0.93, damping 0.62, wet 0.30, 45 ms pre-delay) | howls, roars, bells, stone/metal impacts, gate, quake, far ambience |
| Ambience | Master | low-pass (idle; muffled by `stun()`) | wind bed, biome beds, scattered events |
| Voice | Master | Reverb (wet 0.10) | narration, Varkas, barks |
| UI | Master | none | hitmarker, kill tick, interface, pause |

Player volumes (`master, music, sfx, ambience, voice, ui`, linear 0..1) are stored in
`user://audio.cfg`, together with the subtitle switch. API on `GoatAudio`:
`get_bus_volume(name)`, `set_bus_volume(name, linear)`, `set_subtitles_enabled(bool)`.

* **Air absorption**: every `play_at` uses `AudioStreamPlayer3D` attenuation filtering
  (6.5 kHz cutoff, -18 dB), so distance dulls the highs; `REACH` widens the full-level radius
  of loud sounds (shots 3x, roar/quake 3x, mother bell 5x).
* **Occlusion**: two rays (chest and head height) from the camera to the source; each blocked
  ray lowers the cutoff toward 1.1 kHz and costs up to 3 dB (6 dB fully blocked). Sources beyond
  `max_distance * 1.15` are not started.
* **Ducking**: `DUCKS` lists which sounds push Music/Ambience down (shot -7/-5 dB, roar -10/-8,
  bell -9/-6 ...) with a 30 ms attack and about 0.9 s release; Herdkeeper/Varkas speech ducks
  music by 5 dB and ambience by 4 dB.
* **Pause and title**: the audio nodes run while the tree is paused; pausing closes a low-pass on
  Music and lowers it 7 dB. The score plays a `title` state until the start button.
* **Aliases**: `GoatAudio.POSITIONAL_ALIAS` maps a positional `shot` (someone else's gun) to `rifle_crack`; the player's own carbine uses `play("shot")`.
* **Unknown names**: `play`/`play_at` ignore an unknown name and, in debug builds only
  (`OS.is_debug_build()`), `push_warning` once per name. `GoatAudio.sound_names()` lists the registry.

## Sound names

Every effect the game can request. Bus is the routing bus (see above). Peaks are the file peaks
(the mix trims them); several names have random variants.

| Name | Variants | Bus | Format | Length | Peak dBFS | What it is |
| --- | --- | --- | --- | --- | --- | --- |
| `amb_bell_far` | 3 | canyon | ogg | 8.6 s | -20 | Far bell across the ravine. |
| `amb_cage` | 2 | canyon | wav | 1.6 s | -20 | Iron cage squeal and chain. |
| `amb_carrion` | 1 | ambience | ogg | 30.0 s | -10 | Dry rasp, wind across bone, ritual sub throb (30 s loop). |
| `amb_chain` | 2 | canyon | wav | 0.7 s | -20 | Chain rattle. |
| `amb_creak_pine` | 3 | canyon | wav | 2.2 s | -20 | Frozen trunk groan. |
| `amb_ember` | 3 | room | wav | 1.0 s | -22 | Ember pops. |
| `amb_iron_crown` | 1 | ambience | ogg | 30.0 s | -10 | Embers, forge roar, vibrating iron (30 s loop). |
| `amb_rock` | 2 | canyon | wav | 1.2 s | -20 | Rock fall. |
| `amb_rope` | 2 | room | wav | 1.0 s | -22 | Rope creak. |
| `amb_snow` | 2 | canyon | wav | 1.9 s | -24 | Snow sliding. |
| `amb_widowpine` | 1 | ambience | ogg | 30.0 s | -10 | Needle hiss, snow ticks (30 s loop). |
| `ammo_pickup` | 2 | sfx | wav | 0.8 s | -16 | Cartridges rattling in a pouch. |
| `armor_break` | 1 | canyon | ogg | 2.2 s | -3 | Varkas' plates tearing off: shear, clangs, falling shards. |
| `armor_clink` | 3 | room | wav | 0.5 s | -18 | Loose iron plates. |
| `bell` | 1 | canyon | ogg | 16.7 s | -3 | The mother bell: 16 inharmonic partials with beating pairs, 16 s shimmering decay. |
| `bell_pickup` | 3 | sfx | ogg | 3.7 s | -9 | Stolen neck-bell freed: clapper knocks then a dented ring. |
| `bell_toll` | 3 | canyon | ogg | 7.0 s | -8 | Warm distant toll. |
| `bite` | 3 | room | wav | 0.6 s | -5 | Jaw snap with wet chomp. |
| `bolt` | 2 | room | wav | 1.0 s | -8 | Bolt cycle: lift, pull, push, lock. |
| `casing` | 3 | room | wav | 0.5 s | -14 | Brass case bounces on stone. |
| `casing_snow` | 3 | room | wav | 0.7 s | -20 | Brass case in snow (dull). |
| `charge_rumble` | 1 | room | ogg | 2.3 s | -6 | Red Horn charge: rumble plus accelerating hoof beats. |
| `chime` | 3 | sfx | wav | 1.8 s | -12 | Handbell chime (pouch pickup). |
| `click` | 1 | sfx | wav | 0.2 s | -8 | Dry-fire hammer tick. |
| `converge` | 1 | sfx | wav | 2.9 s | -8 | Converging rounds: rising choir glide into a strike. |
| `death` | 2 | room | wav | 1.8 s | -7 | Death whine, rattle and last exhale. |
| `gate` | 1 | canyon | ogg | 4.8 s | -4 | Iron gate opening: stick-slip stone grind, chain clanks, sub rumble. |
| `growl` | 3 | room | wav | 1.1 s | -8 | Wolverine growl: source-filter voice with vocal-fry flutter and rattle AM. |
| `growl_windup` | 1 | room | wav | 0.9 s | -7 | Rising warning growl ending in an intake: the tell before a bite. |
| `hang` | 1 | sfx | ogg | 4.0 s | -10 | Remembrance round hung: glass bell over a choir pad. |
| `headshot` | 2 | room | wav | 0.3 s | -4 | Flesh hit with bone crack and ring. |
| `heartbeat` | 1 | sfx | wav | 0.8 s | -10 | Lub-dub (played automatically below 35 health). |
| `hit` | 3 | room | wav | 0.3 s | -6 | Bullet into flesh (player-side hit). |
| `hitmarker` | 1 | ui | wav | 0.1 s | -16 | Soft UI tick on a confirmed hit. |
| `howl` | 3 | canyon | wav | 2.7 s | -6 | Pack howl: two detuned voices, vibrato, voice break. |
| `huff` | 3 | room | wav | 0.5 s | -14 | Suspicious snort. |
| `hurt` | 3 | room | wav | 0.6 s | -6 | Player takes damage: body blow and pained breath. |
| `impact_flesh` | 3 | room | wav | 0.4 s | -6 | Heavy wet thud. |
| `impact_metal` | 3 | canyon | wav | 1.1 s | -8 | Ping and ricochet zing. |
| `impact_snow` | 3 | room | wav | 0.3 s | -12 | Muffled fump with crystal hiss. |
| `impact_stone` | 3 | canyon | wav | 0.7 s | -8 | Crack, chip and ricochet whine. |
| `impact_wood` | 3 | room | wav | 0.4 s | -8 | Crack, knock and splinter ticks. |
| `kill` | 1 | ui | wav | 0.9 s | -10 | Low double-thud with bell tone on a kill. |
| `land` | 2 | room | wav | 0.5 s | -12 | Landing thump in snow with gear rattle. |
| `mag_in` | 1 | room | wav | 0.6 s | -9 | Magazine slide in and seat. |
| `mag_out` | 1 | room | wav | 0.6 s | -9 | Magazine release and slide out. |
| `pause_in` | 1 | ui | wav | 0.9 s | -12 | Pause: felt thump and closing rush. |
| `pause_out` | 1 | ui | wav | 0.7 s | -12 | Resume swell. |
| `pickup` | 1 | sfx | wav | 0.7 s | -12 | Generic item pickup. |
| `quake` | 1 | canyon | ogg | 6.0 s | -2 | Bellquake: sub boom, debris, dying bell ring. |
| `reload` | 1 | room | wav | 2.1 s | -8 | Whole reload (mag out, cloth, mag in, bolt), about 2.1 s. |
| `rifle_crack` | 3 | sfx | wav | 3.3 s | -2 | Enemy rifleman: sharper, thinner, later and longer echo, so it is distinct from the carbine. |
| `roar` | 1 | canyon | ogg | 5.0 s | -3 | Varkas' roar: three detuned throat voices, sub, saturated, canyon tail. |
| `sense` | 1 | sfx | wav | 2.0 s | -12 | Remembrance sensing ping. |
| `shot` | 3 | sfx | wav | 3.3 s | -1 | Player carbine: crack + blast + chest thump, baked canyon slap echoes (stereo). |
| `snarl` | 2 | room | wav | 0.6 s | -8 | Short rasping snarl. |
| `snuff` | 2 | room | wav | 0.9 s | -12 | Lantern snuffed: hand, puff, sizzle, glass tink. |
| `sting` | 1 | sfx | ogg | 5.6 s | -8 | Chapter / death sting: cold drone, choir and bell. |
| `stone_land` | 2 | room | wav | 0.5 s | -8 | Thrown stone lands. |
| `takedown` | 2 | room | wav | 0.9 s | -4 | Horn-strike takedown: stab, crunch, thud. |
| `throw` | 2 | room | wav | 0.2 s | -14 | Stone throw. |
| `tinnitus` | 1 | sfx | wav | 3.2 s | -22 | Ringing after a near miss; muffles the mix (see stun()). |
| `ui_back` | 1 | ui | wav | 0.2 s | -14 | Falling back tone. |
| `ui_click` | 2 | ui | wav | 0.1 s | -12 | Interface click. |
| `ui_confirm` | 1 | ui | wav | 0.5 s | -12 | Two-note confirm. |
| `ui_hover` | 1 | ui | wav | 0.1 s | -20 | Hover tick. |
| `volley` | 1 | sfx | ogg | 5.4 s | -3 | Remembrance release: boom, air rush, bell cluster, choir swell. |
| `whoosh` | 3 | room | wav | 0.4 s | -14 | Melee swish (three variants). |
| `wind` | 1 | ambience | ogg | 30.0 s | -6 | Shared wind bed (30 s loop, level driven by set_wind). |
| `wolf_breath` | 2 | room | wav | 1.7 s | -18 | Idle breathing. |
| `wolf_footstep` | 4 | room | wav | 0.2 s | -20 | Paw crunch on snow (four variants). |
| `wolf_footstep_heavy` | 4 | room | wav | 0.3 s | -14 | Brute footfall. |
| `yelp` | 2 | room | wav | 0.5 s | -8 | Pain yelp. |

Kenney Impact Sounds (CC0), unchanged:

| Name | Source |
| --- | --- |
| `footstep` | Kenney snow footsteps (CC0), five variants. |
| `bell_strike` | Kenney heavy bell impact (CC0). |
| `thud` | Kenney punch (CC0). |
| `stone` | Kenney soft impact (CC0). |
| `clank` | Kenney metal impact (CC0). |
| `wood` | Kenney wood/plank (CC0). |
| `rock_hit` | Kenney mining impact (CC0). |

## Music

`GoatAudio.set_music_state(state)` / `GoatMusic.set_state(state)`: `title`, `stealth`,
`suspicious`, `combat`, `boss1`, `boss2`, `boss3`, `victory`, `death`.
`set_biome(name)`: `whitewood` (Widowpine), `carrion_cut`, `iron_crown` (aliases `widowpine`, `carrion`).
Transitions only move fade targets (60 dB per fade time: combat in 1.2 s, out 6 s, stealth in 5 s,
death 0.5 s), so stems stay in sync. Biome stems are retired 12 s after they go silent.

| State | drone | motif | tension | combat |
| --- | --- | --- | --- | --- |
| title | 0 dB | -3 | off | off |
| stealth | 0 | -1 | off | off |
| suspicious | -2 | -14 | -1 | off |
| combat | -9 | off | -6 | 0 |

`boss1/2/3` fade in the phase's base + perc stems (0 dB) and silence the biome stems; `victory` and
`death` start their one-shot. Colour per biome: Widowpine is A minor pentatonic with open fifths and
single bells (bare, lonely); Carrion Cut is D Phrygian with choir drones, frame drums, bone clacks (ritual);
Iron Crown is a C minor cluster with anvil and sub (oppressive). Boss: Iron Hide 72 BPM heavy horn stabs,
Call the Warpack 96 BPM howling choir over an ostinato, Red Horn 128 BPM horn calls and an accelerating bell.

| Stem | Length | Playback |
| --- | --- | --- |
| `music_boss1_base` | 40.0 s | loop |
| `music_boss1_perc` | 40.0 s | loop |
| `music_boss2_base` | 30.0 s | loop |
| `music_boss2_perc` | 30.0 s | loop |
| `music_boss3_base` | 30.0 s | loop |
| `music_boss3_perc` | 30.0 s | loop |
| `music_carrion_combat` | 32.0 s | loop |
| `music_carrion_drone` | 32.0 s | loop |
| `music_carrion_motif` | 32.0 s | loop |
| `music_carrion_tension` | 32.0 s | loop |
| `music_death` | 9.0 s | one-shot |
| `music_iron_crown_combat` | 29.1 s | loop |
| `music_iron_crown_drone` | 29.1 s | loop |
| `music_iron_crown_motif` | 29.1 s | loop |
| `music_iron_crown_tension` | 29.1 s | loop |
| `music_victory` | 52.0 s | one-shot |
| `music_widowpine_combat` | 35.6 s | loop |
| `music_widowpine_drone` | 35.6 s | loop |
| `music_widowpine_motif` | 35.6 s | loop |
| `music_widowpine_tension` | 35.6 s | loop |

## Ambience

`wind` (level via `set_wind`, as before), one bed per biome (`amb_widowpine`, `amb_carrion`,
`amb_iron_crown`, crossfaded over 6 s on a biome change) and positional one-shots scattered around the
listener every 3.5-22 s depending on the biome (creaking pine, far bell, sliding snow, rock fall; embers,
iron cage, chain and rope in the Iron Crown).

## Voice

Voices (Higgsfield `seed_audio`, 44.1 kHz WAV, then processed by `tools/audio/voice_process.py`):
Herdkeeper narration = "Brooks" (speech rate -12), Varkas = "Vlad" (speech rate -18, pitch -3, then slowed
6 % more, body boost and grit), pack barks = "Landon" and "Gideon". Silence trimmed, level per speaker
(-22 dBFS speech RMS for the Herdkeeper, -18 for Varkas and barks), -1.5 dB ceiling.

`GoatVoice`: `say(id, at := Vector3.INF)`, `say_later(id, seconds)`, `say_intro()`, `stop_narration()`,
`is_speaking()`; signals `line_started(id, speaker, text, seconds, at)` and `line_finished(id)`.
Group ids (`Story.VOICE_GROUPS`) pick a random variant. Narration queues (priority: intro/victory 5, boss 4,
memory/bell 3, chapter 1; stale lines expire), Varkas has his own channel, barks are positional and rate limited
(3.5 s per group, 1 s overall). `GoatSubtitles` (created by `GoatAudio`) shows every line bottom-centre; Varkas in
amber, nearby barks (within 30 m) in steel; togglable. All texts live in `scripts/story.gd`
(`Story.voice_text(id)`, `VARKAS_LINES`, `PACK_BARKS`, `VOICE_GROUPS`); a test checks that the recorded
speech text equals the story text.

| Id | Voice | Text |
| --- | --- | --- |
| `intro_0` | Brooks | Nine neck-bells. Nine names. One great bell to call the herd home. |
| `intro_1` | Brooks | Varkas came in the blue hour. By dawn the birthing pen was black-red, and our bells hung from his killers. |
| `intro_2` | Brooks | Maren pushed me beneath the ice trough before his knife found her. Ten winters later, I have come back with her carbine. |
| `intro_3` | Brooks | Cross three scars of this mountain. Take every name. Ring the mother bell. Put Varkas in the ground. |
| `memory_0` | Brooks | Asha taught me to step where the needles were thick. Her killer wore her bell to warn the others when he fed. |
| `memory_1` | Brooks | Rowan mended every broken strap in the fold. I have to cut his bell free. The leather has grown into the rust. |
| `memory_2` | Brooks | Tember built the ice trough. He made it deep enough for a winter's water. Deep enough to hide one child. |
| `memory_3` | Brooks | Lissa could name a missing goat by the silence in the herd. Four bells answer now. The mother bell will hear us. |
| `memory_4` | Brooks | Hollin hauled the abbey's first stones. His bell is dented flat on one side. I turn that side into my palm. |
| `memory_5` | Brooks | Brae stitched Maren's wounds after the rockfall. There was nobody left to stitch hers. I wipe the bell on my coat. |
| `memory_6` | Brooks | Sorrel kept seed beneath the hearth through every lean winter. The hearth is cold. I keep the bell warm in my hand. |
| `memory_7` | Brooks | Maren put her hand over my mouth beneath the trough. Stay quiet, she said. I carried her carbine here. I carry her name out. |
| `memory_8` | Brooks | Orin was small enough to sleep against my ribs. Varkas wore his bell through ten winters. He will not wear it through another dawn. |
| `chapter_trailhead` | Brooks | The pines kept the smell for ten winters: sap, cold iron, and the blood they could not bury. |
| `chapter_homestead` | Brooks | They sleep inside our fence. Four of our bells knock against their armour when they breathe. |
| `chapter_shrine` | Brooks | The snow thins here. Bone shows through the old red earth. Four names will wake the mother bell. |
| `chapter_ascent` | Brooks | The bell has given the dead a voice. I carry it uphill, one shot at a time. |
| `chapter_gate` | Brooks | Eight names open the abbey our herd built. The ninth still knocks against Varkas' throat. Orin. My little brother. |
| `bell_rung` | Brooks | The mother bell tears the silence open. Every wolverine looks uphill. Every stolen bell answers. |
| `boss_phase_1` | Brooks | Varkas lowers his plated head. Orin's bell knocks once against his throat. |
| `boss_phase_2` | Brooks | His hide splits under the iron. Four memorial lamps spit red; he howls, and the last of the pack comes running. |
| `boss_phase_3` | Brooks | The plates tear free. Eight names burn around him. He lowers the red horn; I remember Maren's hand. Be still. Let him commit. Then move. |
| `victory_0` | Brooks | Varkas dies beneath the bell he stole from Orin. I leave his iron in the mud. |
| `victory_1` | Brooks | I do not wear the nine bells as trophies. I carry them down through ash, bone, and snow. |
| `victory_2` | Brooks | At dawn the mother bell calls them home: Asha. Rowan. Tember. Lissa. Hollin. Brae. Sorrel. Maren. Orin. |
| `victory_3` | Brooks | The mountain remembers. This time, it speaks our names instead of his. |
| `varkas_alert_0` | Vlad | Another goat, climbing my mountain. |
| `varkas_alert_1` | Vlad | The bells told me you were coming. |
| `varkas_phase_1` | Vlad | I wear their names. Take one, if you can. |
| `varkas_phase_2` | Vlad | Pack! Tear it down! |
| `varkas_phase_3` | Vlad | Come, then. Meet the horn. |
| `varkas_hurt` | Vlad | Is that all the herd left? |
| `varkas_kill_1` | Vlad | Down you go, with the rest. |
| `varkas_final` | Vlad | Ring it, then. I hear them anyway. |
| `bark_contact_a` | Landon | Contact! Contact! |
| `bark_lost_a` | Landon | Lost him. |
| `varkas_kill_0` | Vlad | The mountain keeps the goat. |
| `bark_contact_b` | Gideon | There he is! |
| `bark_lost_b` | Gideon | Where did he go? |
| `bark_flank_a` | Landon | Flank him! |
| `bark_flank_b` | Gideon | Go around! |
| `bark_body_a` | Landon | Body! Someone's here! |
| `bark_body_b` | Gideon | Someone killed him. Find them. |

## Automatic behaviour (`GoatWatch`, four times a second, no hooks needed)

Reads `main.started, current_biome, zone, bells, bell_rung, boss_awake, boss, victory, enemies, player.health`
and `chapter_title.text` (duck-typed; a renamed field silences one cue instead of breaking audio):

* biome -> `set_biome`; not started -> `title`; alert wolverine -> `combat` (held 7 s), suspicious/search ->
  `suspicious` (3 s), otherwise `stealth`; Varkas awake -> `boss1..3` by `boss_phase`; victory / death.
* start -> intro narration; first entry of each zone -> `chapter_*`; mother bell rung -> `bell_rung`; a new bell
  (title "NAME // A NAME RETURNED") -> `memory_<index>`; victory -> `varkas_final` then `victory_0..3` after 6.5 s.
* Varkas: `varkas_alert` on waking, `varkas_phase_N` (+ `boss_phase_N` narration 4.6 s later) on each phase,
  `varkas_hurt` after a 20 % health loss (25 s apart), `varkas_kill` when the player dies during the fight.
* Pack barks (positional, within 50 m): `bark_contact` / `bark_flank` when a wolverine turns alert,
  `bark_lost` when it drops to search, `bark_body` when a packmate finds a corpse.
* Low health (< 35): `heartbeat`, faster as health falls (skipped when another system played one recently).

## Optional hooks for other agents (finer cues; none required)

Explicit calls are ignored when the watcher already made the same call (narration repeats within 8 s).

* main.gd, pause menu (volume sliders and subtitle switch, one line):
  `pause_overlay.add_child(GoatAudioSettings.create(audio))` (the panel is bottom-centre; the overlay's
  click-to-resume still works because sliders consume their own clicks).
* main.gd: `audio.play("ui_click")` on Start/Return buttons; `audio.play("pause_in")` / `"pause_out"` when pausing;
  `bell_pickup` instead of `chime` for bell pouches (`_update_pouches`, use `pickup`/`ammo_pickup` for ammo);
  `audio.stun(2.0)` after a bellquake hit; `audio.say("memory_%d" % pouch.bell)` if the chapter title format changes.
* player.gd: `casing` (about 0.35 s after a shot, `casing_snow` on snow), `bolt` after each shot, reload stages `mag_out` /
  `mag_in` / `bolt` (or the whole `reload`, 2.15 s), `impact_snow|impact_stone|impact_wood|impact_metal|impact_flesh` (positional at
  the hit, replacing `rock_hit`), `hitmarker` and `kill` (non-positional), `whoosh` for melee, `throw` when a stone leaves the
  hand and `stone_land` where it lands, `stun()` on a near miss.
* enemy.gd: `growl_windup` before a bite, `rifle_crack` for riflemen (a positional `play_at("shot")` is already mapped to it), `whoosh` on swings, `wolf_footstep` /
  `wolf_footstep_heavy` from step events (about 0.32 s at walk pace, 0.2 s at a run), `armor_clink` while a brute moves,
  boss: `roar` on phase change / charge start, `charge_rumble` at charge start, `quake` for the bellquake, `armor_break`
  when plates shed, `snarl` / `wolf_breath` for idle presence.

## Verification (you cannot listen, so it is measured)

* `python3 tools/audio/analyze.py --strict` -> 206 files, 0 problems: peaks <= -0.5 dBFS, no clipping or NaN, DC < 0.01,
  click-free edges, 44.1 kHz, loop seams within a few sample steps, no harsh (2.5-6 kHz > 55 %) material.
* `tests/test_audio_registry.gd` decodes every WAV in the engine (16-bit, 44.1 kHz, peak <= 0.90 and > 0.008, RMS,
  DC, edges, crest factor), loads every OGG, checks stem loop lengths, required names, bus tree and effects, unknown names,
  volume API and persistence, ducking, muffle, music states/crossfades, voice registry against the recorded text,
  subtitle emission and cooldowns, and the ObjectDB leak hygiene after `shutdown()`.
* `tests/test_audio_watch.gd` drives a real `main.tscn` through title, stealth, alert, barks, zones, bell memory,
  low health, Varkas phases, death and victory.
* `python3 tools/audio/mix_preview.py` mixes four scenes with the in-game gains (A-weighted): loudest 400 ms window
  -17.6 dB (firefight), median -29 to -33 dB, peak <= -2.3 dBFS, 2.5-6 kHz share 4-12 %, nothing above the limiter.
* `tools/audio/record_mix.gd` records Godot's own mix (buses, reverb, ducking, compressor, limiter): stealth peak -8.2 dB /
  RMS -23.6 dB, firefight peak -3.6 / -21.7, boss peak -5.3 / -19.3, no clipped samples.

## Regenerating

```
python3 tools/audio/render.py                      # all effects, beds, music, scripts/audio_bank.gd
python3 tools/audio/voice_manifest_build.py        # voice_manifest.json from the recorded Higgsfield jobs
python3 tools/audio/voice_fetch.py <raw_dir>       # download the takes
python3 tools/audio/voice_process.py <raw_dir>     # -> assets/audio/voice/*.ogg
Godot --headless --path . --import                 # then set compress/mode=0 on new .wav.import files (PCM, not QOA)
Godot --headless --path . --script res://tools/audio/build_bus_layout.gd   # default_bus_layout.tres
```

Note: ffmpeg here has no libvorbis; the native encoder is stereo-only, so mono clips and voice lines are
stored dual-mono.
