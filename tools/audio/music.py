"""Original adaptive score, rendered as synchronised stereo stems.

Each biome has four stems that share one loop length and tempo, so the game
can fade them in and out freely:
    drone    cold sustained bed (stealth)
    motif    sparse bell melody (stealth)
    tension  unsettled pulse and dissonant swells (suspicious)
    combat   percussion and stabs (combat)
Varkas' three phases each get a base (harmony/horn) and a perc stem. Victory and
death are one-shots. Everything is synthesised from scratch with numpy.

Colour per biome
    Widowpine    A minor pentatonic, open fifths, single bells: bare and lonely.
    Carrion Cut  D Phrygian, choir drones, frame drums and bone clacks: ritual.
    Iron Crown   C minor cluster, anvil and sub: oppressive machinery.
"""
import numpy as np

from dsp import (SR, seam_fade, bandpass, canyon_ir, colored, convolve, decay_env, glide_phase, highpass, lowpass, make_loop, n_of,
                 place, resonate, rng_for, saturate, smooth_random, sum_clips, swell, white)
from sfx_creatures import F_AH, F_OO
from sfx_weapons import _exp_sweep, _thunk

NOTE = {"C": 0, "Db": 1, "D": 2, "Eb": 3, "E": 4, "F": 5, "Gb": 6, "G": 7, "Ab": 8, "A": 9, "Bb": 10, "B": 11}
TAIL = 6.0


def hz(name):
	pitch, octave = name[:-1], int(name[-1])
	return 440.0 * 2.0 ** ((NOTE[pitch] + 12 * (octave + 1) - 69) / 12.0)


def pan(x, p):
	"""Equal-power pan, p in [-1, 1]."""
	a = (p + 1.0) * np.pi / 4.0
	return np.stack([x * np.cos(a), x * np.sin(a)], axis=1)


def add_at(buf, clip_stereo, at_seconds, gain=1.0):
	i = n_of(at_seconds)
	if i >= len(buf):
		return
	j = min(len(buf), i + len(clip_stereo))
	buf[i:j] += clip_stereo[: j - i] * gain


# --- Instruments ---------------------------------------------------------------------

def bell(rng, f, dur, tau=2.5):
	n = n_of(dur)
	t = np.arange(n) / SR
	ratios = [1.0, 2.0, 2.4, 3.0, 4.2, 5.4]
	amps = [1.0, 0.55, 0.42, 0.3, 0.16, 0.08]
	out = np.zeros(n)
	for r, a in zip(ratios, amps):
		out += a * np.sin(2 * np.pi * f * r * (1 + rng.uniform(-0.002, 0.002)) * t + rng.uniform(0, 6.28)) * np.exp(-t / (tau / (1.0 + 0.55 * (r - 1))))
	strike = bandpass(white(rng, n), 400.0, 5000.0, 2) * decay_env(n, 0.008, 0.0004) * 0.25
	return (out + strike) * np.minimum(1.0, t / 0.003)


def pad_voice(rng, f, dur, harmonics=14, tilt=1.3, detune=0.004, bright_lfo=0.11):
	"""Additive pad: detuned partial pairs with slowly wandering brightness."""
	n = n_of(dur)
	t = np.arange(n) / SR
	out = np.zeros(n)
	for h in range(1, harmonics + 1):
		fh = f * h
		if fh > 9000.0:
			break
		lfo = 0.6 + 0.4 * np.sin(2 * np.pi * (bright_lfo * (0.7 + 0.13 * h)) * t + rng.uniform(0, 6.28))
		amp = h ** (-tilt) * (lfo if h > 2 else 1.0)
		out += amp * np.sin(2 * np.pi * fh * t + rng.uniform(0, 6.28))
		out += amp * 0.7 * np.sin(2 * np.pi * fh * (1.0 + detune) * t + rng.uniform(0, 6.28))
	return out * swell(n, min(dur * 0.4, 3.0), min(dur * 0.45, 3.5))


