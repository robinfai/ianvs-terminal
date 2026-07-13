# iTerm2 OSC 1337 shell metadata and cell-size query

Ianvs implements the non-authorizing `SetMark`, `ShellIntegrationVersion` and
`ReportCellSize` subset documented by
[iTerm2 proprietary escape codes](https://iterm2.com/documentation-escape-codes.html).
These commands extend the existing `CurrentDir`, `RemoteHost`, `SetUserVar` and
`SetBadgeFormat` product path without granting file, process or window authority.

## Supported grammar

```text
OSC 1337 ; SetMark ST
OSC 1337 ; ShellIntegrationVersion=<version> [ ; <shell> ] ST
OSC 1337 ; ReportCellSize ST
```

- `SetMark` records the primary-screen global cursor line in the same bounded
  navigation model used by OSC 133 prompt marks. It does not synthesize a
  command lifecycle or create a shell zone.
- `ShellIntegrationVersion` accepts 1–32 ASCII decimal digits. The optional
  shell name is at most 32 ASCII alphanumeric/`._+-` characters. Invalid
  versions are ignored; an invalid optional shell does not discard a valid
  version.
- `ReportCellSize` is exact and parameterless. The reusable parser emits a
  typed request; the Flutter runtime replies only after it has a committed
  render metric:

```text
OSC 1337 ; ReportCellSize=<height>;<width>;<scale> ST
```

Height and width are logical Flutter points with two decimal places. Scale is
the device-pixel ratio with two decimal places. This avoids reporting physical
pixels as points on Retina displays. Queries received before first layout are
queued (maximum 16) and answered after the first committed resize; every
retained query receives one response.

## Policy and lifecycle

`SetMark` and `ShellIntegrationVersion` require the metadata capability;
`ReportCellSize` requires appearance capability. VT220 and explicit
fine-grained denials reject them. The legacy `disable_insecure_sequences`
switch intentionally retains its historical mapping and does not disable safe
metadata/appearance. Marks and version metadata are ignored on the alternate
screen, while the geometry query remains valid because it cannot mutate
primary shell state.

Product prompt marks remain capped at 100. Parser event queues, response queues
and OSC ingress retain their existing count/byte limits. RIS/session close
clears product metadata and any pending geometry replies. Diagnostics retain
only bounded field metadata and never shell output.

## Deliberately separate host actions

`RequestUpload`, `StealFocus`, `SetProfile`, custom controls and shell-provided
command execution remain unsupported at the product boundary. Non-inline file
download and OpenURL have separate explicit-consent contracts. This metadata
subset must not be used as evidence that any host action is authorized.
