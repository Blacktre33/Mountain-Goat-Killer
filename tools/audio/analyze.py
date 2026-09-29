"""Numeric QA for rendered audio (you cannot listen, so measure).

Usage:
    python3 tools/audio/analyze.py [--dir assets/audio/generated] [--spectro NAME OUT.png] [--strict]

For every file in manifest.json (and voice/*.ogg when present) reports peak,
RMS, crest factor, DC offset, clipping count, NaN/Inf, edge discontinuities,
spectral centroid, band energy split and a "harshness" ratio (2.5-6 kHz share).
With --strict exits non-zero when a hard rule is broken.
"""
import argparse
import json
import os
import subprocess
import sys
import wave
import zlib

import numpy as np

BANDS = [(20, 120), (120, 500), (500, 2000), (2000, 6000), (6000, 20000)]


def load(path):
	if path.endswith(".wav"):
		with wave.open(path) as fh:
			ch, sr = fh.getnchannels(), fh.getframerate()
			x = np.frombuffer(fh.readframes(fh.getnframes()), dtype="<i2").astype(np.float64) / 32768.0
	else:
		raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "s16le", "-acodec", "pcm_s16le", "-"], capture_output=True, check=True).stdout
		probe = subprocess.run(["ffprobe", "-loglevel", "error", "-show_entries", "stream=channels,sample_rate", "-of", "csv=p=0", path], capture_output=True, check=True).stdout.decode().strip().split(",")
		sr, ch = int(probe[0]), int(probe[1])
		x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
	return x.reshape(-1, ch), sr


def band_split(mono, sr):
	spec = np.abs(np.fft.rfft(mono)) ** 2
	f = np.fft.rfftfreq(len(mono), 1.0 / sr)
	total = spec.sum() + 1e-18
	return [float(spec[(f >= lo) & (f < hi)].sum() / total) for lo, hi in BANDS], float((spec * f).sum() / total)


def analyse(path):
	x, sr = load(path)
	mono = x.mean(axis=1)
	peak = float(np.max(np.abs(x))) if x.size else 0.0
	rms = float(np.sqrt(np.mean(x ** 2))) if x.size else 0.0
	bands, centroid = band_split(mono, sr)
	# Loudness proxy: RMS of the loudest 400 ms window (short sounds are judged by their body).
	win = max(1, int(0.4 * sr))
	env = np.convolve(mono ** 2, np.ones(win) / win, mode="valid") if len(mono) >= win else np.array([np.mean(mono ** 2)])
	return {
		"sr": sr, "ch": x.shape[1], "seconds": len(x) / sr,
		"peak_db": 20 * np.log10(peak + 1e-12), "rms_db": 20 * np.log10(rms + 1e-12),
		"loud400_db": 10 * np.log10(env.max() + 1e-18), "crest_db": 20 * np.log10((peak + 1e-12) / (rms + 1e-12)),
		"dc": float(abs(x.mean())), "clipped": int(np.sum(np.abs(x) >= 0.999)),
		"nan": bool(not np.all(np.isfinite(x))),
		"first": float(np.max(np.abs(x[:2]))) if len(x) else 0.0, "last": float(np.max(np.abs(x[-2:]))) if len(x) else 0.0,
		"centroid": centroid, "bands": bands, "harsh": bands[3],
	}


def png_write(path, rgb):
	h, w, _ = rgb.shape
	raw = b"".join(b"\x00" + rgb[y].astype(np.uint8).tobytes() for y in range(h))

	def chunk(tag, data):
		c = struct_pack(len(data)) + tag + data
		return c + struct_pack(zlib.crc32(tag + data) & 0xFFFFFFFF)

	def struct_pack(v):
		return int(v).to_bytes(4, "big")

	with open(path, "wb") as fh:
		fh.write(b"\x89PNG\r\n\x1a\n")
		fh.write(chunk(b"IHDR", struct_pack(w) + struct_pack(h) + bytes([8, 2, 0, 0, 0])))
		fh.write(chunk(b"IDAT", zlib.compress(raw, 6)))
		fh.write(chunk(b"IEND", b""))


