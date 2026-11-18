"""Builds every app icon, splash mark and brand master from one definition.

    python scripts/build_app_icons.py

The Liftanium mark is a faceted titanium hexagon with an L cut through it
(chosen 2026-11-15). Its geometry and colours live only in this file, on a
512-unit grid, and everything below is generated from them, so the Android
vectors and the PNGs cannot drift apart:

- assets/branding/: liftanium-mark.svg, liftanium-icon-1024.png and
  liftanium-icon-512.png (rounded, transparent corners), and
  liftanium-icon-512-opaque.png (square, no alpha: the Play Console icon)
- Android: the adaptive foreground (also the Android 12+ splash icon), the
  themed-icon monochrome, the notification glyph, and the legacy mipmaps
- iOS: the AppIcon set (square, opaque; iOS applies its own mask) and the
  launch image
- web: favicon, Icon-192/512 and the maskable pair

The background navy is not defined here: it stays `@color/ironyx_navy` and
`ic_launcher_background.xml`, which this script does not touch.

Facets are flat colours, not gradients, because an Android vector can draw
those exactly. Needs Pillow (`pip install pillow`).
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android/app/src/main/res"
BRANDING = ROOT / "assets/branding"
IOS_ICONS = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
IOS_LAUNCH = ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
WEB = ROOT / "web"

GRID = 512
SUPERSAMPLE = 4

# Background: the same diagonal navy as ic_launcher_background.xml.
NAVY_START = (0x0B, 0x16, 0x28)
NAVY_END = (0x12, 0x2D, 0x48)
TILE_RADIUS = 112  # rounded-tile corner, in grid units

# The hexagon: pointy top, centred, radius in grid units.
HEX_CENTRE = (256.0, 256.0)
HEX_RADIUS = 176.0

# Facet colours, clockwise from the upper-right facet: lit from the upper
# left, so the left-hand facets are lightest and the lower ones darkest.
FACETS = ["#72E3D3", "#43C7C4", "#26A4AC", "#1E858F", "#3DB3AD", "#61E2CF"]

# The L, cut through the hexagon (navy in colour, a hole in the glyphs).
# Its box sits a little right of centre, which balances the L's
# left-heavy weight optically.
L_CUT = [(206, 170), (262, 170), (262, 288), (330, 288), (330, 342), (206, 342)]
L_COLOUR = "#0F2238"

# How the 512 grid maps onto each Android vector. The hexagon spans
# 2 * HEX_RADIUS = 352 units.
#  - adaptive foreground, 108dp canvas, 72dp visible: radius 24.75dp, the
#    same share of the visible tile as on the 512 master (176 / 256 of
#    the half-width is about 0.69, and 24.75 / 36 is the same), and well
#    inside the 33dp safe circle
#  - notification glyph, 24dp: the hexagon fills 22dp of it
ADAPTIVE_SCALE = 24.75 / HEX_RADIUS
NOTIFICATION_SCALE = 22.0 / (2 * HEX_RADIUS)


def hex_vertices() -> list[tuple[float, float]]:
    cx, cy = HEX_CENTRE
    return [
        (
            cx + HEX_RADIUS * math.cos(math.radians(angle)),
            cy + HEX_RADIUS * math.sin(math.radians(angle)),
        )
        for angle in range(-90, 270, 60)
    ]


def facet_triangles() -> list[list[tuple[float, float]]]:
    v = hex_vertices()
    return [[HEX_CENTRE, v[i], v[(i + 1) % 6]] for i in range(6)]


def rgb(colour: str) -> tuple[int, int, int]:
    return tuple(int(colour[i : i + 2], 16) for i in (1, 3, 5))  # type: ignore[return-value]


def fmt(n: float) -> str:
    return f"{n:.2f}".rstrip("0").rstrip(".")


def path_data(points: list[tuple[float, float]]) -> str:
    head, *rest = points
    return (
        f"M{fmt(head[0])},{fmt(head[1])} "
        + " ".join(f"L{fmt(x)},{fmt(y)}" for x, y in rest)
        + " Z"
    )


# --- raster -----------------------------------------------------------------


def navy_gradient(size: int) -> Image.Image:
    small = Image.new("RGB", (256, 256))
    px = small.load()
    for y in range(256):
        for x in range(256):
            t = (x + y) / 510
            px[x, y] = tuple(
                round(a + (b - a) * t) for a, b in zip(NAVY_START, NAVY_END)
            )
    return small.resize((size, size), Image.Resampling.BICUBIC)


def draw_mark(
    image: Image.Image, scale: float, offset: tuple[float, float]
) -> None:
    """Draws the hexagon and the L onto [image], grid unit -> scale px."""
    draw = ImageDraw.Draw(image)

    def place(points):
        return [(offset[0] + x * scale, offset[1] + y * scale) for x, y in points]

    for triangle, colour in zip(facet_triangles(), FACETS):
        draw.polygon(place(triangle), fill=rgb(colour))
    draw.polygon(place(L_CUT), fill=rgb(L_COLOUR))


def render(
    size: int,
    *,
    background: bool = True,
    rounded: bool = False,
    mark_scale: float = 1.0,
) -> Image.Image:
    """The icon at [size] px.

    [mark_scale] shrinks the mark about the centre (maskable icons need it
    inside their safe zone). Without [background] the mark sits on
    transparency.
    """
    big = size * SUPERSAMPLE
    if background:
        image = navy_gradient(big).convert("RGBA")
    else:
        image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    unit = big / GRID * mark_scale
    margin = big * (1 - mark_scale) / 2
    draw_mark(image, unit, (margin, margin))
    if rounded:
        mask = Image.new("L", (big, big), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, big - 1, big - 1), radius=TILE_RADIUS * big / GRID, fill=255
        )
        image.putalpha(mask)
    return image.resize((size, size), Image.Resampling.LANCZOS)


def save_png(image: Image.Image, path: Path, *, opaque: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    (image.convert("RGB") if opaque else image).save(path, format="PNG", optimize=True)
    print(f"wrote {path.relative_to(ROOT)} ({image.width}x{image.height})")


# --- vectors ----------------------------------------------------------------

VECTOR_HEAD = """<?xml version="1.0" encoding="utf-8"?>
<!-- GENERATED by scripts/build_app_icons.py: edit the script, not this file.
     {note} -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="{dp}dp"
    android:height="{dp}dp"
    android:viewportWidth="{dp}"
    android:viewportHeight="{dp}">
    <group
        android:scaleX="{scale}"
        android:scaleY="{scale}"
        android:translateX="{shift}"
        android:translateY="{shift}">
