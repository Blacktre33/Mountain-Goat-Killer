"""Download Higgsfield seed_audio speech jobs listed in a manifest.

Usage: python3 tools/audio/voice_fetch.py <raw_dir>

Reads tools/audio/voice_manifest.json (id, speaker, text, url) and downloads every
missing `<raw_dir>/<id>.wav`. Processing into game assets is voice_process.py.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def main(raw_dir):
	os.makedirs(raw_dir, exist_ok=True)
	with open(os.path.join(HERE, "voice_manifest.json")) as fh:
		manifest = json.load(fh)
	for entry in manifest["lines"]:
		dest = os.path.join(raw_dir, entry["id"] + ".wav")
		if os.path.exists(dest) and os.path.getsize(dest) > 1000:
			continue
		print("fetch", entry["id"])
		subprocess.run(["curl", "-sL", "--max-time", "60", "-o", dest, entry["url"]], check=True)


if __name__ == "__main__":
	main(sys.argv[1])
