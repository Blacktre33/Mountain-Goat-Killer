"""Firearm, impact, casing and mechanical sounds."""
import numpy as np

from dsp import (SR, sum_clips, ad, bandpass, canyon_ir, colored, convolve, decay_env, glide_phase, highpass, lowpass, n_of, partials,
                 place, resonate, reverb_stereo, saturate, sine, sweep_lowpass, t_of, to_stereo, white)


def _exp_sweep(f_start, f_end, n, tau):
	t = np.arange(n) / SR
	return f_end + (f_start - f_end) * np.exp(-t / tau)


def _rifle_dry(rng, crack_hz, crack_tau, blast_tau, thump_hz, thump_tau, body, crack_gain=0.75, thump_gain=1.05):
	"""Dry muzzle event: supersonic crack, expanding blast and a chest thump."""
	n = n_of(0.45)
	crack = highpass(white(rng, n), crack_hz, 2) * decay_env(n, crack_tau, 0.0002)
	# N-wave: a tiny bipolar pulse just before the noise settles gives the snap.
	pulse = np.zeros(n)
	pulse[5:9] = [1.0, 1.0, -1.1, -0.7]
	crack += pulse * 1.4
	curve = 300.0 + 6500.0 * np.exp(-np.arange(n) / SR / 0.05)
	blast = sweep_lowpass(white(rng, n), curve) * decay_env(n, blast_tau, 0.0004)
	f = _exp_sweep(thump_hz * 1.9, thump_hz * 0.62, n, 0.045)
	thump = np.sin(glide_phase(f)) * decay_env(n, thump_tau, 0.001)
	ring = resonate(white(rng, n), 2850.0, 18.0) * decay_env(n, 0.028, 0.0003) * 2.5
	dry = crack * crack_gain + blast * body + thump * thump_gain + ring * 0.25
	return saturate(dry / (np.max(np.abs(dry)) + 1e-9), 1.8)


def _shot_stereo(rng, dry, wet, slaps, rt_low=2.7, rt_high=0.8):
	n_tail = n_of(3.2)
	left = np.zeros(len(dry) + n_tail)
	right = np.zeros_like(left)
	left[: len(dry)] += dry
	right[: len(dry)] += dry
	ir_l = canyon_ir(rng, 3.2, rt_low, rt_high, slaps)
	ir_r = canyon_ir(rng, 3.2, rt_low, rt_high, tuple((d * 1.07, g * 0.9) for d, g in slaps))
	wl = convolve(dry, ir_l)[: len(left)]
	wr = convolve(dry, ir_r)[: len(left)]
	left[: len(wl)] += wl * wet
	right[: len(wr)] += wr * wet
	return np.stack([left, right], axis=1)


def carbine_shot(rng, v):
	dry = _rifle_dry(rng, 1400.0, 0.0055 + 0.0004 * v, 0.055, 92.0 - 4 * v, 0.11, 1.0, 1.2, 0.9)
	return _shot_stereo(rng, dry, 0.42, ((0.17 + 0.01 * v, 0.30), (0.41, 0.19), (0.78, 0.12)))


def rifle_crack(rng, v):
	"""Enemy marksman: sharper, higher and thinner than the player's carbine, with
	a later, longer echo so you can tell whose gun it is across the ravine."""
	dry = _rifle_dry(rng, 2000.0, 0.0045, 0.03, 150.0 + 12 * v, 0.05, 0.6, 2.4, 0.35)
	return _shot_stereo(rng, dry, 0.5, ((0.26 + 0.02 * v, 0.33), (0.58, 0.22), (1.05, 0.14)), rt_low=3.0, rt_high=1.0)


def dry_click(rng, v):
	n = n_of(0.16)
	tick = bandpass(white(rng, n), 1200.0, 5000.0, 2) * decay_env(n, 0.003, 0.0001)
	body = resonate(white(rng, n), 900.0 + 100 * v, 6.0) * decay_env(n, 0.016, 0.0002) * 2.0
	thunk = _thunk(rng, 260.0, 0.16, 0.012, 0.2)
	ring = partials([2100.0, 3400.0], [0.3, 0.15], [0.02, 0.012], n, rng)
	return tick * 0.5 + body * 0.9 + thunk * 0.7 + ring * 0.2


