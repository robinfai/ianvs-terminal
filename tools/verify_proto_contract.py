#!/usr/bin/env python3
"""Verify committed descriptor, Rust, and Dart contracts against proto sources."""

from __future__ import annotations

import re
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parent.parent
CONTRACTS = [
    (
        REPOSITORY / "native/core/proto/frame_diff.proto",
        REPOSITORY / "native/core/src/proto/frame_diff.rs",
        REPOSITORY / "packages/ianvs_terminal/lib/src/proto/frame_diff.pb.dart",
        REPOSITORY / "packages/ianvs_terminal/lib/src/proto/frame_diff.pbenum.dart",
    ),
    (
        REPOSITORY / "native/core/proto/graphic_asset.proto",
        REPOSITORY / "native/core/src/proto/graphic_asset.rs",
        REPOSITORY / "packages/ianvs_pty/lib/src/proto/graphic_asset.pb.dart",
        REPOSITORY / "packages/ianvs_pty/lib/src/proto/graphic_asset.pbenum.dart",
    ),
]
DESCRIPTOR = REPOSITORY / "native/core/proto/ianvs_runtime_contract.pb"

SCALAR_DESCRIPTOR_TYPES = {
    "double": 1,
    "float": 2,
    "int64": 3,
    "uint64": 4,
    "int32": 5,
    "fixed64": 6,
    "fixed32": 7,
    "bool": 8,
    "string": 9,
    "bytes": 12,
    "uint32": 13,
    "sfixed32": 15,
    "sfixed64": 16,
    "sint32": 17,
    "sint64": 18,
}


def snake_to_lower_camel(name: str) -> str:
    first, *remaining = name.split("_")
    return first + "".join(part[:1].upper() + part[1:] for part in remaining)


def proto_blocks(source: str, kind: str) -> dict[str, str]:
    blocks: dict[str, str] = {}
    pattern = re.compile(rf"\b{kind}\s+(\w+)\s*\{{")
    for match in pattern.finditer(source):
        depth = 1
        cursor = match.end()
        while cursor < len(source) and depth:
            if source[cursor] == "{":
                depth += 1
            elif source[cursor] == "}":
                depth -= 1
            cursor += 1
        if depth:
            raise ValueError(f"unterminated {kind} {match.group(1)}")
        blocks[match.group(1)] = source[match.end() : cursor - 1]
    return blocks


def proto_message_fields(source: str) -> dict[str, dict[str, int]]:
    messages: dict[str, dict[str, int]] = {}
    field_pattern = re.compile(
        r"^\s*(?:optional\s+|repeated\s+)?[.\w]+\s+(\w+)\s*=\s*(\d+)\s*;",
        flags=re.MULTILINE,
    )
    for message, body in proto_blocks(source, "message").items():
        messages[message] = {
            snake_to_lower_camel(name): int(number)
            for name, number in field_pattern.findall(body)
        }
    return messages


def proto_field_contracts(
    source: str,
) -> dict[str, dict[str, tuple[int, str, str, bool]]]:
    messages: dict[str, dict[str, tuple[int, str, str, bool]]] = {}
    field_pattern = re.compile(
        r"^\s*(?:(optional|repeated)\s+)?([.\w]+)\s+(\w+)\s*=\s*(\d+)\s*;",
        flags=re.MULTILINE,
    )
    for message, body in proto_blocks(source, "message").items():
        fields: dict[str, tuple[int, str, str, bool]] = {}
        for label, field_type, name, number in field_pattern.findall(body):
            fields[name] = (
                int(number),
                field_type,
                label or "singular",
                label == "optional",
            )
        messages[message] = fields
    return messages


def dart_message_fields(source: str) -> dict[str, dict[str, int]]:
    messages: dict[str, dict[str, int]] = {}
    class_pattern = re.compile(r"^class (\w+) extends \$pb\.GeneratedMessage \{", re.MULTILINE)
    matches = list(class_pattern.finditer(source))
    field_pattern = re.compile(
        r"@\$pb\.TagNumber\((\d+)\)\s+[^\n]+\s+get\s+(\w+)\s*=>",
        flags=re.MULTILINE,
    )
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(source)
        messages[match.group(1)] = {
            name: int(number)
            for number, name in field_pattern.findall(source[match.end() : end])
        }
    return messages