def saw_horn(rng, f, dur, bright=3500.0, vibrato=0.006, attack=0.25, release=0.5, tremolo=0.0):
	"""Bowed/brassy saw built from partials with a brightness swell (low-pass tracked)."""
	n = n_of(dur)
	t = np.arange(n) / SR
	vib = 1.0 + vibrato * np.sin(2 * np.pi * 5.3 * t + rng.uniform(0, 6.28)) * np.minimum(1.0, t / 0.6)
	phase = np.cumsum(f * vib) / SR
	fc = bright * (0.25 + 0.75 * np.minimum(1.0, t / (attack * 1.5 + 0.05)))
	out = np.zeros(n)
	for h in range(1, 40):
		fh = f * h
		if fh > 12000.0:
			break
		gain = 1.0 / h / (1.0 + (fh / fc) ** 4)
		out += gain * np.sin(2 * np.pi * h * phase + rng.uniform(0, 6.28) * 0.1)
	env = np.minimum(1.0, t / attack) * np.minimum(1.0, np.maximum(0.0, (dur - t) / release))
	if tremolo > 0:
		out *= 1.0 - tremolo * (0.5 + 0.5 * np.sin(2 * np.pi * 6.0 * t))
	return out * env


def choir_note(rng, f, dur, formants, breath=0.25):
	from sfx_world import _choir
	return _choir(rng, [f, f * 1.003, f * 0.997], dur, formants, breath) * swell(n_of(dur), min(dur * 0.4, 2.5), min(dur * 0.4, 3.0))


def frame_drum(rng, f=78.0, dur=1.2, gain=1.0):
	n = n_of(dur)
	body = np.sin(glide_phase(_exp_sweep(f * 1.9, f, n, 0.035))) * decay_env(n, 0.22, 0.001)
	skin = bandpass(white(rng, n), 180.0, 900.0, 2) * decay_env(n, 0.06, 0.0005) * 0.5
	slap = bandpass(white(rng, n), 1200.0, 4200.0, 2) * decay_env(n, 0.012, 0.0003) * 0.25
	return (body + skin + slap) * gain


def war_drum(rng, f=48.0, dur=2.0, gain=1.0):
	n = n_of(dur)
	body = np.sin(glide_phase(_exp_sweep(f * 2.2, f, n, 0.05))) * decay_env(n, 0.5, 0.001)
	body += 0.4 * np.sin(glide_phase(_exp_sweep(f * 3.4, f * 1.6, n, 0.05))) * decay_env(n, 0.25, 0.001)
	beater = bandpass(white(rng, n), 300.0, 2500.0, 2) * decay_env(n, 0.02, 0.0005) * 0.55
	return (body + beater) * gain


def anvil(rng, f, dur=1.6, gain=1.0):
	n = n_of(dur)
	t = np.arange(n) / SR
	ratios = [1.0, 2.76, 5.4, 8.93, 13.3]
	amps = [1.0, 0.6, 0.35, 0.2, 0.1]
	taus = [0.9, 0.5, 0.3, 0.16, 0.08]
	out = np.zeros(n)
	for r, a, tau in zip(ratios, amps, taus):
		out += a * np.sin(2 * np.pi * f * r * t + rng.uniform(0, 6.28)) * np.exp(-t / tau)
	out += bandpass(white(rng, n), 800.0, 7000.0, 2) * decay_env(n, 0.006, 0.0002) * 0.6
	return out * gain * np.minimum(1.0, t / 0.0015)


def bone_clack(rng, gain=1.0):
	n = n_of(0.16)
	t = np.arange(n) / SR
	out = np.sin(2 * np.pi * (860.0 + rng.uniform(-60, 60)) * t) * np.exp(-t / 0.02) + 0.5 * np.sin(2 * np.pi * 1730.0 * t) * np.exp(-t / 0.012)
	out += bandpass(white(rng, n), 1500.0, 6000.0, 1) * decay_env(n, 0.004, 0.0001) * 0.7
	return out * gain


def shaker(rng, dur=0.5, gain=1.0):
	n = n_of(dur)
	t = np.arange(n) / SR
	env = np.exp(-((t - dur * 0.35) / (dur * 0.25)) ** 2)
	return bandpass(white(rng, n), 3500.0, 9000.0, 2) * env * gain * 0.6