def _metal_hit(rng, freqs, amps, decays, dur, noise_tau=0.004, noise_gain=0.6, noise_band=(1200.0, 8000.0)):
	n = n_of(dur)
	ring = partials(freqs, amps, decays, n, rng)
	noise = bandpass(white(rng, n), *noise_band, 2) * decay_env(n, noise_tau, 0.0002)
	return ring + noise * noise_gain


def _rattle(rng, dur, lo, hi, rough=90.0, floor=0.15):
	"""Friction rattle: band noise with rapid irregular amplitude ripples."""
	n = n_of(dur)
	ripple = np.abs(lowpass(white(rng, n), rough, 1))
	ripple = floor + (1 - floor) * ripple / (np.max(ripple) + 1e-9)
	return bandpass(white(rng, n), lo, hi, 2) * ripple * np.minimum(1.0, np.arange(n) / SR / 0.02)


def _thunk(rng, freq, dur, tau, air=0.3):
	n = n_of(dur)
	f = _exp_sweep(freq * 1.5, freq, n, 0.01)
	body = np.sin(glide_phase(f)) * decay_env(n, tau, 0.0008)
	air_n = lowpass(white(rng, n), freq * 4, 2) * decay_env(n, tau * 0.6, 0.0004)
	return body + air_n * air


def _bolt_stages(rng):
	"""Return dict of stage clips for a bolt-action cycle."""
	lift = _metal_hit(rng, [2400.0, 3700.0], [0.5, 0.3], [0.010, 0.006], 0.06, 0.003, 0.5)
	back_fric = _rattle(rng, 0.24, 900.0, 4200.0, 70.0)
	back_stop = sum_clips(_thunk(rng, 210.0, 0.12, 0.03) * 0.9, _metal_hit(rng, [1250.0, 2900.0, 4600.0], [0.5, 0.4, 0.2], [0.05, 0.03, 0.02], 0.15, 0.003, 0.7))
	fwd_fric = _rattle(rng, 0.16, 900.0, 4200.0, 80.0)
	slam = sum_clips(_thunk(rng, 170.0, 0.16, 0.035) * 1.1, _metal_hit(rng, [880.0, 2100.0, 3700.0, 5600.0], [0.6, 0.5, 0.35, 0.18], [0.09, 0.05, 0.03, 0.02], 0.35, 0.005, 0.9))
	down = _metal_hit(rng, [1900.0, 3100.0], [0.45, 0.3], [0.012, 0.008], 0.08, 0.003, 0.45)
	return lift, back_fric, back_stop, fwd_fric, slam, down


def bolt_cycle(rng, v):
	lift, back_fric, back_stop, fwd_fric, slam, down = _bolt_stages(rng)
	out = np.zeros(n_of(1.05))
	place(out, lift, 0.0, 0.7)
	place(out, back_fric, 0.10, 0.45)
	place(out, back_stop, 0.33, 0.95)
	place(out, fwd_fric, 0.50, 0.4)
	place(out, slam, 0.63, 1.0)
	place(out, down, 0.78, 0.7)
	return out


def mag_out(rng, v):
	out = np.zeros(n_of(0.6))
	catch = _metal_hit(rng, [2100.0, 3300.0], [0.5, 0.35], [0.012, 0.008], 0.07, 0.003, 0.6)
	place(out, catch, 0.0, 0.8)
	place(out, _rattle(rng, 0.2, 700.0, 3200.0, 60.0), 0.05, 0.4)
	place(out, sum_clips(_thunk(rng, 240.0, 0.14, 0.03, 0.4), _metal_hit(rng, [1100.0, 2600.0], [0.3, 0.2], [0.03, 0.02], 0.1, 0.003, 0.5)), 0.27, 0.8)
	return out