def proto_enums(source: str) -> dict[str, dict[str, int]]:
    value_pattern = re.compile(r"^\s*(\w+)\s*=\s*(\d+)\s*;", re.MULTILINE)
    return {
        name: {value: int(number) for value, number in value_pattern.findall(body)}
        for name, body in proto_blocks(source, "enum").items()
    }


def dart_enums(source: str) -> dict[str, dict[str, int]]:
    enums: dict[str, dict[str, int]] = {}
    class_pattern = re.compile(r"^class (\w+) extends \$pb\.ProtobufEnum \{", re.MULTILINE)
    matches = list(class_pattern.finditer(source))
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(source)
        enum_name = match.group(1)
        body = source[match.end() : end]
        value_pattern = re.compile(
            rf"static const {enum_name} (\w+)\s*=\s*{enum_name}\._\(\s*(\d+)",
            flags=re.MULTILINE,
        )
        enums[enum_name] = {
            value: int(number) for value, number in value_pattern.findall(body)
        }
    return enums


def rust_message_contracts(
    source: str,
) -> dict[str, dict[str, tuple[int, str, bool, bool]]]:
    messages: dict[str, dict[str, tuple[int, str, bool, bool]]] = {}
    struct_pattern = re.compile(r"^pub struct (\w+) \{", re.MULTILINE)
    matches = list(struct_pattern.finditer(source))
    field_pattern = re.compile(
        r'#\[prost\(([^\]]+)\)\]\s+pub\s+(\w+):',
        flags=re.MULTILINE,
    )
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(source)
        fields: dict[str, tuple[int, str, bool, bool]] = {}
        for annotation, name in field_pattern.findall(source[match.end() : end]):
            tag_match = re.search(r'tag\s*=\s*"(\d+)"', annotation)
            if tag_match is None:
                raise ValueError(f"Rust field {match.group(1)}.{name} has no tag")
            if "enumeration" in annotation:
                field_type = "enumeration"
            elif re.search(r"(?:^|,\s*)message(?:,|$)", annotation):
                field_type = "message"
            elif "bytes" in annotation:
                field_type = "bytes"
            else:
                field_type = annotation.split(",", 1)[0].strip()
            fields[name] = (
                int(tag_match.group(1)),
                field_type,
                "repeated" in annotation,
                "optional" in annotation,
            )
        messages[match.group(1)] = fields
    return messages


def expected_rust_message_contracts(
    proto_fields: dict[str, dict[str, tuple[int, str, str, bool]]],
    enum_names: set[str],
) -> dict[str, dict[str, tuple[int, str, bool, bool]]]:
    expected: dict[str, dict[str, tuple[int, str, bool, bool]]] = {}
    for message, fields in proto_fields.items():
        expected_fields: dict[str, tuple[int, str, bool, bool]] = {}
        for name, (number, field_type, label, proto3_optional) in fields.items():
            if field_type in enum_names:
                rust_type = "enumeration"
            elif field_type in SCALAR_DESCRIPTOR_TYPES:
                rust_type = field_type
            else:
                rust_type = "message"
            expected_fields[name] = (
                number,
                rust_type,
                label == "repeated",
                proto3_optional or (rust_type == "message" and label == "singular"),
            )
        expected[message] = expected_fields
    return expected


def rust_enum_numbers(source: str) -> dict[str, list[int]]:
    enums: dict[str, list[int]] = {}
    value_pattern = re.compile(r"^\s*\w+\s*=\s*(-?\d+),", re.MULTILINE)
    for name, body in proto_blocks(source, "enum").items():
        enums[name] = sorted(int(value) for value in value_pattern.findall(body))
    return enums