"""
VECTOR_TAIL = """    </group>
</vector>
"""


def vector(dp: int, scale: float, note: str, body: str) -> str:
    shift = dp / 2 - HEX_CENTRE[0] * scale
    return (
        VECTOR_HEAD.format(dp=dp, scale=fmt(round(scale, 5)), shift=fmt(round(shift, 3)), note=note)
        + body
        + VECTOR_TAIL
    )


def colour_body() -> str:
    lines = [
        f'        <path\n            android:fillColor="{colour}"\n'
        f'            android:pathData="{path_data(tri)}" />\n'
        for tri, colour in zip(facet_triangles(), FACETS)
    ]
    lines.append(
        f'        <path\n            android:fillColor="{L_COLOUR}"\n'
        f'            android:pathData="{path_data(L_CUT)}" />\n'
    )
    return "".join(lines)


def glyph_body() -> str:
    """The hexagon with the L as a hole, for alpha-mask uses."""
    return (
        '        <path\n            android:fillColor="#FFFFFF"\n'
        '            android:fillType="evenOdd"\n'
        f'            android:pathData="{path_data(hex_vertices())} {path_data(L_CUT)}" />\n'
    )


def write_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {path.relative_to(ROOT)}")


def svg_master() -> str:
    facets = "\n".join(
        f'  <path d="{path_data(tri)}" fill="{colour}"/>'
        for tri, colour in zip(facet_triangles(), FACETS)
    )
    start = "#%02X%02X%02X" % NAVY_START
    end = "#%02X%02X%02X" % NAVY_END
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {GRID} {GRID}">
  <!-- GENERATED by scripts/build_app_icons.py: edit the script, not this file. -->
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{start}"/>
      <stop offset="1" stop-color="{end}"/>
    </linearGradient>
  </defs>
  <rect width="{GRID}" height="{GRID}" rx="{TILE_RADIUS}" fill="url(#bg)"/>
{facets}
  <path d="{path_data(L_CUT)}" fill="{L_COLOUR}"/>
</svg>
"""


# --- main -------------------------------------------------------------------


def main() -> None:
    # Brand masters.
    BRANDING.mkdir(parents=True, exist_ok=True)
    write_text(BRANDING / "liftanium-mark.svg", svg_master())
    save_png(render(1024, rounded=True), BRANDING / "liftanium-icon-1024.png")
    save_png(render(512, rounded=True), BRANDING / "liftanium-icon-512.png")
    save_png(render(512), BRANDING / "liftanium-icon-512-opaque.png", opaque=True)

    # Android vectors.
    write_text(
        RES / "drawable/ic_launcher_foreground.xml",
        vector(
            108,
            ADAPTIVE_SCALE,
            "Adaptive-icon foreground over ic_launcher_background; also the\n"
            "     Android 12+ splash icon and the pre-12 splash (launch_background.xml).",
            colour_body(),
        ),
    )
    write_text(
        RES / "drawable/ic_launcher_monochrome.xml",
        vector(
            108,
            ADAPTIVE_SCALE,
            "Single-colour mark for Android 13+ themed icons; the system tints it.",
            glyph_body(),
        ),
    )
    write_text(
        RES / "drawable/ic_notification.xml",
        vector(
            24,
            NOTIFICATION_SCALE,
            "Status-bar icon for timer notifications. Android renders these as a\n"
            "     flat alpha mask, so this is the hexagon with the L cut out.",
            glyph_body(),
        ),
    )

    # Android legacy launcher icons (Android 7.1 and below).
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        save_png(render(size, rounded=True), RES / f"mipmap-{density}/ic_launcher.png")

    # iOS: every size Contents.json lists, square and opaque.
    contents = json.loads((IOS_ICONS / "Contents.json").read_text(encoding="utf-8"))
    for entry in contents["images"]:
        if "filename" not in entry:
            continue
        points = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        size = round(points * scale)
        save_png(render(size), IOS_ICONS / entry["filename"], opaque=True)
    # The launch image is 128pt, mark only, over the storyboard's navy.
    for suffix, scale in {"": 1, "@2x": 2, "@3x": 3}.items():
        save_png(
            render(128 * scale, background=False),
            IOS_LAUNCH / f"LaunchImage{suffix}.png",
        )

    # Web.
    save_png(render(32, rounded=True), WEB / "favicon.png")
    for size in (192, 512):
        save_png(render(size, rounded=True), WEB / f"icons/Icon-{size}.png")
        # Maskable icons are cropped to a circle of 80% of the width: full
        # bleed, with the mark shrunk to sit inside that.
        save_png(render(size, mark_scale=0.8), WEB / f"icons/Icon-maskable-{size}.png")


if __name__ == "__main__":
    main()
