# Running a human playtest

The automated campaign probe proves every gate can be passed. It cannot say
whether the climb is fair, readable, or fun. The aim of a round is 3–5 people
who have never seen the game, each playing once without help.

## 1. Build what testers will run

- Push to any branch. The **CI** workflow runs every test suite, then attaches
  Linux, Windows and macOS builds to the run as artifacts
  (`the-last-bell-linux`, `-windows`, `-macos`).
- To build locally, install the Godot 4.7.2 export templates and run
  `godot --headless --path . --export-release "macOS" "build/macos/The Last Bell.zip"`
  (or `"Windows"` / `"Linux"`; see `export_presets.cfg`).
- The macOS build is ad-hoc signed and not notarized. Testers right-click the
  app and choose **Open** the first time. Windows SmartScreen needs
  **More info → Run anyway**.

## 2. What to tell testers

Keep it to this. Anything more tells them how to play.

> This is a first-person stealth game. Play as far as you like, at your own pace,
> until you finish or want to stop. Say out loud whatever you're thinking,
> especially when you're confused or frustrated. I won't help, but I'll answer
> questions afterwards.

- Let them choose a difficulty. Which preset they pick is itself data.
- Watch without steering. Note the moments they hesitate, misread a prompt,
  or ask "what do I do?".
- Stop after 45 minutes if they have not finished.

## 3. Collect the logs

With **Options → Playtesting → Record a local playtest log** on (the default),
each run writes one `session-<time>.jsonl` file. Nothing is uploaded. The
folder is shown in Options, and **Open log folder** opens it:

| OS | Folder |
| --- | --- |
| macOS | `~/Library/Application Support/Godot/app_userdata/Mountain Goat Killer- The Last Bell/playtests/` |
| Windows | `%APPDATA%\Godot\app_userdata\Mountain Goat Killer- The Last Bell\playtests\` |
| Linux | `~/.local/share/godot/app_userdata/Mountain Goat Killer- The Last Bell/playtests/` |

Copy every tester's files into one folder, e.g. `playtests/round-1/`, then run:

```bash
python3 tools/summarize_playtests.py playtests/round-1 -o playtests/round-1/REPORT.md
```

The report covers outcomes, time per zone, deaths by zone and cause (with
positions), alerts by reason (sight, scent, noise, pack, shot), zone and
enemy type, bodies found, which of Maren's cairns each tester found, silent
vs alerted kills,
Varkas attempts, deaths per boss phase and attack, pauses, input devices and
mid-run difficulty changes.

## 4. Ask afterwards (2 minutes)

1. When did you feel most confused? Most frustrated?
2. Did you understand what the wind indicator was telling you?
3. Did you use Remembrance (F / RB)? If not, why not? Did you notice the
   stone cairns, and what did you think they did?
4. Did Varkas's warnings give you enough time to react?
5. Did the music tell you when you had been spotted before the HUD did?
6. Which chapter would you cut, and which would you want more of?
7. From 1 to 5, how likely are you to play a second mission?

## 5. Reading the results

These are rules of thumb for deciding what to tune next, not pass/fail bars:

- **Deaths cluster in one zone** (more than about 1 per session there): look at
  its `cause` column first. Rifle deaths point at sightlines or rifleman
  accuracy. Brute or stalker deaths point at encounter spacing.
- **Median time in a zone is long but deaths are low**: that's a navigation or
  objective problem. Check the notes for "what do I do?" moments.
- **Most sight alerts happen while lit**: lanterns are working as intended.
  If most happen while crouched and unlit, sight rates may be too high. Many
  **scent** alerts mean the wind indicator isn't being read.
- **Few silent kills**: the stealth tools (wind, stones, horn strike) aren't
  being discovered. Revisit the title field note and first-chapter prompts.
- **More than 3 Varkas attempts per session**, or deaths concentrated on one
  attack: lengthen that tell or add a clearer audio cue before touching damage.
- **Many bodies found**: kills are happening in patrol sightlines. Fine if
  the testers then adapted; a problem if every discovery snowballed into a
  death (compare the next death's time and zone).
- **Few cairns found**: the flank routes are not reading as routes. Nobody
  finding the gully camp's cairn is expected on a first run; nobody finding
  the Widowpine shoulder cairn is not.
- **Tracker alerts ("pack" reason, role tracker) dominate**: trackers may be
  too punishing for a first climb; check whether testers learned to kill them
  first.
- **Testers switched to STORY mid-run**: HUNTER is too hard somewhere. The
  switch time points to where.

Keep each round's `REPORT.md` and notes beside its logs so later tuning can be
checked against them.
