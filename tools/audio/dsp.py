"""Small numpy DSP toolkit for the offline sound-design renderer.

Everything is deterministic: every sound draws from a generator seeded by a
hash of its name, so re-running the renderer reproduces the shipped assets
bit-for-bit (given the same numpy). No scipy: filtering is done in the
frequency domain (zero-phase, periodic, which also makes looping beds seamless)
or with short pure-python biquads where a resonant time-varying filter is
needed.
"""
import zlib

import numpy as np

SR = 44100


def rng_for(name: str) -> np.random.Generator:
	return np.random.default_rng(zlib.crc32(name.encode("utf-8")))


def n_of(seconds: float) -> int:
	return int(round(seconds * SR))


def t_of(seconds: float) -> np.ndarray:
	return np.arange(n_of(seconds)) / SR


# --- Sources -------------------------------------------------------------------

def white(rng, n):
	return rng.standard_normal(n)


def colored(rng, n, exponent):
	"""Noise with a 1/f^exponent power spectrum (0 white, 1 pink, 2 brown)."""
	spec = np.fft.rfft(rng.standard_normal(n))
	f = np.fft.rfftfreq(n, 1.0 / SR)
	f[0] = f[1] if len(f) > 1 else 1.0
	spec *= f ** (-exponent / 2.0)
	out = np.fft.irfft(spec, n)
	return out / (np.max(np.abs(out)) + 1e-12)


# --- Filters (frequency domain, zero phase) ------------------------------------

def _shape(x, fn):
	n = len(x)
	spec = np.fft.rfft(x)
	f = np.fft.rfftfreq(n, 1.0 / SR)
	return np.fft.irfft(spec * fn(f), n)


def lowpass(x, fc, order=2):
	return _shape(x, lambda f: 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order)))


def highpass(x, fc, order=2):
	return _shape(x, lambda f: 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))


def bandpass(x, lo, hi, order=2):
	return highpass(lowpass(x, hi, order), lo, order)


def resonate(x, fc, q):
	"""Single resonant peak (unit gain at centre, energy elsewhere rolled off)."""
	return _shape(x, lambda f: 1.0 / np.sqrt(1.0 + (q * (f / fc - fc / np.maximum(f, 1e-3))) ** 2))


def shape_by(x, points):
	"""Piecewise-linear (in dB, log-frequency) magnitude response.
	points: [(hz, db), ...] ascending."""
	hz = np.log(np.array([p[0] for p in points], dtype=float))
	db = np.array([p[1] for p in points], dtype=float)

	def fn(f):
		lf = np.log(np.maximum(f, 1.0))
		return 10.0 ** (np.interp(lf, hz, db) / 20.0)

	return _shape(x, fn)


def biquad(x, kind, fc, q=0.707, gain_db=0.0):
	"""Causal RBJ biquad in pure python. Only for short signals or few calls."""
	w0 = 2.0 * np.pi * fc / SR
	cw, sw = np.cos(w0), np.sin(w0)
	alpha = sw / (2.0 * q)
	a_lin = 10.0 ** (gain_db / 40.0)
	if kind == "lp":
		b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
		a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
	elif kind == "hp":
		b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
		a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
	elif kind == "bp":
		b0, b1, b2 = alpha, 0.0, -alpha
		a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
	elif kind == "peak":
		b0, b1, b2 = 1 + alpha * a_lin, -2 * cw, 1 - alpha * a_lin
		a0, a1, a2 = 1 + alpha / a_lin, -2 * cw, 1 - alpha / a_lin
	else:
		raise ValueError(kind)
	b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
	out = np.empty(len(x))
	x1 = x2 = y1 = y2 = 0.0
	for i, v in enumerate(x.tolist()):
		y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		out[i] = y
		x2, x1 = x1, v
		y2, y1 = y1, y
	return out


def sweep_lowpass(x, fc_curve, bank=10):
	"""Time-varying low-pass by cross-fading a log-spaced bank of static ones."""
	fc_curve = np.clip(fc_curve, 60.0, 20000.0)
	lo, hi = np.log(fc_curve.min()) - 1e-6, np.log(fc_curve.max()) + 1e-6
	if hi - lo < 1e-3:
		return lowpass(x, float(fc_curve[0]))
	centres = np.exp(np.linspace(lo, hi, bank))
	filtered = np.stack([lowpass(x, c, 2) for c in centres])
	pos = (np.log(fc_curve) - lo) / (hi - lo) * (bank - 1)
	i0 = np.clip(np.floor(pos).astype(int), 0, bank - 2)
	frac = pos - i0
	idx = np.arange(len(x))
	return filtered[i0, idx] * (1 - frac) + filtered[i0 + 1, idx] * frac


# --- Envelopes -----------------------------------------------------------------

def ad(n, attack, tau):
	"""Linear attack (seconds), exponential decay with time constant tau."""
	t = np.arange(n) / SR
	env = np.exp(-t / max(tau, 1e-6))
	if attack > 0:
		env = env * np.minimum(1.0, t / attack)
	return env


def decay_env(n, tau, attack=0.0015):
	return ad(n, attack, tau)


