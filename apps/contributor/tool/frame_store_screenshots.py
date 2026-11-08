#!/usr/bin/env python3
"""Frame the rendered app screens in a phone mockup for the Play listing.

The generator (`generate_store_screenshots.dart`) renders the app's real widget
tree at 1080x2340. Those are honest screenshots but they are not *listing* images:
shown edge to edge, a control in the app's top-right corner floats in empty space
and reads as a stray banner, and a white rectangle on a white page has no weight.

This puts each screen inside a phone body on a brand gradient, at 1080x1920
(ratio 1.78, inside Play's 2:1 limit). Nothing inside the screen is altered: the
body, the bezel and the background are drawn around the render, never on it.

Requires Pillow (the only non-Dart step in the screenshot pipeline).

    python3 apps/contributor/tool/frame_store_screenshots.py \
        --src build/store-screenshots --out build/store-framed
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFilter

CANVAS = (1080, 1920)
BODY_RADIUS = 92
SCREEN_RADIUS = 78
BEZEL = 16

# Deep emerald: the app's own UI is light, so a dark ground makes the screen — and
# the emerald accent inside it — carry the image.
TOP = (15, 59, 46)
BOTTOM = (6, 24, 18)
GLOW = (52, 227, 168)


def _gradient(size):
    width, height = size
    base = Image.new("RGB", size)
    draw = ImageDraw.Draw(base)
    for y in range(height):
        t = y / max(height - 1, 1)
        draw.line(
            [(0, y), (width, y)],
            fill=tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)),
        )
    return base


def frame(screen_path, out_path):
    screen = Image.open(screen_path).convert("RGB")

    # The phone is inset so there is a margin of background on every side.
    screen_h = CANVAS[1] - 2 * 164
    screen_w = round(screen.width * screen_h / screen.height)
    body_w, body_h = screen_w + 2 * BEZEL, screen_h + 2 * BEZEL
    left = (CANVAS[0] - body_w) // 2
    top = (CANVAS[1] - body_h) // 2

    canvas = _gradient(CANVAS).convert("RGBA")

    # A soft emerald glow behind the phone, so the ground is not a flat wall.
    glow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        [left - 150, top + 120, left + body_w + 150, top + body_h - 120],
        fill=GLOW + (34,),
    )
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(90)))

    # Drop shadow under the body.
    shadow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [left - 10, top + 26, left + body_w + 10, top + body_h + 34],
        radius=BODY_RADIUS + 8,
        fill=(0, 0, 0, 140),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)))

    # Phone body, then the screen inside it, masked to its own corners.
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        [left, top, left + body_w, top + body_h],
        radius=BODY_RADIUS,
        fill=(11, 15, 13, 255),
        outline=(31, 42, 38, 255),
        width=2,
    )

    scaled = screen.resize((screen_w, screen_h), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (screen_w, screen_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, screen_w - 1, screen_h - 1], radius=SCREEN_RADIUS, fill=255
    )
    scaled.putalpha(mask)
    canvas.alpha_composite(scaled, (left + BEZEL, top + BEZEL))

    # Side buttons: power on the right, volume on the left.
    def button(x, y, w, h):
        draw.rounded_rectangle([x, y, x + w, y + h], radius=w // 2, fill=(24, 32, 29, 255))

    button(left + body_w - 3, top + body_h * 0.24, 6, 92)
    button(left - 3, top + body_h * 0.20, 6, 58)
    button(left - 3, top + body_h * 0.28, 6, 58)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    canvas.convert("RGB").save(out_path, optimize=True)
    return out_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--src", default="build/store-screenshots")
    parser.add_argument("--out", default="build/store-framed")
    args = parser.parse_args()

    names = sorted(n for n in os.listdir(args.src) if n.endswith(".png"))
    if not names:
        raise SystemExit(f"no .png files in {args.src}")

    for name in names:
        out = frame(os.path.join(args.src, name), os.path.join(args.out, name))
        print(f"  {name} -> {out} ({os.path.getsize(out) // 1024} KB)")
    print(f"  {len(names)} image(s) at {CANVAS[0]}x{CANVAS[1]}")


if __name__ == "__main__":
    main()
