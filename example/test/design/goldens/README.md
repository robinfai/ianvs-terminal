# Visual regression baselines

These PNG files are inputs to the adjacent `*_visual_capture_test.dart` and
`settings_final_capture_test.dart` tests. Their subdirectories identify the
existing fixture groups; they are not historical review screenshots or proof
that the current build passes.

Run the affected test from `example/` without `--update-goldens` to compare the
current UI. Update a baseline only when an intentional UI change has been
reviewed. The tests use local macOS fonts; follow the platform requirements in
each test.

Design-review screenshots, logs and videos belong in `build/`, not `docs/` or
this baseline directory.
