#!/usr/bin/env python3
"""Generate a small synthetic, OpenSlide-compatible tiled pyramidal TIFF.

This gives the SQ Web Viewer something to display in a fresh environment. The
image contains genuine high-frequency detail (a fine grid and crosshairs) at
full resolution, and the pyramid levels are produced by box-downsampling the
base image. As a result, zooming in reveals crisp detail that is not visible
when zoomed out -- a faithful demonstration of multi-resolution tiling.

OpenSlide opens the resulting plain tiled RGB TIFF as the ``generic-tiff``
vendor.
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


def render_base(size):
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    c = size / 2.0
    r = np.sqrt((xs - c) ** 2 + (ys - c) ** 2)
    ring = np.sin(r / (size / 40.0)) * 0.5 + 0.5
    red = ring * 255.0
    green = xs / size * 255.0
    blue = ys / size * 255.0

    xi = xs.astype(np.int32)
    yi = ys.astype(np.int32)

    # Coarse checkerboard of 512 px cells: a clearly structured, tiled pattern
    # that stays visible at every zoom level (darken alternate cells).
    cell = 512
    checker = ((xi // cell + yi // cell) % 2 == 1)
    dim = np.where(checker, 0.65, 1.0).astype(np.float32)
    img = np.dstack([red * dim, green * dim, blue * dim]).astype(np.uint8)

    # Bold black cell borders (4 px) frame the checkerboard cells.
    border = ((xi % cell) < 4) | ((yi % cell) < 4)
    img[border] = (10, 10, 10)

    # Fine white grid every 64 px: crisp only near full resolution, it box-
    # averages away at coarse pyramid levels, so zooming in visibly sharpens.
    fine = (xi % 64 == 0) | (yi % 64 == 0)
    img[fine] = (255, 255, 255)
    return img


def downsample(img):
    # 2x box downsample (average 2x2 blocks).
    h, w = img.shape[:2]
    h -= h % 2
    w -= w % 2
    a = img[:h, :w].astype(np.float32)
    a = a.reshape(h // 2, 2, w // 2, 2, 3).mean(axis=(1, 3))
    return a.astype(np.uint8)

base = render_base(BASE)
pyramid = [base]
while min(pyramid[-1].shape[:2]) > TILE:
    pyramid.append(downsample(pyramid[-1]))

with tifffile.TiffWriter(out, bigtiff=True) as tif:
    for i, img in enumerate(pyramid):
        tif.write(
            img,
            tile=(TILE, TILE),
            photometric="rgb",
            subfiletype=0 if i == 0 else 1,
        )
print(f"make-demo-slide: wrote {out} ({BASE}x{BASE} base, {len(pyramid)} levels)")