def swell(n, rise, fall):
	t = np.arange(n) / SR
	up = np.minimum(1.0, t / max(rise, 1e-6)) ** 2
	dur = n / SR
	down = np.minimum(1.0, (dur - t) / max(fall, 1e-6)) ** 2
	return up * np.clip(down, 0.0, 1.0)


def smooth_random(rng, n, rate_hz, depth=1.0):
	"""Slow band-limited random modulation in [-depth, depth]."""
	pts = max(4, int(n / SR * rate_hz) + 2)
	knots = rng.uniform(-1, 1, pts)
	x = np.interp(np.linspace(0, pts - 1, n), np.arange(pts), knots)
	x = lowpass(x, rate_hz * 1.5, 1)
	return x / (np.max(np.abs(x)) + 1e-12) * depth


def sum_clips(*clips):
	"""Add clips of different lengths (zero-padded to the longest)."""
	n = max(len(c) for c in clips)
	out = np.zeros(n)
	for c in clips:
		out[: len(c)] += c
	return out


def place(buf, clip, at_seconds, gain=1.0):
	"""Mix clip into buf at a time offset (clipped to buffer length)."""
	i = n_of(at_seconds)
	if i >= len(buf):
		return buf
	j = min(len(buf), i + len(clip))
	buf[i:j] += clip[: j - i] * gain
	return buf


# --- Synthesis primitives ------------------------------------------------------

def sine(freq, n, phase=0.0):
	t = np.arange(n) / SR
	return np.sin(2 * np.pi * freq * t + phase)


def glide_phase(freq_curve):
	return 2 * np.pi * np.cumsum(freq_curve) / SR


def partials(freqs, amps, decays, n, rng=None, detune=0.0, start_phase=True):
	"""Sum of exponentially decaying partials. decays are time constants (s)."""
	t = np.arange(n) / SR
	out = np.zeros(n)
	for k, (f, a, d) in enumerate(zip(freqs, amps, decays)):
		ph = rng.uniform(0, 2 * np.pi) if (rng is not None and start_phase) else 0.0
		out += a * np.sin(2 * np.pi * f * t + ph) * np.exp(-t / d)
		if detune:
			# Beating twin: gives bells their slow shimmer.
			out += a * 0.8 * np.sin(2 * np.pi * (f + detune * (1 + 0.37 * k)) * t + ph * 1.7) * np.exp(-t / d)
	return out


def formant_gain(f, formants):
	"""Vocal-tract magnitude at frequencies f for [(Fc, bandwidth, gain), ...]."""
	g = np.zeros_like(f, dtype=float)
	for fc, bw, gain in formants:
		g += gain / (1.0 + ((f - fc) / (bw * 0.5)) ** 2)
	return g + 0.015


def voiced(f0_curve, formants_t, n, harm_slope=1.1, breath=0.0, rng=None, max_harm=60, formants_end=None, pulsatile=0.0):
	"""Source-filter voice by harmonic synthesis.

	f0_curve: array of instantaneous f0 (Hz), length n.
	formants: list of (Fc, bandwidth, gain) or callable(t01)->list (interpolated
	linearly between formants and formants_end when formants_end is given).
	pulsatile: 0..1 depth of a glottal-pulse amplitude flutter (vocal fry).
	"""
	phase = np.cumsum(f0_curve) / SR
	out = np.zeros(n)
	t01 = np.linspace(0.0, 1.0, n)
	for k in range(1, max_harm + 1):
		fk = f0_curve * k
		if np.all(fk > SR * 0.47):
			break
		if formants_end is None:
			g = formant_gain(fk, formants_t)
		else:
			g = np.zeros(n)
			for (a, b) in zip(formants_t, formants_end):
				fc = a[0] * (1 - t01) + b[0] * t01
				bw = a[1] * (1 - t01) + b[1] * t01
				gn = a[2] * (1 - t01) + b[2] * t01
				g += gn / (1.0 + ((fk - fc) / (bw * 0.5)) ** 2)
			g += 0.015
		amp = g * k ** (-harm_slope)
		amp = np.where(fk < SR * 0.45, amp, 0.0)
		out += amp * np.sin(2 * np.pi * k * phase + (0 if rng is None else rng.uniform(0, 2 * np.pi)))
	if pulsatile > 0.0 and rng is not None:
		flutter = 1.0 - pulsatile * (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(f0_curve * 0.5) / SR))
		out *= flutter
	if breath > 0.0 and rng is not None:
		nz = colored(rng, n, 0.6)
		ff = np.linspace(80, 6000, 2048)
		resp = formant_gain(ff, formants_t)
		nz = _shape(nz, lambda f: np.interp(f, ff, resp / resp.max()))
		out += breath * nz * (np.max(np.abs(out)) + 1e-9) * 0.7
	return out / (np.max(np.abs(out)) + 1e-12)


def saturate(x, drive):
	return np.tanh(x * drive) / np.tanh(drive)


# --- Space ---------------------------------------------------------------------