def scrape(rng, dur=3.0, gain=1.0, f=380.0):
	"""Metal scrape: resonant noise with a slowly gliding centre."""
	n = n_of(dur)
	t = np.arange(n) / SR
	sig = bandpass(white(rng, n), 900.0, 4800.0, 2) * (0.5 + 0.5 * np.abs(lowpass(white(rng, n), 7.0, 1)) / 0.1).clip(0, 1.4)
	tone = np.sin(glide_phase(f * (1.0 + 0.15 * np.sin(2 * np.pi * 0.33 * t)))) * 0.25
	return (sig * 0.5 + tone) * swell(n, dur * 0.4, dur * 0.4) * gain


# --- Rendering helpers ---------------------------------------------------------------

def wet(stereo, name, amount, rt_low=3.4, rt_high=1.0, seconds=4.5):
	"""Add a cold canyon reverb tail to a stereo stem."""
	rl = rng_for("music-ir:" + name)
	ir_l = canyon_ir(rl, seconds, rt_low, rt_high, ((0.23, 0.15), (0.51, 0.10), (0.9, 0.07)), 0.02)
	ir_r = canyon_ir(rl, seconds, rt_low, rt_high, ((0.27, 0.15), (0.57, 0.10), (0.97, 0.07)), 0.02)
	n = len(stereo)
	out = stereo.copy()
	out[:, 0] += convolve(stereo[:, 0], ir_l)[:n] * amount
	out[:, 1] += convolve(stereo[:, 1], ir_r)[:n] * amount
	return out


def loop_stem(buf, length):
	"""buf is length+TAIL long: fold the tail over the head for a seamless loop."""
	return make_loop(buf, TAIL) if len(buf) == n_of(length + TAIL) else buf


def new_buffer(length):
	return np.zeros((n_of(length + TAIL), 2))


def beats(bpm, count):
	return 60.0 / bpm * count


# --- Biome scores ----------------------------------------------------------------------

def _stem_widowpine(name, rng, kind):
	bpm = 54.0
	b = 60.0 / bpm
	length = b * 32
	buf = new_buffer(length)
	if kind == "drone":
		for f_name, start, dur in (("A1", 0, 16), ("E2", 0, 16), ("A1", 16, 16), ("D2", 16, 16)):
			v = pad_voice(rng, hz(f_name), b * dur + 2.5, 10, 1.6, 0.0035)
			add_at(buf, pan(v, rng.uniform(-0.4, 0.4)), start * b - 1.0 if start else 0.0, 0.16)
		for f_name, start in (("A3", 3), ("E4", 8), ("C4", 19), ("E4", 25)):
			v = pad_voice(rng, hz(f_name), b * 9, 6, 2.0, 0.005)
			add_at(buf, pan(v, rng.uniform(-0.8, 0.8)), start * b, 0.05)
		wind = lowpass(colored(rng, n_of(length + TAIL), 1.5), 700.0, 2) * (0.5 + 0.5 * np.sin(np.linspace(0, 2 * np.pi * 2, n_of(length + TAIL), endpoint=False)))
		buf += np.stack([wind, np.roll(wind, 700)], axis=1) * 0.07
	elif kind == "motif":
		phrase = [(0, "E5"), (2.5, "C5"), (6, "A4"), (8, "D5"), (11.5, "E5"), (16, "G5"), (18.5, "E5"), (22, "D5"), (24, "C5"), (27.5, "A4")]
		for bt, note in phrase:
			f = hz(note)
			add_at(buf, pan(bell(rng, f, 9.0, 3.0), rng.uniform(-0.7, 0.7)), bt * b, 0.30)
			if bt in (11.5, 27.5):
				add_at(buf, pan(bell(rng, f * 0.5, 9.0, 4.0), 0.0), bt * b + 0.02, 0.12)
	elif kind == "tension":
		for start, f_name in ((0, "Bb2"), (8, "A2"), (16, "Bb2"), (24, "Ab2")):
			v = saw_horn(rng, hz(f_name), b * 9, 900.0, 0.004, 3.5, 3.5, 0.35) + 0.7 * saw_horn(rng, hz("A2") * 1.0, b * 9, 900.0, 0.004, 3.5, 3.5, 0.35)
			add_at(buf, pan(v, rng.uniform(-0.5, 0.5)), start * b, 0.055)
		for i in range(32):
			if i % 2 == 0:
				add_at(buf, pan(frame_drum(rng, 46.0, 1.0), 0.0), i * b, 0.32 if i % 4 == 0 else 0.18)
		for at in (5.2, 13.1, 21.7, 28.9):
			add_at(buf, pan(scrape(rng, 3.0, 1.0), rng.uniform(-0.6, 0.6)), at * b, 0.03)
	elif kind == "combat":
		pattern = [(0, 1.0, 62), (1.5, 0.55, 62), (2, 0.8, 78), (3, 0.9, 62), (3.5, 0.5, 78)]
		for bar in range(8):
			for off, g, f in pattern:
				add_at(buf, pan(frame_drum(rng, f, 0.9), 0.0), (bar * 4 + off) * b * 0.5, 0.55 * g)
		# Iron hits and dissonant stabs on the bar lines.
		for bar in range(8):
			add_at(buf, pan(anvil(rng, hz("A3") * (1.0 if bar % 2 == 0 else 1.0595), 1.2), rng.uniform(-0.5, 0.5)), bar * 4 * b * 0.5 + 0.0, 0.16)
			if bar % 2 == 1:
				stab = saw_horn(rng, hz("A2"), 1.4, 2600.0, 0.0, 0.03, 0.9) + saw_horn(rng, hz("Bb2"), 1.4, 2600.0, 0.0, 0.03, 0.9) + saw_horn(rng, hz("E3"), 1.4, 2600.0, 0.0, 0.03, 0.9)
				add_at(buf, pan(saturate(stab, 1.2), 0.0), (bar * 4 + 2) * b * 0.5, 0.11)
		v = saw_horn(rng, hz("A1"), length, 500.0, 0.0, 0.5, 1.0, 0.0)
		add_at(buf, pan(v, 0.0), 0.0, 0.16)
	return length, buf


