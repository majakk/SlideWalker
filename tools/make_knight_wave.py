#!/usr/bin/env python3
"""Derive two "wave" frames for the Brackeys knight (CC0) from its first idle
frame: a raised arm beside the helmet with an open hand, upright in frame 1
and tipped outward in frame 2. Writes assets/brackeys/knight_wave.png (64x32).

Dev tool; needs ImageMagick (`magick`). Run from the project root:
    python3 tools/make_knight_wave.py
"""
import subprocess

SRC = "assets/brackeys/knight.png"
OUT = "assets/brackeys/knight_wave.png"

PALETTE = {"K": "#0E0D0E", "G": "#7C776F", "g": "#B3AAA1"}

# Rows of the raised arm, listed as (row, first column, pixels) in 32x32
# frame coordinates. The helmet's right outline (column 21) doubles as the
# arm's left outline where they touch.
ARM_UP = [
    (8, 22, "KK"),
    (9, 21, "KggK"),
    (10, 21, "KggK"),
    (11, 21, "KggK"),
    (12, 21, "KGGK"),
    (13, 21, "KGGK"),
    (14, 21, "KGGK"),
    (15, 21, "KGGK"),
    (16, 21, "KGGK"),
    (17, 21, "KGGK"),
    (18, 21, "KGGK"),
    (19, 21, "KGGK"),
    (20, 21, "KGGK"),
    (21, 21, "KKKK"),
]
# Hand and wrist tipped one pixel outward.
ARM_OUT = [
    (8, 23, "KK"),
    (9, 22, "KggK"),
    (10, 22, "KggK"),
    (11, 22, "KggK"),
    (12, 21, "KKGGK"),
    (13, 21, "KGGKK"),
] + ARM_UP[6:]


def frame_ops(arm, x_offset):
    ops = []
    for row, col, pixels in arm:
        for i, ch in enumerate(pixels):
            ops += ["-fill", PALETTE[ch], "-draw", f"point {x_offset + col + i},{row}"]
    return ops


def main():
    cmd = ["magick", "-size", "64x32", "xc:none",
           "(", SRC, "-crop", "32x32+0+0", "+repage", ")", "-geometry", "+0+0", "-composite",
           "(", SRC, "-crop", "32x32+0+0", "+repage", ")", "-geometry", "+32+0", "-composite"]
    cmd += frame_ops(ARM_UP, 0) + frame_ops(ARM_OUT, 32) + [OUT]
    subprocess.run(cmd, check=True)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
