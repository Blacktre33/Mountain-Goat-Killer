"""Print a short-time RMS level profile (dB re peak) of rendered files.

Usage: python3 tools/audio/profile.py FILE [FILE...] [--win-ms 50]
"""
import argparse
import sys

import numpy as np

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from analyze import load  # noqa: E402


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("files", nargs="+")
	ap.add_argument("--win-ms", type=float, default=50.0)
	ap.add_argument("--max-bins", type=int, default=40)
	args = ap.parse_args()
	for path in args.files:
		x, sr = load(path)
		mono = x.mean(axis=1)
		peak = np.max(np.abs(mono)) + 1e-12
		win = int(args.win_ms * sr / 1000)
		bins = len(mono) // win
		step = max(1, bins // args.max_bins)
		row = []
		for b in range(0, bins, step):
			seg = mono[b * win : (b + step) * win]
			row.append("%3.0f" % (20 * np.log10(np.sqrt(np.mean(seg ** 2)) / peak + 1e-9)))
		print(path.rsplit("/", 1)[-1], "(each bin %.0f ms):" % (args.win_ms * step))
		print(" ".join(row))


if __name__ == "__main__":
	main()
