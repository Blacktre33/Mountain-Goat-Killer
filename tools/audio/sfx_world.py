"""Bells, Remembrance, pickups, interface and scattered ambient one-shots."""
import numpy as np

from dsp import (SR, sum_clips, ad, bandpass, canyon_ir, colored, convolve, decay_env, glide_phase, highpass, lowpass, n_of,
                 partials, place, resonate, reverb_stereo, saturate, sine, smooth_random, swell, sweep_lowpass, voiced, white)
from sfx_creatures import F_AH, F_OO, _jitter, _norm
from sfx_weapons import _exp_sweep, _metal_hit, _rattle, _thunk

# Church-bell partial ratios relative to the prime (hum, prime, tierce, quint,
# nominal, deciem, undeciem, ...). The minor-third tierce is what makes a big
# bronze bell sound grave; the slightly sharp upper partials make it inharmonic.
BELL_RATIOS = [0.5, 1.0, 1.183, 1.506, 2.0, 2.514, 2.662, 3.011, 4.166, 5.433, 6.796, 8.1, 9.7, 11.5, 13.6, 15.8]
BELL_AMPS = [0.6, 1.0, 0.72, 0.6, 0.85, 0.42, 0.36, 0.3, 0.22, 0.16, 0.12, 0.09, 0.07, 0.05, 0.04, 0.03]
BELL_DECAYS = [1.0, 0.85, 0.62, 0.55, 0.46, 0.34, 0.3, 0.24, 0.16, 0.10, 0.07, 0.05, 0.04, 0.03, 0.025, 0.02]


def bell_body(rng, prime_hz, decay_scale, dur, shimmer=0.35, channels=2):
	"""Large bell: beating partial pairs so the tone slowly breathes, with the
	twin phases differing per channel to shimmer across the stereo field."""
	n = n_of(dur)
	t = np.arange(n) / SR
	outs = []
	for ch in range(channels):
		sig = np.zeros(n)
		for k, (r, a, d) in enumerate(zip(BELL_RATIOS, BELL_AMPS, BELL_DECAYS)):
			f = prime_hz * r * (1.0 + rng.uniform(-0.0015, 0.0015))
			beat = shimmer * (0.25 + 0.5 * ((k * 7) % 5) / 5.0) * (1 if ch == 0 else -1)
			ph = rng.uniform(0, 2 * np.pi)
			tau = d * decay_scale
			sig += a * np.sin(2 * np.pi * f * t + ph) * np.exp(-t / tau) * 0.6
			sig += a * np.sin(2 * np.pi * (f + beat) * t + ph * 1.3) * np.exp(-t / (tau * 1.05)) * 0.6
		outs.append(sig)
	return np.stack(outs, axis=1) if channels == 2 else outs[0]


def _clapper(rng, n, level=1.0):
	strike = bandpass(white(rng, n), 250.0, 3200.0, 2) * decay_env(n, 0.012, 0.0004)
	knock = _thunk(rng, 95.0, n / SR, 0.05, 0.2)
	return (strike * 0.9 + knock * 0.7) * level


def mother_bell(rng, v):
	dur = 14.0
	body = bell_body(rng, 130.8, 12.0, dur, shimmer=0.4)
	n = len(body)
	body *= np.minimum(1.0, np.arange(n) / SR / 0.004)[:, None]
	body += _clapper(rng, n, 1.3)[:, None] * 0.6
	l, r = reverb_stereo(body[:, 0], 0.4, "mother_bell_l", 3.6, rt_low=3.2, rt_high=0.9)
	l2, r2 = reverb_stereo(body[:, 1], 0.4, "mother_bell_r", 3.6, rt_low=3.2, rt_high=0.9)
	return np.stack([(l + r2) * 0.5, (r + l2) * 0.5], axis=1)


