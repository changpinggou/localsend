#!/usr/bin/env python3
"""localU logo generator.

Draws the localU logo from pure geometry (no image dependencies):
8 tapered arc petals (LocalSend "ripple" DNA) around a bold U glyph
(USB drive / "localU" mark). Rasterizes with capsule-chain distance at 6x
supersampling and emits the same asset set as app/assets/img/.

Usage:
    python3 generate.py                 # primary USB-blue set
    python3 generate.py --color teal    # LocalSend-teal colorway
    python3 generate.py --color '#RRGGBB'
"""

import argparse
import math
import struct
import zlib
from pathlib import Path

# ---------------------------------------------------------------------------
# Geometry (512 design grid, y-down)
# ---------------------------------------------------------------------------
GRID = 512
SS = 6                       # supersample factor -> master raster 3072
MASTER = GRID * SS
CX = CY = GRID / 2

# Ripple ring: 8 tapered petals, one centered at 12 o'clock (LocalSend DNA)
PETALS = 8
RING_R = 170.0               # petal centerline radius
PETAL_SPAN = math.radians(26)  # angular span of one petal
PETAL_HW_END = 12.0          # half-width at petal ends
PETAL_HW_MID = 19.0          # half-width at petal middle

# U glyph: uniform-width capsule chain with round caps, bbox centered
U_A = 70.0                   # centerline half-width (bowl radius)
U_S = 23.0                   # stroke half-width -> 46 total
U_TOP_Y = 181.0              # centerline top of the two bars
U_BOWL_Y = 261.0             # centerline of the semicircular bowl

COLORS = {
    "blue": (0x1B, 0x82, 0xD6),  # USB blue - localU primary
    "teal": (0x17, 0x86, 0x8C),  # LocalSend teal - family colorway
}


# ---------------------------------------------------------------------------
# Shape builders -> capsule chains: ([(x, y), ...], [halfwidth, ...])
# ---------------------------------------------------------------------------
def build_petals():
    chains = []
    for k in range(PETALS):
        center = math.radians(90 * 0) + k * (2 * math.pi / PETALS) - math.pi / 2
        pts, hws = [], []
        n = 30
        for i in range(n + 1):
            u = -1.0 + 2.0 * i / n                 # -1 .. 1 along the petal
            theta = center + u * PETAL_SPAN / 2
            hw = PETAL_HW_MID - (PETAL_HW_MID - PETAL_HW_END) * u * u
            pts.append((CX + RING_R * math.cos(theta),
                        CY + RING_R * math.sin(theta)))
            hws.append(hw)
        chains.append((pts, hws))
    return chains


def build_u():
    pts, hws = [], []
    x_l, x_r = CX - U_A, CX + U_A
    pts.append((x_l, U_TOP_Y))
    hws.append(U_S)
    pts.append((x_l, U_BOWL_Y))
    hws.append(U_S)
    n = 40
    for i in range(1, n):                          # bowl: 180deg -> 0deg via bottom
        phi = math.pi - math.pi * i / n
        pts.append((CX + U_A * math.cos(phi), U_BOWL_Y + U_A * math.sin(phi)))
        hws.append(U_S)
    pts.append((x_r, U_BOWL_Y))
    hws.append(U_S)
    pts.append((x_r, U_TOP_Y))
    hws.append(U_S)
    return [(pts, hws)]


CHAINS = build_petals() + build_u()


# ---------------------------------------------------------------------------
# Rasterizer: capsule-chain distance into a 1-bit-style alpha master
# ---------------------------------------------------------------------------
def rasterize_master():
    m = MASTER
    buf = bytearray(m * m)
    for pts, hws in CHAINS:
        for i in range(len(pts) - 1):
            # all math in master (supersampled) units
            mx0, my0 = pts[i][0] * SS, pts[i][1] * SS
            mx1, my1 = pts[i + 1][0] * SS, pts[i + 1][1] * SS
            r = (hws[i] + hws[i + 1]) / 2 * SS
            pad = r + 2
            bx0 = max(0, int(min(mx0, mx1) - pad))
            by0 = max(0, int(min(my0, my1) - pad))
            bx1 = min(m - 1, int(math.ceil(max(mx0, mx1) + pad)))
            by1 = min(m - 1, int(math.ceil(max(my0, my1) + pad)))
            dx, dy = mx1 - mx0, my1 - my0
            seg2 = dx * dx + dy * dy
            for py in range(by0, by1 + 1):
                sy = py + 0.5
                row = py * m
                for px in range(bx0, bx1 + 1):
                    sx = px + 0.5
                    if seg2 == 0:
                        ddx, ddy = sx - mx0, sy - my0
                        d2 = ddx * ddx + ddy * ddy
                    else:
                        t = ((sx - mx0) * dx + (sy - my0) * dy) / seg2
                        t = 0.0 if t < 0 else (1.0 if t > 1 else t)
                        ddx, ddy = sx - (mx0 + t * dx), sy - (my0 + t * dy)
                        d2 = ddx * ddx + ddy * ddy
                    if d2 <= r * r:
                        buf[row + px] = 255
    return buf


