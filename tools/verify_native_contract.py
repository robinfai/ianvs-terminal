#!/usr/bin/env python3
"""Generate or verify the checked-in Rust C ABI contract manifest."""

from __future__ import annotations

import argparse
import ctypes
import json
import re
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parent.parent
HEADER = REPOSITORY / "native/core/ianvs_core.h"
MANIFEST = REPOSITORY / "native/core/ianvs_core_abi_v1.json"
DART_LIBRARY = REPOSITORY / "packages/ianvs_pty/lib"
UNBOUND_LEGACY_EXPORTS = [
    "ianvs_session_search_json",
    "ianvs_session_selection_text",
]


def normalized_declarations(header: str) -> dict[str, str]:
    without_comments = re.sub(r"/\*.*?\*/", "", header, flags=re.DOTALL)
    declarations: dict[str, str] = {}
    for fragment in without_comments.split(";"):
        if "ianvs_" not in fragment or "(" not in fragment:
            continue
        match = re.search(r"\b(ianvs_[a-z0-9_]+)\s*\(", fragment)
        if match is None:
            continue
        declaration = fragment[fragment.rfind("\n\n") + 2 :].strip() + ";"
        declarations[match.group(1)] = " ".join(declaration.split())
    return dict(sorted(declarations.items()))


def graphic_asset_fields(header: str) -> list[str]:
    match = re.search(
        r"typedef struct IanvsGraphicAssetMeta \{(?P<body>.*?)\} IanvsGraphicAssetMeta;",
        header,
        flags=re.DOTALL,
    )
    if match is None:
        raise ValueError("IanvsGraphicAssetMeta is missing from the C header")
    return [
        " ".join(field.strip().split()) + ";"
        for field in match.group("body").split(";")
        if field.strip()
    ]


def schema_constants(header: str) -> dict[str, int]:
    constants: dict[str, int] = {}
    for name, value in re.findall(
        r"^#define ([A-Z0-9_]*SCHEMA_VERSION) ([0-9]+)$",
        header,
        flags=re.MULTILINE,
    ):
        constants[name] = int(value)
    return dict(sorted(constants.items()))


def dart_symbols() -> set[str]:
    symbols: set[str] = set()
    for dart_file in DART_LIBRARY.rglob("*.dart"):
        symbols.update(
            re.findall(r"['\"](ianvs_[a-z0-9_]+)['\"]", dart_file.read_text())
        )
    return symbols


def _normalize_dart_type(value: str) -> str:
    normalized = re.sub(r"\s+", "", value.replace("ffi.", ""))
    return normalized.replace(",)", ")")


def _split_dart_function_types(value: str) -> tuple[str, str]:
    angle_depth = 0
    paren_depth = 0
    for index, character in enumerate(value):
        if character == "<":
            angle_depth += 1
        elif character == ">":
            angle_depth -= 1
        elif character == "(":
            paren_depth += 1
        elif character == ")":
            paren_depth -= 1
        elif character == "," and angle_depth == 0 and paren_depth == 0:
            return value[:index], value[index + 1 :]
    raise ValueError(f"lookupFunction must have native and Dart types: {value}")


def _matching_delimiter(source: str, start: int, opener: str, closer: str) -> int:
    depth = 0
    for index in range(start, len(source)):
        character = source[index]
        if character == opener:
            depth += 1
        elif character == closer:
            depth -= 1
            if depth == 0:
                return index
    raise ValueError(f"unterminated {opener}{closer} expression")


def _dart_typedefs(source: str) -> dict[str, str]:
    return {
        name: _normalize_dart_type(value)
        for name, value in re.findall(
            r"typedef\s+([A-Za-z_]\w*)\s*=\s*(.*?);", source, flags=re.DOTALL
        )
    }


def _expanded_dart_type(value: str, typedefs: dict[str, str]) -> str:
    normalized = _normalize_dart_type(value)
    visited: set[str] = set()
    while normalized in typedefs:
        if normalized in visited:
            raise ValueError(f"recursive Dart typedef: {normalized}")
        visited.add(normalized)
        normalized = typedefs[normalized]
    return normalized


