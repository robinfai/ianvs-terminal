# Lint policy

Ianvs uses versioned, repository-local lint policy. A clean checkout must pass
the same checks locally and in CI; editor defaults are not part of the policy.

## Dart and Flutter

The workspace extends
[`very_good_analysis` 10.3.0](https://pub.dev/packages/very_good_analysis), a
widely used community ruleset built on the Dart analyzer. The include is pinned
to its versioned configuration file in `analysis_options.yaml` so a dependency
update cannot silently change the active rules.

The analyzer also enables strict casts, strict inference, and strict raw types.
All workspace packages inherit the root configuration. Project exceptions are
kept in the root file, with a reason beside every disabled rule. In particular,
exceptions cover established API/layout conventions and intentional JSON, FFI,
or platform boundaries; correctness rules such as discarded futures remain
enabled.

The baseline follows Dart's
[official lint guidance](https://dart.dev/tools/linter-rules) and Flutter's
[official lint package](https://pub.dev/packages/flutter_lints), while choosing
the stricter community set for this application workspace.

Run the Dart gate from the repository root:

```sh
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
```

When upgrading `very_good_analysis`, update the dependency and versioned include
together, run `dart fix --dry-run`, review every proposed migration, then run the
full verification script.

## Rust

The native core declares its minimum supported Rust version and lint policy in
`native/core/Cargo.toml`. It enables Clippy's stable `all` group plus a small,
reviewed set of high-signal rules:

- no `dbg!`, `todo!`, or `unimplemented!` in committed code;
- no process exit from the embeddable native library;
- one unsafe operation per unsafe block;
- explicit unsafe operations inside unsafe functions;
- no unused lifetimes.

This intentionally does not enable the complete `pedantic`, `nursery`, or
`restriction` groups. Clippy's own documentation recommends selecting
restriction lints individually, and a full pedantic rollout produces substantial
test and FFI noise in this codebase. New rules should be added only after a
clean-tree probe and review of their false-positive rate.

Run the Rust gate with the CI toolchain:

```sh
cd native/core
cargo +1.88.0 fmt --check
cargo +1.88.0 clippy --locked --all-targets -- -D warnings
```

References:

- [Clippy usage](https://doc.rust-lang.org/stable/clippy/usage.html)
- [Clippy lint groups](https://doc.rust-lang.org/clippy/lints.html)
- [Cargo lint configuration](https://doc.rust-lang.org/cargo/reference/lints.html)

## Repository gate

`tools/verify_flutter_terminal.sh` enforces formatting and analysis once at the
workspace root, then runs the package tests and Rust checks. Do not add a local
package lint file that bypasses the root policy; add a documented, narrow root
exception instead.
