#!/usr/bin/env python3
"""
Build every derived icon artifact from the two source marks.

    ./build-icons.py              # write icon/
    ./build-icons.py --dry-run    # stage intermediate SVGs, print inkscape cmds

Sources (hand-edited, the only files you version):
    src/keyrecall-mark.svg               gradients + shadows, 48x48 viewBox
    src/keyrecall-mark-flat.svg          flat, 48x48 viewBox

Everything under icon/ is disposable.

Three placements, three different fits:

  square    iOS / Play. The source mark's own padding is only ~10.4% per side,
            which sits its corners closer to the tile edge than the WhatChord
            mark does. Re-fit to SQUARE_INSET so the two read as a pair.

  adaptive  Android. Bound by the mark's DIAGONAL against the 66dp safe circle,
            not its width -- full-bleed would put the corners 77% past it.

  badge     UI and the README. Also diagonal-bound, but against a drawn circle.
            Uses the mark's true circumscribed radius (25.73) rather than half
            the bbox diagonal (26.28), since the 1.35 key corner radius pulls
            the extreme points in.
"""

from __future__ import annotations

import argparse
import dataclasses
import math
import pathlib
import re
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
SRC, BUILD, TMP = HERE / "src" / "icon", HERE / "icon", HERE / "icon" / ".tmp"

BRAND_BG = "#800020"
KEY, SHARP = "#FFFFFF", "#0A0A0D"

MARK_W, MARK_H = 38.8, 35.47  # mark bbox in the 48 viewBox: x 5..43.8, y 6.27..41.74
MARK_CX, MARK_CY = 24.4, 24.005  # bbox center; the wider key gap pushed it right
MARK_R = 25.728  # circumscribed radius about (MARK_CX, MARK_CY)
CANVAS, SAFE_D = 108.0, 66.0
SQUARE_INSET = 0.14  # clear margin per edge on the mark's wide axis
SQUARE_OPTICAL = 0.015  # leftward optical correction, fraction of the canvas
BADGE_R, BADGE_FILL = 22.0, 0.84  # Material 44dp circle keyline; mark fills 84%

SOURCES = {
    "flat": "keyrecall-mark-flat.svg",
    "brand": "keyrecall-mark.svg",
}

SHARP_EL = re.compile(
    r"[ \t]*<path[^>]*--kr-sharp[^>]*?d=\"([^\"]+)\"[^>]*/>\n?", re.DOTALL
)
KEY_GROUP = re.compile(r"<g fill=\"[^\"]*\" style=\"fill:var\(--kr-key[^\"]*\">")
ROOT = re.compile(r"<svg\b[^>]*>(.*)</svg>\s*$", re.DOTALL)


@dataclasses.dataclass(frozen=True)
class Target:
    name: str
    source: str
    fmt: str = "png"
    px: int | None = None
    bg: str | None = None
    key: str = KEY
    sharp: str = SHARP
    wrap: str | None = None
    punch: bool = False
    bake_tokens: bool = True


def inner(svg: str) -> str:
    m = ROOT.search(svg)
    if not m:
        raise SystemExit("no <svg> root")
    return m.group(1)


def flatten(svg: str, key: str, sharp: str) -> str:
    """Inkscape cannot resolve CSS custom properties; bake them to literals."""
    svg = re.sub(r"var\(--kr-key,[^)]*\)", key, svg)
    svg = re.sub(r"var\(--kr-sharp,[^)]*\)", sharp, svg)
    if "var(--" in svg:
        raise SystemExit(
            f"unresolved tokens: {set(re.findall(r'var\(--[^)]*\)', svg))}"
        )
    return svg


def punch_sharp(svg: str) -> str:
    """Turn the sharp into a real hole for the Android themed-icon layer.

    A themed icon is recoloured wholesale from its alpha, so a painted sharp
    comes back the same color as the naturals and vanishes. It has to be
    absent from the alpha channel.

    A mask, not a clip on the keys with the sharp drawn back over it: that
    composites wrong at the boundary. An edge pixel with sharp coverage c ends
    up white*(1-c)^2 + bg*c*(1-c) instead of white*(1-c), which reads as a
    hairline outline. Mask values are pure #FFF/#000, so the sRGB-vs-linearRGB
    luminance ambiguity affecting grey masks does not arise.
    """
    m = SHARP_EL.search(svg)
    if not m:
        raise SystemExit("punch_sharp: no element carrying --kr-sharp found")
    svg = SHARP_EL.sub("", svg, count=1)
    svg = svg.replace(
        "</defs>",
        '    <mask id="kr-punch" maskUnits="userSpaceOnUse" x="0" y="0" width="48" height="48">\n'
        '      <rect x="0" y="0" width="48" height="48" fill="#FFFFFF"/>\n'
        f'      <path fill="#000000" d="{m.group(1)}"/>\n'
        "    </mask>\n  </defs>",
        1,
    )
    svg, n = KEY_GROUP.subn(
        lambda g: g.group(0)[:-1] + ' mask="url(#kr-punch)">', svg, count=1
    )
    if n != 1:
        raise SystemExit("punch_sharp: key group not found")
    return svg


