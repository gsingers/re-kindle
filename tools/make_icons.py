#!/usr/bin/env python3
"""Draws the dashboard's line-style weather icons as grayscale PNGs (stdlib only).

Run: python3 tools/make_icons.py   ->  extensions/dashboard/icons/<name>-<size>.png
Shapes are defined in unit coordinates (0..1, y down) and supersampled for smooth edges.
"""
import math
import struct
import sys
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "extensions" / "dashboard" / "icons"
SIZES = {160: 6, 120: 5, 48: 3}  # icon px -> stroke width px
SS = 4  # supersampling factor


def circle(cx, cy, r):
    return lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def capsule(x1, y1, x2, y2, w):
    def inside(x, y):
        dx, dy = x2 - x1, y2 - y1
        t = max(0.0, min(1.0, ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)))
        return (x - x1 - t * dx) ** 2 + (y - y1 - t * dy) ** 2 <= (w / 2) ** 2
    return inside


def polygon(points):
    def inside(x, y):
        hit = False
        for (ax, ay), (bx, by) in zip(points, points[1:] + points[:1]):
            if (ay > y) != (by > y) and x < ax + (y - ay) * (bx - ax) / (by - ay):
                hit = not hit
        return hit
    return inside


def cloud(d, dx=0.0, dy=0.0):
    """Cloud silhouette shrunk by d (so cloud(0) minus cloud(stroke) is its outline)."""
    parts = [circle(0.34 + dx, 0.58 + dy, 0.17 - d), circle(0.55 + dx, 0.46 + dy, 0.23 - d),
             circle(0.76 + dx, 0.60 + dy, 0.15 - d)]
    bottom = 0.75 + dy - d

    def inside(x, y):
        if y > bottom:
            return False
        if 0.34 + dx <= x <= 0.76 + dx and y >= 0.58 + dy:
            return True
        return any(p(x, y) for p in parts)
    return inside


def outline(shape, s):
    return [("ink", shape(0)), ("erase", shape(s))]


def sun(cx, cy, r, s):
    ops = [("ink", circle(cx, cy, r)), ("erase", circle(cx, cy, r - s))]
    for i in range(8):
        a = i * math.pi / 4
        ops.append(("ink", capsule(cx + (r + 0.07) * math.cos(a), cy + (r + 0.07) * math.sin(a),
                                   cx + (r + 0.15) * math.cos(a), cy + (r + 0.15) * math.sin(a), s)))
    return ops


def moon(cx, cy, r, s):
    ox, oy, k = 0.13 * r / 0.22, -0.09 * r / 0.22, 0.82
    outer = lambda x, y: circle(cx, cy, r)(x, y) and not circle(cx + ox, cy + oy, r * k)(x, y)
    inner = lambda x, y: circle(cx, cy, r - s)(x, y) and not circle(cx + ox, cy + oy, r * k + s)(x, y)
    return [("ink", outer), ("erase", inner)]


def with_cloud(back, s, dx=0.06, dy=0.08):
    return back + outline(lambda d: cloud(d, dx, dy), s)


def precip(s, kind):
    ops = outline(lambda d: cloud(d, 0, -0.12), s)
    xs = (0.36, 0.53, 0.70)
    for i, x in enumerate(xs):
        if kind == "rain":
            ops.append(("ink", capsule(x, 0.72, x - 0.05, 0.88, s)))
        elif kind == "drizzle":
            ops.append(("ink", circle(x - 0.02, 0.78 + 0.06 * (i % 2), s * 0.8)))
        elif kind == "snow":
            for y in (0.76, 0.90):
                ops.append(("ink", circle(x + (0.06 if y > 0.8 else 0), y, s * 0.9)))
    if kind == "storm":
        ops.append(("ink", polygon([(0.56, 0.62), (0.40, 0.82), (0.51, 0.82), (0.45, 0.97),
                                    (0.64, 0.75), (0.53, 0.75), (0.60, 0.62)])))
    return ops


def icons(s):
    return {
        "sun": sun(0.5, 0.5, 0.2, s),
        "moon": moon(0.48, 0.52, 0.28, s),
        "partly": with_cloud(sun(0.36, 0.36, 0.13, s), s),
        "partly-night": with_cloud(moon(0.36, 0.38, 0.17, s), s),
        "cloud": outline(lambda d: cloud(d, 0, 0.02), s),
        "fog": [("ink", capsule(x1, y, x2, y, s)) for x1, x2, y in
                ((0.18, 0.70, 0.34), (0.30, 0.82, 0.48), (0.18, 0.74, 0.62), (0.32, 0.82, 0.76))],
        "drizzle": precip(s, "drizzle"),
        "rain": precip(s, "rain"),
        "snow": precip(s, "snow"),
        "storm": precip(s, "storm"),
    }


def render(ops, size):
    n = size * SS
    rows = []
    for py in range(size):
        row = bytearray()
        for px in range(size):
            ink = 0
            for sy in range(SS):
                for sx in range(SS):
                    x, y = (px * SS + sx + 0.5) / n, (py * SS + sy + 0.5) / n
                    for mode, shape in reversed(ops):
                        if shape(x, y):
                            ink += mode == "ink"
                            break
            row.append(255 - round(255 * ink / (SS * SS)))
        rows.append(bytes(row))
    return rows


def dots(filled, n=5, d=13, gap=24, stroke=2):
    """Rain-chance strip: n circles of diameter d, the first `filled` solid, the rest outlined."""
    w, h = gap * (n - 1) + d + 1, d + 1
    rows = []
    for py in range(h):
        row = bytearray()
        for px in range(w):
            ink = 0
            for sy in range(SS):
                for sx in range(SS):
                    x, y = px + (sx + 0.5) / SS, py + (sy + 0.5) / SS
                    k = min(n - 1, int(x // gap))
                    r = math.hypot(x - (k * gap + h / 2), y - h / 2)
                    ink += r <= d / 2 and (k < filled or r >= d / 2 - stroke)
            row.append(255 - round(255 * ink / (SS * SS)))
        rows.append(bytes(row))
    return rows


def png(rows):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    raw = b"".join(b"\x00" + r for r in rows)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", len(rows[0]), len(rows), 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for size, stroke in SIZES.items():
        for name, ops in icons(stroke / size).items():
            rows = render(ops, size)
            assert len(rows) == size and all(len(r) == size for r in rows)
            ink = sum(255 - v for r in rows for v in r)
            assert ink > 0, f"{name} came out blank"
            (OUT / f"{name}-{size}.png").write_bytes(png(rows))
            print(f"{name}-{size}.png")
    for n in range(6):
        (OUT / f"dots-{n}.png").write_bytes(png(dots(n)))
        print(f"dots-{n}.png")


if __name__ == "__main__":
    sys.exit(main())