def bell_toll(rng, v):
	"""Distant toll for the abbey and the shrine: shorter, warmer, filtered."""
	body = bell_body(rng, 165.0 * (1.0, 1.12, 0.94)[v % 3], 5.0, 7.0, shimmer=0.3)
	n = len(body)
	body *= np.minimum(1.0, np.arange(n) / SR / 0.006)[:, None]
	body += _clapper(rng, n, 0.9)[:, None] * 0.4
	return np.stack([lowpass(body[:, 0], 3000.0, 2), lowpass(body[:, 1], 3000.0, 2)], axis=1)


def _handbell(rng, f0, dur, tau_scale=1.0):
	n = n_of(dur)
	ratios = [1.0, 2.32, 3.94, 5.7, 7.9]
	amps = [1.0, 0.55, 0.35, 0.22, 0.12]
	taus = [0.9, 0.6, 0.4, 0.28, 0.18]
	sig = partials([f0 * r for r in ratios], amps, [t * tau_scale for t in taus], n, rng, detune=1.1)
	strike = highpass(white(rng, n), 2500.0, 2) * decay_env(n, 0.004, 0.0002) * 0.3
	return sig + strike


def chime(rng, v):
	f0 = (1174.7, 1318.5, 987.8)[v % 3]
	return _handbell(rng, f0, 1.8)


def bell_pickup(rng, v):
	"""A stolen neck-bell freed from its strap: clapper knocks then a dented ring."""
	f0 = (740.0, 830.0, 660.0)[v % 3]
	n = n_of(2.4)
	out = np.zeros(n)
	for i, at in enumerate((0.0, 0.11, 0.19, 0.34)):
		clack = _metal_hit(rng, [f0 * 1.9, f0 * 3.1], [0.35, 0.25], [0.03, 0.02], 0.18, 0.004, 0.5)
		place(out, clack, at, 0.7 - 0.12 * i)
	ring = partials([f0, f0 * 2.05, f0 * 3.3, f0 * 4.8], [1.0, 0.5, 0.3, 0.15], [0.8, 0.5, 0.3, 0.15], n_of(2.2), rng, detune=1.4)
	place(out, ring, 0.05, 0.85)
	leather = bandpass(colored(rng, n_of(0.3), 1.0), 300.0, 2200.0) * np.hanning(n_of(0.3)) * 0.2
	place(out, leather, 0.0, 1.0)
	l, r = reverb_stereo(out, 0.3, "bell_pickup", 2.0, rt_low=1.8, rt_high=0.6)
	return np.stack([l, r], axis=1)


def pickup(rng, v):
	n = n_of(0.8)
	rustle = _rattle(rng, 0.22, 400.0, 3400.0, 55.0, 0.05) * np.hanning(n_of(0.22))
	chime_ = _handbell(rng, 1568.0, 0.6, 0.4) * 0.45
	out = np.zeros(n)
	place(out, rustle, 0.0, 0.5)
	place(out, chime_, 0.09, 1.0)
	return out


def ammo_pickup(rng, v):
	n = n_of(0.75)
	out = np.zeros(n)
	place(out, _rattle(rng, 0.2, 350.0, 2800.0, 45.0, 0.05) * np.hanning(n_of(0.2)), 0.0, 0.45)
	for i in range(5):
		f0 = rng.uniform(2100.0, 3300.0)
		tick = partials([f0, f0 * 1.6, f0 * 0.55], [0.4, 0.2, 0.3], [0.03, 0.02, 0.05], n_of(0.2), rng)
		place(out, tick, 0.05 + i * rng.uniform(0.035, 0.06), rng.uniform(0.2, 0.55))
	place(out, _thunk(rng, 140.0, 0.15, 0.03, 0.5), 0.02, 0.35)
	return out


def ui_click(rng, v):
	n = n_of(0.08)
	tick = bandpass(white(rng, n), 1500.0, 6000.0) * decay_env(n, 0.004, 0.0002)
	tone = sine(1100.0 + 60 * v, n) * decay_env(n, 0.012, 0.0006) * 0.5
	return tick * 0.55 + tone


def ui_hover(rng, v):
	n = n_of(0.05)
	return sine(1900.0, n) * decay_env(n, 0.01, 0.002) * 0.35 + bandpass(white(rng, n), 3000.0, 9000.0) * decay_env(n, 0.003, 0.0003) * 0.15


