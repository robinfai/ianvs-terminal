#!/usr/bin/env python3
"""Validate the mirrored byte-level OSC protocol corpus."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
NATIVE_CORPUS = ROOT / "native/core/tests/fixtures/osc/osc_protocol_corpus_v1.json"
DART_CORPUS = (
    ROOT
    / "packages/ianvs_terminal/test/fixtures/osc/osc_protocol_corpus_v1.json"
)
HEX_PATTERN = re.compile(r"(?:[0-9a-f]{2})+")
REQUIRED_COVERAGE = {
    "BEL terminator",
    "ST terminator",
    "split ESC",
    "split ST",
    "split UTF-8",
    "empty parameter",
    "missing parameter",
    "duplicate parameter",
    "oversized payload",
    "malformed Base64",
    "malformed percent encoding",
    "unknown key",
    "mixed supported/unsupported sequence",
    "OSC 99 chunk assembly",
    "OSC 21 batch color control",
    "OSC 23 title no-op",
    "OSC 22 pointer shape stack",
    "OSC 22 screen-local state",
    "OSC 66 sized text",
    "OSC 66 overwrite/edit recovery",
    "OSC 72 target negotiation",
    "OSC 72 bounded host authorization",
    "OSC 1337 shell metadata",
    "OSC 133 semantic prompts and aid lifecycle",
    "OSC 5522 binary MIME clipboard",
    "OSC 1337 cell-size query",
    "OSC 1337 cursor shape",
    "DECSCUSR cursor override coexistence",
    "xterm OSC 5/6 special colors",
    "xterm OSC 13-19 dynamic colors",
    "xterm OSC 105/119 resets and 106 alias",
    "iTerm2 OSC 4 negative queries",
    "iTerm2 OSC 1337 SetColors",
    "iTerm2 SetColors color spaces and tab reset",
    "OSC 3008 hierarchy",
    "OSC 3008 malformed close recovery",
    "tmux passthrough fixture",
    "screen passthrough fixture",
}


class CorpusValidationError(ValueError):
    """Raised when a corpus contract is invalid."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CorpusValidationError(message)


def object_value(value: Any, label: str) -> dict[str, Any]:
    require(isinstance(value, dict), f"{label} must be an object")
    return value


def string_value(value: Any, label: str) -> str:
    require(isinstance(value, str) and bool(value), f"{label} must be a string")
    return value


def decode_hex(value: Any, label: str) -> bytes:
    encoded = string_value(value, label)
    require(
        HEX_PATTERN.fullmatch(encoded) is not None,
        f"{label} must contain non-empty lowercase byte hex",
    )
    return bytes.fromhex(encoded)


def load_corpus(path: Path) -> dict[str, Any]:
    require(path.is_file(), f"missing corpus: {path}")
    with path.open(encoding="utf-8") as source:
        return object_value(json.load(source), str(path))


def concrete_wire(case_id: str, wire: dict[str, Any]) -> tuple[list[bytes], bytes]:
    chunks_hex = wire.get("chunks_hex")
    if chunks_hex is not None:
        require(isinstance(chunks_hex, list) and chunks_hex, f"{case_id}: chunks_hex")
        chunks = [
            decode_hex(value, f"{case_id}.wire.chunks_hex[{index}]")
            for index, value in enumerate(chunks_hex)
        ]
        return chunks, b"".join(chunks)

    prefix = decode_hex(wire.get("prefix_hex"), f"{case_id}.wire.prefix_hex")
    repeated = decode_hex(wire.get("repeat_hex"), f"{case_id}.wire.repeat_hex")
    suffix = decode_hex(wire.get("suffix_hex"), f"{case_id}.wire.suffix_hex")
    repeat_count = wire.get("repeat_count")
    limit = wire.get("declared_payload_limit_bytes")
    require(isinstance(repeat_count, int) and repeat_count > 0, f"{case_id}: repeat_count")
    require(isinstance(limit, int) and limit > 0, f"{case_id}: declared limit")
    require(len(repeated) == 1, f"{case_id}: repeat_hex must encode one byte")
    require(repeat_count > limit, f"{case_id}: generated payload is not oversized")
    # The fixture is deliberately represented without allocating the oversized body.
    return [prefix, repeated, suffix], prefix + suffix