def spectrogram(path, out_png, width=900, height=300, fmax=12000):
	x, sr = load(path)
	mono = x.mean(axis=1)
	nfft = 2048
	hop = max(1, (len(mono) - nfft) // width) if len(mono) > nfft else 1
	frames = []
	win = np.hanning(nfft)
	for i in range(0, max(1, len(mono) - nfft), hop):
		seg = mono[i : i + nfft]
		if len(seg) < nfft:
			seg = np.pad(seg, (0, nfft - len(seg)))
		frames.append(np.abs(np.fft.rfft(seg * win)))
	sp = 20 * np.log10(np.array(frames).T + 1e-9)
	f = np.fft.rfftfreq(nfft, 1.0 / sr)
	keep = f <= fmax
	sp = sp[keep][::-1]
	top = sp.max()
	img = np.clip((sp - (top - 80)) / 80.0, 0, 1)
	img = np.array([[img[int(r * img.shape[0] / height), min(int(c * img.shape[1] / width), img.shape[1] - 1)] for c in range(width)] for r in range(height)])
	rgb = np.stack([np.clip(img * 2.0, 0, 1), np.clip(img * 2 - 0.6, 0, 1), np.clip(img * 1.2 - 0.2, 0, 1)], axis=-1) * 255
	png_write(out_png, rgb)


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--dir", default="assets/audio/generated")
	ap.add_argument("--spectro", nargs=2)
	ap.add_argument("--strict", action="store_true")
	ap.add_argument("--voice-dir", default="assets/audio/voice")
	ap.add_argument("--files", nargs="+", help="analyse these audio files instead of the manifest (e.g. recorded mixes)")
	args = ap.parse_args()
	if args.files:
		for path in args.files:
			r = analyse(path)
			print("%s: %.1f s peak %.1f dB rms %.1f dB loudest-400ms %.1f dB clipped %d NaN %s | bands <120/500/2k/6k/20k %s" % (
				os.path.basename(path), r["seconds"], r["peak_db"], r["rms_db"], r["loud400_db"], r["clipped"], r["nan"], " ".join("%2.0f" % (b * 100) for b in r["bands"])))
		return
	if args.spectro:
		name, out = args.spectro
		spectrogram(os.path.join(args.dir, name), out)
		return
	with open(os.path.join(args.dir, "manifest.json")) as fh:
		manifest = json.load(fh)
	problems = []
	print("%-26s %5s %6s %6s %6s %5s %6s | %s" % ("file", "sec", "peak", "rms", "loud", "cent", "harsh", "bands <120/500/2k/6k/20k %"))
	paths = []
	for name, entry in sorted(manifest.items()):
		for f in entry["files"]:
			paths.append((name, f, os.path.join(args.dir, f), entry))
	if os.path.isdir(args.voice_dir):
		for f in sorted(os.listdir(args.voice_dir)):
			if f.endswith(".ogg"):
				paths.append(("voice", f, os.path.join(args.voice_dir, f), None))
	for name, f, path, entry in paths:
		if not os.path.exists(path):
			problems.append("%s missing" % f)
			continue
		r = analyse(path)
		flag = ""
		if r["nan"]:
			problems.append("%s NaN" % f)
		if r["clipped"] > 0:
			problems.append("%s clipped %d samples" % (f, r["clipped"]))
		if r["peak_db"] > -0.5:
			problems.append("%s peak %.1f dB is too hot" % (f, r["peak_db"]))
		if r["peak_db"] < -40:
			problems.append("%s is near silent (%.1f dB)" % (f, r["peak_db"]))
		if r["dc"] > 0.01:
			problems.append("%s DC offset %.4f" % (f, r["dc"]))
		if entry and entry.get("loop"):
			# A loop has no fade: its seam is the step from the last sample back to the first,
			# which must not exceed a few of the signal's own sample-to-sample steps.
			x, _ = load(path)
			step = np.sqrt(np.mean(np.diff(x, axis=0) ** 2)) + 1e-9
			seam = np.max(np.abs(x[0] - x[-1]))
			if seam > 8.0 * step + 0.01:
				problems.append("%s loop seam jumps %.4f (typical step %.4f)" % (f, seam, step))
		else:
			if r["first"] > 0.05 and not f.startswith(("shot", "rifle", "click")):
				problems.append("%s starts abruptly (%.3f)" % (f, r["first"]))
			if r["last"] > 0.01 and not (entry and entry.get("loop")):
				problems.append("%s ends abruptly (%.3f)" % (f, r["last"]))
		if r["sr"] != 44100 and name != "voice":
			problems.append("%s sample rate %d" % (f, r["sr"]))
		if r["harsh"] > 0.55 and r["loud400_db"] > -30:
			flag = " HARSH"
		print("%-26s %5.2f %6.1f %6.1f %6.1f %5.0f %5.0f%% | %s%s" % (f[:26], r["seconds"], r["peak_db"], r["rms_db"], r["loud400_db"], r["centroid"], r["harsh"] * 100, " ".join("%2.0f" % (b * 100) for b in r["bands"]), flag))
	print("\n%d files, %d problems" % (len(paths), len(problems)))
	for p in problems:
		print("  PROBLEM:", p)
	if args.strict and problems:
		sys.exit(1)


if __name__ == "__main__":
	main()
