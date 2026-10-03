#!/usr/bin/env python3
"""localU platform launcher icon generator.

Derives the full per-platform launcher set from the same capsule-chain
geometry as generate.py (single source of truth), mirroring the layout of
LocalSend's own launcher assets — measured from the repo PNGs:

    Android legacy ic_launcher / _round   white circle Ø 0.917 + glyph 0.703
    Android adaptive ic_launcher_foreground / _monochrome   glyph 0.512 (108dp grid)
    Android ic_launcher_quicktile_foreground                white glyph 0.611
    iOS AppIcon.appiconset                white full-bleed + glyph 0.762
    macOS AppIcon.appiconset (logo-1024-mac-*)              transparent + glyph 0.805
    Windows runner/resources/app_icon.ico                   transparent glyph 16-256
    web/icons/Icon-*                      white full-bleed + glyph 0.62 (maskable 0.55)

Output drops in under launchers/<platform>/ with repo-identical paths, e.g.

    cp -R launchers/android/app/src/main/res/* app/android/app/src/main/res/
    cp -R launchers/ios/Runner/Assets.xcassets/AppIcon.appiconset/*  <same path>
    cp -R launchers/macos/Runner/Assets.xcassets/AppIcon.appiconset/* <same path>
    cp launchers/windows/runner/resources/app_icon.ico <same path>
    cp launchers/web/icons/* app/web/icons/

Usage:
    python3 make_launchers.py                 # USB blue (signed off)
    python3 make_launchers.py --color teal
"""

import argparse
import subprocess
from math import isqrt
from pathlib import Path

import generate as G

# glyph-box fraction of the canvas, measured from LocalSend's launcher PNGs
FRAC_LEGACY = 0.703       # glyph inside legacy launcher / round
FRAC_CIRCLE = 0.917       # white circle diameter in legacy launcher
FRAC_ADAPTIVE = 0.512     # foreground + monochrome glyph on the 108dp grid
FRAC_QUICKTILE = 0.611    # quick-settings tile glyph
FRAC_IOS = 0.762          # glyph on the white full-bleed iOS tile
FRAC_MAC = 0.805          # bare glyph on transparent (macOS)
FRAC_WEB = 0.62           # PWA "any" icon
FRAC_WEB_MASKABLE = 0.55  # PWA maskable (safe zone = central 80%)

ANDROID_DENSITIES = [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                     ("xxhdpi", 144), ("xxxhdpi", 192)]
ADAPTIVE_SIZES = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

# every PNG in the iOS ladder (from Contents.json): filename -> pixel size
IOS_LADDER = {
    "Icon-App-20.png": 20, "Icon-App-20@2x.png": 40, "Icon-App-20@3x.png": 60,
    "Icon-App-29.png": 29, "Icon-App-29@2x.png": 58, "Icon-App-29@3x.png": 87,
    "Icon-App-40.png": 40, "Icon-App-40@2x.png": 80, "Icon-App-40@3x.png": 120,
    "Icon-App-60@2x.png": 120, "Icon-App-60@3x.png": 180,
    "Icon-App-76.png": 76, "Icon-App-76@2x.png": 152,
    "Icon-App-83.5@2x.png": 167, "Icon-App-1024.png": 1024,
}
MACOS_SIZES = [16, 32, 64, 128, 256, 512, 1024]

IO_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>"""

BG_XML = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#FFFFFF</color>
</resources>"""


# ---------------------------------------------------------------------------
# resampling helpers
# ---------------------------------------------------------------------------
class GlyphPyramid:
    """Logo alpha at power-of-two levels; float-resamples to any target size."""

    def __init__(self, master):
        self.levels = {G.MASTER: master}
        a, size = master, G.MASTER
        for next_size in (512, 256, 128, 64, 32, 16):
            a = G.box_resize(a, size, next_size)
            size = next_size
            self.levels[size] = a
        self.cache = {}

    def at(self, size):
        """Glyph alpha at `size` px, anti-aliased from the nearest larger level."""
        if size in self.cache:
            return self.cache[size]
        big = min((s for s in self.levels if s >= size * 2), default=max(self.levels))
        a = G.float_resize(self.levels[big], big, size)
        self.cache[size] = a
        return a