def validate_case(case: Any) -> set[str]:
    item = object_value(case, "case")
    case_id = string_value(item.get("id"), "case.id")
    string_value(item.get("protocol"), f"{case_id}.protocol")
    terminator = string_value(item.get("terminator"), f"{case_id}.terminator")
    require(terminator in {"BEL", "ST", "DCS_ST", "mixed"}, f"{case_id}: terminator")

    coverage_value = item.get("coverage")
    require(isinstance(coverage_value, list) and coverage_value, f"{case_id}: coverage")
    coverage = {
        string_value(value, f"{case_id}.coverage") for value in coverage_value
    }

    expected = object_value(item.get("expected"), f"{case_id}.expected")
    string_value(expected.get("semantic_intent"), f"{case_id}.semantic_intent")
    string_value(expected.get("state_effect"), f"{case_id}.state_effect")
    string_value(expected.get("reply"), f"{case_id}.reply")
    require(expected.get("must_not_crash") is True, f"{case_id}: must_not_crash")

    wire = object_value(item.get("wire"), f"{case_id}.wire")
    chunks, stream = concrete_wire(case_id, wire)
    if terminator == "BEL":
        require(stream.endswith(b"\x07"), f"{case_id}: missing BEL")
    elif terminator in {"ST", "DCS_ST"}:
        require(stream.endswith(b"\x1b\\"), f"{case_id}: missing ST")
    else:
        sequence_count = wire.get("sequence_count")
        require(isinstance(sequence_count, int) and sequence_count >= 2, f"{case_id}: count")
        require(stream.count(b"\x1b]") == sequence_count, f"{case_id}: sequence count")

    if case_id == "split_escape_introducer":
        require(chunks[0] == b"\x1b" and chunks[1].startswith(b"]"), case_id)
    elif case_id == "split_st_terminator":
        require(chunks[0].endswith(b"\x1b") and chunks[1] == b"\\", case_id)
    elif case_id == "split_utf8_scalar":
        stream.decode("utf-8", errors="strict")
        split_is_inside_scalar = False
        for chunk in chunks[1:-1]:
            try:
                chunk.decode("utf-8", errors="strict")
            except UnicodeDecodeError:
                split_is_inside_scalar = True
        require(split_is_inside_scalar, f"{case_id}: UTF-8 was not split inside a scalar")
    elif case_id == "duplicate_parameter":
        require(stream.count(b"id=") >= 2, f"{case_id}: duplicate id missing")
    elif case_id == "malformed_base64":
        require(b"%%%not-base64%%%" in stream, f"{case_id}: malformed payload missing")
    elif case_id == "malformed_percent_encoding":
        require(b"%ZZ" in stream, f"{case_id}: malformed percent payload missing")
    elif case_id == "osc3008_malformed_close_recovery":
        require(stream.count(b"\x1b]3008;") == 4, f"{case_id}: lifecycle sequence count")
        require(b"end=missing" in stream, f"{case_id}: malformed close missing")
    elif case_id == "osc21_batch_and_osc23_noop":
        require(stream.count(b"\x1b]") == 3, f"{case_id}: sequence count")
        require(b"future=?" in stream, f"{case_id}: unknown query missing")
    elif case_id == "osc22_pointer_shape_stack":
        require(stream.count(b"\x1b]22;") == 6, f"{case_id}: OSC 22 sequence count")
        require(stream.count(b"\x1b[?1049") == 2, f"{case_id}: screen switch count")
        require(b"__current__" in stream, f"{case_id}: current query missing")
    elif case_id == "osc66_sized_text_edit_recovery":
        require(stream.count(b"\x1b]66;") == 2, f"{case_id}: OSC 66 sequence count")
        require(b"s=2:w=2:n=1:d=2:v=2:h=1;AB" in stream, f"{case_id}: metadata")
        require(b"\x1b[X" in stream, f"{case_id}: erase recovery missing")
    elif case_id == "osc72_drop_target_negotiation":
        require(stream.count(b"\x1b]72;") == 3, f"{case_id}: OSC 72 sequence count")
        require(b"t=a:i=7;text/plain text/uri-list" in stream, f"{case_id}: accept")
        require(b"t=r:i=7:x=1;" in stream, f"{case_id}: data request")
    elif case_id == "xterm_special_dynamic_colors":
        require(stream.count(b"\x1b]") == 7, f"{case_id}: sequence count")
        require(b"\x1b]5;0;#ff00ff;0;?" in stream, f"{case_id}: OSC 5 query")
        require(b"\x1b]17;?;?;?" in stream, f"{case_id}: sequential query")
        require(b"\x1b]106;0;0" in stream, f"{case_id}: OSC 106 alias")
        require(b"\x1b]119" in stream, f"{case_id}: selection reset")
    elif case_id == "iterm_color_extensions":
        require(stream.count(b"\x1b]") == 3, f"{case_id}: sequence count")
        require(b"SetColors=fg=123" in stream, f"{case_id}: SetColors mutation")
        require(b"bg=p3:808080" in stream, f"{case_id}: Display-P3 color")
        require(b"\x1b]4;-2;?;-1;?" in stream, f"{case_id}: negative queries")
        require(b"tab=default,preset=Grass" in stream, f"{case_id}: safe reset")
    elif case_id == "tmux_passthrough":
        require(stream.startswith(b"\x1bPtmux;\x1b\x1b]"), f"{case_id}: bad wrapper")
    elif case_id == "screen_passthrough":
        require(stream.startswith(b"\x1bP\x1b]"), f"{case_id}: bad wrapper")

    return coverage


def validate() -> int:
    require(
        NATIVE_CORPUS.read_bytes() == DART_CORPUS.read_bytes(),
        "native and Dart OSC corpus files differ byte-for-byte",
    )
    native = load_corpus(NATIVE_CORPUS)
    dart = load_corpus(DART_CORPUS)
    require(native == dart, "native and Dart OSC corpus mirrors differ")
    require(native.get("schema_version") == "ianvs-osc-corpus-v1", "schema version")
    require(native.get("encoding") == "lowercase-hex", "encoding")

    cases = native.get("cases")
    require(isinstance(cases, list) and cases, "cases must be a non-empty array")
    ids: set[str] = set()
    covered: set[str] = set()
    for case in cases:
        item = object_value(case, "case")
        case_id = string_value(item.get("id"), "case.id")
        require(case_id not in ids, f"duplicate case id: {case_id}")
        ids.add(case_id)
        covered.update(validate_case(item))

    require(
        REQUIRED_COVERAGE <= covered,
        f"missing required coverage: {sorted(REQUIRED_COVERAGE - covered)}",
    )
    print(
        f"OSC corpus valid: {len(cases)} cases, "
        f"{len(REQUIRED_COVERAGE)} required edge classes"
    )
    return len(cases)


def main() -> int:
    try:
        validate()
    except (CorpusValidationError, json.JSONDecodeError, OSError) as error:
        print(f"OSC corpus validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