def read_varint(data: bytes, cursor: int) -> tuple[int, int]:
    value = 0
    shift = 0
    while cursor < len(data):
        byte = data[cursor]
        cursor += 1
        value |= (byte & 0x7F) << shift
        if byte < 0x80:
            return value, cursor
        shift += 7
        if shift >= 70:
            raise ValueError("protobuf varint exceeds 10 bytes")
    raise ValueError("truncated protobuf varint")


def wire_fields(data: bytes) -> list[tuple[int, int, int | bytes]]:
    fields: list[tuple[int, int, int | bytes]] = []
    cursor = 0
    while cursor < len(data):
        tag, cursor = read_varint(data, cursor)
        number = tag >> 3
        wire_type = tag & 7
        if number == 0:
            raise ValueError("protobuf field number zero")
        if wire_type == 0:
            value, cursor = read_varint(data, cursor)
        elif wire_type == 1:
            if cursor + 8 > len(data):
                raise ValueError("truncated protobuf fixed64")
            value = data[cursor : cursor + 8]
            cursor += 8
        elif wire_type == 2:
            length, cursor = read_varint(data, cursor)
            if cursor + length > len(data):
                raise ValueError("truncated protobuf length-delimited field")
            value = data[cursor : cursor + length]
            cursor += length
        elif wire_type == 5:
            if cursor + 4 > len(data):
                raise ValueError("truncated protobuf fixed32")
            value = data[cursor : cursor + 4]
            cursor += 4
        else:
            raise ValueError(f"unsupported protobuf wire type {wire_type}")
        fields.append((number, wire_type, value))
    return fields


def field_values(data: bytes, number: int) -> list[int | bytes]:
    return [value for field, _, value in wire_fields(data) if field == number]


def first_int(data: bytes, number: int, default: int = 0) -> int:
    values = field_values(data, number)
    if not values:
        return default
    value = values[0]
    if not isinstance(value, int):
        raise ValueError(f"protobuf field {number} is not a varint")
    return value


def first_text(data: bytes, number: int, default: str = "") -> str:
    values = field_values(data, number)
    if not values:
        return default
    value = values[0]
    if not isinstance(value, bytes):
        raise ValueError(f"protobuf field {number} is not length-delimited")
    return value.decode("utf-8")


def parse_descriptor_field(data: bytes) -> tuple[str, tuple[int, int, int, str, bool]]:
    return (
        first_text(data, 1),
        (
            first_int(data, 3),
            first_int(data, 4),
            first_int(data, 5),
            first_text(data, 6),
            first_int(data, 17) == 1,
        ),
    )


def parse_descriptor_message(
    data: bytes,
) -> tuple[str, dict[str, tuple[int, int, int, str, bool]]]:
    fields: dict[str, tuple[int, int, int, str, bool]] = {}
    for value in field_values(data, 2):
        if not isinstance(value, bytes):
            raise ValueError("descriptor message field is not embedded")
        name, contract = parse_descriptor_field(value)
        fields[name] = contract
    return first_text(data, 1), fields


def parse_descriptor_enum(data: bytes) -> tuple[str, dict[str, int]]:
    values: dict[str, int] = {}
    for value in field_values(data, 2):
        if not isinstance(value, bytes):
            raise ValueError("descriptor enum value is not embedded")
        values[first_text(value, 1)] = first_int(value, 2)
    return first_text(data, 1), values


def parse_file_descriptor(data: bytes) -> tuple[str, dict[str, object]]:
    messages: dict[str, dict[str, tuple[int, int, int, str, bool]]] = {}
    for value in field_values(data, 4):
        if not isinstance(value, bytes):
            raise ValueError("file descriptor message is not embedded")
        name, fields = parse_descriptor_message(value)
        messages[name] = fields
    enums: dict[str, dict[str, int]] = {}
    for value in field_values(data, 5):
        if not isinstance(value, bytes):
            raise ValueError("file descriptor enum is not embedded")
        name, enum_values = parse_descriptor_enum(value)
        enums[name] = enum_values
    return first_text(data, 1), {
        "package": first_text(data, 2),
        "syntax": first_text(data, 12),
        "messages": messages,
        "enums": enums,
    }


