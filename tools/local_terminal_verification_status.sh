#!/usr/bin/env bash
# Read-only entrypoints; no historical completion state is embedded.
set -u
cat <<'EOF'
Current checkout status: not evaluated by this read-only helper.

Full validation: make verify
Focused batches: bash tools/local_terminal_verification_batches.sh list
Capture output: bash tools/local_terminal_verification_capture.sh run <batch>

Current requirements: docs/TESTING.md
Manual checks: docs/compatibility/MANUAL_VERIFICATION.md
Known issues: docs/KNOWN_ISSUES.md

Generated results belong in build/, not docs/.
EOF
