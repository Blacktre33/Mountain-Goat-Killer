"""Seamless stereo ambience beds: a shared wind bed plus one bed per biome.

All frequency-domain filtering is circular and every modulator uses a whole
number of cycles per loop, so the beds tile without a click or a level step.
"""
import numpy as np

from dsp import SR, bandpass, colored, decay_env, highpass, lowpass, n_of, resonate, rng_for, seam_fade, white

LOOP = 30.0


def _periodic_gust(rng, n, cycles, depth):
	"""Positive modulator in [1-depth, 1] built from whole-cycle sinusoids."""
	t = np.arange(n) / n
	m = np.zeros(n)
	for c in cycles:
		m += np.sin(2 * np.pi * (c * t + rng.uniform()))
	m = m / (np.max(np.abs(m)) + 1e-9)
	return 1.0 - depth * (0.5 - 0.5 * m)


def _wrap_place(buf, clip, at_sample, gain):
	n = len(buf)
	idx = (np.arange(len(clip)) + at_sample) % n
	np.add.at(buf, idx, clip * gain)


def _stereo(fn, name):
	"""Build left and right from independent noise so the bed has real width."""
	return np.stack([fn(rng_for(name + ":L")), fn(rng_for(name + ":R"))], axis=1)


def wind_bed(rng):
	n = n_of(LOOP)
	gust = _periodic_gust(rng, n, (2, 3, 5), 0.6)
	slow = _periodic_gust(rng, n, (1, 2, 4), 0.5)
	low = lowpass(colored(rng, n, 2.0), 260.0, 2) * gust * 1.6
	mid = bandpass(colored(rng, n, 1.0), 220.0, 1500.0, 2) * slow * 0.55
	whistle = (resonate(white(rng, n), 610.0 + 25.0, 28.0) * 0.5 + resonate(white(rng, n), 1180.0, 30.0) * 0.28) * (gust ** 3) * 0.6
	air = highpass(lowpass(white(rng, n), 5200.0, 2), 1800.0, 2) * (slow ** 2) * 0.12
	return low / (np.std(low) + 1e-9) * 0.6 + mid / (np.std(mid) + 1e-9) * 0.35 + whistle / (np.std(whistle) + 1e-9) * 0.16 + air / (np.std(air) + 1e-9) * 0.1


def widowpine_bed(rng):
	"""Frost pine: needle hiss in the gusts, a few snow ticks, hollow trunk knock."""
	n = n_of(LOOP)
	gust = _periodic_gust(rng, n, (3, 4, 7), 0.75)
	hiss = bandpass(colored(rng, n, 0.6), 1400.0, 4200.0, 2) * gust ** 2
	body = bandpass(colored(rng, n, 1.2), 200.0, 900.0, 2) * _periodic_gust(rng, n, (2, 3), 0.6)
	out = hiss / (np.std(hiss) + 1e-9) * 0.3 + body / (np.std(body) + 1e-9) * 0.28
	ticks = np.zeros(n)
	for i in range(70):
		fc = rng.uniform(2500.0, 7000.0)
		tick = bandpass(white(rng, n_of(0.02)), fc * 0.7, fc * 1.4, 1) * decay_env(n_of(0.02), 0.002, 0.0001)
		_wrap_place(ticks, tick, int(rng.uniform(0, n)), rng.uniform(0.05, 0.3))
	sub = lowpass(colored(rng, n, 2.0), 90.0, 2) * _periodic_gust(rng, n, (1, 3), 0.5)
	return out + ticks * 0.6 + sub / (np.std(sub) + 1e-9) * 0.2


