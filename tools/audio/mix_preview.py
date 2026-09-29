"""Offline mixdown of representative game scenes with the in-game bus gains,
ducking and master compressor/limiter, then numeric QA of the result.

Usage: python3 tools/audio/mix_preview.py [--out DIR]

It mirrors scripts/audio.gd (bus trims, default user volumes, DUCKS, compressor
threshold -14 dB / ratio 3 / +2 dB, hard limiter -1 dB) and the volume_db values the
game's call sites use. Each scene is written as a 16-bit stereo WAV (default
directory: the system temp dir) and reported: peak, RMS, short-term loudness,
limiter reduction, and spectral balance. Exits non-zero when a rule is broken:
  peak after limiter <= -1 dBFS, no NaN, A-weighted 400 ms loudness within [-40, -15] dBFS,
  A-weighted 2.5-6 kHz share <= 45 %, raw sub-60 Hz share <= 45 %. RMS, loudness and band shares are A-weighted.
"""
import argparse
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
GEN = "assets/audio/generated"
VOICE = "assets/audio/voice"
KENNEY = "assets/audio"

# scripts/audio.gd BUSES trims + DEFAULT_VOLUME (linear -> dB), pause not modelled.
BUS_DB = {"music": -3.0 + 20 * np.log10(0.8), "sfx": 0.0, "ambience": -2.0 + 20 * np.log10(0.9), "voice": 0.0, "ui": -2.0}
DUCKS = {"shot": (-7, -5, 0.8), "rifle_crack": (-4, -3, 0.6), "volley": (-8, -6, 1.4), "roar": (-10, -8, 2.0), "quake": (-10, -8, 2.2),
	"bell": (-9, -6, 3.0), "armor_break": (-6, -4, 1.0), "howl": (-4, -2, 1.0), "takedown": (-3, -1, 0.5), "bell_strike": (-4, -2, 1.0)}
VOICE_DUCK = (-5, -4)
MAKEUP_DB = 4.0  # AudioEffectCompressor.gain in audio.gd


def load(path):
	raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
	return np.frombuffer(raw, dtype="<f4").reshape(-1, 2).astype(np.float64)


def sound_path(name, index=0):
	import json
	with open(os.path.join(GEN, "manifest.json")) as fh:
		manifest = json.load(fh)
	return os.path.join(GEN, manifest[name]["files"][index % len(manifest[name]["files"])])


def resample(x, pitch):
	if abs(pitch - 1.0) < 1e-3:
		return x
	src = np.arange(int(len(x) / pitch)) * pitch
	idx = np.arange(len(x))
	return np.stack([np.interp(src, idx, x[:, c]) for c in range(2)], axis=1)


class Scene:
	def __init__(self, name, seconds):
		self.name = name
		self.n = int(seconds * SR)
		self.buses = {b: np.zeros((self.n, 2)) for b in BUS_DB}
		self.duck_events = []
		self.voice_spans = []

	def add(self, bus, path, start, db=0.0, pitch=1.0, loop=False, gain_env=None, duck_key=None, voice=False):
		x = resample(load(path), pitch) * 10 ** (db / 20)
		if loop:
			reps = int(np.ceil((self.n - int(start * SR)) / len(x))) + 1
			x = np.tile(x, (reps, 1))
		i = int(start * SR)
		j = min(self.n, i + len(x))
		seg = x[: j - i]
		if gain_env is not None:
			seg = seg * gain_env[i:j, None]
		self.buses[bus][i:j] += seg
		if duck_key in DUCKS:
			self.duck_events.append((start, DUCKS[duck_key]))
		if voice:
			self.voice_spans.append((start, start + len(x) / SR))

	def duck_curve(self, which):
		t = np.arange(self.n) / SR
		target = np.zeros(self.n)
		for start, (m, a, hold) in self.duck_events:
			amount = m if which == 0 else a
			mask = (t >= start) & (t < start + hold)
			target = np.minimum(target, np.where(mask, amount, 0.0))
		for start, end in self.voice_spans:
			mask = (t >= start) & (t < end)
			target = np.minimum(target, np.where(mask, VOICE_DUCK[which], 0.0))
		# fast attack (~30 ms), slow release (~0.9 s) applied as a one-pole follower per block
		out = np.zeros(self.n)
		cur = 0.0
		block = 256
		for k in range(0, self.n, block):
			tgt = target[k : k + block].min()
			step = (90.0 if tgt < cur else 14.0) * block / SR
			cur = cur + np.clip(tgt - cur, -step, step)
			out[k : k + block] = cur
		return out

	def mix(self):
		total = np.zeros((self.n, 2))
		for bus, sig in self.buses.items():
			gain = BUS_DB[bus]
			env = np.zeros(self.n)
			if bus == "music":
				env = self.duck_curve(0)
			elif bus == "ambience":
				env = self.duck_curve(1)
			total += sig * 10 ** ((gain + env) / 20)[:, None]
		return total