def mag_in(rng, v):
	out = np.zeros(n_of(0.55))
	place(out, _rattle(rng, 0.16, 700.0, 3200.0, 60.0), 0.0, 0.4)
	place(out, sum_clips(_thunk(rng, 200.0, 0.16, 0.03, 0.4), _metal_hit(rng, [1000.0, 2400.0, 3900.0], [0.5, 0.35, 0.2], [0.05, 0.03, 0.02], 0.2, 0.004, 0.8)), 0.15, 1.0)
	place(out, _metal_hit(rng, [2500.0, 3800.0], [0.5, 0.3], [0.010, 0.006], 0.06, 0.003, 0.5), 0.24, 0.7)
	return out


def reload_full(rng, v):
	"""Mag out, a beat of cloth and pouch, mag in, then the bolt (about 2.1 s)."""
	out = np.zeros(n_of(2.15))
	place(out, mag_out(rng, v), 0.05, 0.95)
	cloth = bandpass(colored(rng, n_of(0.35), 1.0), 300.0, 2600.0) * np.hanning(n_of(0.35)) * 0.16
	place(out, cloth, 0.55, 1.0)
	place(out, mag_in(rng, v), 0.85, 1.0)
	place(out, bolt_cycle(rng, v), 1.20, 0.95)
	return out


def casing(rng, v, surface="stone"):
	"""Brass case falling: a few decaying bounces of a ringing brass tube."""
	dur = 0.7
	out = np.zeros(n_of(dur))
	base = 3900.0 + 250.0 * v
	times = [0.0, 0.085 + 0.01 * v, 0.14 + 0.012 * v, 0.175 + 0.01 * v, 0.19]
	gains = [1.0, 0.62, 0.38, 0.22, 0.10]
	for t0, g in zip(times, gains):
		if surface == "stone":
			ping = partials([base, base * 1.58, base * 2.31, base * 0.61], [0.55, 0.3, 0.18, 0.3], [0.045, 0.03, 0.02, 0.05], n_of(0.25), rng)
			tick = highpass(white(rng, n_of(0.25)), 3000.0, 2) * decay_env(n_of(0.25), 0.002, 0.0001) * 0.5
			place(out, ping + tick, t0, g)
		else:
			puff = lowpass(white(rng, n_of(0.2)), 800.0, 2) * decay_env(n_of(0.2), 0.02, 0.001)
			ping = partials([base * 0.7], [0.12], [0.012], n_of(0.2), rng)
			place(out, puff * 0.9 + ping, t0, g * 0.8)
	if surface == "stone":
		roll = _rattle(rng, 0.25, 2500.0, 7000.0, 55.0, 0.0) * np.linspace(1, 0, n_of(0.25)) ** 2 * 0.06
		place(out, roll, 0.2, 1.0)
	return out


def casing_snow(rng, v):
	return casing(rng, v, "snow")


def flesh_hit(rng, v, sharp=0.0):
	n = n_of(0.3)
	f = _exp_sweep(210.0 - 20 * v, 70.0, n, 0.03)
	thud = np.sin(glide_phase(f)) * decay_env(n, 0.06, 0.001)
	slap = bandpass(white(rng, n), 600.0, 2600.0) * decay_env(n, 0.025, 0.0005)
	wet = bandpass(white(rng, n), 250.0, 1200.0) * decay_env(n, 0.09, 0.004) * 0.5
	out = thud * 0.9 + slap * 0.75 + wet * 0.4
	if sharp > 0.0:
		crack = highpass(white(rng, n), 2200.0, 2) * decay_env(n, 0.004, 0.0002)
		ring = partials([1400.0, 2300.0, 3600.0], [0.5, 0.3, 0.2], [0.07, 0.045, 0.03], n, rng)
		out += (crack * 0.9 + ring * 0.6) * sharp
	return out


def hit(rng, v):
	return flesh_hit(rng, v, 0.0)


