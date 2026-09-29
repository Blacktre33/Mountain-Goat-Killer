"""Warpack wolverines and Varkas: source-filter voices, footfalls and armour."""
import numpy as np

from dsp import (SR, sum_clips, ad, bandpass, colored, decay_env, glide_phase, highpass, lowpass, n_of, partials, place, resonate,
                 reverb_stereo, saturate, sine, smooth_random, swell, sweep_lowpass, voiced, white)
from sfx_weapons import _exp_sweep, _metal_hit, _rattle, _thunk

# Vocal-tract formant sets (Fc, bandwidth, gain) for a large predator's throat.
F_UH = [(480.0, 220.0, 1.0), (1050.0, 340.0, 0.6), (2450.0, 600.0, 0.22), (3700.0, 900.0, 0.08)]
F_AW = [(620.0, 240.0, 1.0), (920.0, 300.0, 0.7), (2500.0, 600.0, 0.18), (3700.0, 900.0, 0.07)]
F_OO = [(330.0, 160.0, 1.0), (760.0, 220.0, 0.55), (2300.0, 500.0, 0.10), (3500.0, 800.0, 0.04)]
F_EE = [(420.0, 200.0, 0.9), (2000.0, 380.0, 0.8), (2900.0, 500.0, 0.3), (3900.0, 800.0, 0.1)]
F_AH = [(760.0, 200.0, 1.0), (1250.0, 260.0, 0.75), (2600.0, 500.0, 0.25), (3700.0, 800.0, 0.08)]


def _norm(x):
	return x / (np.max(np.abs(x)) + 1e-12)


def _jitter(rng, n, depth=0.02, rate=9.0):
	return 1.0 + smooth_random(rng, n, rate, depth) + smooth_random(rng, n, 60.0, depth * 0.35)


def growl(rng, v):
	dur = (1.05, 1.5, 0.75)[v % 3]
	n = n_of(dur)
	t = np.arange(n) / SR
	base = (68.0, 60.0, 82.0)[v % 3]
	f0 = base * _jitter(rng, n, 0.035) * (1.0 + 0.12 * smooth_random(rng, n, 1.7, 1.0))
	src = voiced(f0, F_UH, n, harm_slope=0.85, breath=0.55, rng=rng, formants_end=F_AW, pulsatile=0.55)
	rattle_hz = 26.0 + 5.0 * smooth_random(rng, n, 2.0, 1.0)
	am = 0.62 + 0.38 * np.sin(np.cumsum(2 * np.pi * rattle_hz / SR))
	env = swell(n, 0.09, 0.28 + 0.1 * v) * (0.85 + 0.15 * smooth_random(rng, n, 3.0, 1.0))
	chest = lowpass(white(rng, n), 130.0, 2)
	chest = _norm(chest) * am * 0.35
	out = (src * am * 0.9 + chest) * env
	out = saturate(out, 1.7)
	return highpass(lowpass(out, 5200.0, 2), 45.0, 2)


def snarl(rng, v):
	n = n_of(0.62 + 0.08 * v)
	f0 = np.linspace(125.0, 185.0, n) * _jitter(rng, n, 0.05, 14.0) * (1.0 + 0.05 * v)
	src = voiced(f0, F_AH, n, harm_slope=0.7, breath=1.1, rng=rng, formants_end=F_UH, pulsatile=0.35)
	am = 0.55 + 0.45 * np.sin(np.cumsum(2 * np.pi * (38.0 + 6.0 * smooth_random(rng, n, 3.0, 1.0)) / SR))
	env = swell(n, 0.03, 0.2)
	hiss = highpass(white(rng, n), 3800.0, 2) * ad(n, 0.005, 0.07) * 0.3
	out = saturate(src * am * env, 1.9) + hiss
	return lowpass(out, 6500.0, 2)


def growl_windup(rng, v):
	"""Rising warning growl that ends in a sharp intake, so the bite has a tell."""
	n = n_of(0.95)
	t = np.arange(n) / SR
	f0 = np.linspace(56.0, 96.0, n) * _jitter(rng, n, 0.03)
	src = voiced(f0, F_UH, n, harm_slope=0.85, breath=0.6, rng=rng, formants_end=F_AH, pulsatile=0.6)
	am = 0.6 + 0.4 * np.sin(np.cumsum(2 * np.pi * np.linspace(20.0, 34.0, n) / SR))
	env = np.minimum(1.0, t / 0.55) ** 1.4 * (1.0 - np.clip((t - 0.78) / 0.10, 0, 1))
	body = saturate(src * am * env, 1.8)
	intake = highpass(lowpass(colored(rng, n_of(0.14), 0.3), 4500.0, 2), 800.0, 2) * np.hanning(n_of(0.14)) * 0.35
	out = body
	place(out, intake, 0.80, 1.0)
	return lowpass(out, 5200.0, 2)


