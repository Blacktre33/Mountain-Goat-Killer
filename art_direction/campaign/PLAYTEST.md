# Full campaign progression proof — 2026-09-05

The final build, including rebuilt vegetation and pause/replay, completes all
gates with **9/9 bells, 42 shots, 68 health, 6/136 ammunition and no retry**.
See `final-run.log` and `result.png`. All thirteen functional suites pass;
their final logs are preserved in `../final_verification/`.

The final route audit also exposed a probe limitation: its old flat grid
connected free floor samples across a raised terrace edge. The player kept
jumping against the terrace. The probe now uses a 3D path graph with height
limits between neighboring samples, avoids diagonal corner cuts, and measures
stalls horizontally so jumping cannot hide a blocked route. The corrected
probe crosses the ascent using ordinary player movement; no game collision
was removed to accommodate it. It still stops if progress stalls.

The ascent objective now changes after eight recoveries, telling the player
to climb to the Iron Crown instead of asking again for eight names.

## Earlier successful runs

Latest repeat with Varkas's joined facial sculpt and four-sample MSAA also
completes every gate: 42 shots, 43 health, 6/136 ammunition and no retry. See
`sculpt-run.log`. The difference in final health between runs is not evidence
of a difficulty change; this is an automated progression probe.

The graphical campaign probe completed the real route from deployment to the
ninth bell. It moves through Godot's player controls and collision, aims and
fires the real carbine, reloads normally, collects proximity drops, rings the
mother bell through its prompt, opens the gated courtyard, and performs the
final horn strike through the actual interaction. Enemy AI and Varkas's
reinforcements remain active. It does not teleport, add health/ammunition,
directly damage enemies, set bell counts, or skip phase locks.

The final run recovered **9/9 bells**, rang the mother bell, opened the gate,
visited Varkas phases **1, 2 and 3**, and observed active reinforcements. It
finished with **34 health**, **42 shots fired**, **6/136 ammunition**, and
**zero retries**. See `verified-run.log` and `result.png`. The elapsed 63.7
seconds is a direct automated route with accurate aim; it does not estimate
human playtime, story-reading time, or player difficulty. This probe currently
uses the carbine, so the separate Remembrance and boss-counterplay suites
remain necessary. The final pose is deliberately close to the horn strike;
these are gameplay evidence frames, not selected character beauty shots.

## Problems reproduced and corrected

- A named drop at the shrine was placed at height-field level beneath the
  mother-bell dais, and its bobbing animation continually restored that buried
  height. Drops now sample real world collision and retain the surface height.
- The old shrine patrol led into the dais. It now follows the clear east side
  of the shrine. The ascent brute's initial capsule intersected TerraceTwo;
  its start now sits on the clear approach. The spawn regression checks every
  initial enemy capsule against world collision.
- A first navigation probe stopped at the nearest grid sample rather than
  taking the final approach to a target. The probe now drives that last segment
  with normal collision and reports lack of mission progress after 30 seconds.
  This probe-only limitation was kept separate from the buried-drop finding.

## Repeat

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --resolution 960x540 --fixed-fps 60 --script res://tools/playtest_campaign.gd
```

The graphical runtime is required: the headless display cannot capture the
mouse for player input. Captures are saved under this directory. All twelve
headless suites passed at this checkpoint. The traversal test's subsequent
cleanup now waits for the audio mixer and checks release of generated streams
and playbacks; three runs of the final saved test exit without its prior warning.
No frame-rate or human balance claim follows from this playback.
