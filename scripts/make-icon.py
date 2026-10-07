#!/usr/bin/env python3
"""Render the AgoyNotch skull app icon to Resources/AppIcon.png (1024x1024 RGBA).

Mirrors the geometry of Resources/AppIcon.svg (keep the two in sync). Python 3 stdlib
only (no Pillow / cairo needed): every shape is a signed-distance function, and pixel
coverage clamp(0.5 - d, 0, 1) gives 1-px anti-aliasing. The PNG is written by hand.

Re-run:  python3 scripts/make-icon.py
"""
import math
import os
import struct
import zlib

SIZE = 1024
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources", "AppIcon.png")


def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


BG_TOP = hex_rgb("3B3F47")
BG_BOTTOM = hex_rgb("141519")
SKULL = hex_rgb("F1EEE6")
HOLE = hex_rgb("1A1B20")


# --- Signed distance functions (negative inside) --------------------------------------

def sd_round_rect(px, py, x, y, w, h, r):
    cx, cy = x + w / 2, y + h / 2
    qx = abs(px - cx) - (w / 2 - r)
    qy = abs(py - cy) - (h / 2 - r)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    return outside + min(max(qx, qy), 0.0) - r


def sd_circle(px, py, cx, cy, r):
    return math.hypot(px - cx, py - cy) - r


def sd_ellipse(px, py, cx, cy, rx, ry):
    # First-order approximation; exact on the boundary, good enough for AA.
    dx, dy = (px - cx) / rx, (py - cy) / ry
    k0 = math.hypot(dx, dy)
    k1 = math.hypot(dx / rx, dy / ry)
    if k1 == 0:
        return -min(rx, ry)
    return k0 * (k0 - 1.0) / k1


def sd_convex_polygon(px, py, pts):
    # Max of signed distances to each edge line (points listed clockwise in y-down space).
    d = -1e9
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        ex, ey = x1 - x0, y1 - y0
        length = math.hypot(ex, ey)
        # outward normal for clockwise order in y-down coordinates
        nx, ny = ey / length, -ex / length
        d = max(d, (px - x0) * nx + (py - y0) * ny)
    return d


def coverage(d):
    return min(max(0.5 - d, 0.0), 1.0)


# --- Geometry (same numbers as AppIcon.svg) -------------------------------------------

SQ = (100, 100, 824, 824, 185)
NOSE = [(512, 615), (542, 672), (482, 672)]  # clockwise (y down)
TEETH = [(392, 706, 240, 14), (450, 706, 14, 54), (505, 706, 14, 54), (560, 706, 14, 54)]


def skull_cov(px, py):
    if not (260 <= px <= 764 and 230 <= py <= 766):
        return 0.0
    d = min(sd_circle(px, py, 512, 480, 245),
            sd_round_rect(px, py, 352, 560, 320, 200, 60))
    return coverage(d)


def hole_cov(px, py):
    if not (340 <= px <= 684 and 452 <= py <= 766):
        return 0.0
    d = min(sd_ellipse(px, py, 420, 540, 72, 80),
            sd_ellipse(px, py, 604, 540, 72, 80),
            sd_convex_polygon(px, py, NOSE))
    for (x, y, w, h) in TEETH:
        d = min(d, sd_round_rect(px, py, x, y, w, h, 0.0))
    return coverage(d)


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def render():
    rows = []
    for j in range(SIZE):
        py = j + 0.5
        t = min(max((py - 100) / 824.0, 0.0), 1.0)
        bg = lerp(BG_TOP, BG_BOTTOM, t)
        row = bytearray([0])  # PNG filter type 0
        for i in range(SIZE):
            px = i + 0.5
            d_sq = sd_round_rect(px, py, *SQ)
            alpha = coverage(d_sq)
            if alpha <= 0.0:
                row += b"\x00\x00\x00\x00"
                continue
            c = bg
            # 2 px inner highlight stroke (white @ 8%).
            stroke = coverage(abs(d_sq + 2.0) - 1.0) * 0.08
            if stroke > 0:
                c = lerp(c, (1.0, 1.0, 1.0), stroke)
            s = skull_cov(px, py)
            if s > 0:
                c = lerp(c, SKULL, s)
                h = hole_cov(px, py)
                if h > 0:
                    c = lerp(c, HOLE, h * s)
            row += bytes((int(round(c[0] * 255)), int(round(c[1] * 255)),
                          int(round(c[2] * 255)), int(round(alpha * 255))))
        rows.append(bytes(row))
    return b"".join(rows)


def write_png(path, raw):
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)  # 8-bit RGBA
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    write_png(OUT, render())
    print("wrote", OUT)