def howl(rng, v):
	dur = 2.7
	n = n_of(dur)
	t = np.arange(n) / SR
	scale = (1.0, 0.88, 1.13)[v % 3]
	rise = 1.0 - np.exp(-t / 0.22)
	contour = 300.0 + 270.0 * rise + 60.0 * np.clip((t - 0.5) / 0.9, 0, 1) - 240.0 * np.clip((t - 1.55) / 1.0, 0, 1) ** 1.2
	vib_depth = 0.008 + 0.03 * np.clip((t - 0.4) / 0.8, 0, 1)
	vib = vib_depth * np.sin(2 * np.pi * (4.8 + 0.8 * t) * t)
	f0 = contour * scale * (1.0 + vib) * _jitter(rng, n, 0.004, 6.0)
	# Voice-break: a brief upward crack near the end of the note.
	f0 = f0 * (1.0 + 0.06 * np.exp(-((t - 1.62) / 0.03) ** 2))
	forms_a = [(520.0, 160.0, 1.0), (1000.0, 220.0, 0.55), (2400.0, 400.0, 0.10), (3400.0, 700.0, 0.04)]
	forms_b = [(700.0, 180.0, 1.0), (1150.0, 240.0, 0.6), (2500.0, 400.0, 0.12), (3500.0, 700.0, 0.05)]
	v1 = voiced(f0, forms_a, n, harm_slope=0.95, breath=0.16, rng=rng, formants_end=forms_b)
	v2 = voiced(f0 * 1.006, forms_a, n, harm_slope=0.95, breath=0.1, rng=rng, formants_end=forms_b)
	out = (v1 * 0.7 + v2 * 0.45) * swell(n, 0.30, 0.85) * (0.9 + 0.1 * np.sin(2 * np.pi * 0.9 * t))
	out = saturate(out, 1.25)
	return lowpass(out, 6000.0, 2)


def yelp(rng, v):
	n = n_of(0.5)
	t = np.arange(n) / SR
	f0 = np.where(t < 0.2, 1150.0 - 1500.0 * t, 850.0 - 900.0 * (t - 0.2) + 90.0 * np.sin(2 * np.pi * 22.0 * t))
	f0 = np.maximum(f0, 300.0) * (1.0 + 0.02 * v) * _jitter(rng, n, 0.01, 12.0)
	forms = [(900.0, 250.0, 1.0), (2200.0, 400.0, 0.7), (3300.0, 600.0, 0.2)]
	src = voiced(f0, forms, n, harm_slope=0.9, breath=0.3, rng=rng)
	env = swell(n, 0.008, 0.18) * (1.0 - 0.5 * (np.abs(t - 0.22) < 0.02))
	return lowpass(src * env, 7000.0, 2)


def death(rng, v):
	dur = 1.8
	n = n_of(dur)
	t = np.arange(n) / SR
	f0 = 820.0 * np.exp(-t / 0.55) + 190.0
	f0 = f0 * (1.0 + 0.05 * np.sin(2 * np.pi * 7.5 * t)) * _jitter(rng, n, 0.012, 10.0)
	forms = [(760.0, 220.0, 1.0), (1500.0, 320.0, 0.6), (2600.0, 500.0, 0.2)]
	whine = voiced(f0, forms, n, harm_slope=1.0, breath=0.4, rng=rng, formants_end=[(500.0, 220.0, 1.0), (1000.0, 300.0, 0.5), (2200.0, 500.0, 0.1)])
	env = swell(n, 0.012, 0.9) * np.exp(-t / 1.0)
	m = n_of(0.5)
	rattle = _rattle(rng, 0.5, 250.0, 1400.0, 30.0, 0.0) * np.hanning(m) * 0.5
	out = whine * env
	place(out, rattle, 1.0, 0.5 * 1.0)
	exhale = lowpass(colored(rng, n_of(0.6), 0.6), 1400.0, 2) * np.hanning(n_of(0.6)) * 0.25
	place(out, exhale, 1.15, 1.0)
	return out


def huff(rng, v):
	n = n_of(0.5)
	body = bandpass(colored(rng, n, 0.4), 200.0 + 40 * v, 3200.0, 2)
	env = np.hanning(n) ** 1.6
	env = env * (1.0 + 0.4 * np.exp(-((np.arange(n) / SR - 0.07) / 0.03) ** 2))
	snort = lowpass(white(rng, n_of(0.1)), 900.0, 2) * np.hanning(n_of(0.1)) * 0.5
	out = body * env
	place(out, snort, 0.0, 1.0)
	return out


