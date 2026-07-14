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
    "OSC 21337 incremental tab status",
    "OSC 1337 cell-size query",
    "OSC 1337 cursor shape",
    "DECSCUSR cursor override coexistence",
    "xterm OSC 5/6 special colors",
    "xterm OSC 13-19 dynamic colors",
    "xterm OSC 105/119 resets and 106 alias",
    "iTerm2 OSC 4 negative queries",
    "iTerm2 OSC 1337 SetColors",
    "iTerm2 SetColors color spaces and tab reset",
    "iTerm2 OSC 6 incremental tab color",
    "iTerm2 OSC 6 profile reset",
    "iTerm2 and xterm OSC 6 coexistence",
    "iTerm2 OSC 6 malformed value fail-closed handling",
    "iTerm2 OSC 6 mixed BEL/ST and fragmented ST termination",
    "OSC 0 combined window and icon title",
    "xterm legacy OSC l window title alias",
    "xterm legacy OSC L icon label alias",
    "xterm OSC 60 allowed categories",
    "xterm OSC 61 disallowed subcategories",
    "xterm OSC 62 allowable subcategories",
    "xterm OSC capability mixed BEL/ST and fragmented ST termination",
    "xterm OSC capability reply-loop suppression",
    "OSC 1337 clear buffer",
    "iTerm2 OSC 1337 cursor guide",
    "iTerm2 OSC 1337 clipboard write",
    "iTerm2 OSC 1337 streaming clipboard capture",
    "iTerm2 OSC 1337 annotations",
    "iTerm2 visible and hidden annotations",
    "iTerm2 annotation coordinate range",
    "iTerm2 OSC 1337 block lifecycle",
    "iTerm2 OSC 1337 nested block folding",
    "iTerm2 OSC 1337 block update no-op safety",
    "iTerm2 OSC 1337 copy button",
    "iTerm2 OSC 1337 custom button",
    "iTerm2 OSC 1337 custom button invalidation",
    "iTerm2 OSC 1337 mixed BEL/ST termination",
    "iTerm2 OSC 1337 ReportVariable Base64 name decoding",
    "iTerm2 OSC 1337 ReportVariable user and session variable resolution",
    "iTerm2 OSC 1337 ReportVariable malformed and unknown fail-closed handling",
    "iTerm2 OSC 1337 ReportVariable mixed BEL/ST termination",
    "iTerm2 OSC 1337 UnicodeVersion 8 and 9 cell widths",
    "iTerm2 OSC 1337 UnicodeVersion labeled push and pop",
    "iTerm2 OSC 1337 UnicodeVersion malformed version fail-closed handling",
    "iTerm2 OSC 1337 UnicodeVersion mixed BEL/ST termination",
    "iTerm2 OSC 1337 ClearCapturedOutput exact command",
    "iTerm2 OSC 1337 ClearCapturedOutput mixed BEL/ST termination",
    "iTerm2 OSC 1337 ClearCapturedOutput fragmented ST termination",
    "iTerm2 OSC 1337 ClearCapturedOutput malformed suffix fail-closed handling",
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
    elif case_id == "osc21337_tab_status":
        require(stream.count(b"\x1b]21337;") == 2, f"{case_id}: update count")
        require(b"status=Working\\;phase" in stream, f"{case_id}: escaped status")
        require(b"status=;status-color=" in stream, f"{case_id}: partial clear")
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
    elif case_id == "osc6_iterm_tab_color":
        require(stream.count(b"\x1b]") == 8, f"{case_id}: sequence count")
        require(
            stream.count(b"\x1b]6;1;bg;") == 6,
            f"{case_id}: iTerm2 component/reset count",
        )
        require(b"red;brightness;255\x07" in stream, f"{case_id}: BEL component")
        require(
            b"green;brightness;128\x1b\\" in stream,
            f"{case_id}: fragmented ST component",
        )
        require(b"red;brightness;999\x07" in stream, f"{case_id}: invalid value")
        require(b"bg;*;default\x1b\\" in stream, f"{case_id}: profile reset")
        require(b"\x1b]6;0;1\x1b\\" in stream, f"{case_id}: xterm coexistence")
        require(
            stream.endswith(b"\x1b]2;osc6-iterm-tab-color-corpus-ok\x1b\\"),
            f"{case_id}: parser recovery",
        )
    elif case_id == "xterm_osc_capability_queries":
        require(stream.count(b"\x1b]60") == 2, f"{case_id}: OSC 60 count")
        require(stream.count(b"\x1b]61") == 2, f"{case_id}: OSC 61 count")
        require(stream.count(b"\x1b]62") == 1, f"{case_id}: OSC 62 count")
        require(b"\x1b]61;allowMouseOps\x07" in stream, case_id)
        require(b"\x1b]60;reply-like\x1b\\" in stream, case_id)
        require(b"\x1b]61;unknown\x1b\\" in stream, case_id)
        require(
            chunks[1].endswith(b"\x1b") and chunks[2].startswith(b"\\"),
            f"{case_id}: fragmented ST",
        )
    elif case_id == "xterm_legacy_title_aliases":
        require(stream.count(b"\x1b]") == 4, f"{case_id}: sequence count")
        require(b"\x1b]0;Combined;title\x07" in stream, f"{case_id}: OSC 0")
        require(b"\x1b]LLegacy;icon\x1b\\" in stream, f"{case_id}: OSC L")
        require(b"\x1b]lLegacy;window-" in stream, f"{case_id}: OSC l")
        require(chunks[2] == b"\xe7", f"{case_id}: split UTF-8 lead byte")
    elif case_id == "osc1337_clear_buffer":
        require(stream.count(b"\x1b]") == 2, f"{case_id}: sequence count")
        require(b"1337;ClearScrollback" in stream, f"{case_id}: command")
        require(b"after-clear" in stream, f"{case_id}: post-clear marker")
    elif case_id == "osc1337_cursor_guide":
        require(stream.count(b"\x1b]") == 3, f"{case_id}: sequence count")
        require(
            b"1337;HighlightCursorLine=no" in stream,
            f"{case_id}: documented no value",
        )
        require(
            b"1337;HighlightCursorLine=yes" in stream,
            f"{case_id}: documented yes value",
        )
    elif case_id == "osc1337_clipboard_copy":
        require(stream.count(b"\x1b]") == 4, f"{case_id}: sequence count")
        require(b"1337;CopyToClipboard=find" in stream, f"{case_id}: stream start")
        require(b"1337;EndCopy" in stream, f"{case_id}: stream end")
        require(b"1337;Copy=:ZGlyZWN0" in stream, f"{case_id}: direct copy")
    elif case_id == "osc1337_annotations":
        require(stream.count(b"\x1b]") == 3, f"{case_id}: sequence count")
        require(b"1337;AddAnnotation=4|Visible note" in stream, f"{case_id}: visible")
        require(
            b"1337;AddHiddenAnnotation=Hidden note|6|0|1" in stream,
            f"{case_id}: hidden coordinate range",
        )
        require(b"osc1337-annotation-corpus-ok" in stream, f"{case_id}: recovery")
    elif case_id == "osc1337_blocks":
        require(stream.count(b"\x1b]1337;Block=") == 4, f"{case_id}: block marks")
        require(
            stream.count(b"\x1b]1337;UpdateBlock=") == 2,
            f"{case_id}: block updates",
        )
        require(
            b"Block=id=outer;attr=start;type=build" in stream,
            f"{case_id}: typed start",
        )
        require(
            b"Block=id=outer;attr=end;render=1" in stream,
            f"{case_id}: rendered end",
        )
        require(
            b"UpdateBlock=id=outer;action=fold" in stream,
            f"{case_id}: fold update",
        )
        require(
            b"UpdateBlock=id=missing;action=unfold" in stream,
            f"{case_id}: missing update",
        )
    elif case_id == "osc1337_inline_buttons":
        require(stream.count(b"\x1b]1337;Button=") == 3, f"{case_id}: buttons")
        require(b"Button=type=copy;block=copy-1" in stream, f"{case_id}: copy")
        require(
            b"Button=type=custom;code=42;icon=star.fill" in stream,
            f"{case_id}: custom",
        )
        require(b"Button=type=custom\x07" in stream, f"{case_id}: invalidation")
        require(b"osc1337-button-corpus-ok" in stream, f"{case_id}: recovery")
    elif case_id == "osc1337_report_variable":
        require(
            stream.count(b"\x1b]1337;ReportVariable=") == 4,
            f"{case_id}: report requests",
        )
        require(
            b"SetUserVar=REPORT_KEY=cmVwb3J0LXZhbHVl" in stream,
            f"{case_id}: user variable setup",
        )
        require(
            b"ReportVariable=dXNlci5SRVBPUlRfS0VZ\x07" in stream,
            f"{case_id}: user variable query",
        )
        require(
            b"ReportVariable=c2Vzc2lvbi5jb2x1bW5z\x1b\\" in stream,
            f"{case_id}: split ST session query",
        )
        require(
            b"ReportVariable=%%%\x07" in stream,
            f"{case_id}: malformed Base64",
        )
        require(
            b"ReportVariable=c2Vzc2lvbi5lbnZpcm9ubWVudA==\x07" in stream,
            f"{case_id}: unknown variable",
        )
        require(
            b"osc1337-report-variable-corpus-ok" in stream,
            f"{case_id}: recovery",
        )
    elif case_id == "osc1337_clear_captured_output":
        require(
            stream.count(b"\x1b]1337;ClearCapturedOutput") == 3,
            f"{case_id}: exact and malformed requests",
        )
        require(
            stream.count(b"\x1b]1337;ClearCapturedOutput\x07") == 1,
            f"{case_id}: BEL request",
        )
        require(
            b"\x1b]1337;ClearCapturedOutput\x1b\\" in stream,
            f"{case_id}: fragmented ST request",
        )
        require(
            b"\x1b]1337;ClearCapturedOutput=1\x07" in stream,
            f"{case_id}: malformed suffix",
        )
        require(
            b"osc1337-clear-captured-output-corpus-ok" in stream,
            f"{case_id}: recovery",
        )
    elif case_id == "osc1337_unicode_version":
        require(
            stream.count(b"\x1b]1337;UnicodeVersion=") == 5,
            f"{case_id}: UnicodeVersion operations",
        )
        require(b"UnicodeVersion=8\x07" in stream, f"{case_id}: Unicode 8 BEL")
        require(
            b"UnicodeVersion=push corpus\x1b\\" in stream,
            f"{case_id}: labeled push",
        )
        require(
            b"UnicodeVersion=9\x1b\\" in stream,
            f"{case_id}: split ST Unicode 9",
        )
        require(
            b"UnicodeVersion=pop corpus\x07" in stream,
            f"{case_id}: labeled pop",
        )
        require(
            b"UnicodeVersion=10\x07" in stream,
            f"{case_id}: malformed version",
        )
        require(
            b"osc1337-unicode-version-corpus-ok" in stream,
            f"{case_id}: recovery",
        )
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
