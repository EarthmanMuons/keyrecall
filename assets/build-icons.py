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

  none      iOS / Play. The mark's bbox is 38 x 35.47 in the 48 viewBox, i.e.
            ~10.4% side padding, already inside Apple's 10-15% guidance.

  adaptive  Android. Bound by the mark's DIAGONAL against the 66dp safe circle,
            not its width -- full-bleed would put the corners 77% past it.

  badge     UI. Also diagonal-bound, but against a drawn circle. Uses the mark's
            true circumscribed radius (25.43) rather than half the bbox diagonal
            (25.99), since the 1.35 key corner radius pulls the extreme points in.
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

BRAND_BG = "#685C50"
KEY, SHARP = "#FFFFFF", "#0A0A0D"

MARK_W, MARK_H, MARK_X, MARK_Y = 38.0, 35.47, 5.0, 6.27
MARK_CX, MARK_CY = 24.0, 24.005
MARK_R = 25.433  # circumscribed radius about (MARK_CX, MARK_CY)
CANVAS, SAFE_D = 108.0, 66.0
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
    comes back the same colour as the naturals and vanishes. It has to be
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


def wrap_adaptive(svg: str) -> str:
    """48 viewBox onto a 108dp canvas, sized so the mark fits the 66dp safe circle."""
    scale = SAFE_D / math.hypot(MARK_W, MARK_H)
    off = (CANVAS - 48.0 * scale) / 2.0
    r = math.hypot(MARK_W * scale / 2, MARK_H * scale / 2)
    assert abs(r - SAFE_D / 2) < 1e-6, f"corners at r={r}, safe radius {SAFE_D / 2}"
    assert abs(off + (MARK_X + MARK_W / 2) * scale - CANVAS / 2) < 0.01, "not centred"
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS:g} {CANVAS:g}">\n'
        f'  <g transform="translate({off:.3f} {off:.3f}) scale({scale:.5f})">{inner(svg)}  </g>\n'
        "</svg>\n"
    )


def wrap_badge(svg: str) -> str:
    """Mark centred in a filled circle, everything outside it transparent.

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


WRAPS = {"adaptive": wrap_adaptive, "badge": wrap_badge}

TARGETS = [
    # --- iOS. Opaque, square, no pre-rounded corners; iOS masks and (26+) glasses it.
    # default name (image_path): assets/icon/icon.png
    Target("icon.png", "brand", px=1024, bg=BRAND_BG),
    # iOS 18+ dark variant. Apple recommends transparent here.
    # default name (image_path_ios_dark_transparent): assets/icon/icon_dark.png
    Target("icon_dark.png", "brand", px=1024),
    # iOS 18+ tinted variant. The mark is already achromatic, so this is the
    # same artwork on neutral rather than a separate desaturation pass.
    # default name (image_path_ios_tinted_grayscale): assets/icon/icon_tinted.png
    Target("icon_tinted.png", "brand", px=1024, bg="#8A8A8A"),
    # --- Android adaptive. Flat mark: the launcher applies its own elevation,
    # and baked shadow spread falls outside the safe circle.
    # default name (adaptive_icon_foreground): assets/icon/foreground.png
    Target("foreground.png", "flat", px=432, wrap="adaptive"),
    # default name (adaptive_icon_monochrome): assets/icon/monochrome.png
    Target("monochrome.png", "flat", px=432, wrap="adaptive", punch=True),
    # --- Store listing. No default name in flutter_launcher_icons; kept custom.
    Target("playstore.png", "brand", px=512, bg=BRAND_BG),
    # --- In-app UI. Vector, tokens left intact so the circle can be themed at
    # runtime via --kr-badge / --kr-key / --kr-sharp.
    Target("keyrecall-badge.svg", "brand", fmt="svg", wrap="badge", bake_tokens=False),
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not args.dry_run and not shutil.which("inkscape"):
        print("error: inkscape not on PATH", file=sys.stderr)
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

        stage = TMP / (t.name[:-4] + ".svg")
        stage.write_text(svg)
        cmd = [
            "inkscape",
            str(stage),
            "--export-type=png",
            "--export-area-page",
            f"--export-width={t.px}",
            f"--export-height={t.px}",
            f"--export-filename={BUILD / t.name}",
        ]
        if t.bg:
            cmd += [f"--export-background={t.bg}", "--export-background-opacity=255"]
        if args.dry_run:
            print(" ".join(cmd))
        else:
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
            print(
                f"  {t.name:26} {t.px}px     bg={t.bg or 'transparent':<12} {t.source}"
            )

    if not args.dry_run:
        shutil.rmtree(TMP)
        print(f"\nwrote {len(TARGETS)} files to {BUILD}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