def dart_function_bindings() -> dict[str, tuple[str, str]]:
    """Return symbol -> expanded (NativeFunction, Dart function) signatures."""

    bindings: dict[str, tuple[str, str]] = {}
    for dart_file in DART_LIBRARY.rglob("*.dart"):
        source = dart_file.read_text()
        typedefs = _dart_typedefs(source)
        helper_signatures: dict[str, tuple[str, str]] = {}
        cursor = 0
        marker = "lookupFunction<"
        while True:
            lookup_start = source.find(marker, cursor)
            if lookup_start == -1:
                break
            generic_start = lookup_start + len("lookupFunction")
            generic_end = _matching_delimiter(source, generic_start, "<", ">")
            native_type, dart_type = _split_dart_function_types(
                source[generic_start + 1 : generic_end]
            )
            signature = (
                _expanded_dart_type(native_type, typedefs),
                _expanded_dart_type(dart_type, typedefs),
            )
            call_start = generic_end + 1
            while call_start < len(source) and source[call_start].isspace():
                call_start += 1
            if call_start >= len(source) or source[call_start] != "(":
                raise ValueError(f"malformed lookupFunction in {dart_file}")
            call_end = _matching_delimiter(source, call_start, "(", ")")
            arguments = source[call_start + 1 : call_end]
            symbol_match = re.search(r"['\"](ianvs_[a-z0-9_]+)['\"]", arguments)
            if symbol_match is not None:
                symbol = symbol_match.group(1)
                existing = bindings.get(symbol)
                if existing is not None and existing != signature:
                    raise ValueError(
                        f"conflicting Dart ABI signatures for {symbol}: "
                        f"{existing} and {signature}"
                    )
                bindings[symbol] = signature
            else:
                helpers = list(
                    re.finditer(r"\b(_lookup[A-Za-z0-9_]+)\s*\(", source[:lookup_start])
                )
                if not helpers:
                    raise ValueError(
                        f"dynamic lookupFunction without a named helper in {dart_file}"
                    )
                helper_signatures[helpers[-1].group(1)] = signature
            cursor = call_end + 1

        for helper, signature in helper_signatures.items():
            for symbol in re.findall(
                rf"\b{re.escape(helper)}\s*\(\s*[^,]+,\s*"
                r"['\"](ianvs_[a-z0-9_]+)['\"]",
                source,
                flags=re.DOTALL,
            ):
                existing = bindings.get(symbol)
                if existing is not None and existing != signature:
                    raise ValueError(
                        f"conflicting Dart ABI signatures for {symbol}: "
                        f"{existing} and {signature}"
                    )
                bindings[symbol] = signature
    return bindings


def _c_type_to_dart(value: str, *, native: bool) -> str:
    canonical = " ".join(value.replace("const ", "").replace("struct ", "").split())
    canonical = canonical.replace(" *", "*").replace("* ", "*")
    if canonical.endswith("*"):
        pointee = canonical[:-1]
        pointee_type = {
            "char": "Utf8",
            "uint8_t": "Uint8",
            "uintptr_t": "Size",
            "IanvsGraphicAssetMeta": "_NativeGraphicAssetMeta",
        }.get(pointee)
        if pointee_type is None:
            raise ValueError(f"unsupported C ABI pointer type: {value}")
        return f"Pointer<{pointee_type}>"
    scalar = {
        "void": "Void" if native else "void",
        "int": "Int32" if native else "int",
        "int32_t": "Int32" if native else "int",
        "uint8_t": "Uint8" if native else "int",
        "uint16_t": "Uint16" if native else "int",
        "uint32_t": "Uint32" if native else "int",
        "uint64_t": "Uint64" if native else "int",
        "uintptr_t": "Size" if native else "int",
        "intptr_t": "IntPtr" if native else "int",
    }.get(canonical)
    if scalar is None:
        raise ValueError(f"unsupported C ABI type: {value}")
    return scalar


def _c_function_signature(declaration: str, symbol: str, *, native: bool) -> str:
    symbol_index = declaration.index(symbol)
    return_type = declaration[:symbol_index].strip()
    arguments = declaration[
        declaration.index("(", symbol_index) + 1 : declaration.rindex(")")
    ].strip()
    argument_types: list[str] = []
    if arguments and arguments != "void":
        for argument in arguments.split(","):
            c_type = re.sub(r"[A-Za-z_]\w*\s*$", "", argument.strip()).strip()
            argument_types.append(_c_type_to_dart(c_type, native=native))
    return (
        f"{_c_type_to_dart(return_type, native=native)}"
        f"Function({','.join(argument_types)})"
    )