def place(svg: str, canvas: float, scale: float, nudge: float = 0.0) -> str:
    """Scale the mark about its own bbox center and drop it in the canvas center.

    Centering on MARK_CX/MARK_CY rather than the 48 viewBox center matters: the
    mark is not centered in its own viewBox, so scaling the box would leave the
    keys off to one side. `nudge` shifts left from there, in canvas units.
    """
    tx, ty = canvas / 2 - MARK_CX * scale - nudge, canvas / 2 - MARK_CY * scale
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {canvas:g} {canvas:g}">\n'
        f'  <g transform="translate({tx:.3f} {ty:.3f}) scale({scale:.5f})">{inner(svg)}  </g>\n'
        "</svg>\n"
    )


def wrap_square(svg: str) -> str:
    """Same 48 canvas, mark re-fit to leave SQUARE_INSET clear on the wide axis.

    Width-bound, not diagonal-bound: iOS and Play both round the tile, so the
    edges are what the eye measures against. The taller-than-wide margin that
    falls out (~17%) is what pulls the corners in off the mask.

    Then shifted left off true center. The three receding keys run at 25/50/75%,
    so the mark's ink centroid sits ~7% of the canvas right of its bbox center
    and a geometrically centered mark reads as having a fat left margin. Only
    the square fit does this: it is the one placement with slack to spend, and
    the diagonal-bound fits are already up against a hard boundary.
    """
    return place(svg, 48.0, (1 - 2 * SQUARE_INSET) * 48.0 / MARK_W,
                 SQUARE_OPTICAL * 48.0)


def wrap_adaptive(svg: str) -> str:
    """48 viewBox onto a 108dp canvas, sized so the mark fits the 66dp safe circle."""
    scale = SAFE_D / math.hypot(MARK_W, MARK_H)
    r = math.hypot(MARK_W * scale / 2, MARK_H * scale / 2)
    assert abs(r - SAFE_D / 2) < 1e-6, f"corners at r={r}, safe radius {SAFE_D / 2}"
    return place(svg, CANVAS, scale)


def wrap_badge(svg: str) -> str:
    """Mark centered in a filled circle, everything outside it transparent.

    Clip and transform live on separate groups on purpose: a clip-path is
    resolved in the user space established *after* the element's own transform,
    so putting both on one element would scale the clip circle too.
    """
    scale = BADGE_R * BADGE_FILL / MARK_R
    tx, ty = 24 - MARK_CX * scale, 24 - MARK_CY * scale
    reach = BADGE_R * BADGE_FILL + (0.85 + 3 * 0.8) * scale  # shadow offset + ~3 sigma
    assert reach < BADGE_R, f"shadow reaches {reach:.2f}, circle is {BADGE_R}"
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="48" height="48" '
        'role="img" aria-label="KeyRecall">\n'
        "  <defs>\n"
        f'    <clipPath id="kr-badge-clip"><circle cx="24" cy="24" r="{BADGE_R:g}"/></clipPath>\n'
        "  </defs>\n"
        f'  <circle cx="24" cy="24" r="{BADGE_R:g}" fill="{BRAND_BG}" '
        f'style="fill:var(--kr-badge,{BRAND_BG})"/>\n'
        '  <g clip-path="url(#kr-badge-clip)">\n'
        f'    <g transform="translate({tx:.3f} {ty:.3f}) scale({scale:.5f})">{inner(svg)}    </g>\n'
        "  </g>\n"
        "</svg>\n"
    )


WRAPS = {"square": wrap_square, "adaptive": wrap_adaptive, "badge": wrap_badge}