def _stem_carrion(name, rng, kind):
	bpm = 60.0
	b = 60.0 / bpm
	length = b * 32
	buf = new_buffer(length)
	if kind == "drone":
		for start, notes in ((0, ("D2", "A2")), (16, ("D2", "Bb2"))):
			for f_name in notes:
				v = choir_note(rng, hz(f_name), b * 17.5, F_OO, 0.3)
				add_at(buf, pan(v, rng.uniform(-0.4, 0.4)), start * b, 0.30)
		sub = pad_voice(rng, hz("D1"), length + 2.0, 6, 1.5, 0.003)
		add_at(buf, pan(sub, 0.0), 0.0, 0.18)
	elif kind == "motif":
		phrase = [(0, "Eb5"), (3, "D5"), (5, "C5"), (8, "D5"), (12, "A4"), (16, "Bb4"), (19, "A4"), (21, "G4"), (24, "A4"), (28, "D4")]
		for bt, note in phrase:
			add_at(buf, pan(bell(rng, hz(note), 8.0, 2.4), rng.uniform(-0.6, 0.6)), bt * b, 0.26)
		for i, at in enumerate((0, 8, 16, 24)):
			add_at(buf, pan(war_drum(rng, 42.0, 2.5), 0.0), at * b, 0.34)
		for at in (2, 6, 10, 14, 18, 22, 26, 30):
			add_at(buf, pan(bone_clack(rng), rng.uniform(-0.8, 0.8)), at * b + 0.5, 0.10)
	elif kind == "tension":
		for start, f_name in ((0, "Ab2"), (8, "D2"), (16, "Ab2"), (24, "G2")):
			v = saw_horn(rng, hz(f_name), b * 9, 1100.0, 0.005, 3.0, 3.0, 0.4) + 0.8 * saw_horn(rng, hz("D2"), b * 9, 1100.0, 0.005, 3.0, 3.0, 0.4)
			add_at(buf, pan(v, rng.uniform(-0.4, 0.4)), start * b, 0.05)
		for i in range(64):
			add_at(buf, pan(shaker(rng, 0.4), rng.uniform(-0.9, 0.9)), i * b * 0.5, 0.05 if i % 2 else 0.09)
		for i in range(8):
			add_at(buf, pan(frame_drum(rng, 58.0, 1.2), 0.0), (i * 4) * b, 0.36)
			add_at(buf, pan(frame_drum(rng, 70.0, 1.0), 0.2), (i * 4 + 1.5) * b, 0.2)
	elif kind == "combat":
		pat = [(0, 1.0, 56), (0.75, 0.5, 70), (1.5, 0.8, 56), (2.0, 0.7, 70), (2.5, 0.9, 56), (3.25, 0.6, 70)]
		for bar in range(8):
			for off, g, f in pat:
				add_at(buf, pan(war_drum(rng, f, 1.2) if off in (0, 1.5) else frame_drum(rng, f + 10, 0.8), 0.0), (bar * 4 + off) * b, 0.5 * g)
			for k in range(8):
				add_at(buf, pan(bone_clack(rng), rng.uniform(-0.8, 0.8)), (bar * 4 + k * 0.5 + 0.25) * b, 0.09)
		for bar in (1, 3, 5, 7):
			chant = choir_note(rng, hz("D3"), 1.6, F_AH, 0.45) + choir_note(rng, hz("Eb3"), 1.6, F_AH, 0.45)
			add_at(buf, pan(saturate(chant, 1.4), 0.0), bar * 4 * b, 0.20)
		for bar in (0, 4):
			add_at(buf, pan(anvil(rng, hz("D4"), 1.6), 0.4), bar * 4 * b + 2.0 * b, 0.11)
	return length, buf


