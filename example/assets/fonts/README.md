# Trail light icons

This font supplies Google Material Symbols Outlined at weight 300, optical size
20, grade 0 and fill 0 using Flutter's existing MaterialIcons codepoints. It
covers Trail and shared ianvs_design components without changing icon identities.
The original SDK font has fixed strokes; IconTheme.weight cannot lighten it.

The pubspec intentionally disables automatic Material Icons inclusion and
registers this replacement explicitly. Flutter may warn that a dependency
requests Material Icons; the bundled font supplies that family. Enabling the
automatic font as well would duplicate the family.

Source: https://github.com/google/material-design-icons/tree/master/variablefont

Inputs: MaterialSymbolsOutlined[FILL,GRAD,opsz,wght].ttf and .codepoints,
downloaded 2026-09-15. SHA-256:

- TTF: bf4c94b08c06c6b17e9d1a2d54a68c3f2c3435454761d487768df137a81f851d
- Codepoints: c18564f64d7d92dd3a6895a2c59ea69adfb56d6f553bcbbc88811c328159d715

Regenerate from repository root (Python with fonttools installed):

```sh
python tools/build_light_material_icons.py \
  /path/to/flutter/bin/cache/artifacts/material_fonts \
  /path/to/MaterialSymbolsOutlined.ttf \
  /path/to/MaterialSymbolsOutlined.codepoints \
  example/assets/fonts/TrailLightIcons.ttf
```

Names absent from Symbols retain their original SDK outlines; the generated
fallback list is included. All icons currently referenced in example/lib have
a Symbols mapping. Both upstream licenses are included alongside this file.
