#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["fonttools>=4.50", "skia-pathops>=0.8"]
# ///
"""
Build the KeyRecall Symbols fonts from the vendored Bravura.

    ./build-symbols.py            # write fonts/

Bravura's U+266D-U+266F and U+1D12A-U+1D12B are staff-sized and centered on
the baseline, so in running text they sit low and inflate the line. Its SMuFL
chord-symbol accidentals are drawn for text instead; this remaps them to the
Unicode accidentals so the theme can put the family ahead of the platform font
and leave every other character to it.

Bravura ships one weight, so Bold is synthesized by stroking each outline.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from pathlib import Path

import pathops
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.transformPen import TransformPen
from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables._c_m_a_p import cmap_format_4, cmap_format_12

ASSETS = Path(__file__).resolve().parent
SOURCE = (
    ASSETS.parent
    / "third_party/crisp_notation/packages/crisp_notation/assets/fonts/Bravura.otf"
)
OUTPUT_DIR = ASSETS / "fonts"

FAMILY = "KeyRecall Symbols"
VERSION = "1.000"

GLYPHS = {
    0xED60: 0x266D,  # csymAccidentalFlat
    0xED61: 0x266E,  # csymAccidentalNatural
    0xED62: 0x266F,  # csymAccidentalSharp
    0xED63: 0x1D12A,  # csymAccidentalDoubleSharp
    0xED64: 0x1D12B,  # csymAccidentalDoubleFlat
}

# Font units per side, at 1000 units per em. SMuFL glyphs carry no
# sidebearings because an engraver spaces them.
SIDE_PAD = 50

# A stem as the leftmost ink reads closer to the letter before it than the
# open side of a sharp does, so those glyphs take more room on the left.
STEM_LEFT_PAD = 80
STEM_FIRST = {0x266D, 0x266E, 0x1D12B}

BOLD_STRENGTH = 20

# The platform UI fonts split their extent about 4:1 above and below the
# baseline, so a run in this font neither raises nor lowers a shared line.
ASCENT = 800
DESCENT = 200


@dataclass(frozen=True)
class Instance:
    style: str
    weight: int

    @property
    def bold(self) -> bool:
        return self.weight >= 700

    @property
    def ps_name(self) -> str:
        return f"{FAMILY.replace(' ', '')}-{self.style}"

    @property
    def full_name(self) -> str:
        return FAMILY if self.style == "Regular" else f"{FAMILY} {self.style}"


INSTANCES = [Instance("Regular", 400), Instance("Bold", 700)]


def build_cmap(mapping: dict[int, str]):
    def subtable(fmt, platform_id: int, encoding_id: int):
        table = (cmap_format_4 if fmt == 4 else cmap_format_12)(fmt)
        table.platformID = platform_id
        table.platEncID = encoding_id
        table.language = 0
        if fmt == 4:
            table.cmap = {cp: name for cp, name in mapping.items() if cp <= 0xFFFF}
        else:
            table.reserved = table.length = table.nGroups = 0
            table.cmap = dict(mapping)
        return table

    cmap = newTable("cmap")
    cmap.tableVersion = 0
    cmap.tables = [
        subtable(4, 0, 3),
        subtable(4, 3, 1),
        subtable(12, 0, 4),
        subtable(12, 3, 10),
    ]
    return cmap


def set_identity(font: TTFont, inst: Instance) -> None:
    name = font["name"]
    name.names = []
    for name_id, value in {
        1: FAMILY,
        2: inst.style,
        3: f"{inst.ps_name};{VERSION}",
        4: inst.full_name,
        5: f"Version {VERSION}",
        6: inst.ps_name,
    }.items():
        name.setName(value, name_id, 3, 1, 0x409)
        name.setName(value, name_id, 1, 0, 0)

    cff = font["CFF "].cff
    top = cff[cff.fontNames[0]]
    cff.fontNames = [inst.ps_name]
    top.FullName = inst.full_name
    top.FamilyName = FAMILY
    top.Weight = inst.style
    top.version = VERSION
    for key in ("Notice", "Copyright"):
        top.rawDict.pop(key, None)
        if hasattr(top, key):
            delattr(top, key)

    head = font["head"]
    head.fontRevision = float(VERSION)
    head.modified = int(time.time()) - 2082844800
    head.macStyle = (head.macStyle & ~0x01) | (0x01 if inst.bold else 0)

    os2 = font["OS/2"]
    os2.achVendID = "    "
    os2.usWeightClass = inst.weight
    selection = os2.fsSelection & ~(0x01 | 0x20 | 0x40)
    os2.fsSelection = selection | (0x20 if inst.bold else 0x40) | 0x80
    os2.recalcUnicodeRanges(font, pruneOnly=False)

    for tag in ("GSUB", "GPOS"):
        if tag in font:
            del font[tag]


def set_vertical_metrics(font: TTFont) -> None:
    hhea = font["hhea"]
    hhea.ascent, hhea.descent, hhea.lineGap = ASCENT, -DESCENT, 0
    os2 = font["OS/2"]
    os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = ASCENT, -DESCENT, 0
    os2.usWinAscent, os2.usWinDescent = ASCENT, DESCENT


def set_outline(font: TTFont, glyph: str, path, advance: int) -> None:
    cff = font["CFF "].cff
    top = cff[cff.fontNames[0]]
    pen = T2CharStringPen(advance, font.getGlyphSet())
    path.draw(pen)
    charstring = top.CharStrings[glyph]
    charstring.program = pen.getCharString(top.Private, top.GlobalSubrs).program
    charstring.bytecode = None


def outline(font: TTFont, glyph: str) -> pathops.Path:
    glyph_set = font.getGlyphSet()
    path = pathops.Path()
    glyph_set[glyph].draw(path.getPen(glyphSet=glyph_set))
    return path


def embolden(font: TTFont, glyph: str) -> None:
    stroked = outline(font, glyph)
    stroked.stroke(
        2 * BOLD_STRENGTH, pathops.LineCap.BUTT_CAP, pathops.LineJoin.MITER_JOIN, 4.0
    )
    builder = pathops.OpBuilder(fix_winding=True, keep_starting_points=False)
    builder.add(outline(font, glyph), pathops.PathOp.UNION)
    builder.add(stroked, pathops.PathOp.UNION)
    set_outline(font, glyph, builder.resolve(), font["hmtx"][glyph][0])


def pad_sides(font: TTFont, glyph: str, left_pad: int) -> None:
    glyph_set = font.getGlyphSet()
    bounds = BoundsPen(glyph_set)
    glyph_set[glyph].draw(bounds)
    if bounds.bounds is None:
        font["hmtx"][glyph] = (left_pad + SIDE_PAD, left_pad)
        return
    left, _, right, _ = bounds.bounds
    shift = left_pad - left
    advance = round(right - left + left_pad + SIDE_PAD)
    path = pathops.Path()
    glyph_set[glyph].draw(
        TransformPen(path.getPen(glyphSet=glyph_set), (1, 0, 0, 1, shift, 0))
    )
    set_outline(font, glyph, path, advance)
    font["hmtx"][glyph] = (advance, left_pad)


def recompute_bounds(font: TTFont) -> None:
    glyph_set = font.getGlyphSet()
    boxes = []
    for glyph in font.getGlyphOrder():
        bounds = BoundsPen(glyph_set)
        glyph_set[glyph].draw(bounds)
        if bounds.bounds is not None:
            boxes.append(bounds.bounds)
    box = [
        round(min(b[0] for b in boxes)),
        round(min(b[1] for b in boxes)),
        round(max(b[2] for b in boxes)),
        round(max(b[3] for b in boxes)),
    ]
    head = font["head"]
    head.xMin, head.yMin, head.xMax, head.yMax = box
    font["CFF "].cff[font["CFF "].cff.fontNames[0]].FontBBox = box


def build(inst: Instance) -> Path:
    font = TTFont(SOURCE)
    source_cmap = font.getBestCmap()
    targets = {target: source_cmap[source] for source, target in GLYPHS.items()}

    options = Options()
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.name_languages = ["*"]
    options.notdef_outline = True
    options.recalc_bounds = True
    options.drop_tables = ["DSIG"]
    subsetter = Subsetter(options=options)
    subsetter.populate(unicodes=GLYPHS.keys())
    subsetter.subset(font)

    font["cmap"] = build_cmap(targets)
    set_identity(font, inst)
    set_vertical_metrics(font)
    stem_first = {targets[target] for target in STEM_FIRST}
    for glyph in font.getGlyphOrder():
        if inst.bold:
            embolden(font, glyph)
        pad_sides(font, glyph, STEM_LEFT_PAD if glyph in stem_first else SIDE_PAD)
    recompute_bounds(font)

    OUTPUT_DIR.mkdir(exist_ok=True)
    output = OUTPUT_DIR / f"{inst.ps_name}.otf"
    font.save(output)
    return output


def main() -> None:
    for inst in INSTANCES:
        print(f"wrote {build(inst).relative_to(ASSETS.parent)}")


if __name__ == "__main__":
    main()