TARGETS = [
    # --- iOS. Opaque, square, no pre-rounded corners; iOS masks and (26+) glasses it.
    # flutter_launcher_icons: image_path / image_path_android / image_path_ios
    Target("icon.png", "brand", px=1024, bg=BRAND_BG, wrap="square"),
    # iOS 18+ dark variant. Apple recommends transparent here.
    # flutter_launcher_icons: image_path_ios_dark_transparent
    Target("icon-dark.png", "brand", px=1024, wrap="square"),
    # iOS 18+ tinted (and iOS 26 clear) variant. Apple wants an opaque
    # GRAYSCALE image here and maps its luminance onto the system tint ramp, so
    # the background has to be black: a mid-grey one tints to a filled light
    # tile, which is the opposite of the dark-tile-with-light-glyph the rest of
    # the home screen shows. The mark is already achromatic, so no separate
    # desaturation pass is needed.
    # flutter_launcher_icons: image_path_ios_tinted_grayscale
    Target("icon-tinted.png", "brand", px=1024, bg="#000000", wrap="square"),
    # --- Android adaptive. Flat mark: the launcher applies its own elevation,
    # and baked shadow spread falls outside the safe circle.
    # flutter_launcher_icons: adaptive_icon_foreground
    Target("foreground.png", "flat", px=432, wrap="adaptive"),
    # flutter_launcher_icons: adaptive_icon_monochrome
    Target("monochrome.png", "flat", px=432, wrap="adaptive", punch=True),
    # --- Store listing. Not consumed by flutter_launcher_icons.
    Target("play-store.png", "brand", px=512, bg=BRAND_BG, wrap="square"),
    # --- In-app UI. Vector, tokens left intact so the circle can be themed at
    # runtime via --kr-badge / --kr-key / --kr-sharp.
    Target("keyrecall-badge.svg", "brand", fmt="svg", wrap="badge", bake_tokens=False),
    # --- README. 200px to match the WhatChord logo, so the two repositories
    # present at the same size. Transparent, because GitHub renders it against
    # both themes.
    Target("keyrecall-logo.webp", "brand", fmt="webp", px=200, wrap="badge"),
    # --- Onboarding. The same badge the README shows, raster because Flutter
    # has no SVG decoder of its own, and at 512px so it stays sharp at 3x on
    # the largest size the welcome screen draws it.
    Target("keyrecall-badge.webp", "brand", fmt="webp", px=512, wrap="badge"),
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    needed = ["inkscape"] + (["cwebp"] if any(t.fmt == "webp" for t in TARGETS) else [])
    missing = [tool for tool in needed if not shutil.which(tool)]
    if not args.dry_run and missing:
        print(f"error: not on PATH: {', '.join(missing)}", file=sys.stderr)
        return 1

    if BUILD.exists():
        shutil.rmtree(BUILD)
    TMP.mkdir(parents=True)

    for t in TARGETS:
        svg = (SRC / SOURCES[t.source]).read_text()
        if t.punch:
            svg = punch_sharp(svg)
        if t.bake_tokens:
            svg = flatten(svg, t.key, t.sharp)
        if t.wrap:
            svg = WRAPS[t.wrap](svg)

        if t.fmt == "svg":
            (BUILD / t.name).write_text(svg)
            print(f"  {t.name:26} vector    tokens kept   {t.source}")
            continue

        stem = t.name.rsplit(".", 1)[0]
        stage = TMP / (stem + ".svg")
        stage.write_text(svg)
        # Inkscape rasterizes; WebP goes through a PNG it does not keep.
        png = (TMP if t.fmt == "webp" else BUILD) / (stem + ".png")
        cmd = [
            "inkscape",
            str(stage),
            "--export-type=png",
            "--export-area-page",
            f"--export-width={t.px}",
            f"--export-height={t.px}",
            f"--export-filename={png}",
        ]
        if t.bg:
            cmd += [f"--export-background={t.bg}", "--export-background-opacity=255"]
        # Lossless: the mark is flat fills and one gradient, which cwebp's
        # lossless mode encodes smaller than quality 90 and without ringing
        # around the key edges.
        webp = ["cwebp", "-lossless", "-quiet", str(png), "-o", str(BUILD / t.name)]
        if args.dry_run:
            print(" ".join(cmd))
            if t.fmt == "webp":
                print(" ".join(webp))
        else:
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
            if t.fmt == "webp":
                subprocess.run(webp, check=True)
            print(
                f"  {t.name:26} {t.px}px     bg={t.bg or 'transparent':<12} {t.source}"
            )

    if not args.dry_run:
        shutil.rmtree(TMP)
        print(f"\nwrote {len(TARGETS)} files to {BUILD}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