def wolf_breath(rng, v):
	"""Slow inhale then exhale, for an idle pack animal within earshot."""
	n = n_of(1.7)
	t = np.arange(n) / SR
	inhale = bandpass(colored(rng, n, 0.5), 400.0, 3800.0) * np.exp(-((t - 0.35) / 0.2) ** 2) * 0.5
	exhale = bandpass(colored(rng, n, 0.5), 200.0, 2600.0) * np.exp(-((t - 1.0) / 0.28) ** 2)
	rasp = resonate(colored(rng, n, 0.3), 260.0 + 20 * v, 1.2) * np.exp(-((t - 1.0) / 0.3) ** 2) * 0.3
	return inhale + exhale + rasp


def bite(rng, v):
	n = n_of(0.55)
	snap = bandpass(white(rng, n), 1500.0, 7500.0) * decay_env(n, 0.007, 0.0003)
	chomp = _thunk(rng, 150.0, 0.3, 0.05, 0.6)
	teeth = partials([2600.0, 4100.0], [0.25, 0.15], [0.02, 0.012], n, rng)
	wet = bandpass(white(rng, n), 300.0, 1600.0) * decay_env(n, 0.06, 0.004) * 0.5
	out = snap * 0.8 + sum_clips(chomp, np.zeros(n)) * 1.0 + teeth * 0.3 + wet
	huff_ = bandpass(colored(rng, n_of(0.25), 0.4), 250.0, 2400.0) * np.hanning(n_of(0.25)) * 0.35
	place(out, huff_, 0.06, 1.0)
	return out


def wolf_footstep(rng, v, heavy=False):
	dur = 0.34 if heavy else 0.24
	n = n_of(dur)
	grains = np.zeros(n)
	count = int(rng.integers(18, 28)) if heavy else int(rng.integers(14, 22))
	span = 0.09 if heavy else 0.06
	for i in range(count):
		at = rng.uniform(0.0, span)
		fc = rng.uniform(900.0, 3200.0)
		g = bandpass(white(rng, n_of(0.006)), fc * 0.7, fc * 1.4, 1) * decay_env(n_of(0.006), 0.0012, 0.0002)
		place(grains, g, at, rng.uniform(0.25, 1.0) * (1.0 - at / span * 0.6))
	thump_hz = 50.0 if heavy else 82.0
	f = _exp_sweep(thump_hz * 1.7, thump_hz, n, 0.02)
	thump = np.sin(glide_phase(f)) * decay_env(n, 0.05 if heavy else 0.03, 0.002)
	pad = lowpass(white(rng, n), 700.0, 2) * decay_env(n, 0.03, 0.002)
	out = grains * (1.0 if heavy else 1.3) + thump * (0.9 if heavy else 0.5) + pad * (0.5 if heavy else 0.4)
	return out


def wolf_footstep_heavy(rng, v):
	return wolf_footstep(rng, v, True)


def armor_clink(rng, v):
	dur = 0.55
	out = np.zeros(n_of(dur))
	taps = int(rng.integers(3, 6))
	for i in range(taps):
		f0 = rng.uniform(1100.0, 3300.0)
		clip = partials([f0, f0 * 2.7, f0 * 4.9], [0.5, 0.3, 0.15], [0.05, 0.03, 0.02], n_of(0.3), rng)
		clip += bandpass(white(rng, n_of(0.3)), 1800.0, 6000.0) * decay_env(n_of(0.3), 0.003, 0.0001) * 0.4
		clip = lowpass(clip, 6500.0, 2)
		place(out, clip, i * rng.uniform(0.035, 0.09) + rng.uniform(0.0, 0.02), rng.uniform(0.25, 0.7))
	return out


def armor_break(rng, v):
	dur = 2.2
	n = n_of(dur)
	out = np.zeros(n)
	tear = _rattle(rng, 0.7, 500.0, 6000.0, 45.0, 0.05) * np.hanning(n_of(0.7)) ** 0.5
	place(out, saturate(tear, 2.0) * 0.5, 0.0, 1.0)
	for i, (at, f0, g) in enumerate(((0.05, 470.0, 1.0), (0.22, 690.0, 0.8), (0.4, 380.0, 0.9), (0.62, 910.0, 0.5))):
		clang = partials([f0, f0 * 1.43, f0 * 2.31, f0 * 3.37, f0 * 4.73], [0.6, 0.5, 0.35, 0.25, 0.15], [0.42, 0.3, 0.2, 0.13, 0.09], n_of(1.4), rng, detune=1.7)
		clang += bandpass(white(rng, n_of(1.4)), 1200.0, 8000.0) * decay_env(n_of(1.4), 0.008, 0.0002) * 0.5
		place(out, clang, at, g)
	place(out, _thunk(rng, 44.0, 1.2, 0.3, 0.3) * 1.3, 0.05, 1.0)
	for i in range(14):
		at = 0.7 + i * 0.05 * (1.0 + i * 0.12) + rng.uniform(0, 0.04)
		f0 = rng.uniform(900.0, 4200.0)
		bit = partials([f0, f0 * 2.4], [0.4, 0.2], [0.05, 0.03], n_of(0.15), rng)
		place(out, bit, at, rng.uniform(0.1, 0.35) * (1.0 - i / 18.0))
	return out