def headshot(rng, v):
	return flesh_hit(rng, v, 1.0)


def impact_flesh(rng, v):
	n = n_of(0.4)
	f = _exp_sweep(150.0, 55.0, n, 0.05)
	thud = np.sin(glide_phase(f)) * decay_env(n, 0.09, 0.001)
	wet = bandpass(white(rng, n), 200.0, 1500.0) * decay_env(n, 0.06, 0.002)
	squelch = _rattle(rng, 0.14, 300.0, 1400.0, 120.0) * np.hanning(n_of(0.14))
	out = thud + wet * 0.7
	place(out, squelch, 0.02, 0.4)
	return out


def impact_snow(rng, v):
	n = n_of(0.35)
	fump = lowpass(white(rng, n), 420.0 + 40 * v, 2) * decay_env(n, 0.05, 0.002) * 2.0
	crystals = _rattle(rng, 0.2, 3000.0, 8500.0, 200.0, 0.0) * decay_env(n_of(0.2), 0.04, 0.001) * 0.3
	out = fump
	place(out, crystals, 0.005, 1.0)
	return out


def impact_wood(rng, v):
	n = n_of(0.5)
	crack = bandpass(white(rng, n), 900.0, 4500.0) * decay_env(n, 0.009, 0.0005)
	knock = partials([310.0 + 25 * v, 590.0 + 30 * v, 1010.0], [0.9, 0.55, 0.25], [0.05, 0.035, 0.02], n, rng)
	splinter = np.zeros(n)
	for i in range(int(rng.integers(3, 6))):
		place(splinter, highpass(white(rng, n_of(0.02)), 4000.0, 2) * decay_env(n_of(0.02), 0.003, 0.0001), 0.02 + 0.02 * i + rng.uniform(0, 0.02), rng.uniform(0.15, 0.4))
	return crack * 0.9 + knock * 0.8 + splinter


def impact_stone(rng, v):
	n = n_of(0.9)
	crack = highpass(white(rng, n), 1800.0, 2) * decay_env(n, 0.006, 0.0002)
	chip = partials([1800.0, 2900.0, 4300.0], [0.3, 0.25, 0.15], [0.03, 0.02, 0.015], n, rng)
	# Ricochet whine: a falling chirp with a little wobble.
	t = np.arange(n) / SR
	f = 3800.0 * np.exp(-t / 0.22) + 900.0 + 60.0 * np.sin(2 * np.pi * 38.0 * t)
	whine = np.sin(glide_phase(f)) * decay_env(n, 0.12, 0.004) * 0.22
	dust = lowpass(white(rng, n), 2500.0, 2) * decay_env(n, 0.05, 0.001) * 0.4
	return crack * 0.9 + chip * 0.8 + whine + dust


def impact_metal(rng, v):
	n = n_of(1.1)
	ping = partials([1180.0 + 60 * v, 2430.0, 3910.0, 5720.0], [0.6, 0.5, 0.3, 0.18], [0.16, 0.10, 0.07, 0.04], n, rng)
	tick = highpass(white(rng, n), 2500.0, 2) * decay_env(n, 0.003, 0.0001)
	t = np.arange(n) / SR
	f = 4800.0 * np.exp(-t / 0.18) + 1200.0
	whine = np.sin(glide_phase(f)) * decay_env(n, 0.09, 0.004) * 0.16
	return ping + tick * 0.8 + whine


def hitmarker(rng, v):
	n = n_of(0.09)
	tone = sine(1560.0, n) * 0.6 + sine(2340.0, n) * 0.3 + sine(780.0, n) * 0.2
	return tone * decay_env(n, 0.02, 0.0015)


def kill_confirm(rng, v):
	n = n_of(0.9)
	f = _exp_sweep(150.0, 62.0, n, 0.06)
	thud = np.sin(glide_phase(f)) * decay_env(n, 0.12, 0.002)
	bell = partials([660.0, 1584.0, 2640.0], [0.5, 0.3, 0.15], [0.35, 0.22, 0.12], n, rng)
	tick = sine(2600.0, n) * decay_env(n, 0.012, 0.0008) * 0.35
	return thud * 0.9 + bell * 0.5 + tick