def ui_confirm(rng, v):
	n = n_of(0.5)
	a = _handbell(rng, 880.0, 0.5, 0.3) * 0.6
	out = np.zeros(n)
	place(out, a, 0.0, 1.0)
	place(out, _handbell(rng, 1318.5, 0.42, 0.3) * 0.6, 0.075, 1.0)
	return out


def ui_back(rng, v):
	n = n_of(0.16)
	f = _exp_sweep(900.0, 500.0, n, 0.04)
	return np.sin(glide_phase(f)) * decay_env(n, 0.03, 0.001) * 0.6 + bandpass(white(rng, n), 800.0, 3500.0) * decay_env(n, 0.006, 0.0003) * 0.3


def pause_in(rng, v):
	n = n_of(0.9)
	t = np.arange(n) / SR
	sweep = sweep_lowpass(colored(rng, n, 0.9), 4000.0 * np.exp(-t / 0.22) + 200.0) * decay_env(n, 0.25, 0.02)
	thunk = _thunk(rng, 70.0, 0.4, 0.09, 0.4)
	out = sweep * 0.8
	place(out, thunk, 0.0, 0.9)
	return out


def pause_out(rng, v):
	n = n_of(0.7)
	t = np.arange(n) / SR
	sweep = sweep_lowpass(colored(rng, n, 0.9), 250.0 + 4200.0 * np.minimum(1.0, t / 0.3)) * np.exp(-((t - 0.28) / 0.22) ** 2)
	return sum_clips(sweep * 0.8, _thunk(rng, 90.0, 0.25, 0.05, 0.3) * 0.5)


# --- Remembrance: eerie choral bells -----------------------------------------------

def _choir(rng, f0s, dur, formants, breath=0.25, vib_hz=5.2, vib_depth=0.01):
	n = n_of(dur)
	t = np.arange(n) / SR
	out = np.zeros(n)
	for k, f0 in enumerate(f0s):
		vib = 1.0 + vib_depth * np.sin(2 * np.pi * (vib_hz + 0.4 * k) * t + k * 1.7)
		curve = f0 * vib * (1.0 + 0.003 * (k - len(f0s) / 2.0)) * _jitter(rng, n, 0.003, 5.0)
		out += voiced(curve, formants, n, harm_slope=1.6, breath=breath, rng=rng)
	return _norm(out)


def hang(rng, v):
	n = n_of(2.2)
	t = np.arange(n) / SR
	pad = _choir(rng, [392.0 * 0.5, 588.0 * 0.5, 784.0 * 0.5], 2.2, F_OO, 0.3) * swell(n, 0.5, 1.2) * 0.5
	glass = _handbell(rng, 784.0, 2.2, 1.4)
	out = pad + glass * 0.6
	l, r = reverb_stereo(out, 0.45, "hang", 2.4, rt_low=2.2, rt_high=0.9)
	return np.stack([l, r], axis=1)


def sense(rng, v):
	n = n_of(0.6)
	ping = partials([1480.0, 3550.0, 6070.0], [0.6, 0.3, 0.15], [0.16, 0.09, 0.05], n, rng, detune=0.9)
	breath = _choir(rng, [740.0], 0.6, F_AH, 0.4) * swell(n, 0.05, 0.4) * 0.12
	l, r = reverb_stereo(ping + breath, 0.4, "sense", 1.8, rt_low=1.6, rt_high=0.6)
	return np.stack([l, r], axis=1)