def roar(rng, v):
	"""Varkas' roar: three detuned throat voices, a sub layer, tearing breath."""
	dur = 2.6
	n = n_of(dur)
	t = np.arange(n) / SR
	contour = 62.0 + 40.0 * (1 - np.exp(-t / 0.18)) - 32.0 * np.clip((t - 1.4) / 1.2, 0, 1) ** 1.3
	contour = contour * (1.0 + 0.01 * np.sin(2 * np.pi * 5.5 * t)) * _jitter(rng, n, 0.03, 8.0)
	forms_a = [(600.0, 260.0, 1.0), (1000.0, 340.0, 0.7), (2500.0, 600.0, 0.25), (3600.0, 900.0, 0.12)]
	forms_b = [(760.0, 280.0, 1.0), (1150.0, 340.0, 0.75), (2600.0, 600.0, 0.28), (3700.0, 900.0, 0.12)]
	layers = np.zeros(n)
	for k, (ratio, gain) in enumerate(((1.0, 1.0), (1.012, 0.8), (0.5, 0.45))):
		layers += gain * voiced(contour * ratio * (1 + 0.004 * k), forms_a, n, harm_slope=0.8, breath=0.5, rng=rng, formants_end=forms_b, pulsatile=0.4)
	rasp = highpass(lowpass(white(rng, n), 4500.0, 2), 600.0, 2) * (0.5 + 0.5 * np.sin(np.cumsum(2 * np.pi * 45.0 / SR))) * 0.35
	sub = np.sin(glide_phase(contour * 0.5)) * 0.6
	env = swell(n, 0.16, 1.0)
	out = saturate((_norm(layers) + rasp + sub) * env, 2.6)
	out = lowpass(out, 5600.0, 2)
	l, r = reverb_stereo(out, 0.3, "roar", 2.4, rt_low=2.2, rt_high=0.7)
	return np.stack([l, r], axis=1)


def charge_rumble(rng, v):
	dur = 2.3
	n = n_of(dur)
	t = np.arange(n) / SR
	rumble = lowpass(colored(rng, n, 1.6), 140.0, 2) * (0.5 + 0.5 * t / dur)
	gallop = np.zeros(n)
	at = 0.0
	gap = 0.36
	while at < dur - 0.2:
		hoof = _thunk(rng, 58.0 + rng.uniform(-4, 4), 0.35, 0.06, 0.6) + bandpass(white(rng, n_of(0.35)), 300.0, 2600.0) * decay_env(n_of(0.35), 0.02, 0.001) * 0.5
		place(gallop, hoof, at, 0.55 + 0.45 * at / dur)
		place(gallop, hoof, at + 0.09, 0.4 + 0.4 * at / dur)
		at += gap
		gap = max(0.17, gap * 0.87)
	debris = highpass(lowpass(colored(rng, n, 0.8), 2200.0, 2), 300.0, 2) * (t / dur) ** 2 * 0.18
	out = rumble * 1.4 + gallop + debris
	return out * swell(n, 0.25, 0.25)


def quake(rng, v):
	dur = 3.4
	n = n_of(dur)
	t = np.arange(n) / SR
	f = _exp_sweep(78.0, 27.0, n, 0.5)
	boom = np.sin(glide_phase(f)) * decay_env(n, 0.85, 0.004)
	boom += np.sin(glide_phase(f * 1.98)) * decay_env(n, 0.35, 0.004) * 0.35
	rumble = lowpass(colored(rng, n, 1.5), 150.0, 2) * decay_env(n, 1.4, 0.03) * 1.2
	crack = highpass(white(rng, n), 1200.0, 2) * decay_env(n, 0.012, 0.0004) * 0.5
	debris = np.zeros(n)
	for i in range(28):
		at = rng.uniform(0.05, 2.4)
		f0 = rng.uniform(400.0, 3200.0)
		g = bandpass(white(rng, n_of(0.12)), f0 * 0.6, f0 * 1.5, 1) * decay_env(n_of(0.12), 0.02, 0.001)
		place(debris, g, at, rng.uniform(0.08, 0.3) * np.exp(-at / 1.6))
	ring = partials([392.0, 587.0, 940.0], [0.12, 0.08, 0.05], [1.4, 1.0, 0.7], n, rng, detune=0.8)
	out = boom * 1.0 + rumble + crack + debris * 1.4 + ring
	l, r = reverb_stereo(out, 0.25, "quake", 2.6, rt_low=2.4, rt_high=0.6)
	return np.stack([l, r], axis=1)
