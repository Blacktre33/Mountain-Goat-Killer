"""Turn raw Higgsfield speech takes into game-ready 44.1 kHz Ogg files (dual-mono: ffmpeg's native Vorbis encoder is stereo-only).

Usage: python3 tools/audio/voice_process.py <raw_dir> [out_dir=assets/audio/voice]

Per speaker chain (all deterministic):
  keeper  Herdkeeper inner narration: high-pass, gentle air roll-off, level to -22 dBFS speech RMS.
  varkas  Slowed ~6 % (about one semitone lower), body boost, tanh grit, band-limited.
  pack_*  Warpack barks: band-limited and lightly saturated so they cut through gunfire.
Every take has leading/trailing silence trimmed (keeping short pads), a fade out,
and a peak ceiling of -1.5 dBFS.
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from dsp import SR, highpass, lowpass, shape_by  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
TARGET_RMS_DB = {"keeper": -22.0, "varkas": -18.0, "pack_a": -18.0, "pack_b": -18.0}


def read_wav(path):
	with wave.open(path) as fh:
		ch = fh.getnchannels()
		x = np.frombuffer(fh.readframes(fh.getnframes()), dtype="<i2").astype(np.float64) / 32768.0
		assert fh.getframerate() == SR, "expected 44.1 kHz takes"
	return x.reshape(-1, ch).mean(axis=1)


def trim(x, pad_head=0.05, pad_tail=0.18, floor_db=-46.0):
	peak = np.max(np.abs(x))
	idx = np.nonzero(np.abs(x) > peak * 10.0 ** (floor_db / 20.0))[0]
	a = max(0, idx[0] - int(pad_head * SR))
	b = min(len(x), idx[-1] + int(pad_tail * SR))
	return x[a:b]


def speech_rms_db(x):
	frame = int(0.03 * SR)
	n = len(x) // frame
	e = np.sqrt(np.mean(x[: n * frame].reshape(n, frame) ** 2, axis=1))
	active = e[e > e.max() * 0.1]
	return 20 * np.log10(np.sqrt(np.mean(active ** 2)) + 1e-9)


def resample(x, ratio):
	"""ratio < 1 slows and lowers the take."""
	src = np.arange(int(len(x) / ratio)) * ratio
	return np.interp(src, np.arange(len(x)), x)


def chain(x, speaker):
	x = highpass(x, 70.0, 2)
	if speaker == "keeper":
		x = lowpass(x, 9500.0, 2)
	elif speaker == "varkas":
		x = resample(x, 0.94)
		x = shape_by(x, [(40, -20), (90, 0), (150, 3.5), (300, 2.0), (1500, 0), (4000, -2), (7000, -9), (12000, -24)])
		x = np.tanh(x * 2.2 / (np.max(np.abs(x)) + 1e-9)) * 0.9
	else:
		x = shape_by(x, [(80, -18), (200, -3), (700, 0), (2500, 2), (5500, -2), (8000, -12), (14000, -30)])
		x = np.tanh(x * 1.8 / (np.max(np.abs(x)) + 1e-9)) * 0.9
	return x


def finish(x, speaker):
	x = trim(x)
	x = x - x.mean()
	x = x * 10.0 ** ((TARGET_RMS_DB[speaker] - speech_rms_db(x)) / 20.0)
	ceiling = 10.0 ** (-1.5 / 20.0)
	x = np.tanh(x / ceiling) * ceiling
	fi, fo = int(0.006 * SR), int(0.08 * SR)
	x[:fi] *= np.linspace(0, 1, fi)
	x[-fo:] *= np.linspace(1, 0, fo)
	return x


def write_ogg(path, x, bitrate="96k"):
	tmp = path + ".tmp.wav"
	pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
	with wave.open(tmp, "wb") as fh:
		fh.setnchannels(1)
		fh.setsampwidth(2)
		fh.setframerate(SR)
		fh.writeframes(pcm.tobytes())
	subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-c:a", "vorbis", "-strict", "-2", "-ac", "2", "-b:a", bitrate, path], check=True)
	os.remove(tmp)


def main(raw_dir, out_dir):
	os.makedirs(out_dir, exist_ok=True)
	with open(os.path.join(HERE, "voice_manifest.json")) as fh:
		manifest = json.load(fh)
	for entry in manifest["lines"]:
		src = os.path.join(raw_dir, entry["id"] + ".wav")
		x = finish(chain(read_wav(src), entry["speaker"]), entry["speaker"])
		write_ogg(os.path.join(out_dir, entry["id"] + ".ogg"), x)
		print("%-20s %-7s %5.2fs" % (entry["id"], entry["speaker"], len(x) / SR))


if __name__ == "__main__":
	main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "assets/audio/voice")