def box_resize(alpha, src, dst):
    """Integer-factor area-average downscale of a single-channel buffer."""
    f = src // dst
    out = bytearray(dst * dst)
    for dy in range(dst):
        sy0 = dy * f
        drow = dy * dst
        for dx in range(dst):
            sx0 = dx * f
            acc = 0
            for yy in range(sy0, sy0 + f):
                srow = yy * src + sx0
                acc += sum(alpha[srow:srow + f])
            out[drow + dx] = acc // (f * f)
    return out


def float_resize(alpha, src, dst):
    """Area-average downscale with fractional windows (for 48px etc.)."""
    scale = src / dst
    out = bytearray(dst * dst)
    for dy in range(dst):
        fy0, fy1 = dy * scale, (dy + 1) * scale
        drow = dy * dst
        for dx in range(dst):
            fx0, fx1 = dx * scale, (dx + 1) * scale
            acc = n = 0
            for yy in range(int(fy0), int(fy1) + 1):
                wy = min(yy + 1, fy1) - max(yy, fy0)
                if wy <= 0:
                    continue
                srow = yy * src
                for xx in range(int(fx0), int(fx1) + 1):
                    wx = min(xx + 1, fx1) - max(xx, fx0)
                    if wx > 0:
                        acc += alpha[srow + xx] * wx * wy
                        n += wx * wy
            out[drow + dx] = int(acc / n)
    return out


def render_rgba(alpha, size, color):
    r, g, b = color
    out = bytearray(size * size * 4)
    for i, a in enumerate(alpha):
        j = i * 4
        out[j], out[j + 1], out[j + 2], out[j + 3] = r, g, b, a
    return bytes(out)


# ---------------------------------------------------------------------------
# Encoders (pure stdlib)
# ---------------------------------------------------------------------------
def write_png(path, size, rgba):
    def chunk(tag, data):
        raw = tag + data
        return struct.pack(">I", len(data)) + raw + struct.pack(">I", zlib.crc32(raw))

    stride = size * 4
    scanned = b"".join(b"\x00" + rgba[y * stride:(y + 1) * stride] for y in range(size))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(scanned, 9))
           + chunk(b"IEND", b""))
    path.write_bytes(png)


def write_ico(path, entries):
    """entries: [(size, png_bytes)] -> PNG-embedded ICO (Vista+)."""
    hdr = struct.pack("<HHH", 0, 1, len(entries))
    offset = 6 + 16 * len(entries)
    body = b""
    for size, png in entries:
        s = 0 if size >= 256 else size
        body += struct.pack("<BBBBHHII", s, s, 0, 0, 1, 32, len(png), offset)
        offset += len(png)
    path.write_bytes(hdr + body + b"".join(png for _, png in entries))


