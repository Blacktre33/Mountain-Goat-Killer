#!/usr/bin/env python3
"""Summarise The Last Bell playtest logs into one Markdown report.

Each play session writes a JSON-lines file to the game's user folder:

    macOS:   ~/Library/Application Support/Godot/app_userdata/Mountain Goat Killer- The Last Bell/playtests/
    Windows: %APPDATA%\\Godot\\app_userdata\\Mountain Goat Killer- The Last Bell\\playtests\\
    Linux:   ~/.local/share/godot/app_userdata/Mountain Goat Killer- The Last Bell/playtests/

(An exported build without a custom user dir uses the same paths.) Collect the
files from every tester into one folder, then:

    python3 tools/summarize_playtests.py playtests/            # print the report
    python3 tools/summarize_playtests.py playtests/ -o report.md

Standard library only.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path

ZONE_ORDER = ["trailhead", "homestead", "shrine", "shrine_rung", "ascent", "gate"]
ZONE_NAMES = {
    "trailhead": "Widowpine trailhead",
    "homestead": "The Broken Fold",
    "shrine": "Carrion Cut shrine",
    "shrine_rung": "Shrine (bell rung)",
    "ascent": "Black Ravine ascent",
    "gate": "Iron Crown / Varkas",
    "": "(between zones)",
}


def load_sessions(paths: list[Path]) -> list[dict]:
    files: list[Path] = []
    for path in paths:
        if path.is_dir():
            files.extend(sorted(path.rglob("*.jsonl")))
        elif path.suffix == ".jsonl":
            files.append(path)
    sessions = []
    for file in files:
        events = []
        for number, line in enumerate(file.read_text(encoding="utf-8").splitlines(), 1):
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                print(f"warning: {file}:{number} is not valid JSON; skipped", file=sys.stderr)
        if events:
            sessions.append({"file": file.name, "events": events})
    return sessions


def first(events: list[dict], kind: str) -> dict:
    return next((e for e in events if e.get("event") == kind), {})


def last(events: list[dict], kind: str) -> dict:
    return next((e for e in reversed(events) if e.get("event") == kind), {})


def of(events: list[dict], kind: str) -> list[dict]:
    return [e for e in events if e.get("event") == kind]


def zone_times(events: list[dict]) -> dict[str, float]:
    """Seconds spent in each zone, from successive zone entries to the session end."""
    times: dict[str, float] = defaultdict(float)
    current, since = None, 0.0
    for event in events:
        if event.get("event") == "zone_enter":
            if current is not None:
                times[current] += max(0.0, event["t"] - since)
            current, since = event.get("zone", ""), event["t"]
    end = events[-1].get("t", since) if events else since
    if current is not None:
        times[current] += max(0.0, end - since)
    return dict(times)


def analyse(session: dict) -> dict:
    events = session["events"]
    start = first(events, "session_start")
    end = last(events, "session_end")
    victory = bool(of(events, "victory"))
    outcome = "victory" if victory else (end.get("reason", "") or "no end recorded (crash or kill?)")
    duration = events[-1].get("t", 0.0)
    shots = end.get("shots", 0)
    hits = end.get("hits", 0)
    return {
        "file": session["file"],
        "difficulty": start.get("difficulty", "?"),
        "device": start.get("device", "?"),
        "continued": start.get("continued", False),
        "outcome": outcome,
        "victory": victory,
        "duration": duration,
        "deaths": of(events, "death"),
        "detections": of(events, "detected"),
        "kills": of(events, "enemy_killed"),
        "bells": max([e.get("bells", 0) for e in events if "bells" in e] or [0]),
        "zone_times": zone_times(events),
        "boss_engaged": len(of(events, "boss_engaged")),
        "boss_retries": sum(1 for e in of(events, "respawn") if e.get("boss_retry")),
        "boss_phase": max([e.get("phase", 0) for e in of(events, "boss_phase")] or [0]),
        "pauses": len(of(events, "pause")),
        "difficulty_changes": [e.get("difficulty") for e in of(events, "difficulty_changed")],
        "devices_used": {e.get("device") for e in of(events, "input_device")} | {start.get("device", "?")},
        "accuracy": (hits / shots) if shots else None,
        "mother_bell": bool(of(events, "mother_bell_rung")),
        "bodies_found": of(events, "body_found"),
        "cairns": sorted({e.get("index") for e in of(events, "cairn_kindled")}),
    }


def minutes(seconds: float) -> str:
    return f"{int(seconds // 60)}:{int(seconds % 60):02d}"


def table(headers: list[str], rows: list[list]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    lines += ["| " + " | ".join(str(cell) for cell in row) + " |" for row in rows]
    return lines


def report(sessions: list[dict]) -> str:
    runs = [analyse(s) for s in sessions]
    out = ["# The Last Bell — playtest summary", ""]
    if not runs:
        return "\n".join(out + ["No playtest sessions found."]) + "\n"

    won = [r for r in runs if r["victory"]]
    out += [
        f"**{len(runs)} sessions**, {len(won)} reached the ending "
        f"({100 * len(won) / len(runs):.0f}%). "
        f"Total play time {minutes(sum(r['duration'] for r in runs))}.",
        "",
        "Difficulty: " + ", ".join(f"{k} ×{v}" for k, v in Counter(r["difficulty"] for r in runs).most_common()),
        "",
        "Input: " + ", ".join(f"{k} ×{v}" for k, v in Counter(d for r in runs for d in r["devices_used"]).most_common()),
        "",
        "## Sessions",
        "",
    ]
    out += table(
        ["Log", "Difficulty", "Outcome", "Play time", "Bells", "Deaths", "Alerts", "Boss phase", "Boss retries", "Accuracy"],
        [[
            r["file"], r["difficulty"] + (" (continued)" if r["continued"] else ""), r["outcome"], minutes(r["duration"]),
            r["bells"], len(r["deaths"]), len(r["detections"]), r["boss_phase"] or "—", r["boss_retries"],
            f"{100 * r['accuracy']:.0f}%" if r["accuracy"] is not None else "—",
        ] for r in runs],
    )

    out += ["", "## Time per zone", "", "Seconds of unpaused play, across sessions that entered the zone.", ""]
    rows = []
    for zone in ZONE_ORDER:
        samples = [r["zone_times"][zone] for r in runs if zone in r["zone_times"]]
        if samples:
            rows.append([ZONE_NAMES[zone], len(samples), minutes(statistics.median(samples)), minutes(max(samples))])
    out += table(["Zone", "Sessions", "Median", "Longest"], rows)

    deaths = [d for r in runs for d in r["deaths"]]
    out += ["", f"## Deaths ({len(deaths)})", ""]
    if deaths:
        by_zone = Counter(ZONE_NAMES.get(d.get("zone", ""), d.get("zone", "")) for d in deaths)
        by_cause = Counter(d.get("cause") or "unknown" for d in deaths)
        out += table(["Zone", "Deaths", "Per session"], [[z, n, f"{n / len(runs):.2f}"] for z, n in by_zone.most_common()])
        out += [""]
        out += table(["Cause", "Deaths"], [[c, n] for c, n in by_cause.most_common()])
        out += ["", "Death positions (x, z) for plotting against the ravine: " + ", ".join(
            f"({d.get('x', '?')}, {d.get('z', '?')})" for d in deaths[:60]) + ("…" if len(deaths) > 60 else "")]
    else:
        out += ["No deaths recorded."]

    detections = [d for r in runs for d in r["detections"]]
    out += ["", f"## Alerts ({len(detections)})", "",
            "Each time a wolverine went fully alert. Reasons: sight or scent (it sensed the Herdkeeper), "
            "noise (gunfire or a volley), pack (a packmate's or tracker's howl, or the mother bell), "
            "shot (it was hit), boss (Varkas woke).", ""]
    if detections:
        out += table(["Reason", "Alerts"], [[k or "unknown", n] for k, n in Counter(d.get("reason", "") for d in detections).most_common()])
        out += [""]
        out += table(["Zone", "Alerts", "Per session"], [
            [ZONE_NAMES.get(z, z), n, f"{n / len(runs):.2f}"]
            for z, n in Counter(d.get("zone", "") for d in detections).most_common()])
        out += [""]
        out += table(["Spotted by", "Count"], [[k, n] for k, n in Counter(d.get("role", "?") for d in detections).most_common()])
        crouched = sum(1 for d in detections if d.get("crouched"))
        lit = sum(1 for d in detections if d.get("lit"))
        out += ["", f"Herdkeeper crouched at the time: {crouched} ({100 * crouched / len(detections):.0f}%). "
                    f"While lit by lanterns or fire: {lit} ({100 * lit / len(detections):.0f}%)."]
    else:
        out += ["No alerts recorded."]

    kills = [k for r in runs for k in r["kills"] if k.get("role") != "boss"]
    if kills:
        silent = sum(1 for k in kills if not k.get("aware"))
        out += ["", "## Kills", "", f"{len(kills)} warpack kills; {silent} ({100 * silent / len(kills):.0f}%) "
                "landed before the target was alerted (ambushes and horn strikes)."]

    bodies = [b for r in runs for b in r["bodies_found"]]
    out += ["", f"## Bodies found ({len(bodies)})", "",
            "A patrol discovered a body left in the open; the pack searched and stayed wary."]
    if bodies:
        out += [""]
        out += table(["Zone", "Bodies found", "Per session"], [
            [ZONE_NAMES.get(z, z), n, f"{n / len(runs):.2f}"]
            for z, n in Counter(b.get("zone", "") for b in bodies).most_common()])

    out += ["", "## Maren's cairns (optional flank routes)", ""]
    cairn_counts = Counter(len(r["cairns"]) for r in runs)
    out += table(["Cairns kindled", "Sessions"], [[k, cairn_counts.get(k, 0)] for k in range(4)])
    by_cairn = Counter(i for r in runs for i in r["cairns"])
    names = {0: "Widowpine shoulder", 1: "Shrine east shoulder", 2: "Black Ravine gully camp"}
    out += ["", "Found per cairn: " + ", ".join(f"{names[i]} {by_cairn.get(i, 0)}/{len(runs)}" for i in range(3)) + "."]

    reached = [r for r in runs if r["boss_engaged"]]
    out += ["", "## Varkas", ""]
    if reached:
        attempts = sum(r["boss_engaged"] for r in reached)
        boss_deaths = Counter(d.get("cause") or "unknown" for r in reached for d in r["deaths"] if d.get("boss_phase", 0) > 0)
        phase_deaths = Counter(d.get("boss_phase") for r in reached for d in r["deaths"] if d.get("boss_phase", 0) > 0)
        out += [
            f"{len(reached)} sessions reached Varkas; {sum(1 for r in reached if r['victory'])} beat him. "
            f"{attempts} attempts in total ({attempts / len(reached):.1f} per session).",
            "",
        ]
        if boss_deaths:
            out += table(["Killed by", "Deaths"], [[c, n] for c, n in boss_deaths.most_common()])
            out += ["", "Deaths by phase: " + ", ".join(f"phase {p}: {n}" for p, n in sorted(phase_deaths.items()))]
    else:
        out += ["No session reached Varkas."]

    changed = [r for r in runs if r["difficulty_changes"]]
    out += ["", "## Other signals", "",
            f"- Pauses: {sum(r['pauses'] for r in runs)} across all sessions.",
            f"- Difficulty changed mid-run in {len(changed)} session(s)"
            + (": " + "; ".join(f"{r['file']} → {', '.join(r['difficulty_changes'])}" for r in changed) if changed else "."),
            f"- Rang the mother bell: {sum(1 for r in runs if r['mother_bell'])} of {len(runs)} sessions.",
            f"- Sessions that ended without a clean close (possible crash): "
            f"{sum(1 for r in runs if r['outcome'].startswith('no end'))}."]
    return "\n".join(out) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="+", type=Path, help="session .jsonl files or folders containing them")
    parser.add_argument("-o", "--output", type=Path, help="write the Markdown report here instead of stdout")
    args = parser.parse_args()
    text = report(load_sessions(args.paths))
    if args.output:
        args.output.write_text(text, encoding="utf-8")
        print(f"Wrote {args.output}")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
