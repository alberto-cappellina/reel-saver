#!/usr/bin/env python3
"""Generate the Reel Saver icon assets.

Output in assets/icon/:
  - icon.png     full icon (rounded gradient + symbol)            [legacy]
  - icon_bg.png  solid gradient background                        [adaptive bg]
  - icon_fg.png  symbol only, transparent, centered in safe-zone  [adaptive fg]

Usage: python3 tool/gen_icon.py
"""
import os
from PIL import Image, ImageDraw

S = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")
os.makedirs(OUT, exist_ok=True)

# Instagram-style diagonal gradient (warm -> magenta -> purple/blue)
STOPS = [(0.0, (254, 218, 119)), (0.5, (214, 41, 118)), (1.0, (79, 91, 213))]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def grad_color(t):
    for i in range(len(STOPS) - 1):
        t0, c0 = STOPS[i]
        t1, c1 = STOPS[i + 1]
        if t0 <= t <= t1:
            return lerp(c0, c1, (t - t0) / (t1 - t0))
    return STOPS[-1][1]


def gradient(size):
    img = Image.new("RGB", (size, size))
    px = img.load()
    maxd = (size - 1) * 2
    for y in range(size):
        for x in range(size):
            px[x, y] = grad_color((x + y) / maxd)
    return img


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def draw_symbol(draw, size, scale=1.0, cx=None, cy=None):
    """Draw a play symbol + download arrow in white."""
    cx = size / 2 if cx is None else cx
    cy = size / 2 if cy is None else cy
    white = (255, 255, 255, 255)

    # Play triangle (pointing right), slightly above center
    r = size * 0.19 * scale
    pcy = cy - size * 0.05 * scale
    tri = [
        (cx - r * 0.72, pcy - r),
        (cx - r * 0.72, pcy + r),
        (cx + r * 0.95, pcy),
    ]
    draw.polygon(tri, fill=white)

    # Download arrow below
    aw = size * 0.11 * scale          # half width of the arrow head
    stem_w = size * 0.045 * scale
    top = cy + size * 0.10 * scale
    tip = cy + size * 0.27 * scale
    head_top = tip - aw * 1.15
    # stem
    draw.rectangle([cx - stem_w, top, cx + stem_w, head_top + aw * 0.2], fill=white)
    # head
    draw.polygon([(cx - aw, head_top), (cx + aw, head_top), (cx, tip)], fill=white)
    # base (tray)
    by = tip + size * 0.045 * scale
    bw = size * 0.17 * scale
    bh = size * 0.035 * scale
    draw.rounded_rectangle([cx - bw, by, cx + bw, by + bh], radius=bh / 2, fill=white)


def main():
    # --- solid gradient background (adaptive background) ---
    bg = gradient(S).convert("RGBA")
    bg.save(os.path.join(OUT, "icon_bg.png"))

    # --- full, rounded icon (legacy) ---
    full = gradient(S).convert("RGBA")
    d = ImageDraw.Draw(full)
    draw_symbol(d, S, scale=1.0)
    mask = rounded_mask(S, int(S * 0.22))
    rounded = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rounded.paste(full, (0, 0), mask)
    rounded.save(os.path.join(OUT, "icon.png"))

    # --- adaptive foreground: symbol only, inside the safe-zone (~62%) ---
    fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    df = ImageDraw.Draw(fg)
    draw_symbol(df, S, scale=0.62)
    fg.save(os.path.join(OUT, "icon_fg.png"))

    print("OK ->", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
