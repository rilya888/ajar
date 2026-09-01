"""DMG background: one hint, nothing else.

The disk image window is 600x400 with the app on the left and an Applications alias
on the right; this draws the arrow between them plus the single line of text. Icon
positions here must match the AppleScript in Tools/release.sh — they are the same
two numbers in two places, and the picture is wrong the moment they drift.

    /opt/anaconda3/bin/python3 Tools/make_dmg_background.py docs/release/dmg-background.png

Needs an arm64 Pillow, same as Tools/make_icon.py: /usr/local/bin/python3 on this
machine is x86_64 and will not load it.
"""

import sys

from PIL import Image, ImageDraw, ImageFont

S = 4                       # supersample: PIL does not antialias its own draw ops
W, H = 600, 400
LEFT_X, RIGHT_X = 150, 450  # icon centres, mirrored in release.sh
ICON_Y = 190                # icon centre; text sits below both icons

BG = (245, 245, 247)
INK = (142, 142, 147)
TEXT = (99, 99, 102)


def font(size):
    for path in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main(dest):
    img = Image.new("RGB", (W * S, H * S), BG)
    d = ImageDraw.Draw(img)

    # Arrow from app to Applications, stopping clear of both icon slots (64 px each side).
    y = ICON_Y * S
    x0, x1 = (LEFT_X + 70) * S, (RIGHT_X - 70) * S
    d.line([(x0, y), (x1 - 18 * S, y)], fill=INK, width=3 * S)
    d.polygon([(x1, y), (x1 - 20 * S, y - 11 * S), (x1 - 20 * S, y + 11 * S)], fill=INK)

    d.text((W * S / 2, (ICON_Y + 105) * S), "Drag Ajar to Applications",
           font=font(19 * S), fill=TEXT, anchor="mm")

    img.resize((W, H), Image.LANCZOS).save(dest)
    print(dest)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "docs/release/dmg-background.png")
