# Local terminal verification helpers

The batch runner remains available to engineering verification models and
focused regression workflows. `make verify` is the complete current gate.

```sh
bash tools/local_terminal_verification_batches.sh list
bash tools/local_terminal_verification_batches.sh print all-automated
bash tools/local_terminal_verification_capture.sh run broader
bash tools/local_terminal_verification_capture.sh run integration
```

Capture writes output, exit status and a local review template under
`build/local-terminal-verification/`. It does not update documentation or claim
that other gates passed. Keep generated logs and reports out of `docs/`.
Current requirements are in [TESTING](../docs/TESTING.md), manual checks in
[MANUAL_VERIFICATION](../docs/compatibility/MANUAL_VERIFICATION.md).
