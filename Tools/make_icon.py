"""Ajar app icon generator.

The mark is a MacBook seen from the side with the lid ajar (~55 deg): the base is
the horizontal stroke, the lid the raised one. It doubles as the angle sign, which
is the product — the lid angle is the control surface.

Nothing here uses SF Symbols: Apple's licence forbids them in app icons, so every
shape is drawn from primitives. PIL does not antialias its draw ops, so the master
is rendered at 4x and downsampled.

    python3 Tools/make_icon.py                     # preview sheet of all colourways
    python3 Tools/make_icon.py graphite <dest>     # write an AppIcon.appiconset

Needs an arm64 Pillow; the system python3 at /usr/local/bin is x86_64 and will not
load it. /opt/anaconda3/bin/python3 works on this machine.
"""

import json
import math
import os
import sys

from PIL import Image, ImageDraw

S = 4                 # supersample factor
D = 1024              # design space
SQ = 824              # squircle size inside the 1024 canvas (Apple's macOS grid)
SQ_N = 5.0            # superellipse exponent, approximates Apple's rounded rect

# Stroke thickness is set by the 16x16 slot, not by taste: below ~100 in design
# space the mark turns to mush once it is 16 pixels wide.
THICK = 100
# Base and lid are the same length: a lid is as long as the half it folds onto.
ARM_LEN = 540
LID_DEG = 55

VARIANTS = {
    "graphite": dict(bg_top=(68, 72, 80), bg_bottom=(19, 20, 24), body=(255, 255, 255)),
    "indigo": dict(bg_top=(78, 101, 145), bg_bottom=(22, 28, 48), body=(255, 255, 255)),
    "amber": dict(bg_top=(255, 183, 77), bg_bottom=(214, 118, 20), body=(255, 255, 255)),
    "silver": dict(bg_top=(250, 251, 252), bg_bottom=(196, 202, 212), body=(38, 42, 52)),
}

# The ten slots macOS asks for, as (point size, scale).
SLOTS = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
         (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


def _lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def _squircle_points(cx, cy, half, n=SQ_N, steps=720):
    pts = []
    for i in range(steps):
        th = 2 * math.pi * i / steps
        c, s = math.cos(th), math.sin(th)
        pts.append((cx + half * math.copysign(abs(c) ** (2 / n), c),
                    cy + half * math.copysign(abs(s) ** (2 / n), s)))
    return pts


def _gradient(size, top, bottom):
    img = Image.new("RGB", (1, size))
    px = img.load()
    for y in range(size):
        px[0, y] = _lerp(top, bottom, y / (size - 1))
    return img.resize((size, size), Image.BILINEAR)


def _capsule(draw, p0, p1, width, fill):
    """Round-capped thick line. PIL has no round caps, so cap it by hand."""
    r = width / 2
    draw.line([p0, p1], fill=fill, width=int(round(width)))
    for (x, y) in (p0, p1):
        draw.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def _centred_shape():
    """Hinge, base end and lid tip, translated so the mark sits in the middle."""
    th = math.radians(LID_DEG)
    pts = [(0.0, 0.0), (ARM_LEN, 0.0),
           (ARM_LEN * math.cos(th), -ARM_LEN * math.sin(th))]
    r = THICK / 2
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    dx = D / 2 - ((min(xs) - r) + (max(xs) + r)) / 2
    dy = D / 2 - ((min(ys) - r) + (max(ys) + r)) / 2
    return [(x + dx, y + dy) for x, y in pts]


def render(bg_top, bg_bottom, body):
    n = D * S
    canvas = Image.new("RGBA", (n, n), (0, 0, 0, 0))

    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).polygon(_squircle_points(n / 2, n / 2, SQ * S / 2), fill=255)
    canvas.paste(_gradient(n, bg_top, bg_bottom).convert("RGBA"), (0, 0), mask)

    draw = ImageDraw.Draw(canvas)
    hinge, base_end, lid_end = [(x * S, y * S) for x, y in _centred_shape()]
    _capsule(draw, hinge, base_end, THICK * S, body)
    _capsule(draw, hinge, lid_end, THICK * S, body)

    return canvas.resize((D, D), Image.LANCZOS)


def build_appiconset(variant, dest):
    master = render(**VARIANTS[variant])
    os.makedirs(dest, exist_ok=True)

    images = []
    for pt, scale in SLOTS:
        name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
        master.resize((pt * scale,) * 2, Image.LANCZOS).save(os.path.join(dest, name))
        images.append({"idiom": "mac", "size": f"{pt}x{pt}",
                       "scale": f"{scale}x", "filename": name})

    with open(os.path.join(dest, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"version": 1, "author": "xcode"}},
                  f, indent=2)
    return master


def preview_sheet(path):
    """All colourways, each with its 64/32/16 renderings underneath."""
    tiles = [(name, render(**kw)) for name, kw in VARIANTS.items()]
    w = 300
    sheet = Image.new("RGBA", (w * len(tiles), w + 100), (255, 255, 255, 255))
    for i, (_, img) in enumerate(tiles):
        big = img.resize((w, w), Image.LANCZOS)
        sheet.paste(big, (i * w, 0), big)
        x = i * w + 30
        for s in (64, 32, 16):
            small = img.resize((s, s), Image.LANCZOS)
            sheet.paste(small, (x, w + 30), small)
            x += s + 30
    sheet.save(path)


if __name__ == "__main__":
    if len(sys.argv) >= 3:
        build_appiconset(sys.argv[1], sys.argv[2])
        print(f"wrote {sys.argv[1]} appiconset -> {sys.argv[2]}")
    else:
        preview_sheet("icon-variants.png")
        print("wrote icon-variants.png:", ", ".join(VARIANTS))
