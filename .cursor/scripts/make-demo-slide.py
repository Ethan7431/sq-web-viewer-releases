#!/usr/bin/env python3
"""Generate a small synthetic, OpenSlide-compatible tiled pyramidal TIFF.

This gives the SQ Web Viewer something to display in a fresh environment. The
output is a plain tiled RGB TIFF with several downsampled levels, which
OpenSlide opens as the ``generic-tiff`` vendor.
"""
import os
import sys

try:
    import numpy as np
    import tifffile
except Exception as exc:  # pragma: no cover - guarded by caller
    print(f"make-demo-slide: dependencies unavailable ({exc}); skipping", file=sys.stderr)
    sys.exit(0)

BASE = int(os.environ.get("SQWV_DEMO_BASE", "4096"))
TILE = 256
slides_dir = os.environ.get("SQWV_SLIDES_DIR", os.path.join(os.getcwd(), "slides"))
os.makedirs(slides_dir, exist_ok=True)
out = os.path.join(slides_dir, "demo-slide.tif")

if os.path.exists(out):
    print(f"make-demo-slide: {out} already exists; skipping")
    sys.exit(0)

levels = [BASE >> i for i in range(5) if (BASE >> i) >= TILE]


def render(size):
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    c = size / 2.0
    r = np.sqrt((xs - c) ** 2 + (ys - c) ** 2)
    ring = np.sin(r / (size / 40.0)) * 0.5 + 0.5
    red = (ring * 255).astype(np.uint8)
    green = (xs / size * 255).astype(np.uint8)
    blue = (ys / size * 255).astype(np.uint8)
    return np.dstack([red, green, blue])


with tifffile.TiffWriter(out, bigtiff=True) as tif:
    for i, size in enumerate(levels):
        tif.write(
            render(size),
            tile=(TILE, TILE),
            photometric="rgb",
            subfiletype=0 if i == 0 else 1,
        )
print(f"make-demo-slide: wrote {out} ({levels[0]}x{levels[0]} base, {len(levels)} levels)")