def converge(rng, v):
	dur = 1.1
	n = n_of(dur)
	t = np.arange(n) / SR
	u = np.clip(t / 0.9, 0, 1)
	sig = np.zeros(n)
	for spread, gain in ((-1.0, 1.0), (1.0, 1.0), (0.0, 0.8)):
		f = (330.0 * 2.0 ** (u * 1.0)) * 2.0 ** (spread * (1.0 - u) * 0.35)
		curve = f * (1.0 + 0.008 * np.sin(2 * np.pi * 5.5 * t))
		sig += gain * voiced(curve, F_AH, n, harm_slope=1.4, breath=0.2, rng=rng)
	sig = _norm(sig) * (u ** 1.5) * (1.0 - np.clip((t - 0.9) / 0.2, 0, 1))
	strike = np.zeros(n)
	place(strike, _handbell(rng, 1320.0, 0.5, 1.2), 0.86, 0.9)
	out = sig * 0.5 + strike
	l, r = reverb_stereo(out, 0.35, "converge", 1.8, rt_low=1.8, rt_high=0.7)
	return np.stack([l, r], axis=1)


def volley(rng, v):
	dur = 2.6
	n = n_of(dur)
	t = np.arange(n) / SR
	boom = np.sin(glide_phase(_exp_sweep(90.0, 32.0, n, 0.25))) * decay_env(n, 0.5, 0.004)
	rush = sweep_lowpass(colored(rng, n, 0.8), 400.0 + 3800.0 * np.exp(-((t - 0.25) / 0.2) ** 2)) * np.exp(-((t - 0.25) / 0.35) ** 2) * 0.7
	crack = highpass(white(rng, n), 1500.0, 2) * decay_env(n, 0.006, 0.0003) * 0.5
	choir = _choir(rng, [196.0, 294.0, 392.0, 588.0], dur, F_AH, 0.3) * swell(n, 0.35, 1.5) * 0.5
	bells = np.zeros(n)
	for i, f0 in enumerate((523.3, 659.3, 784.0, 987.8, 1174.7)):
		place(bells, _handbell(rng, f0, 1.8, 1.5), 0.05 + i * 0.045, 0.5 - i * 0.04)
	out = boom * 1.2 + rush + crack + choir + bells
	l, r = reverb_stereo(out, 0.4, "volley", 2.8, rt_low=2.6, rt_high=0.8)
	return np.stack([l, r], axis=1)


def sting(rng, v):
	dur = 4.2
	n = n_of(dur)
	t = np.arange(n) / SR
	drone = (sine(73.4, n) * 0.6 + sine(110.0, n) * 0.35 + sine(146.8, n) * 0.15) * swell(n, 0.8, 2.2)
	choir = _choir(rng, [146.8, 220.0, 293.7], dur, F_OO, 0.3) * swell(n, 0.9, 2.4) * 0.5
	bell = bell_body(rng, 293.7, 1.3, dur, 0.3, 1)
	bell = bell * np.minimum(1.0, t / 0.006) * 0.6
	bellp = np.zeros(n)
	place(bellp, bell, 0.25, 1.0)
	out = drone * 0.5 + choir + bellp
	l, r = reverb_stereo(out, 0.4, "sting", 2.6, rt_low=2.4, rt_high=0.8)
	return np.stack([l, r], axis=1)


# --- Scattered ambient one-shots -------------------------------------------------------

def amb_creak_pine(rng, v):
	"""A frozen trunk flexing in the wind: slow stick-slip groan."""
	dur = 2.2 + 0.3 * v
	n = n_of(dur)
	t = np.arange(n) / SR
	f0 = 78.0 + 30.0 * smooth_random(rng, n, 1.2, 1.0) + 25.0 * np.sin(2 * np.pi * 0.45 * t)
	src = voiced(np.maximum(f0, 40.0), [(210.0, 80.0, 1.0), (460.0, 120.0, 0.7), (980.0, 200.0, 0.3), (1900.0, 300.0, 0.1)], n, harm_slope=0.9, breath=0.3, rng=rng, pulsatile=0.7)
	stick = 0.35 + 0.65 * np.abs(lowpass(white(rng, n), 9.0, 1)) / 0.12
	env = swell(n, 0.5, 0.8)
	return src * np.clip(stick, 0.0, 1.5) * env