def wp(path, size, rgba):
    """write_png + parent mkdir (generate.write_png does not create dirs)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    G.write_png(path, size, rgba)


def glyph_alpha(pyramid, canvas, frac):
    return pyramid.at(max(1, round(canvas * frac)))


# ---------------------------------------------------------------------------
# canvas treatments (all centered)
# ---------------------------------------------------------------------------
def on_white(ga, canvas, color):
    """Opaque white full-bleed tile, `ga` (side <= canvas) centered on top."""
    r, g, b = color
    gs = isqrt(len(ga))
    ox = oy = (canvas - gs) // 2
    out = bytearray(b"\xff" * (canvas * canvas * 4))
    for gy in range(gs):
        for gx in range(gs):
            a = ga[gy * gs + gx]
            if a == 0:
                continue
            j = ((oy + gy) * canvas + ox + gx) * 4
            inv = 255 - a
            out[j] = r * a // 255 + inv
            out[j + 1] = g * a // 255 + inv
            out[j + 2] = b * a // 255 + inv
    return bytes(out)


def on_transparent(ga, canvas, color, base=None):
    """Transparent canvas, glyph buffer `ga` (side <= canvas) centered,
    alpha-blended over optional `base` RGBA."""
    r, g, b = color
    gs = isqrt(len(ga))
    ox = oy = (canvas - gs) // 2
    out = bytearray(base) if base is not None else bytearray(canvas * canvas * 4)
    for gy in range(gs):
        for gx in range(gs):
            a = ga[gy * gs + gx]
            if a == 0:
                continue
            j = ((oy + gy) * canvas + ox + gx) * 4
            if base is None:
                out[j], out[j + 1], out[j + 2], out[j + 3] = r, g, b, a
            else:
                br, bg_, bb, ba = base[j], base[j + 1], base[j + 2], base[j + 3]
                sa = a + ba * (255 - a) // 255
                out[j] = (r * a + br * ba * (255 - a) // 255) // sa
                out[j + 1] = (g * a + bg_ * ba * (255 - a) // 255) // sa
                out[j + 2] = (b * a + bb * ba * (255 - a) // 255) // sa
                out[j + 3] = sa
    return bytes(out)


def white_circle(canvas, diameter_frac):
    """White circle (AA) on transparent — the legacy Android launcher base."""
    big = canvas * 4
    radius = diameter_frac * big / 2
    cx = cy = big / 2
    hard = bytearray(big * big)
    for y in range(big):
        dy = y + 0.5 - cy
        row = y * big
        for x in range(big):
            dx = x + 0.5 - cx
            if dx * dx + dy * dy <= radius * radius:
                hard[row + x] = 255
    return G.box_resize(hard, big, canvas)


# ---------------------------------------------------------------------------
# platform builders
# ---------------------------------------------------------------------------
def android_legacy(pyramid, color, out):
    for dpi, size in ANDROID_DENSITIES:
        base = on_transparent(white_circle(size, FRAC_CIRCLE), size, (255, 255, 255))
        rgba = on_transparent(glyph_alpha(pyramid, size, FRAC_LEGACY), size, color, base)
        d = out / f"android/app/src/main/res/mipmap-{dpi}"
        for name in ("ic_launcher.png", "ic_launcher_round.png"):
            wp(d / name, size, rgba)


def android_adaptive(pyramid, color, out):
    for dpi, size in ADAPTIVE_SIZES.items():
        ga = glyph_alpha(pyramid, size, FRAC_ADAPTIVE)
        d = out / f"android/app/src/main/res/mipmap-{dpi}"
        wp(d / "ic_launcher_foreground.png", size,
                    on_transparent(ga, size, color))
        wp(d / "ic_launcher_monochrome.png", size,
                    on_transparent(ga, size, (255, 255, 255)))
        q = glyph_alpha(pyramid, size, FRAC_QUICKTILE)
        wp(d / "ic_launcher_quicktile_foreground.png", size,
                    on_transparent(q, size, (255, 255, 255)))
    res = out / "android/app/src/main/res"
    (res / "mipmap-anydpi-v26").mkdir(parents=True, exist_ok=True)
    (res / "mipmap-anydpi-v26/ic_launcher.xml").write_text(IO_XML)
    (res / "values").mkdir(parents=True, exist_ok=True)
    (res / "values/ic_launcher_background.xml").write_text(BG_XML)


def ios_appiconset(pyramid, color, out):
    d = out / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, size in IOS_LADDER.items():
        wp(d / name, size, on_white(glyph_alpha(pyramid, size, FRAC_IOS), size, color))


def macos_appiconset(pyramid, color, out):
    d = out / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    icons = {}
    for size in MACOS_SIZES:
        rgba = on_transparent(glyph_alpha(pyramid, size, FRAC_MAC), size, color)
        wp(d / f"logo-1024-mac-{size}.png", size, rgba)
        icons[size] = rgba
    return icons


def build_icns(icons, out):
    """Assemble launchers/macos/localu.icns via iconutil (macOS only)."""
    iconset = out / "macos/localu.iconset"
    iconset.mkdir(parents=True, exist_ok=True)
    mapping = {
        "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
    }
    for name, size in mapping.items():
        (iconset / name).write_bytes(
            Path(out / f"macos/Runner/Assets.xcassets/AppIcon.appiconset/logo-1024-mac-{size}.png")
            .read_bytes())
    icns = out / "macos/localu.icns"
    r = subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  ! iconutil failed ({r.stderr.strip()}); keeping .iconset only")
    else:
        print(f"  wrote {icns}")


def windows(pyramid, color, out):
    a256 = glyph_alpha(pyramid, 256, 1.0)
    ladder = [(16, pyramid.at(16)), (32, pyramid.at(32)), (48, G.float_resize(a256, 256, 48)),
              (64, pyramid.at(64)), (128, pyramid.at(128)), (256, a256)]
    d = out / "windows/runner/resources"
    d.mkdir(parents=True, exist_ok=True)
    G.write_ico(d / "app_icon.ico", [(s, G.render_rgba(a, s, color)) for s, a in ladder])


def web(pyramid, color, out):
    d = out / "web/icons"
    for size in (192, 512):
        wp(d / f"Icon-{size}.png", size,
                    on_white(glyph_alpha(pyramid, size, FRAC_WEB), size, color))
        wp(d / f"Icon-maskable-{size}.png", size,
                    on_white(glyph_alpha(pyramid, size, FRAC_WEB_MASKABLE), size, color))


def copy_catalogs(_pyramid, _color, out):
    """Contents.json catalogs are copied verbatim from the repo (same filenames)."""
    app = Path(__file__).resolve().parents[2] / "app"
    for rel in ("ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json",
                "macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"):
        src = app / rel
        dst = out / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(src.read_bytes())


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--color", default="blue", help="blue | teal | #RRGGBB")
    ap.add_argument("--out", type=Path, default=Path(__file__).parent / "launchers")
    args = ap.parse_args()
    if args.color.startswith("#"):
        c = tuple(int(args.color[i:i + 2], 16) for i in (1, 3, 5))
    else:
        c = G.COLORS[args.color]

    print(f"rasterizing {G.MASTER}x{G.MASTER} master ...")
    pyramid = GlyphPyramid(G.rasterize_master())

    out = args.out
    for step in (android_legacy, android_adaptive, ios_appiconset,
                 lambda p, col, o: build_icns(macos_appiconset(p, col, o), o),
                 windows, web, copy_catalogs):
        step(pyramid, c, out)
        print(f"  {step.__name__} done")
    print(f"done -> {out}")


if __name__ == "__main__":
    main()