def parse_descriptor_set(data: bytes) -> dict[str, dict[str, object]]:
    files: dict[str, dict[str, object]] = {}
    for value in field_values(data, 1):
        if not isinstance(value, bytes):
            raise ValueError("descriptor set file is not embedded")
        name, contract = parse_file_descriptor(value)
        files[name] = contract
    return files


def expected_descriptor_contract(source: str) -> dict[str, object]:
    package_match = re.search(r"^package\s+([.\w]+)\s*;", source, re.MULTILINE)
    if package_match is None:
        raise ValueError("proto source has no package")
    package = package_match.group(1)
    enums = proto_enums(source)
    descriptor_messages: dict[str, dict[str, tuple[int, int, int, str, bool]]] = {}
    for message, fields in proto_field_contracts(source).items():
        descriptor_fields: dict[str, tuple[int, int, int, str, bool]] = {}
        for name, (number, field_type, label, proto3_optional) in fields.items():
            if field_type in SCALAR_DESCRIPTOR_TYPES:
                descriptor_type = SCALAR_DESCRIPTOR_TYPES[field_type]
                type_name = ""
            elif field_type in enums:
                descriptor_type = 14
                type_name = f".{package}.{field_type}"
            else:
                descriptor_type = 11
                type_name = f".{package}.{field_type}"
            descriptor_fields[name] = (
                number,
                3 if label == "repeated" else 1,
                descriptor_type,
                type_name,
                proto3_optional,
            )
        descriptor_messages[message] = descriptor_fields
    return {
        "package": package,
        "syntax": "proto3",
        "messages": descriptor_messages,
        "enums": enums,
    }


def main() -> None:
    failures: list[str] = []
    expected_descriptors: dict[str, dict[str, object]] = {}
    for proto_path, rust_path, dart_message_path, dart_enum_path in CONTRACTS:
        proto_source = proto_path.read_text()
        proto_messages = proto_message_fields(proto_source)
        dart_messages = dart_message_fields(dart_message_path.read_text())
        if proto_messages != dart_messages:
            failures.append(
                f"{dart_message_path.relative_to(REPOSITORY)} does not match "
                f"message fields in {proto_path.relative_to(REPOSITORY)}"
            )
        proto_enum_values = proto_enums(proto_source)
        dart_enum_values = dart_enums(dart_enum_path.read_text())
        if proto_enum_values != dart_enum_values:
            failures.append(
                f"{dart_enum_path.relative_to(REPOSITORY)} does not match "
                f"enum values in {proto_path.relative_to(REPOSITORY)}"
            )
        proto_fields = proto_field_contracts(proto_source)
        expected_rust = expected_rust_message_contracts(
            proto_fields,
            set(proto_enum_values),
        )
        rust_source = rust_path.read_text()
        if expected_rust != rust_message_contracts(rust_source):
            failures.append(
                f"{rust_path.relative_to(REPOSITORY)} does not match field/type/label "
                f"contracts in {proto_path.relative_to(REPOSITORY)}"
            )
        expected_enum_numbers = {
            name: sorted(values.values()) for name, values in proto_enum_values.items()
        }
        if expected_enum_numbers != rust_enum_numbers(rust_source):
            failures.append(
                f"{rust_path.relative_to(REPOSITORY)} does not match enum numbers in "
                f"{proto_path.relative_to(REPOSITORY)}"
            )
        expected_descriptors[proto_path.name] = expected_descriptor_contract(proto_source)
    try:
        committed_descriptors = parse_descriptor_set(DESCRIPTOR.read_bytes())
    except (OSError, UnicodeDecodeError, ValueError) as error:
        failures.append(f"cannot parse {DESCRIPTOR.relative_to(REPOSITORY)}: {error}")
    else:
        if committed_descriptors != expected_descriptors:
            failures.append(
                f"{DESCRIPTOR.relative_to(REPOSITORY)} does not exactly match proto "
                "package/message/field/type/label/enum contracts"
            )
    if failures:
        raise SystemExit("\n".join(failures))


if __name__ == "__main__":
    main()
