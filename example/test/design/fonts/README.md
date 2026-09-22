# Visual test fonts

These assets provide stable glyphs for visual tests without relying on the
host macOS font version. They are not bundled into the production application.

`NotoSansSC-Regular.otf` is the unmodified Simplified Chinese subset published
by the Noto CJK project:

- Source: https://github.com/notofonts/noto-cjk/blob/f8d157532fbfaeda587e826d4cd5b21a49186f7c/Sans/SubsetOTF/SC/NotoSansSC-Regular.otf
- Revision: `f8d157532fbfaeda587e826d4cd5b21a49186f7c`
- SHA-256: `faa6c9df652116dde789d351359f3d7e5d2285a2b2a1f04a2d7244df706d5ea9`
- License: [SIL Open Font License 1.1](OFL.txt), copied from the same revision's
  `Sans/LICENSE`; copyright metadata remains embedded in the font.

The shared capture helper also loads Roboto and Material Icons from the pinned
Flutter SDK, and reuses the repository's vendored JetBrains Mono font. No Apple
system font files are copied or loaded. Update font sources deliberately and
review the resulting exact golden changes together with the source change.