def amb_bell_far(rng, v):
	"""Faraway bell across the ravine: low-passed and drowned in the canyon."""
	f0 = (196.0, 174.6, 233.1)[v % 3]
	body = bell_body(rng, f0, 4.5, 6.0, 0.25, 1) * np.minimum(1.0, t_env(6.0) / 0.01)
	body = lowpass(body, 1800.0, 2)
	l, r = reverb_stereo(body, 0.7, "amb_bell_far%d" % v, 3.0, rt_low=3.0, rt_high=0.6)
	return np.stack([l, r], axis=1) * 0.6


def t_env(dur):
	return np.arange(n_of(dur)) / SR


def amb_ember(rng, v):
	n = n_of(1.0)
	out = np.zeros(n)
	for i in range(int(rng.integers(4, 9))):
		at = rng.uniform(0.0, 0.8)
		f0 = rng.uniform(1800.0, 5200.0)
		pop = bandpass(white(rng, n_of(0.03)), f0 * 0.7, f0 * 1.5, 1) * decay_env(n_of(0.03), 0.004, 0.0002)
		place(out, pop, at, rng.uniform(0.2, 1.0))
	hiss = lowpass(white(rng, n), 3000.0, 2) * decay_env(n, 0.25, 0.01) * 0.07
	return out + hiss


def amb_rope(rng, v):
	n = n_of(1.0)
	t = np.arange(n) / SR
	f = 240.0 + 110.0 * np.sin(2 * np.pi * 1.6 * t) + 40.0 * smooth_random(rng, n, 6.0, 1.0)
	src = voiced(f, [(600.0, 160.0, 1.0), (1500.0, 300.0, 0.6), (2800.0, 400.0, 0.2)], n, harm_slope=0.8, breath=0.5, rng=rng, pulsatile=0.8)
	return src * swell(n, 0.15, 0.5) * (0.4 + 0.6 * np.abs(lowpass(white(rng, n), 14.0, 1)) / 0.14).clip(0, 1.4)


def amb_cage(rng, v):
	n = n_of(1.6)
	t = np.arange(n) / SR
	f = 640.0 + 180.0 * np.sin(2 * np.pi * 1.1 * t + v)
	squeal = np.sin(glide_phase(f)) * 0.5 + np.sin(glide_phase(f * 2.71)) * 0.25
	squeal *= swell(n, 0.25, 0.7) * (0.5 + 0.5 * np.abs(lowpass(white(rng, n), 18.0, 1)) / 0.18).clip(0, 1.4)
	out = squeal
	for i in range(3):
		f0 = rng.uniform(500.0, 1500.0)
		place(out, partials([f0, f0 * 2.3], [0.4, 0.25], [0.1, 0.06], n_of(0.5), rng), rng.uniform(0.0, 1.2), 0.3)
	return out


def amb_chain(rng, v):
	n = n_of(1.1)
	out = np.zeros(n)
	for i in range(int(rng.integers(6, 11))):
		f0 = rng.uniform(900.0, 2600.0)
		link = partials([f0, f0 * 2.4, f0 * 3.7], [0.5, 0.3, 0.2], [0.05, 0.03, 0.02], n_of(0.25), rng) + bandpass(white(rng, n_of(0.25)), 2500.0, 9000.0) * decay_env(n_of(0.25), 0.003, 0.0001) * 0.35
		place(out, link, i * rng.uniform(0.04, 0.11), rng.uniform(0.2, 0.7))
	return out


def amb_snow(rng, v):
	n = n_of(1.9)
	t = np.arange(n) / SR
	body = sweep_lowpass(colored(rng, n, 1.0), 900.0 + 1800.0 * np.exp(-((t - 0.5) / 0.4) ** 2)) * np.exp(-((t - 0.55) / 0.5) ** 2)
	return body


def amb_rock(rng, v):
	n = n_of(1.2)
	out = _thunk(rng, 65.0, 1.2, 0.05, 0.5) * 0.8
	for i in range(9):
		f0 = rng.uniform(300.0, 2400.0)
		g = bandpass(white(rng, n_of(0.12)), f0 * 0.6, f0 * 1.5, 1) * decay_env(n_of(0.12), 0.02, 0.001)
		place(out, g, 0.05 + i * rng.uniform(0.04, 0.12), rng.uniform(0.15, 0.5))
	return out