def _stem_iron(name, rng, kind):
	bpm = 66.0
	b = 60.0 / bpm
	length = b * 32
	buf = new_buffer(length)
	if kind == "drone":
		for f_name, g in (("C1", 0.30), ("Db1", 0.16), ("G1", 0.20), ("C2", 0.12)):
			v = pad_voice(rng, hz(f_name), length + 3.0, 8, 0.9, 0.006, 0.05)
			add_at(buf, pan(v, rng.uniform(-0.3, 0.3)), 0.0, g)
		grind = resonate(white(rng, n_of(length + TAIL)), 218.0, 30.0)
		grind = grind / (np.std(grind) + 1e-9) * (0.5 + 0.5 * np.sin(np.linspace(0, 2 * np.pi * 3, n_of(length + TAIL), endpoint=False)))
		buf += np.stack([grind, np.roll(grind, 300)], axis=1) * 0.03
	elif kind == "motif":
		for bt, note in ((0, "C3"), (8, "Db3"), (16, "C3"), (24, "G2")):
			add_at(buf, pan(bell(rng, hz(note), 12.0, 6.0), 0.0), bt * b, 0.42)
			add_at(buf, pan(bell(rng, hz(note) * 2.01, 8.0, 3.5), rng.uniform(-0.5, 0.5)), bt * b + 0.02, 0.14)
		for bt in (4, 12, 20, 28):
			add_at(buf, pan(anvil(rng, hz("C4"), 2.2), rng.uniform(-0.4, 0.4)), bt * b, 0.06)
	elif kind == "tension":
		for start, notes in ((0, ("C2", "Db2", "Gb2")), (16, ("C2", "B1", "F2"))):
			for f_name in notes:
				v = saw_horn(rng, hz(f_name), b * 17, 800.0, 0.003, 3.0, 3.0, 0.5)
				add_at(buf, pan(v, rng.uniform(-0.5, 0.5)), start * b, 0.06)
		for i in range(16):
			add_at(buf, pan(war_drum(rng, 40.0, 1.4), 0.0), i * 2 * b, 0.32 if i % 2 == 0 else 0.20)
		for at in (3, 11, 19, 27):
			add_at(buf, pan(anvil(rng, hz("Gb3"), 1.6), rng.uniform(-0.7, 0.7)), at * b, 0.05)
	elif kind == "combat":
		for bar in range(8):
			base = bar * 4 * b
			add_at(buf, pan(war_drum(rng, 46.0, 1.4), 0.0), base, 0.62)
			add_at(buf, pan(war_drum(rng, 46.0, 1.4), 0.0), base + 2.5 * b, 0.5)
			add_at(buf, pan(anvil(rng, hz("C3"), 1.4), rng.uniform(-0.3, 0.3)), base + 1.0 * b, 0.20)
			add_at(buf, pan(anvil(rng, hz("Gb3"), 1.4), rng.uniform(-0.3, 0.3)), base + 3.0 * b, 0.16)
			for k in range(4):
				add_at(buf, pan(frame_drum(rng, 88.0, 0.5), rng.uniform(-0.5, 0.5)), base + (k + 0.5) * b, 0.16)
		for bar in (1, 3, 5, 7):
			stab = sum_clips(saw_horn(rng, hz("C2"), 2.0, 2200.0, 0.0, 0.04, 1.2), saw_horn(rng, hz("Db2"), 2.0, 2200.0, 0.0, 0.04, 1.2), saw_horn(rng, hz("Gb2"), 2.0, 2200.0, 0.0, 0.04, 1.2))
			add_at(buf, pan(saturate(stab, 1.4), 0.0), (bar * 4 + 0.0) * b, 0.12)
	return length, buf


