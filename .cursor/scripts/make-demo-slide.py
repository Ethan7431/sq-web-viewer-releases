#!/usr/bin/env python3
"""Write a small OpenSlide-readable pyramidal TIFF into the slides folder.

The base image is a checkerboard with a fine grid. Coarser pyramid levels are
box-downsampled, so zooming in reveals detail that is not visible when zoomed
out. OpenSlide opens the tiled RGB TIFF as generic-tiff.
"""

import os
import sys

import numpy as np
import tifffile

BASE = int(os.environ.get("SQWV_DEMO_BASE", "4096"))
TILE = 256
slides_dir = os.environ.get("SQWV_SLIDES_DIR", os.path.join(os.getcwd(), "slides"))
os.makedirs(slides_dir, exist_ok=True)
out = os.path.join(slides_dir, "demo-slide.tif")

if os.path.exists(out):
    print(f"make-demo-slide: {out} already exists")
    sys.exit(0)


def render_base(size: int) -> np.ndarray:
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    center = size / 2.0
    radius = np.sqrt((xs - center) ** 2 + (ys - center) ** 2)
    ring = np.sin(radius / (size / 40.0)) * 0.5 + 0.5
    image = np.dstack([ring * 255.0, xs / size * 255.0, ys / size * 255.0]).astype(np.uint8)

    xi = xs.astype(np.int32)
    yi = ys.astype(np.int32)
    cell = 512
    checker = ((xi // cell + yi // cell) % 2) == 1
    image[checker] = (image[checker].astype(np.float32) * 0.65).astype(np.uint8)
    border = ((xi % cell) < 4) | ((yi % cell) < 4)
    image[border] = (10, 10, 10)
    fine = (xi % 64 == 0) | (yi % 64 == 0)
    image[fine] = (255, 255, 255)
    return image


def downsample(image: np.ndarray) -> np.ndarray:
    height, width = image.shape[:2]
    height -= height % 2
    width -= width % 2
    block = image[:height, :width].astype(np.float32)
    block = block.reshape(height // 2, 2, width // 2, 2, 3).mean(axis=(1, 3))
    return block.astype(np.uint8)


base = render_base(BASE)
pyramid = [base]
while min(pyramid[-1].shape[:2]) > TILE:
    pyramid.append(downsample(pyramid[-1]))

with tifffile.TiffWriter(out, bigtiff=True) as writer:
    for index, image in enumerate(pyramid):
        writer.write(
            image,
            tile=(TILE, TILE),
            photometric="rgb",
            compression=None,
            subfiletype=0 if index == 0 else 1,
        )

print(f"make-demo-slide: wrote {out} ({BASE}x{BASE}, {len(pyramid)} levels)")
