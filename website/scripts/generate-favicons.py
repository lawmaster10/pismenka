#!/usr/bin/env python3
"""
Generate the full favicon set for pismenka.com.

The brand mark is a sun-yellow rounded tile with an ink-charcoal "P", matching
the header logo in the website Layout. The SVG embeds the actual glyph path
extracted from SF Compact Rounded at weight 900 so it's font-independent.

Outputs (all into website/public/):
    favicon.svg              vector, font-independent
    favicon.ico              multi-res 16/32/48
    favicon-16.png
    favicon-32.png
    favicon-48.png
    apple-touch-icon.png     180x180 (iOS home screen)
    icon-192.png             PWA / Android home screen
    icon-512.png             PWA / OG image fallback

Run:
    python3 website/scripts/generate-favicons.py
"""

import os
from PIL import Image, ImageDraw, ImageFont

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WEBSITE_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
OUT = os.path.join(WEBSITE_DIR, "public")

FONT = "/System/Library/Fonts/SFCompactRounded.ttf"
SUN_HEX = "#ffd166"
INK_HEX = "#172033"
SUN = (255, 209, 102, 255)
INK = (23, 32, 51, 255)


def draw_tile(size, ss=4, radius_ratio=0.22, letter_h_ratio=0.66, weight=900):
    s = size * ss
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, s - 1, s - 1), radius=int(s * radius_ratio), fill=SUN)
    target_h = int(s * letter_h_ratio)
    f = ImageFont.truetype(FONT, target_h)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    bbox = f.getbbox("P", anchor="lt")
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x = (s - tw) // 2 - bbox[0]
    y = (s - th) // 2 - bbox[1]
    d.text((x, y), "P", font=f, fill=INK, anchor="lt")
    return img.resize((size, size), Image.LANCZOS)


def write_pngs():
    os.makedirs(OUT, exist_ok=True)
    targets = {
        "favicon-16.png": 16,
        "favicon-32.png": 32,
        "favicon-48.png": 48,
        "apple-touch-icon.png": 180,
        "icon-192.png": 192,
        "icon-512.png": 512,
    }
    for fn, sz in targets.items():
        img = draw_tile(sz)
        img.save(os.path.join(OUT, fn), "PNG", optimize=True)
        print(f"  wrote {fn} ({sz}x{sz}, {os.path.getsize(os.path.join(OUT, fn))} B)")

    ico_img = Image.open(os.path.join(OUT, "favicon-48.png"))
    ico_path = os.path.join(OUT, "favicon.ico")
    ico_img.save(ico_path, format="ICO", sizes=[(16, 16), (32, 32), (48, 48)])
    print(f"  wrote favicon.ico ({os.path.getsize(ico_path)} B)")


def write_svg():
    try:
        from fontTools.ttLib import TTFont
        from fontTools.varLib.instancer import instantiateVariableFont
        from fontTools.pens.svgPathPen import SVGPathPen
    except ImportError:
        print("  fontTools not installed; skipping favicon.svg")
        return

    base = TTFont(FONT)
    inst = instantiateVariableFont(base, {"wght": 900})
    cmap = inst.getBestCmap()
    gname = cmap[ord("P")]
    glyph_set = inst.getGlyphSet()
    glyph = glyph_set[gname]
    pen = SVGPathPen(glyph_set)
    glyph.draw(pen)
    path_d = pen.getCommands()

    glyf = inst["glyf"][gname]
    xmin, ymin, xmax, ymax = glyf.xMin, glyf.yMin, glyf.xMax, glyf.yMax

    SIDE = 64
    radius = SIDE * 0.22
    letter_h = SIDE * 0.66
    glyph_h = ymax - ymin
    glyph_w = xmax - xmin
    scale = letter_h / glyph_h
    rendered_w = glyph_w * scale
    rendered_h = glyph_h * scale
    cx = SIDE / 2
    cy = SIDE / 2
    tx = cx - rendered_w / 2 - xmin * scale
    ty = cy + rendered_h / 2 + ymin * scale

    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIDE} {SIDE}">'
        f'<rect width="{SIDE}" height="{SIDE}" rx="{radius:.3f}" ry="{radius:.3f}" fill="{SUN_HEX}"/>'
        f'<g transform="translate({tx:.3f} {ty:.3f}) scale({scale:.5f} {-scale:.5f})">'
        f'<path d="{path_d}" fill="{INK_HEX}"/>'
        f'</g>'
        f'</svg>'
    )
    out = os.path.join(OUT, "favicon.svg")
    with open(out, "w") as f:
        f.write(svg)
    print(f"  wrote favicon.svg ({len(svg)} B)")


if __name__ == "__main__":
    print(f"Generating favicons into {OUT}")
    write_pngs()
    write_svg()