BIOMES = {
	"widowpine": (_stem_widowpine, {"drone": 0.22, "motif": 0.5, "tension": 0.35, "combat": 0.3}),
	"carrion": (_stem_carrion, {"drone": 0.22, "motif": 0.4, "tension": 0.32, "combat": 0.3}),
	"iron_crown": (_stem_iron, {"drone": 0.24, "motif": 0.45, "tension": 0.35, "combat": 0.3}),
}


# --- Boss ---------------------------------------------------------------------------------

def _stem_boss(phase, rng, kind):
	params = {1: (72.0, "C"), 2: (96.0, "C"), 3: (128.0, "C")}[phase]
	bpm = params[0]
	b = 60.0 / bpm
	bars = 16 if phase == 3 else 12
	length = b * 4 * bars if phase != 2 else b * 4 * 12
	buf = new_buffer(length)
	total_beats = length / b
	if kind == "base":
		if phase == 1:
			# Iron Hide: slow heavy horn stabs over a rumbling sub.
			for bar in range(int(total_beats // 4)):
				root = ("C2", "C2", "Db2", "C2")[bar % 4]
				stab = sum_clips(saw_horn(rng, hz(root), b * 3.4, 1800.0, 0.004, 0.1, 1.2), saw_horn(rng, hz(root) * 1.4983, b * 3.4, 1800.0, 0.004, 0.1, 1.2), 0.6 * saw_horn(rng, hz(root) * 0.5, b * 3.4, 900.0, 0.0, 0.08, 1.2))
				add_at(buf, pan(saturate(stab, 1.6), 0.0), bar * 4 * b, 0.13)
			sub = pad_voice(rng, hz("C1"), length + 2.0, 6, 1.2, 0.004)
			add_at(buf, pan(sub, 0.0), 0.0, 0.22)
		elif phase == 2:
			# Call the Warpack: howling choir glissandi over a driving ostinato.
			for bar in range(0, int(total_beats // 4), 2):
				chant = sum_clips(choir_note(rng, hz("G3"), b * 6.5, F_AH, 0.5), choir_note(rng, hz("Db4"), b * 6.5, F_AH, 0.5), choir_note(rng, hz("C4") * 1.02, b * 6.5, F_AH, 0.5))
				add_at(buf, pan(saturate(chant, 1.3), rng.uniform(-0.4, 0.4)), bar * 4 * b, 0.22)
			for i in range(int(total_beats * 2)):
				note = ("C2", "C2", "Eb2", "C2", "Db2", "C2", "G2", "C2")[i % 8]
				v = saw_horn(rng, hz(note), b * 0.45, 1500.0, 0.0, 0.01, 0.15)
				add_at(buf, pan(saturate(v, 1.5), 0.0), i * b * 0.5, 0.11)
		else:
			# Red Horn: blaring horn calls and a tolling bell that quickens.
			motif = [(0, "C3", 3.5), (4, "Eb3", 3.5), (8, "Db3", 3.5), (12, "C3", 2.0), (14, "G2", 1.9)]
			for rep in range(int(total_beats // 16)):
				for bt, note, d in motif:
					horn = sum_clips(saw_horn(rng, hz(note), b * d, 3200.0, 0.006, 0.12, 0.6), saw_horn(rng, hz(note) * 2.0, b * d, 3000.0, 0.006, 0.12, 0.6) * 0.5, saw_horn(rng, hz(note) * 0.5, b * d, 1200.0, 0.004, 0.1, 0.6) * 0.8)
					add_at(buf, pan(saturate(horn, 1.8), 0.0), (rep * 16 + bt) * b, 0.12)
			toll = 0.0
			gap = 4.0
			while toll < total_beats - 1:
				add_at(buf, pan(bell(rng, hz("C4"), 6.0, 3.0), 0.0), toll * b, 0.22)
				toll += gap
				gap = max(1.0, gap * 0.82)
			sub = pad_voice(rng, hz("C1"), length + 2.0, 6, 1.2, 0.004)
			add_at(buf, pan(sub, 0.0), 0.0, 0.2)
	else:
		for bar in range(int(total_beats // 4)):
			base = bar * 4 * b
			if phase == 1:
				add_at(buf, pan(war_drum(rng, 44.0, 1.8), 0.0), base, 0.7)
				add_at(buf, pan(war_drum(rng, 44.0, 1.8), 0.0), base + 2.0 * b, 0.55)
				add_at(buf, pan(anvil(rng, hz("C3"), 1.6), 0.3), base + 1.0 * b, 0.14)
				add_at(buf, pan(anvil(rng, hz("Db3"), 1.6), -0.3), base + 3.0 * b, 0.12)
			elif phase == 2:
				for k in range(8):
					f = 46.0 if k % 4 == 0 else 74.0
					drum = war_drum(rng, f, 1.0) if k % 4 == 0 else frame_drum(rng, f, 0.7)
					add_at(buf, pan(drum, 0.0), base + k * b * 0.5, 0.6 if k % 4 == 0 else 0.34)
				for k in (1, 3):
					add_at(buf, pan(anvil(rng, hz("C3") * (1 + 0.06 * (bar % 2)), 1.2), rng.uniform(-0.4, 0.4)), base + k * b, 0.13)
				for k in range(8):
					add_at(buf, pan(bone_clack(rng), rng.uniform(-0.9, 0.9)), base + (k + 0.5) * b * 0.5, 0.08)
			else:
				for k in range(16):
					f = 46.0 if k % 4 == 0 else 72.0
					drum = war_drum(rng, f, 0.9) if k % 4 == 0 else frame_drum(rng, f, 0.5)
					add_at(buf, pan(drum, 0.0), base + k * b * 0.25, (0.65 if k % 4 == 0 else 0.22 if k % 2 else 0.34))
				for k in (1, 3):
					add_at(buf, pan(anvil(rng, hz("C3"), 1.2), rng.uniform(-0.3, 0.3)), base + k * b, 0.16)
				if bar % 2 == 1:
					add_at(buf, pan(shaker(rng, 0.8), 0.6), base + 3.5 * b, 0.12)
	return length, buf


# --- Victory and death ------------------------------------------------------------------------

def victory(rng):
	"""Warm A-major resolution: a choir swell and nine bells, one for every name."""
	length = 46.0
	buf = new_buffer(length)
	for i, (f_name, start) in enumerate((("A2", 0.0), ("E3", 0.0), ("A3", 4.0), ("Db4", 8.0), ("E4", 8.0), ("A2", 20.0), ("D3", 20.0), ("Gb3", 20.0), ("A3", 20.0))):
		v = choir_note(rng, hz(f_name), 24.0, F_OO if i % 2 == 0 else F_AH, 0.25)
		add_at(buf, pan(v, rng.uniform(-0.5, 0.5)), start, 0.22)
	scale = ["A4", "B4", "Db5", "E5", "Gb5", "A5", "B5", "Db6", "E6"]
	for i, note in enumerate(scale):
		add_at(buf, pan(bell(rng, hz(note), 9.0, 3.6), -0.7 + 1.4 * i / 8.0), 4.0 + i * 2.6, 0.30)
	add_at(buf, pan(bell(rng, hz("A2"), 14.0, 8.0), 0.0), 29.0, 0.6)
	add_at(buf, pan(bell(rng, hz("A3"), 14.0, 6.0), 0.0), 29.0, 0.3)
	sub = pad_voice(rng, hz("A1"), 30.0, 5, 1.4, 0.003)
	add_at(buf, pan(sub, 0.0), 0.0, 0.12)
	out = wet(buf, "victory", 0.55, 4.0, 1.4)
	fade = np.ones(len(out))
	fade[: n_of(2.0)] = np.linspace(0, 1, n_of(2.0))
	fade[-n_of(5.0):] = np.linspace(1, 0, n_of(5.0)) ** 2
	return out * fade[:, None]


def death(rng):
	buf = np.zeros((n_of(9.0), 2))
	add_at(buf, pan(bell(rng, hz("A2"), 9.0, 4.0), 0.0), 0.15, 0.6)
	add_at(buf, pan(bell(rng, hz("Eb3"), 9.0, 3.0), 0.0), 0.3, 0.24)
	low = saw_horn(rng, hz("A1"), 8.0, 500.0, 0.003, 0.8, 4.0, 0.0)
	add_at(buf, pan(low, 0.0), 0.0, 0.16)
	f = np.linspace(hz("A2"), hz("A2") * 0.7, n_of(8.0))
	fall = np.sin(glide_phase(f)) * swell(n_of(8.0), 0.5, 6.0)
	add_at(buf, pan(fall, 0.0), 0.5, 0.12)
	out = wet(buf, "death", 0.6, 3.5, 1.0, 3.0)
	fade = np.ones(len(out))
	fade[-n_of(3.0):] = np.linspace(1, 0, n_of(3.0)) ** 2
	return out * fade[:, None]


def render_all(out_dir):
	import os

	from render import stats, write_ogg

	entries = {}

	def emit(name, x, bus="music", loop=True, peak_db=-6.0):
		x = x - x.mean(axis=0, keepdims=True)
		x = x * (10.0 ** (peak_db / 20.0) / np.max(np.abs(x)))
		x = seam_fade(x) if loop else x
		write_ogg(os.path.join(out_dir, name + ".ogg"), x, "160k")
		peak, rms = stats(x)
		entries[name] = {"files": [name + ".ogg"], "bus": bus, "fmt": "ogg", "loop": loop, "target_peak_db": peak_db,
			"clips": [{"peak": peak, "rms": rms, "seconds": len(x) / SR}]}
		print("%-24s %s %.1fs peak %.1f dB rms %.1f dB" % (name, "loop" if loop else "once", len(x) / SR, 20 * np.log10(peak), 20 * np.log10(rms)))

	for biome, (fn, levels) in BIOMES.items():
		for kind, level in levels.items():
			rng = rng_for("music:%s:%s" % (biome, kind))
			length, buf = fn(biome, rng, kind)
			buf = wet(buf, "%s-%s" % (biome, kind), 0.35 if kind in ("drone", "motif") else 0.22)
			stem = loop_stem(buf, length)
			emit("music_%s_%s" % (biome, kind), stem, loop=True, peak_db=-6.0)
	for phase in (1, 2, 3):
		for kind in ("base", "perc"):
			rng = rng_for("music:boss%d:%s" % (phase, kind))
			length, buf = _stem_boss(phase, rng, kind)
			buf = wet(buf, "boss%d-%s" % (phase, kind), 0.2)
			emit("music_boss%d_%s" % (phase, kind), loop_stem(buf, length), loop=True, peak_db=-6.0)
	emit("music_victory", victory(rng_for("music:victory")), loop=False, peak_db=-6.0)
	emit("music_death", death(rng_for("music:death")), loop=False, peak_db=-6.0)
	return entries
