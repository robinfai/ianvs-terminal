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
    "clipboard_query": Probe(
        "clipboard_query",
        "OSC 52",
        "Request the current clipboard selection.",
        "Allowed terminals reply with OSC 52; denied terminals remain silent.",
        "clipboard read request; default deny or explicit authorization",
        osc("52;c;?"),
    ),
    "prompt_command_output": Probe(
        "prompt_command_output",
        "OSC 133 A/B/C/D",
        "Emit one prompt, command-input, output, and completion lifecycle.",
        "One command zone completes with exit code 0.",
        "none; metadata must never authorize execution",
        osc("133;A")
        + osc("133;B")
        + b"probe-command\r\n"
        + osc("133;C;probe-command")
        + b"probe-output\r\n"
        + osc("133;D;0"),
    ),
    "notification": Probe(
        "notification",
        "OSC 9",
        "Request a deterministic terminal notification.",
        "Allowed terminals surface one notification; denied terminals do not.",
        "system notification request; policy/rate-limit applies",
        osc("9;Ianvs OSC notification probe"),
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
        "clipboard_query",
        "prompt_command_output",
        "notification",
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