def canyon_ir(rng, seconds=3.2, rt_low=2.6, rt_high=0.7, slaps=((0.19, 0.5), (0.43, 0.32), (0.79, 0.2)), predelay=0.012):
	"""Synthetic canyon impulse response (mono): pre-delay, discrete cliff slaps
	and a cold, low-passed noise tail whose highs die faster than its lows."""
	n = n_of(seconds)
	t = np.arange(n) / SR
	nz = rng.standard_normal(n)
	low = lowpass(nz, 900.0, 2)
	high = highpass(lowpass(nz, 6500.0, 2), 900.0, 1)
	tail = low * np.exp(-t / (rt_low / 6.9)) + high * np.exp(-t / (rt_high / 6.9)) * 0.5
	tail *= np.minimum(1.0, t / 0.03)
	ir = np.zeros(n)
	ir[n_of(predelay) :] += tail[: n - n_of(predelay)] * 0.16
	for delay, gain in slaps:
		burst = lowpass(rng.standard_normal(n_of(0.05)), 2400.0 / (1.0 + delay * 1.6), 2) * np.exp(-np.arange(n_of(0.05)) / SR / 0.012)
		i = n_of(delay)
		if i + len(burst) < n:
			ir[i : i + len(burst)] += burst * gain
	return ir


def convolve(x, ir, wet_len=None):
	n = len(x) + len(ir) - 1
	m = 1
	while m < n:
		m *= 2
	y = np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:n]
	if wet_len is not None:
		y = y[:wet_len]
	return y


def reverb_stereo(x, wet, seed_name, seconds=3.0, **ir_kwargs):
	"""Return (left, right) with decorrelated canyon tails mixed in at `wet`."""
	rng = rng_for("ir:" + seed_name)
	n_total = len(x) + n_of(seconds)
	left = np.zeros(n_total)
	right = np.zeros(n_total)
	left[: len(x)] += x
	right[: len(x)] += x
	ir_l = canyon_ir(rng, seconds, **ir_kwargs)
	ir_r = canyon_ir(rng, seconds, **ir_kwargs)
	wl = convolve(x, ir_l)[:n_total]
	wr = convolve(x, ir_r)[:n_total]
	left[: len(wl)] += wl * wet
	right[: len(wr)] += wr * wet
	return left, right


def to_stereo(x, width=0.0, rng=None):
	"""Mono to stereo, optionally decorrelated with a tiny Haas offset."""
	if width <= 0.0:
		return np.stack([x, x], axis=1)
	d = max(1, int(width * SR))
	r = np.concatenate([np.zeros(d), x[:-d]])
	return np.stack([x, r * 0.95], axis=1)


# --- Finishing -----------------------------------------------------------------

def db(x):
	return 20.0 * np.log10(max(x, 1e-12))


def finish(x, target_peak_db, fade_in_ms=1.0, fade_out_ms=None, dc=True, tail_trim_db=-70.0):
	"""Remove DC, trim trailing silence, fade edges, normalise peak to target."""
	x = np.asarray(x, dtype=np.float64)
	if x.ndim == 1:
		x = x[:, None]
	if dc:
		x = x - x.mean(axis=0, keepdims=True) * 1.0
	peak = np.max(np.abs(x))
	if peak > 0:
		mono = np.max(np.abs(x), axis=1)
		floor = peak * 10.0 ** (tail_trim_db / 20.0)
		idx = np.nonzero(mono > floor)[0]
		end = (idx[-1] + n_of(0.02)) if len(idx) else len(x)
		x = x[: min(end, len(x))]
	n = len(x)
	fi = max(1, int(fade_in_ms * SR / 1000.0))
	x[:fi] *= np.linspace(0, 1, fi)[:, None]
	fo = int((fade_out_ms if fade_out_ms is not None else min(40.0, n / SR * 300.0)) * SR / 1000.0)
	fo = min(max(fo, 32), n)
	x[n - fo :] *= np.linspace(1, 0, fo)[:, None] ** 1.5
	peak = np.max(np.abs(x))
	if peak > 0:
		x *= 10.0 ** (target_peak_db / 20.0) / peak
	return x.squeeze() if x.shape[1] == 1 else x


def soft_limit(x, ceiling_db=-1.0):
	c = 10.0 ** (ceiling_db / 20.0)
	return np.tanh(x / c) * c


def make_loop(x, tail_seconds):
	"""Turn a buffer rendered `tail_seconds` longer than the loop into a seamless
	loop by overlap-adding the natural decay tail onto the head."""
	xf = n_of(tail_seconds)
	body = x[:-xf].copy()
	body[:xf] += x[-xf:]
	return body


def seam_fade(x, milliseconds=6.0):
	"""Short raised-cosine dip at both ends of a loop. Ogg Vorbis encoders pad a few
	samples of silence after the last block; with the loop already at (near) zero
	there the seam stays click-free whatever the decoder does with the padding."""
	n = max(8, int(milliseconds * SR / 1000.0))
	ramp = 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, n))
	if x.ndim == 2:
		ramp = ramp[:, None]
	x = x.copy()
	x[:n] *= ramp
	x[-n:] *= ramp[::-1]
	return x