# ---------------------------------------------------------------------------
# SVG export (identical geometry: filled outlines of the same capsule chains)
# ---------------------------------------------------------------------------
def chain_outline(pts, hws, cap_steps=20):
    """Polygon outline of a capsule chain incl. round caps."""
    n = len(pts)
    normals = []
    for i in range(n):
        if i == 0:
            tx, ty = pts[1][0] - pts[0][0], pts[1][1] - pts[0][1]
        elif i == n - 1:
            tx, ty = pts[-1][0] - pts[-2][0], pts[-1][1] - pts[-2][1]
        else:
            tx, ty = pts[i + 1][0] - pts[i - 1][0], pts[i + 1][1] - pts[i - 1][1]
        ln = math.hypot(tx, ty) or 1.0
        normals.append((-ty / ln, tx / ln))

    def cap(center, hw, a_from, via):
        """Semicircle of radius hw around center from a_from to a_from+/-pi,
        sweeping through the direction `via`."""
        a_via = math.atan2(via[1], via[0])

        def adist(a, b):
            d = (a - b) % (2 * math.pi)
            return min(d, 2 * math.pi - d)

        sign = 1 if adist(a_from + math.pi / 2, a_via) < adist(a_from - math.pi / 2, a_via) else -1
        out = []
        for i in range(cap_steps + 1):
            a = a_from + sign * math.pi * i / cap_steps
            out.append((center[0] + hw * math.cos(a), center[1] + hw * math.sin(a)))
        return out

    outer = [(pts[i][0] + normals[i][0] * hws[i], pts[i][1] + normals[i][1] * hws[i])
             for i in range(n)]
    inner = [(pts[i][0] - normals[i][0] * hws[i], pts[i][1] - normals[i][1] * hws[i])
             for i in range(n)]
    t0 = (pts[1][0] - pts[0][0], pts[1][1] - pts[0][1])
    t1 = (pts[-1][0] - pts[-2][0], pts[-1][1] - pts[-2][1])
    n0, nn = normals[0], normals[-1]
    # loop order: start cap (-N0 -> +N0 via -T0), outer, end cap (+Nn -> -Nn via +Tn), inner
    start_cap = cap(pts[0], hws[0], math.atan2(-n0[1], -n0[0]), (-t0[0], -t0[1]))
    end_cap = cap(pts[-1], hws[-1], math.atan2(nn[1], nn[0]), (t1[0], t1[1]))
    poly = start_cap + outer + end_cap + inner[::-1]
    fmt = " ".join(f"{x:.2f},{y:.2f}" for x, y in poly)
    return f'<path d="M {fmt} Z"/>'


def build_svg(color):
    hexc = "#%02X%02X%02X" % color
    parts = [chain_outline(pts, hws) for pts, hws in CHAINS]
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {GRID} {GRID}" '
            f'width="{GRID}" height="{GRID}">\n'
            f'  <g fill="{hexc}">\n'
            + "\n".join(f"    {p}" for p in parts)
            + "\n  </g>\n</svg>\n")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--color", default="blue", help="blue | teal | #RRGGBB")
    ap.add_argument("--out", type=Path, default=Path(__file__).parent)
    args = ap.parse_args()

    if args.color.startswith("#"):
        c = tuple(int(args.color[i:i + 2], 16) for i in (1, 3, 5))
    else:
        c = COLORS[args.color]
    black, white = (0, 0, 0), (255, 255, 255)

    print(f"rasterizing {MASTER}x{MASTER} master ...")
    master = rasterize_master()
    a512 = box_resize(master, MASTER, 512)
    a256 = box_resize(a512, 512, 256)
    a128 = box_resize(a256, 256, 128)
    a64 = box_resize(a128, 128, 64)
    a48 = float_resize(a256, 256, 48)
    a32 = box_resize(a128, 128, 32)
    a16 = box_resize(a32, 32, 16)

    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    (out / "alt").mkdir(exist_ok=True)

    write_png(out / "logo-512.png", 512, render_rgba(a512, 512, c))
    write_png(out / "logo-256.png", 256, render_rgba(a256, 256, c))
    write_png(out / "logo-128.png", 128, render_rgba(a128, 128, c))
    write_png(out / "logo-32.png", 32, render_rgba(a32, 32, c))
    write_png(out / "logo-32-black.png", 32, render_rgba(a32, 32, black))
    write_png(out / "logo-32-white.png", 32, render_rgba(a32, 32, white))
    write_png(out / "logo-512-white.png", 512, render_rgba(a512, 512, white))
    write_ico(out / "logo.ico", [(s, render_rgba(a, s, c)) for s, a in
                                 [(16, a16), (32, a32), (48, a48), (64, a64),
                                  (128, a128), (256, a256)]])
    (out / "logo.svg").write_text(build_svg(c))

    # alt colorway previews (not part of the shipped set)
    write_png(out / "alt" / "logo-512-teal.png", 512, render_rgba(a512, 512, COLORS["teal"]))
    write_png(out / "alt" / "logo-512-black.png", 512, render_rgba(a512, 512, black))
    print(f"done -> {out}")


if __name__ == "__main__":
    main()