def carrion_bed(rng):
	"""Red stone: dry rasping gusts, wind across old bone, a slow ritual sub throb."""
	n = n_of(LOOP)
	gust = _periodic_gust(rng, n, (2, 5, 6), 0.8)
	rasp = highpass(lowpass(colored(rng, n, 0.4), 6000.0, 2), 1100.0, 2) * gust ** 2
	out = rasp / (np.std(rasp) + 1e-9) * 0.42
	bone_am = _periodic_gust(rng, n, (3, 4), 0.85) ** 3
	bone = (resonate(white(rng, n), 468.0, 55.0) * 0.6 + resonate(white(rng, n), 936.0 * 1.006, 60.0) * 0.3 + resonate(white(rng, n), 1404.0, 70.0) * 0.12) * bone_am
	out += bone / (np.std(bone) + 1e-9) * 0.12
	t = np.arange(n) / SR
	throb = np.sin(2 * np.pi * 38.0 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.2 * t + 1.0)) ** 2
	out += throb * 0.16
	grit = np.zeros(n)
	for i in range(45):
		fc = rng.uniform(1500.0, 5000.0)
		g = bandpass(white(rng, n_of(0.03)), fc * 0.7, fc * 1.4, 1) * decay_env(n_of(0.03), 0.004, 0.0002)
		_wrap_place(grit, g, int(rng.uniform(0, n)), rng.uniform(0.06, 0.25))
	return out + grit * 0.5


def iron_crown_bed(rng):
	"""Ash and forge: embers crackling, a hot low roar, vibrating iron overtones."""
	n = n_of(LOOP)
	gust = _periodic_gust(rng, n, (2, 4, 5), 0.5)
	roar = lowpass(colored(rng, n, 1.6), 320.0, 2) * gust
	out = roar / (np.std(roar) + 1e-9) * 0.42
	ash = bandpass(colored(rng, n, 0.7), 500.0, 3200.0, 2) * _periodic_gust(rng, n, (3, 5), 0.7) ** 2
	out += ash / (np.std(ash) + 1e-9) * 0.14
	iron = (resonate(white(rng, n), 145.0, 60.0) * 0.6 + resonate(white(rng, n), 218.0 * 1.003, 70.0) * 0.4 + resonate(white(rng, n), 391.0, 80.0) * 0.2) * _periodic_gust(rng, n, (2, 3), 0.7)
	out += iron / (np.std(iron) + 1e-9) * 0.12
	crackle = np.zeros(n)
	for i in range(420):
		fc = rng.uniform(1600.0, 6200.0)
		length = n_of(rng.uniform(0.008, 0.03))
		pop = bandpass(white(rng, length), fc * 0.7, fc * 1.5, 1) * decay_env(length, rng.uniform(0.002, 0.006), 0.0002)
		_wrap_place(crackle, pop, int(rng.uniform(0, n)), rng.uniform(0.05, 0.5) ** 2 * 2.0)
	return out + crackle * 0.5


BEDS = {
	"wind": (wind_bed, -6.0),
	"amb_widowpine": (widowpine_bed, -10.0),
	"amb_carrion": (carrion_bed, -10.0),
	"amb_iron_crown": (iron_crown_bed, -10.0),
}


def render_all(out_dir):
	import os

	from dsp import finish
	from render import stats, write_ogg

	entries = {}
	for name, (fn, peak_db) in BEDS.items():
		x = _stereo(lambda rng, fn=fn: fn(rng), name)
		# Fix the level with a single gain: finish() would trim/fade and break the loop.
		x = x - x.mean(axis=0, keepdims=True)
		x = seam_fade(x * (10.0 ** (peak_db / 20.0) / np.max(np.abs(x))))
		write_ogg(os.path.join(out_dir, name + ".ogg"), x)
		peak, rms = stats(x)
		entries[name] = {"files": [name + ".ogg"], "bus": "ambience", "fmt": "ogg", "loop": True, "target_peak_db": peak_db,
			"clips": [{"peak": peak, "rms": rms, "seconds": len(x) / SR}]}
		print("%-20s bed loop %.1fs peak %.1f dB rms %.1f dB" % (name, len(x) / SR, 20 * np.log10(peak), 20 * np.log10(rms)))
	return entries