def verify_dart_struct(header: str) -> None:
    expected = []
    for field in graphic_asset_fields(header):
        match = re.fullmatch(r"(.+?)\s+([A-Za-z_]\w*);", field)
        if match is None:
            raise ValueError(f"unsupported C struct field: {field}")
        c_type, c_name = match.groups()
        dart_name = re.sub(r"_([a-z])", lambda found: found.group(1).upper(), c_name)
        expected.append((_c_type_to_dart(c_type, native=True), dart_name))

    declarations = []
    for dart_file in DART_LIBRARY.rglob("*.dart"):
        source = dart_file.read_text()
        match = re.search(
            r"final\s+class\s+_NativeGraphicAssetMeta\s+extends\s+ffi\.Struct\s*"
            r"\{(?P<body>.*?)\n\}",
            source,
            flags=re.DOTALL,
        )
        if match is not None:
            declarations.extend(
                re.findall(
                    r"@ffi\.([A-Za-z0-9_]+)\(\)\s+external\s+int\s+"
                    r"([A-Za-z_]\w*)\s*;",
                    match.group("body"),
                    flags=re.DOTALL,
                )
            )
    if declarations != expected:
        raise SystemExit(
            "Dart/C IanvsGraphicAssetMeta mismatch: "
            f"expected annotations/fields={expected}, actual={declarations}"
        )


def generated_manifest() -> dict[str, object]:
    header = HEADER.read_text()
    class GraphicAssetMeta(ctypes.Structure):
        _fields_ = [
            ("width", ctypes.c_uint32),
            ("height", ctypes.c_uint32),
            ("rgba_len", ctypes.c_size_t),
            ("version", ctypes.c_uint64),
        ]

    return {
        "schema_version": 1,
        "contract": "ianvs-core-c-abi-v1",
        "schema_constants": schema_constants(header),
        "structs": {"IanvsGraphicAssetMeta": graphic_asset_fields(header)},
        "host_layout": {
            "pointer_width": ctypes.sizeof(ctypes.c_void_p) * 8,
            "IanvsGraphicAssetMeta": {
                "size": ctypes.sizeof(GraphicAssetMeta),
                "alignment": ctypes.alignment(GraphicAssetMeta),
                "offsets": {
                    name: getattr(GraphicAssetMeta, name).offset
                    for name, _ in GraphicAssetMeta._fields_
                },
            },
        },
        "functions": normalized_declarations(header),
        "dart_unbound_legacy_exports": UNBOUND_LEGACY_EXPORTS,
    }


def verify(manifest: dict[str, object]) -> None:
    expected = generated_manifest()
    if manifest != expected:
        raise SystemExit(
            "native/core/ianvs_core_abi_v1.json is stale; "
            "run tools/verify_native_contract.py --write after reviewing the ABI change"
        )
    header = HEADER.read_text()
    functions = expected["functions"]
    if not isinstance(functions, dict):
        raise ValueError("ABI manifest functions must be an object")
    header_symbols = set(functions)
    bound_symbols = dart_symbols()
    missing_bindings = sorted(header_symbols - bound_symbols - set(UNBOUND_LEGACY_EXPORTS))
    unknown_bindings = sorted(bound_symbols - header_symbols)
    if missing_bindings or unknown_bindings:
        raise SystemExit(
            "Dart/C ABI symbol mismatch: "
            f"missing Dart bindings={missing_bindings}, unknown Dart symbols={unknown_bindings}"
        )
    dart_bindings = dart_function_bindings()
    missing_typed_bindings = sorted(
        header_symbols - set(dart_bindings) - set(UNBOUND_LEGACY_EXPORTS)
    )
    signature_mismatches: list[str] = []
    for symbol, (native_signature, dart_signature) in sorted(dart_bindings.items()):
        declaration = functions.get(symbol)
        if not isinstance(declaration, str):
            continue
        expected_native = _c_function_signature(declaration, symbol, native=True)
        expected_dart = _c_function_signature(declaration, symbol, native=False)
        if native_signature != expected_native or dart_signature != expected_dart:
            signature_mismatches.append(
                f"{symbol}: expected ({expected_native}, {expected_dart}), "
                f"actual ({native_signature}, {dart_signature})"
            )
    if missing_typed_bindings or signature_mismatches:
        raise SystemExit(
            "Dart/C ABI function signature mismatch: "
            f"missing typed bindings={missing_typed_bindings}; "
            f"mismatches={signature_mismatches}"
        )
    verify_dart_struct(header)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--write",
        action="store_true",
        help="rewrite the reviewed ABI manifest from the checked-in C header",
    )
    arguments = parser.parse_args()
    if arguments.write:
        MANIFEST.write_text(json.dumps(generated_manifest(), indent=2) + "\n")
    verify(json.loads(MANIFEST.read_text()))


if __name__ == "__main__":
    main()
