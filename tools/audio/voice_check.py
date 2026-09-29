"""Report duration, median pitch, level and leading/trailing silence for raw voice takes.

Usage: python3 tools/audio/voice_check.py <raw_dir>
"""
import os
import sys
import wave

import numpy as np


def median_f0(x, sr):
	fl = int(0.04 * sr)
	vals = []
	for i in range(0, len(x) - fl * 2, fl // 2):
		s = x[i : i + fl * 2]
		if np.sqrt((s ** 2).mean()) < 0.02:
			continue
		s = s - s.mean()
		ac = np.correlate(s, s, "full")[len(s) - 1 :]
		lo, hi = int(sr / 320), int(sr / 55)
		k = np.argmax(ac[lo:hi]) + lo
		if ac[k] / ac[0] > 0.5:
			vals.append(sr / k)
	return float(np.median(vals)) if vals else 0.0


def main(raw_dir):
	for f in sorted(os.listdir(raw_dir)):
		if not f.endswith(".wav"):
			continue
		with wave.open(os.path.join(raw_dir, f)) as fh:
			sr, ch = fh.getframerate(), fh.getnchannels()
			x = np.frombuffer(fh.readframes(fh.getnframes()), dtype="<i2").astype(float) / 32768.0
		x = x.reshape(-1, ch).mean(axis=1)
		gate = 0.01
		idx = np.nonzero(np.abs(x) > gate)[0]
		lead = idx[0] / sr if len(idx) else 0.0
		trail = (len(x) - idx[-1]) / sr if len(idx) else 0.0
		print("%-20s sr %5d %5.2fs f0 %4.0f Hz peak %5.1f dB rms %5.1f dB lead %.2fs trail %.2fs" % (f, sr, len(x) / sr, median_f0(x, sr), 20 * np.log10(np.abs(x).max() + 1e-9), 20 * np.log10(np.sqrt((x ** 2).mean()) + 1e-9), lead, trail))


if __name__ == "__main__":
	main(sys.argv[1])
