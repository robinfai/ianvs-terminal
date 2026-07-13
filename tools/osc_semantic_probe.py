#!/usr/bin/env python3
"""Emit deterministic OSC semantic probes for cross-terminal comparison.

The default output is escaped text. Raw OSC bytes are emitted only when the
caller explicitly selects ``--format raw``.
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
from dataclasses import dataclass


ST = b"\x1b\\"


def osc(payload: str, *, bell: bool = False) -> bytes:
    terminator = b"\x07" if bell else ST
    return b"\x1b]" + payload.encode("utf-8") + terminator


@dataclass(frozen=True)
class Probe:
    intent: str
    protocol: str
    description: str
    expected: str
    host_action: str
    payload: bytes


PROBES = {
    "title": Probe(
        "title",
        "OSC 2",
        "Set a deterministic window/tab title.",
        "Title becomes Ianvs OSC semantic probe.",
        "none",
        osc("2;Ianvs OSC semantic probe"),
    ),
    "cwd": Probe(
        "cwd",
        "OSC 7",
        "Publish an absolute local working directory.",
        "Session cwd metadata becomes /tmp/ianvs-osc-probe.",
        "metadata only; must not reveal or execute",
        osc("7;file://localhost/tmp/ianvs-osc-probe"),
    ),
    "hyperlink_with_id": Probe(
        "hyperlink_with_id",
        "OSC 8",
        "Render a hyperlink carrying a stable protocol id, then close it.",
        "Visible probe text links to example.test and retains id=ianvs-probe.",
        "opening the URL requires user action/policy",
        osc("8;id=ianvs-probe;https://example.test/ianvs-probe")
        + b"Ianvs hyperlink probe"
        + osc("8;;"),
    ),
    "clipboard_copy": Probe(
        "clipboard_copy",
        "OSC 52",
        "Request copying a deterministic UTF-8 string.",
        "Allowed terminals copy Ianvs OSC clipboard probe; denied terminals do not.",
        "clipboard write request; policy-gated",
        osc(
            "52;c;"
            + base64.b64encode(b"Ianvs OSC clipboard probe").decode("ascii")
        ),
    ),
    "iterm_clipboard_copy": Probe(
        "iterm_clipboard_copy",
        "iTerm2 OSC 1337 clipboard",
        "Stream a deterministic string to the general pasteboard, then issue the direct Base64 form.",
        "Allowed terminals copy each value while keeping the streamed text visible; denied terminals only render the text.",
        "clipboard write request; policy-gated",
        osc("1337;CopyToClipboard", bell=True)
        + b"Ianvs iTerm clipboard stream"
        + osc("1337;EndCopy")
        + osc(
            "1337;Copy=:"
            + base64.b64encode(b"Ianvs iTerm clipboard direct").decode("ascii")
        ),
    ),
    "clipboard_query": Probe(
        "clipboard_query",
        "OSC 52",
        "Request the current clipboard selection.",
        "Allowed terminals reply with OSC 52; denied terminals remain silent.",
        "clipboard read request; default deny or explicit authorization",
        osc("52;c;?"),
    ),
    "clipboard_mime": Probe(
        "clipboard_mime",
        "Kitty OSC 5522",
        "Write one binary MIME representation with an alias, then list available MIME types.",
        "Allowed terminals reply DONE for the write and return a DATA list containing the stored MIME type.",
        "clipboard write request is policy-gated; MIME listing requires no clipboard data read",
        osc("5522;type=write:id=ianvs-probe")
        + osc(
            "5522;type=wdata:mime=YXBwbGljYXRpb24vb2N0ZXQtc3RyZWFt;"
            "SWFudnMgT1NDIDU1MjIgcHJvYmU="
        )
        + osc(
            "5522;type=walias:mime=YXBwbGljYXRpb24vb2N0ZXQtc3RyZWFt;"
            "YXBwbGljYXRpb24veC1pYW52cy1wcm9iZQ=="
        )
        + osc("5522;type=wdata")
        + osc("5522;type=read:id=ianvs-list;Lg=="),
    ),
    "tab_status": Probe(
        "tab_status",
        "iTerm2 OSC 21337",
        "Set an orange indicator, Working status text, and blue status text color.",
        "The active session tab shows the indicator and Working status without changing terminal content.",
        "appearance only; no host action",
        osc("21337;indicator=#ff9500;status=Working;status-color=#5f87ff"),
    ),
    "prompt_command_output": Probe(
        "prompt_command_output",
        "OSC 133 N/P/A/B/C/D with k= and aid=",
        "Emit initial and secondary semantic prompts plus one aid-correlated command lifecycle.",
        "One prompt/command zone completes with exit code 0; the secondary prompt adds no navigation mark.",
        "none; metadata must never authorize execution",
        osc("133;N;aid=ianvs-probe;k=i")
        + osc("133;P;k=s;aid=ianvs-probe")
        + osc("133;B")
        + b"probe-command\r\n"
        + osc("133;C;probe-command")
        + b"probe-output\r\n"
        + osc("133;D;aid=ianvs-probe;0"),
    ),
    "notification": Probe(
        "notification",
        "Kitty OSC 99",
        "Request a deterministic chunked title/body notification.",
        "Allowed terminals assemble and surface one notification with id=ianvs-probe.",
        "system notification request; policy/rate-limit applies",
        osc("99;i=ianvs-probe:d=0;Ianvs OSC notification probe")
        + osc("99;i=ianvs-probe:p=body;Safe subset"),
    ),
    "notification_query": Probe(
        "notification_query",
        "Kitty OSC 99",
        "Query the supported OSC 99 notification subset.",
        "Supporting terminals reply with notification capability metadata.",
        "none; response must not grant buttons, callbacks, sound, icons, or commands",
        osc("99;i=ianvs-query:p=?;"),
    ),
    "terminal_context": Probe(
        "terminal_context",
        "UAPI OSC 3008",
        "Emit a nested shell/command hierarchy, an unknown close, then close the root.",
        "Three start/end lifecycle events are retained; the unknown close is ignored.",
        "metadata only; must never authorize execution, identity, or privilege changes",
        osc("3008;start=ianvs-root;type=shell;cwd=/tmp/ianvs-osc-probe")
        + osc("3008;start=ianvs-command;type=command;cmdline=probe-command")
        + osc("3008;end=unknown;exit=failure")
        + osc("3008;end=ianvs-root;exit=success;status=0"),
    ),
    "color_control": Probe(
        "color_control",
        "Kitty OSC 21",
        "Set and query foreground, background, cursor, and palette index 196 in one batch.",
        "Colors change and one OSC 21 response reports all four resulting RGB values.",
        "appearance only; no host action",
        osc(
            "21;foreground=#123456;background=#234567;cursor=#345678;"
            "196=#456789;foreground=?;background=?;cursor=?;196=?"
        ),
    ),
    "xterm_special_colors": Probe(
        "xterm_special_colors",
        "xterm OSC 5/6 and 17-19",
        "Enable a magenta bold resource and set/query selection background, Tek cursor, and selection foreground.",
        "Default-colored bold text becomes magenta and four query responses report the resource colors.",
        "appearance only; no host action",
        osc("5;0;#ff00ff;0;?")
        + osc("6;0;1")
        + osc("17;#112233;#181818;#ddeeff")
        + osc("17;?;?;?"),
    ),
    "iterm_color_extensions": Probe(
        "iterm_color_extensions",
        "iTerm2 OSC 4 and OSC 1337 SetColors",
        "Set session-local iTerm2 foreground, background, semantic, cursor, tab, and ANSI colors; query the default colors; then clear the tab override.",
        "The requested colors reach the terminal frame, OSC 4 reports the default background and foreground, and tab=default restores profile tab styling.",
        "appearance only; preset/profile switching remains unauthorized",
        osc(
            "1337;SetColors=fg=123,bg=p3:808080,bold=ff00ff,"
            "underline=00ff00,link=00ffff,selbg=ff0000,selfg=000000,"
            "curbg=ffff00,curfg=0000ff,tab=123456,red=aabbcc"
        )
        + osc("4;-2;?;-1;?")
        + osc("1337;SetColors=tab=default,preset=Grass"),
    ),
    "osc23_noop": Probe(
        "osc23_noop",
        "OSC 2 + unsupported OSC 23",
        "Set a stable title, then send the non-standard legacy OSC 23 payload.",
        "The title remains Ianvs OSC 23 stable; the CSI title stack is untouched.",
        "none",
        osc("2;Ianvs OSC 23 stable") + osc("23;legacy-payload"),
    ),
    "pointer_shape": Probe(
        "pointer_shape",
        "Kitty OSC 22",
        "Set a pointing hand, push wait and crosshair, then query current and supported shapes.",
        "The pointer is crosshair and the terminal replies crosshair,1,1,0.",
        "appearance only; no host action",
        osc("22;pointer")
        + osc("22;>wait,crosshair")
        + osc("22;?__current__,pointer,wait,no-such-name"),
    ),
    "sized_text": Probe(
        "sized_text",
        "Kitty OSC 66",
        "Render fractional fixed-width text, exercise lower-row writing and erasure, then render natural-width text.",
        "AB occupies a 4x2 block, lower-row x skips to its right, erasure removes the block, and Z occupies 2x2 cells.",
        "appearance only; no host action",
        osc("66;s=2:w=2:n=1:d=2:v=2:h=1;AB")
        + b"\x1b[2;2Hx\x1b[1;2H\x1b[X"
        + osc("66;s=2;Z", bell=True),
    ),
    "drag_drop_query": Probe(
        "drag_drop_query",
        "Kitty OSC 72",
        "Query target-side drag-and-drop support with a multiplexer correlation id.",
        "Supporting terminals reply with t=q:i=72 and bounded optional capability metadata.",
        "none; the query must not register a drop target or read host data",
        osc("72;t=q:i=72;"),
    ),
    "shell_metadata": Probe(
        "shell_metadata",
        "iTerm2 OSC 1337",
        "Publish shell integration version, set a navigation mark, and query the rendered cell size.",
        "The version/shell and mark become typed metadata; the terminal replies with height;width;scale.",
        "none; metadata and a bounded geometry reply only",
        osc("1337;ShellIntegrationVersion=17;zsh")
        + osc("1337;SetMark", bell=True)
        + osc("1337;ReportCellSize"),
    ),
    "clear_buffer": Probe(
        "clear_buffer",
        "iTerm2 OSC 1337 ClearScrollback",
        "Clear the visible terminal buffer and retained scrollback history.",
        "Existing visible rows and scrollback disappear; later terminal output continues on a clean first row.",
        "terminal-local state only; no host action",
        osc("1337;ClearScrollback"),
    ),
    "cursor_guide": Probe(
        "cursor_guide",
        "iTerm2 OSC 1337 HighlightCursorLine",
        "Enable the cursor guide for the current terminal row.",
        "A theme-colored guide follows the visible cursor row until explicitly disabled.",
        "appearance only; no host action",
        osc("1337;HighlightCursorLine=yes"),
    ),
    "dynamic_cursor": Probe(
        "dynamic_cursor",
        "iTerm2 OSC 1337 CursorShape",
        "Select the iTerm2 vertical-bar cursor shape.",
        "The rendered cursor becomes a vertical bar while profile blink behavior is preserved.",
        "appearance only; no host action",
        osc("1337;CursorShape=1"),
    ),
    "progress": Probe(
        "progress",
        "OSC 9;4",
        "Set normal progress to 42 percent.",
        "Progress state is normal at 42 percent.",
        "none",
        osc("9;4;1;42"),
    ),
    "badge": Probe(
        "badge",
        "OSC 1337 SetBadgeFormat",
        "Set a deterministic Base64-encoded badge.",
        "Badge text becomes Ianvs Probe.",
        "appearance metadata only",
        osc("1337;SetBadgeFormat=SWFudnMgUHJvYmU="),
    ),
    "user_var": Probe(
        "user_var",
        "OSC 1337 SetUserVar",
        "Set allowlist-friendly IANVS_PROBE=ready metadata.",
        "IANVS_PROBE is retained as the decoded value ready when allowed.",
        "metadata only; must never authorize execution",
        osc("1337;SetUserVar=IANVS_PROBE=cmVhZHk="),
    ),
}


def escaped(payload: bytes) -> str:
    result: list[str] = []
    for byte in payload:
        if 0x20 <= byte <= 0x7E and byte != 0x5C:
            result.append(chr(byte))
        else:
            result.append(f"\\x{byte:02x}")
    return "".join(result)


def selected_probes(intents: list[str]) -> list[Probe]:
    if not intents or "all" in intents:
        return list(PROBES.values())
    seen: set[str] = set()
    selected: list[Probe] = []
    for intent in intents:
        if intent in seen:
            continue
        seen.add(intent)
        selected.append(PROBES[intent])
    return selected


def self_test() -> None:
    required = {
        "title",
        "cwd",
        "hyperlink_with_id",
        "clipboard_copy",
        "iterm_clipboard_copy",
        "clipboard_query",
        "clipboard_mime",
        "tab_status",
        "prompt_command_output",
        "notification",
        "notification_query",
        "terminal_context",
        "color_control",
        "xterm_special_colors",
        "iterm_color_extensions",
        "osc23_noop",
        "pointer_shape",
        "sized_text",
        "drag_drop_query",
        "shell_metadata",
        "clear_buffer",
        "cursor_guide",
        "dynamic_cursor",
        "progress",
        "badge",
        "user_var",
    }
    if set(PROBES) != required:
        raise ValueError(f"semantic probe set mismatch: {sorted(set(PROBES) ^ required)}")
    for key, probe in PROBES.items():
        if key != probe.intent or not probe.payload.startswith(b"\x1b]"):
            raise ValueError(f"invalid probe identity or introducer: {key}")
        if not probe.payload.endswith((ST, b"\x07")):
            raise ValueError(f"missing OSC terminator: {key}")
        if not all((probe.protocol, probe.description, probe.expected, probe.host_action)):
            raise ValueError(f"missing probe metadata: {key}")
    if b"id=ianvs-probe" not in PROBES["hyperlink_with_id"].payload:
        raise ValueError("hyperlink probe lost its protocol id")
    if b"52;c;?" not in PROBES["clipboard_query"].payload:
        raise ValueError("clipboard query fixture is malformed")
    if PROBES["iterm_clipboard_copy"].payload.count(b"\x1b]1337;") != 3:
        raise ValueError("iTerm2 OSC 1337 clipboard fixture is malformed")
    if PROBES["clipboard_mime"].payload.count(b"\x1b]5522;") != 5:
        raise ValueError("OSC 5522 MIME clipboard fixture is malformed")
    if PROBES["tab_status"].payload.count(b"\x1b]21337;") != 1:
        raise ValueError("OSC 21337 tab status fixture is malformed")
    if PROBES["terminal_context"].payload.count(b"\x1b]3008;") != 4:
        raise ValueError("terminal context lifecycle fixture is malformed")
    if PROBES["color_control"].payload.count(b"=?") != 4:
        raise ValueError("color-control query fixture is malformed")
    if PROBES["iterm_color_extensions"].payload.count(b"\x1b]1337;SetColors=") != 2:
        raise ValueError("iTerm color-extension lifecycle fixture is malformed")
    if b"4;-2;?;-1;?" not in PROBES["iterm_color_extensions"].payload:
        raise ValueError("iTerm negative OSC 4 query fixture is malformed")
    if PROBES["osc23_noop"].payload.count(b"\x1b]") != 2:
        raise ValueError("OSC 23 no-op fixture is malformed")
    if PROBES["pointer_shape"].payload.count(b"\x1b]22;") != 3:
        raise ValueError("pointer-shape lifecycle fixture is malformed")
    if PROBES["sized_text"].payload.count(b"\x1b]66;") != 2:
        raise ValueError("sized-text lifecycle fixture is malformed")
    if b"\x1b[X" not in PROBES["sized_text"].payload:
        raise ValueError("sized-text erase recovery fixture is malformed")
    if b"72;t=q:i=72;" not in PROBES["drag_drop_query"].payload:
        raise ValueError("drag-drop query fixture is malformed")
    if PROBES["shell_metadata"].payload.count(b"\x1b]1337;") != 3:
        raise ValueError("OSC 1337 shell metadata fixture is malformed")
    if PROBES["clear_buffer"].payload != osc("1337;ClearScrollback"):
        raise ValueError("OSC 1337 clear-buffer fixture is malformed")
    if PROBES["cursor_guide"].payload != osc("1337;HighlightCursorLine=yes"):
        raise ValueError("OSC 1337 cursor-guide fixture is malformed")
    if b"1337;CursorShape=1" not in PROBES["dynamic_cursor"].payload:
        raise ValueError("OSC 1337 cursor shape fixture is malformed")


def parser() -> argparse.ArgumentParser:
    command = argparse.ArgumentParser(description=__doc__)
    command.add_argument(
        "--intent",
        action="append",
        choices=[*PROBES, "all"],
        default=[],
        help="Select an intent; repeat the option or use all.",
    )
    command.add_argument(
        "--format",
        choices=["escaped", "hex", "json", "raw"],
        default="escaped",
        help="Output format. raw is the only mode that sends control bytes.",
    )
    command.add_argument("--list", action="store_true", help="List probe intents.")
    command.add_argument(
        "--self-test",
        action="store_true",
        help="Validate the built-in probe catalog without emitting control bytes.",
    )
    return command


def emit(probes: list[Probe], output_format: str) -> None:
    if output_format == "raw":
        sys.stdout.buffer.write(b"\r\n".join(probe.payload for probe in probes))
        sys.stdout.buffer.flush()
        return
    if output_format == "json":
        print(
            json.dumps(
                [
                    {
                        "intent": probe.intent,
                        "protocol": probe.protocol,
                        "description": probe.description,
                        "expected": probe.expected,
                        "host_action": probe.host_action,
                        "payload_hex": probe.payload.hex(),
                    }
                    for probe in probes
                ],
                indent=2,
                sort_keys=True,
            )
        )
        return
    for probe in probes:
        rendered = probe.payload.hex() if output_format == "hex" else escaped(probe.payload)
        print(f"[{probe.intent}] {probe.protocol}")
        print(rendered)


def main() -> int:
    args = parser().parse_args()
    try:
        self_test()
    except ValueError as error:
        print(f"OSC semantic probe validation failed: {error}", file=sys.stderr)
        return 1
    if args.self_test:
        print(f"OSC semantic probes valid: {len(PROBES)} intents")
        return 0
    if args.list:
        for probe in PROBES.values():
            print(f"{probe.intent}\t{probe.protocol}\t{probe.description}")
        return 0
    emit(selected_probes(args.intent), args.format)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
