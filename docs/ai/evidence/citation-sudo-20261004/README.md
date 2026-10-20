# Citation, role icon and smart-review regression

Validated on macOS 27.0.1, 2026-10-04. This folder records the follow-up to the
duplicate evidence key crash and noninteractive sudo review report.

## Changes

- Deduplicate identical valid citation ranges before rendering; use block ID,
  start line and end line for stable keys. Keep distinct overlapping ranges and
  their original evidence provenance.
- Restore the assistant's `auto_awesome_outlined` role icon. The accessible role
  label remains AI; there is no visible AI role text.
- Let a leading `sudo -n` or `sudo --non-interactive` proposal reach independent
  review, including its original wrapper. This does not grant automatic approval:
  the underlying command, task scope and existing mandatory checks still apply.

## Evidence

- `01-before.log`: widget regression reproduces the duplicate-key failure.
- `02-citation-tests.log`: 24 focused widget tests pass, including streamed
  duplicates, overlapping ranges, selection and exact citation navigation.
- `03-ai-regression.log`: all 328 AI tests pass.
- `04-real-review.jsonl`: three real tool-free ACP / `gpt-5.6-sol` reviews. The
  scoped read-only diagnostic was allowed; an explicit no-commands request and
  an out-of-scope privileged modification required confirmation. No example
  command was executed.
- `05-build.log`: normal macOS Development debug build succeeds.

Scoped static analysis, formatting and `git diff --check` passed. Phone-sized
widget tests use fixed fonts; no physical phone or VoiceOver check is claimed.

## Live runtime limitation

The connected app initially reported the same duplicate evidence key. Its
already-corrupted widget tree did not recover after two successful hot-reload
requests and subsequently reported Flutter tree assertions. Fresh test processes
pass. Restart approval is pending because restarting resets the in-memory AI
conversation and disconnects the active SSH session. No live recovery is claimed.