def player_hurt(rng, v):
	n = n_of(0.55)
	f = _exp_sweep(150.0, 60.0, n, 0.06)
	thud = np.sin(glide_phase(f)) * decay_env(n, 0.1, 0.001)
	# A pained exhale: formant-shaped breath, no fake voice.
	breath = resonate(colored(rng, n, 0.5), 700.0, 1.6) * np.hanning(n) ** 0.6 * 0.5
	breath = np.roll(breath, n_of(0.02)) * np.minimum(1.0, np.arange(n) / SR / 0.04)
	cloth = bandpass(colored(rng, n, 1.0), 300.0, 2400.0) * decay_env(n, 0.09, 0.005) * 0.3
	return thud * 0.9 + breath * 0.55 + cloth


def land(rng, v):
	n = n_of(0.45)
	f = _exp_sweep(110.0, 48.0, n, 0.05)
	thud = np.sin(glide_phase(f)) * decay_env(n, 0.09, 0.002)
	snow = lowpass(white(rng, n), 900.0, 2) * decay_env(n, 0.06, 0.003) * 1.3
	gear = _rattle(rng, 0.25, 1500.0, 5000.0, 90.0, 0.0) * decay_env(n_of(0.25), 0.06, 0.005) * 0.25
	out = thud + snow
	place(out, gear, 0.03, 1.0)
	return out


def heartbeat(rng, v):
	"""Lub-dub, kept audible on small speakers with a 110 Hz body and a soft click."""
	n = n_of(0.75)
	out = np.zeros(n)
	for start, gain, f0 in ((0.0, 1.0, 58.0), (0.27, 0.72, 66.0)):
		m = n_of(0.3)
		f = _exp_sweep(f0 * 1.6, f0, m, 0.03)
		body = np.sin(glide_phase(f)) * decay_env(m, 0.07, 0.006)
		mid = sine(f0 * 2.0, m) * decay_env(m, 0.04, 0.006) * 0.4
		click = lowpass(white(rng, m), 500.0, 2) * decay_env(m, 0.012, 0.002) * 0.25
		place(out, body + mid + click, start, gain)
	return out


def tinnitus(rng, v):
	"""Near-miss ringing: two pure partials that fade with a slow flutter."""
	n = n_of(3.2)
	t = np.arange(n) / SR
	flutter = 1.0 + 0.08 * np.sin(2 * np.pi * 3.1 * t + 1.0)
	tone = sine(6300.0, n) * 0.6 + sine(3150.5, n) * 0.25 + sine(8400.0, n) * 0.15
	env = np.exp(-t / 1.2) * np.minimum(1.0, t / 0.03)
	return tone * env * flutter


def whoosh(rng, v):
	"""Melee swish: colour noise through a rising then falling low-pass."""
	dur = 0.42 + 0.05 * v
	n = n_of(dur)
	t = np.arange(n) / SR
	peak = dur * 0.45
	curve = 350.0 + 3400.0 * np.exp(-((t - peak) / (dur * 0.28)) ** 2)
	body = sweep_lowpass(colored(rng, n, 0.7), curve)
	body = highpass(body, 180.0, 1)
	env = np.exp(-((t - peak) / (dur * 0.30)) ** 2)
	return body * env


def throw(rng, v):
	n = n_of(0.24)
	t = np.arange(n) / SR
	curve = 500.0 + 3800.0 * np.exp(-((t - 0.08) / 0.06) ** 2)
	body = sweep_lowpass(colored(rng, n, 0.6), curve)
	env = np.exp(-((t - 0.08) / 0.07) ** 2)
	cloth = bandpass(colored(rng, n, 1.0), 250.0, 1800.0) * np.hanning(n) * 0.25
	return highpass(body, 300.0, 1) * env * 0.9 + cloth


