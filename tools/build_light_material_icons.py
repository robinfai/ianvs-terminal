"""Build Trail's weight-300 Material Symbols with Flutter MaterialIcons codepoints.

Usage: python build_light_material_icons.py FLUTTER_FONT_DIR SYMBOLS_TTF SYMBOLS_CODEPOINTS OUTPUT
Requires fonttools. Symbols are from google/material-design-icons/variablefont.
Original glyphs are retained for names absent from Symbols, so SDK and shared
component icons never disappear. Runtime has no fonttools/network dependency.
"""
import re
import sys
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.recordingPen import DecomposingRecordingPen

sdk, symbols_path, names_path, output = map(Path, sys.argv[1:])
original = TTFont(sdk / 'MaterialIcons-Regular.otf')
symbols = instantiateVariableFont(TTFont(symbols_path), {'wght': 300, 'FILL': 0, 'GRAD': 0, 'opsz': 20}, inplace=True)
lookup = {name: int(code, 16) for name, code in (line.split() for line in names_path.read_text().splitlines())}
source_names = {int(code, 16): name for name, code in (line.split() for line in (sdk / 'codepoints').read_text().splitlines())}
fonts = [original, symbols]
sets = [f.getGlyphSet() for f in fonts]
cmaps = [f.getBestCmap() for f in fonts]
glyphs, metrics, cmap, converted, fallbacks = {}, {}, {}, {}, []
pen = TTGlyphPen(None)
glyphs['.notdef'] = pen.glyph()
metrics['.notdef'] = (1024, 0)
for code, original_glyph in cmaps[0].items():
    name = source_names.get(code, '')
    base = re.sub(r'_(baseline|outlined|rounded|sharp)$', '', name)
    base = {'copy': 'content_copy', 'info_outline': 'info', 'play_circle_outline': 'play_circle'}.get(base, base)
    target = lookup.get(base)
    source = 1 if target in cmaps[1] else 0
    glyph = cmaps[1][target] if source else original_glyph
    if not source:
        fallbacks.append(name or f'U+{code:04X}')
    key = (source, glyph)
    if key not in converted:
        new_name = f'icon{len(converted)}'
        converted[key] = new_name
        scale = 1024 / fonts[source]['head'].unitsPerEm
        recording = DecomposingRecordingPen(sets[source])
        sets[source][glyph].draw(recording)
        pen = TTGlyphPen(None)
        recording.replay(TransformPen(Cu2QuPen(pen, max_err=0.5, reverse_direction=not source), (scale, 0, 0, scale, 0, 0)))
        glyphs[new_name] = pen.glyph()
        metrics[new_name] = (1024, 0)
    cmap[code] = converted[key]
fb = FontBuilder(1024, isTTF=True)
fb.setupGlyphOrder(list(glyphs))
fb.setupCharacterMap(cmap)
fb.setupGlyf(glyphs)
fb.setupHorizontalMetrics(metrics)
fb.setupHorizontalHeader(ascent=1024, descent=0)
fb.setupNameTable({'familyName': 'Trail Light Icons', 'styleName': 'Regular', 'uniqueFontIdentifier': 'TrailLightIcons-300', 'fullName': 'Trail Light Icons', 'psName': 'TrailLightIcons'})
fb.setupOS2(sTypoAscender=1024, sTypoDescender=0, usWinAscent=1024, usWinDescent=0)
fb.setupPost()
fb.save(output)
print(f'{len(cmap)} codepoints; {len(converted)} glyphs; {len(fallbacks)} legacy fallbacks')
Path(str(output) + '.fallbacks.txt').write_text('\n'.join(fallbacks) + '\n')
