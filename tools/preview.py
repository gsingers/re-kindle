#!/usr/bin/env python3
"""Mac-side preview: turns render.awk's drawing commands into an HTML page at 600x800.

  curl -s "$URL" | awk -v place=Vienna -f extensions/dashboard/render.awk | python3 tools/preview.py > preview.html
Write the page at the project root (icon links are relative to it).
Text is approximated with Helvetica (baseline ~0.8*px below the FBInk top margin).
"""
import html
import struct
import sys

ICONS = "extensions/dashboard/icons"
parts = []
for line in sys.stdin.read().splitlines():
    kind, *f = line.split("|")
    if kind == "R":
        x, y, w, h, color = f
        fill = {"B": "#000", "W": "#fff"}.get(color) or "#" + color[-1].lower() * 6  # GRAYA -> #aaaaaa
        parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}"/>')
    elif kind == "I":
        name, x, y = f
        with open(f"{ICONS}/{name}.png", "rb") as png:
            w, h = struct.unpack(">II", png.read(24)[16:24])
        parts.append(f'<image href="{ICONS}/{name}.png" x="{x}" y="{y}" width="{w}" height="{h}"/>')
    elif kind == "T":
        style, px, left, right, top, flags, text = f[0], int(f[1]), int(f[2]), int(f[3]), int(f[4]), f[5], "|".join(f[6:])
        centred = "c" in flags
        x = (left + 600 - right) / 2 if centred else left
        parts.append(f'<text x="{x}" y="{top + 0.8 * px}" font-size="{px}" font-weight="{"bold" if style == "B" else "normal"}"'
                     f' text-anchor="{"middle" if centred else "start"}" fill="{"#fff" if "i" in flags else "#000"}">{html.escape(text)}</text>')
print('<!doctype html><meta charset="utf-8"><title>Dashboard preview</title>'
      '<body style="margin:0;background:#888"><svg xmlns="http://www.w3.org/2000/svg" width="600" height="800"'
      ' style="background:#fff;font-family:Helvetica,Arial,sans-serif;display:block">' + "".join(parts) + "</svg></body>")
