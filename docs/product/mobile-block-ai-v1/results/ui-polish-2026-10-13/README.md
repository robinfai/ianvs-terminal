# PR12 UI polish simulator evidence

The selected reference is `concept-2.png` (Focused Reading), generated with ImageGen and selected by the user. It is a concept, not dimensional evidence.

`12-qa-final-light.png` is a native simulator screenshot with the same draft text as the reference. `20`–`27` are eight **original, unmodified** simulator PNGs plus telemetry sidecars: light/dark × portrait/landscape × software keyboard open/dismissed. Comparison/matrix PNGs are derived review images and are not measurement originals.

Device: Trail PR12 Verification, iPhone 17 Pro, **iOS 26.3.1 (23D8133)**. Fixed text scale. Portrait 402×874, landscape 874×402, DPR 3.

Scope: production `TerminalAiWorkspace(compactMobile: true)` and controller in a temporary native-iOS harness with memory API/terminal ports. This is UI validation, not the complete production login/session flow or physical-phone acceptance. Draft fixtures were seeded using Flutter Driver text-entry emulation; emulation was then disabled before opening/dismissing the native software keyboard in every state. CUA Device Hub controls rotated the simulator. The harness's default `input_mode` text in `after-run.log` alone does **not** prove native character entry; sidecars explicitly qualify preparation. No native Pinyin/composing-input claim is made.

Replay measurements with Python + Pillow:

```sh
python3 verify_measurements.py
shasum -a 256 -c SHA256SUMS
```

The script validates PNG dimensions, DPR, retained two-line draft, focus/insets, zero request/write counters, and five independent border scans in each dismissed state. It identifies the exact outer edge of both 3-pixel strokes with adjacent non-border pixels: **168 / 3 = 56.0 logical pixels**, including border/internal padding, excluding external margin and OS safe area. No tolerance was relaxed. Portrait y=[2334,2502); landscape y=[960,1128).

For fresh captures, copy `review_main.dart.txt` to an ignored `build/` directory, run it with `flutter run -d <simulator-udid> -t <path>`, and point `capture.py` to that run's log/device. `source-sha256.json` binds this evidence to the two production source files. See repository-root `design-qa.md` for decisions and limits.