def master(x):
	"""Compressor (thr -14 dB, ratio 3, attack 15 ms, release 240 ms, +MAKEUP_DB) then -1 dB hard limiter."""
	block = 128
	env = 0.0
	out = np.zeros_like(x)
	gain_db = np.zeros(len(x) // block + 1)
	for bi, k in enumerate(range(0, len(x), block)):
		seg = x[k : k + block]
		peak = np.max(np.abs(seg)) + 1e-9
		coef = np.exp(-block / SR / (0.015 if peak > env else 0.24))
		env = coef * env + (1 - coef) * peak
		level = 20 * np.log10(env)
		reduction = max(0.0, level + 14.0) * (1 - 1 / 3.0)
		g = 10 ** ((MAKEUP_DB - reduction) / 20)
		out[k : k + block] = seg * g
		gain_db[bi] = -reduction
	ceiling = 10 ** (-1.0 / 20)
	peaks = np.max(np.abs(out), axis=1)
	over = np.maximum(peaks / ceiling, 1.0)
	worst = 20 * np.log10(over.max())
	# smooth gain so the limiter does not distort: instant attack, 80 ms release
	g = np.ones(len(out))
	cur = 1.0
	rel = np.exp(-1.0 / (SR * 0.08))
	for i in range(len(out)):
		need = 1.0 / over[i]
		cur = need if need < cur else 1.0 - (1.0 - cur) * rel
		g[i] = cur
	return out * g[:, None], worst, gain_db.min()


def a_weight(mono):
	"""IEC A-weighting applied in the frequency domain (perceived loudness and balance)."""
	f = np.fft.rfftfreq(len(mono), 1 / SR)
	f2 = f ** 2
	ra = (12194.0 ** 2 * f2 ** 2) / ((f2 + 20.6 ** 2) * np.sqrt((f2 + 107.7 ** 2) * (f2 + 737.9 ** 2)) * (f2 + 12194.0 ** 2) + 1e-30)
	ra[0] = 0.0
	return np.fft.irfft(np.fft.rfft(mono) * ra * 10 ** (2.0 / 20), len(mono))


def analyse(name, y, limiter_db):
	mono = a_weight(y.mean(axis=1))
	peak = np.max(np.abs(y))
	rms = np.sqrt(np.mean(mono ** 2))
	win = int(0.4 * SR)
	hop = int(0.1 * SR)
	blocks = [10 * np.log10(np.mean(mono[i : i + win] ** 2) + 1e-12) for i in range(0, len(mono) - win, hop)]
	spec = np.abs(np.fft.rfft(mono)) ** 2
	f = np.fft.rfftfreq(len(mono), 1 / SR)
	total = spec.sum() + 1e-18
	def share(lo, hi):
		return spec[(f >= lo) & (f < hi)].sum() / total
	bands = [share(20, 60), share(60, 250), share(250, 1000), share(1000, 2500), share(2500, 6000), share(6000, 20000)]
	return {
		"peak_db": 20 * np.log10(peak + 1e-12), "rms_db": 20 * np.log10(rms + 1e-12),
		"loud_max": max(blocks), "loud_med": float(np.median(blocks)), "limiter_db": limiter_db,
		"bands": bands, "nan": bool(not np.all(np.isfinite(y))),
	}


def scene_stealth():
	s = Scene("stealth_widowpine", 32)
	s.add("ambience", sound_path("wind"), 0, -13.0, loop=True)
	s.add("ambience", sound_path("amb_widowpine"), 0, -5.0, loop=True)
	s.add("music", sound_path("music_widowpine_drone"), 0, 0.0, loop=True)
	s.add("music", sound_path("music_widowpine_motif"), 0, -1.0, loop=True)
	for i in range(40):
		s.add("sfx", os.path.join(KENNEY, "footstep_snow_00%d.ogg" % (i % 5)), 1.0 + i * 0.62, -10.0)
	s.add("sfx", sound_path("huff"), 9.0, -4.0)
	s.add("sfx", sound_path("wolf_breath"), 14.0, 0.0)
	s.add("sfx", sound_path("amb_creak_pine"), 19.0, 0.0)
	s.add("voice", os.path.join(VOICE, "memory_0.ogg"), 10.0, 0.0, voice=True)
	return s


def scene_firefight():
	s = Scene("firefight_carrion", 34)
	s.add("ambience", sound_path("wind"), 0, -8.0, loop=True)
	s.add("ambience", sound_path("amb_carrion"), 0, -5.0, loop=True)
	s.add("music", sound_path("music_carrion_drone"), 0, -9.0, loop=True)
	s.add("music", sound_path("music_carrion_tension"), 0, -6.0, loop=True)
	s.add("music", sound_path("music_carrion_combat"), 0, 0.0, loop=True)
	for i, t in enumerate((2.0, 3.6, 5.1, 7.4, 8.2, 11.0, 12.5, 15.0, 15.6, 19.0)):
		s.add("sfx", sound_path("shot", i), t, 0.0, duck_key="shot")
		s.add("sfx", sound_path("casing", i), t + 0.35, -4.0)
		s.add("sfx", sound_path("bolt", i), t + 0.7, -4.0)
	for i, t in enumerate((2.5, 4.0, 9.5, 13.0, 17.0)):
		s.add("sfx", sound_path("rifle_crack", i), t, -6.0, duck_key="rifle_crack")
	for i, t in enumerate((3.0, 5.6, 8.7, 12.7)):
		s.add("sfx", sound_path("hit", i), t, -4.0)
		s.add("sfx", sound_path("growl", i), t + 0.5, -6.0)
	s.add("sfx", sound_path("headshot", 0), 15.1, -4.0)
	s.add("sfx", sound_path("howl", 0), 6.0, -2.0, duck_key="howl")
	s.add("sfx", sound_path("bite", 0), 20.0, 0.0)
	s.add("sfx", sound_path("hurt", 0), 20.05, -2.0)
	s.add("sfx", sound_path("death", 0), 21.0, -1.0)
	for i in range(5):
		s.add("sfx", sound_path("wolf_footstep", i), 22.0 + i * 0.3, -4.0)
	s.add("sfx", sound_path("heartbeat"), 24.0, -1.0)
	s.add("sfx", sound_path("heartbeat"), 25.0, -1.0)
	s.add("sfx", sound_path("tinnitus"), 26.0, 0.0)
	s.add("voice", os.path.join(VOICE, "bark_contact_a.ogg"), 2.2, 0.0)
	s.add("voice", os.path.join(VOICE, "bark_flank_a.ogg"), 6.5, 0.0)
	return s


def scene_boss():
	s = Scene("boss_iron_crown", 36)
	s.add("ambience", sound_path("wind"), 0, -8.0, loop=True)
	s.add("ambience", sound_path("amb_iron_crown"), 0, -5.0, loop=True)
	s.add("music", sound_path("music_boss3_base"), 0, 0.0, loop=True)
	s.add("music", sound_path("music_boss3_perc"), 0, 0.0, loop=True)
	s.add("sfx", sound_path("roar"), 3.0, 0.0, duck_key="roar")
	s.add("sfx", sound_path("charge_rumble"), 9.0, 0.0)
	s.add("sfx", sound_path("quake"), 13.0, 0.0, duck_key="quake")
	s.add("sfx", sound_path("armor_break"), 18.0, 0.0, duck_key="armor_break")
	s.add("sfx", sound_path("bell"), 22.0, 0.0, 0.55, duck_key="bell")
	s.add("sfx", sound_path("volley"), 28.0, 0.0, duck_key="volley")
	s.add("sfx", sound_path("shot"), 29.0, 0.0, duck_key="shot")
	s.add("sfx", sound_path("whoosh"), 31.0, 0.0)
	s.add("voice", os.path.join(VOICE, "varkas_phase_3.ogg"), 6.0, 0.0, voice=True)
	return s


def scene_ending():
	s = Scene("ending_victory", 50)
	s.add("ambience", sound_path("wind"), 0, -14.0, loop=True)
	s.add("ambience", sound_path("amb_iron_crown"), 0, -5.0, loop=True)
	s.add("music", sound_path("music_victory"), 1.0, 0.0)
	s.add("sfx", sound_path("bell"), 0.5, 0.0, duck_key="bell")
	t = 7.0
	for i in range(4):
		p = os.path.join(VOICE, "victory_%d.ogg" % i)
		x = load(p)
		s.add("voice", p, t, 0.0, voice=True)
		t += len(x) / SR + 0.4
	return s


def write_wav(path, y):
	pcm = np.clip(np.round(y * 32767), -32768, 32767).astype("<i2")
	with wave.open(path, "wb") as fh:
		fh.setnchannels(2)
		fh.setsampwidth(2)
		fh.setframerate(SR)
		fh.writeframes(pcm.tobytes())


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--out", default=tempfile.gettempdir())
	args = ap.parse_args()
	os.makedirs(args.out, exist_ok=True)
	bad = []
	print("%-20s %6s %6s %7s %7s %6s | bands <60/250/1k/2.5k/6k/20k %%" % ("scene", "peak", "rms", "loud400", "median", "lim"))
	for build in (scene_stealth, scene_firefight, scene_boss, scene_ending):
		scene = build()
		y, limiter_db, comp_db = master(scene.mix())
		write_wav(os.path.join(args.out, scene.name + ".wav"), y)
		r = analyse(scene.name, y, limiter_db)
		print("%-20s %6.1f %6.1f %7.1f %7.1f %6.1f | %s" % (scene.name, r["peak_db"], r["rms_db"], r["loud_max"], r["loud_med"], r["limiter_db"], " ".join("%2.0f" % (b * 100) for b in r["bands"])))
		if r["nan"]:
			bad.append("%s NaN" % scene.name)
		if r["peak_db"] > -0.95:
			bad.append("%s peak %.1f dB" % (scene.name, r["peak_db"]))
		if r["loud_max"] > -15.0:
			bad.append("%s loudest 400 ms %.1f dB is painfully loud" % (scene.name, r["loud_max"]))
		if r["loud_med"] < -40.0:
			bad.append("%s median loudness %.1f dB is too quiet" % (scene.name, r["loud_med"]))
		if r["bands"][4] > 0.45:
			bad.append("%s harsh: %.0f %% of energy at 2.5-6 kHz" % (scene.name, r["bands"][4] * 100))
		if r["bands"][0] > 0.45:
			bad.append("%s boomy: %.0f %% of energy below 60 Hz" % (scene.name, r["bands"][0] * 100))
	for message in bad:
		print("PROBLEM:", message)
	print("preview WAVs in", args.out)
	sys.exit(1 if bad else 0)


if __name__ == "__main__":
	main()
