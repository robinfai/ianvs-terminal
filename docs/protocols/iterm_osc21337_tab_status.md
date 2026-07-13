# iTerm2 OSC 21337 tab status contract

Ianvs supports the public iTerm2 OSC 21337 tab-status fields as bounded,
session-local appearance metadata. The wire form is:

```text
OSC 21337 ; indicator=<color> ; status=<text> ; status-color=<color> ST
```

BEL and ST terminators are accepted. Fields are incremental: an omitted field
keeps its previous value, a present empty value clears it, and a valid non-empty
value replaces it. Unknown keys are ignored. A semicolon or backslash inside a
value is encoded as `\;` or `\\`; other backslash pairs preserve the backslash.

## Supported fields

| Field | Product behavior |
|---|---|
| `indicator` | Colored dot on the active pane's tab |
| `status` | Compact, ellipsized status label on the active pane's tab |
| `status-color` | Requested status-label color, adjusted only when necessary to preserve readable contrast |

Colors accept xterm color syntax, including `#RRGGBB` and
`rgb:RR/GG/BB`, and cross the product boundary in canonical lowercase
`#rrggbb` form. Invalid colors do not clear or overwrite the field. Status text
has control characters removed and is limited to 256 Unicode scalar values.
The appearance ingress gate limits the full payload to 4 KiB.

## State, safety, and UI

- Parser output is a typed tri-state update; presence booleans distinguish
  omission from clearing.
- Native and Dart diagnostics never log raw status text; diagnostics retain
  only length and a one-way hash.
- State belongs to the emitting pane. A split tab displays its active pane's
  status and updates when pane focus changes.
- RIS, pane close, and session close clear the state. Screen clears and resize
  replay do not manufacture updates.
- OSC 21337 is classified under the appearance capability. VT220 profiles and
  denied appearance policy consume it without product-state mutation.
- The indicator and status are included in the tab's accessibility label;
  status text is ellipsized, text scaling is bounded inside the fixed-height
  desktop chrome, and requested colors fall back to a WCAG-AA-readable
  foreground when necessary.

The current scope intentionally excludes later, unpublished extension keys.
The three public fields above match iTerm2's 3.7 release documentation and its
incremental update implementation.