def takedown(rng, v):
	n = n_of(0.9)
	f = _exp_sweep(150.0, 45.0, n, 0.08)
	thud = np.sin(glide_phase(f)) * decay_env(n, 0.14, 0.002)
	stab = bandpass(white(rng, n), 300.0, 2200.0) * decay_env(n, 0.04, 0.003)
	crunch = np.zeros(n)
	for i in range(9):
		place(crunch, bandpass(white(rng, n_of(0.03)), 500.0, 3500.0) * decay_env(n_of(0.03), 0.006, 0.0005), 0.01 + i * 0.022 + rng.uniform(0, 0.012), rng.uniform(0.3, 0.8))
	cloth = bandpass(colored(rng, n, 1.0), 200.0, 1800.0) * decay_env(n, 0.2, 0.02) * 0.3
	return thud * 0.9 + stab * 0.7 + crunch * 0.6 + cloth


def snuff(rng, v):
	n = n_of(0.9)
	hand = lowpass(colored(rng, n, 1.0), 900.0, 2) * decay_env(n_of(0.9), 0.05, 0.01)
	puff = bandpass(white(rng, n), 900.0, 4200.0) * decay_env(n, 0.06, 0.008) * 0.6
	sizzle = highpass(white(rng, n), 4500.0, 2) * decay_env(n, 0.22, 0.05) * 0.16
	tink = partials([2350.0, 3860.0], [0.4, 0.2], [0.08, 0.05], n, rng)
	tink_env = np.zeros(n)
	place(tink_env, tink[: n - n_of(0.25)], 0.25, 0.28)
	return hand * 0.9 + puff + sizzle + tink_env


def stone_land(rng, v):
	n = n_of(0.5)
	thud = _thunk(rng, 120.0, 0.5, 0.05, 0.8)
	grit = _rattle(rng, 0.25, 1200.0, 6000.0, 150.0, 0.0) * decay_env(n_of(0.25), 0.05, 0.003) * 0.4
	place(thud, grit, 0.0, 1.0)
	return thud


def gate_grind(rng, v):
	"""Stone gate opening: stick-slip grinding, iron chain clanks, sub rumble."""
	dur = 4.8
	n = n_of(dur)
	t = np.arange(n) / SR
	stick = np.abs(sine(11.0, n) + 0.6 * sine(17.3, n) + 0.5 * lowpass(white(rng, n), 12.0, 1) * 3)
	stick = stick / stick.max()
	grind = bandpass(colored(rng, n, 0.9), 70.0, 700.0) * (0.35 + 0.65 * stick)
	grit = bandpass(white(rng, n), 900.0, 3500.0) * (0.1 + 0.4 * stick ** 2) * 0.35
	f = np.linspace(46.0, 31.0, n)
	rumble = np.sin(glide_phase(f)) * 0.5 + np.sin(glide_phase(f * 1.5)) * 0.2
	env = np.minimum(1.0, t / 0.5) * (1.0 - np.clip((t - 3.9) / 0.9, 0, 1))
	out = (grind * 1.4 + grit + rumble) * env
	for i in range(11):
		at = rng.uniform(0.2, 3.9)
		f0 = rng.uniform(420.0, 1300.0)
		clank = partials([f0, f0 * 2.31, f0 * 4.1], [0.5, 0.35, 0.2], [0.18, 0.12, 0.08], n_of(0.6), rng) + bandpass(white(rng, n_of(0.6)), 1500.0, 7000.0) * decay_env(n_of(0.6), 0.005, 0.0002) * 0.4
		place(out, clank, at, rng.uniform(0.15, 0.4))
	place(out, _thunk(rng, 52.0, 1.2, 0.2, 0.5) * 1.6, 4.1, 1.0)
	place(out, _rattle(rng, 0.4, 500.0, 4000.0, 150.0, 0.0) * decay_env(n_of(0.4), 0.15, 0.005) * 0.6, 4.1, 1.0)
	return out
