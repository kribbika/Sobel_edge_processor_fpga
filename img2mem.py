#!/usr/bin/env python3
"""
img2mem.py - convert any image into a Verilog $readmemh .mem file for the
Nexys A7 Sobel project, and produce a bit-exact golden Sobel reference.

Outputs (default names):
  image.mem            8-bit grayscale, one hex byte per line, raster order
  expected_edge.mem    golden Sobel magnitude (same algorithm as the RTL)
Optional (only with --preview):
  preview_gray.png     what the FPGA will see
  preview_edge.png     what the FPGA should display

Examples:
  python img2mem.py photo.jpg
  python img2mem.py photo.jpg --fit crop -o ../mem/image.mem --golden ../mem/expected_edge.mem
  python img2mem.py --test-pattern            # no input image needed
  python img2mem.py photo.jpg --preview       # also write preview PNGs

Requires: pip install pillow numpy
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageOps


# ----------------------------------------------------------------------------
# Image preparation
# ----------------------------------------------------------------------------
def to_gray_resized(path, width, height, fit):
    img = Image.open(path)
    img = ImageOps.exif_transpose(img)          # honour phone-camera rotation
    img = img.convert("RGB")

    if fit == "stretch":
        img = img.resize((width, height), Image.LANCZOS)
    elif fit == "crop":
        img = ImageOps.fit(img, (width, height), Image.LANCZOS)
    else:  # pad (letterbox, black bars)
        img = ImageOps.pad(img, (width, height), Image.LANCZOS, color=(0, 0, 0))

    # ITU-R BT.601 luma, integer maths
    rgb = np.asarray(img, dtype=np.uint32)
    gray = (77 * rgb[..., 0] + 150 * rgb[..., 1] + 29 * rgb[..., 2] + 128) >> 8
    return np.clip(gray, 0, 255).astype(np.uint8)


def test_pattern(width, height):
    """Synthetic scene with edges in every direction plus soft gradients."""
    # horizontal gradient background
    grad = np.tile(np.linspace(30, 120, width, dtype=np.uint8), (height, 1))
    img = Image.fromarray(grad)
    d = ImageDraw.Draw(img)
    s = width / 320.0
    d.rectangle([20 * s, 20 * s, 120 * s, 100 * s], fill=230)
    d.ellipse([170 * s, 25 * s, 290 * s, 135 * s], fill=200, outline=255, width=3)
    d.polygon([(40 * s, 220 * s), (110 * s, 120 * s), (160 * s, 220 * s)], fill=180)
    d.line([(180 * s, 160 * s), (300 * s, 225 * s)], fill=255, width=4)
    for i in range(6):                          # vertical bars
        x = int((190 + i * 18) * s)
        d.rectangle([x, 165 * s, x + 8 * s, 200 * s], fill=10 if i % 2 else 250)
    d.text((24 * s, 108 * s), "NEXYS A7 SOBEL", fill=255)
    return np.asarray(img, dtype=np.uint8)


# ----------------------------------------------------------------------------
# Golden model -- must match rtl/sobel_engine.v exactly
# ----------------------------------------------------------------------------
def sobel_golden(gray):
    p = gray.astype(np.int32)
    h, w = p.shape
    out = np.zeros_like(p)
    tl, tc, tr = p[:-2, :-2], p[:-2, 1:-1], p[:-2, 2:]
    ml,     mr = p[1:-1, :-2],               p[1:-1, 2:]
    bl, bc, br = p[2:, :-2],  p[2:, 1:-1],  p[2:, 2:]
    gx = (tr + 2 * mr + br) - (tl + 2 * ml + bl)
    gy = (bl + 2 * bc + br) - (tl + 2 * tc + tr)
    out[1:-1, 1:-1] = np.minimum(np.abs(gx) + np.abs(gy), 255)
    return out.astype(np.uint8)              # border rows/cols stay 0


def write_mem(path, arr):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w") as f:
        f.write("\n".join(f"{v:02x}" for v in arr.flatten()))
        f.write("\n")


# ----------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", nargs="?", help="input image (jpg/png/bmp/...)")
    ap.add_argument("--test-pattern", action="store_true",
                    help="generate a synthetic test image instead of reading one")
    ap.add_argument("-o", "--out", default="image.mem")
    ap.add_argument("--golden", default="expected_edge.mem")
    ap.add_argument("--width", type=int, default=320)
    ap.add_argument("--height", type=int, default=240)
    ap.add_argument("--fit", choices=["pad", "crop", "stretch"], default="pad",
                    help="how to handle aspect ratio (default: pad)")
    ap.add_argument("--preview", action="store_true",
                    help="also write preview_gray.png / preview_edge.png")
    ap.add_argument("--preview-dir", default=".",
                    help="where to write the preview PNGs (with --preview)")
    a = ap.parse_args()

    if a.test_pattern:
        gray = test_pattern(a.width, a.height)
    elif a.input:
        gray = to_gray_resized(a.input, a.width, a.height, a.fit)
    else:
        ap.error("give an input image or --test-pattern")

    edge = sobel_golden(gray)
    write_mem(a.out, gray)
    write_mem(a.golden, edge)

    if a.preview:
        os.makedirs(a.preview_dir, exist_ok=True)
        Image.fromarray(gray).save(os.path.join(a.preview_dir, "preview_gray.png"))
        Image.fromarray(edge).save(os.path.join(a.preview_dir, "preview_edge.png"))
        print(f"wrote previews in {os.path.abspath(a.preview_dir)}")

    n = a.width * a.height
    print(f"{a.width}x{a.height} = {n} pixels  ({n * 8 / 1024:.0f} Kbit per buffer)")
    print(f"wrote {a.out}  (image)")
    print(f"wrote {a.golden}  (golden Sobel)")
    if a.width != 320 or a.height != 240:
        print(f"NOTE: non-default size -> set `define IMG_W {a.width} and "
          f"`define IMG_H {a.height} in sobel_cfg.vh, then rebuild.", file=sys.stderr)


if __name__ == "__main__":
    main()