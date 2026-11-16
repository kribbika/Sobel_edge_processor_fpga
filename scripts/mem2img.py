#!/usr/bin/env python3
"""
mem2img.py - turn a .mem file (e.g. sim_edge_out.mem written by the
testbench with $writememh) back into a PNG so you can look at it.
Also converts the testbench's VGA capture (.pgm) to PNG.

  python mem2img.py sim_edge_out.mem -o sim_edge.png
  python mem2img.py vga_frame.pgm   -o vga_frame.png
  python mem2img.py sim_edge_out.mem --compare expected_edge.mem
"""
import argparse

import numpy as np
from PIL import Image


def read_mem(path, n):
    vals = []
    with open(path) as f:
        for line in f:
            line = line.split("//")[0].strip()
            if not line or line.startswith("@"):
                continue
            for tok in line.split():
                vals.append(0 if "x" in tok.lower() else int(tok, 16))
    if len(vals) < n:
        raise SystemExit(f"{path}: only {len(vals)} values, expected {n}")
    return np.array(vals[:n], dtype=np.uint8)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("-o", "--out", default=None)
    ap.add_argument("--width", type=int, default=320)
    ap.add_argument("--height", type=int, default=240)
    ap.add_argument("--compare", help="golden .mem to diff against")
    a = ap.parse_args()

    if a.input.lower().endswith((".pgm", ".ppm")):
        img = Image.open(a.input)
        if img.mode == "I":                    # 4-bit VGA data, max value 15
            img = Image.fromarray((np.asarray(img) * 17).astype(np.uint8))
        out = a.out or a.input.rsplit(".", 1)[0] + ".png"
        img.save(out)
        print(f"wrote {out}")
        return

    n = a.width * a.height
    arr = read_mem(a.input, n).reshape(a.height, a.width)
    out = a.out or a.input.rsplit(".", 1)[0] + ".png"
    Image.fromarray(arr).save(out)
    print(f"wrote {out}")

    if a.compare:
        ref = read_mem(a.compare, n).reshape(a.height, a.width)
        diff = np.count_nonzero(arr != ref)
        print(f"mismatching pixels: {diff} / {n}")
        raise SystemExit(0 if diff == 0 else 1)


if __name__ == "__main__":
    main()
