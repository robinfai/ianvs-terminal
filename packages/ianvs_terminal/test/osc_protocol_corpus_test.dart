import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const Set<String> _requiredCoverage = <String>{
  'BEL terminator',
  'ST terminator',
  'split ESC',
  'split ST',
  'split UTF-8',
  'empty parameter',
  'missing parameter',
  'duplicate parameter',
  'oversized payload',
  'malformed Base64',
  'malformed percent encoding',
  'unknown key',
  'mixed supported/unsupported sequence',
  'tmux passthrough fixture',
  'screen passthrough fixture',
};

void main() {
  group('shared OSC protocol corpus', () {
    test('native and Dart mirrors are equal and cover every required edge', () {
      final native = _repoJson(
        'native/core/tests/fixtures/osc/osc_protocol_corpus_v1.json',
      );
      final dart = _repoJson(
        'packages/ianvs_terminal/test/fixtures/osc/'
        'osc_protocol_corpus_v1.json',
      );

      expect(dart, equals(native));
      expect(native['schema_version'], 'ianvs-osc-corpus-v1');
      expect(native['encoding'], 'lowercase-hex');

      final cases = _objectList(native['cases'], 'cases');
      final ids = <String>{};
      final covered = <String>{};
      for (final rawFixture in cases) {
        final fixture = _object(rawFixture, 'case');
        final id = _string(fixture['id'], 'case.id');
        expect(ids.add(id), isTrue, reason: 'duplicate case id: $id');
        covered.addAll(
          _objectList(
            fixture['coverage'],
            '$id.coverage',
          ).map((value) => _string(value, '$id.coverage')),
        );
        _validateFixture(id, fixture);
      }

      expect(covered, containsAll(_requiredCoverage));
    });
  });
}

void _validateFixture(String id, Map<String, Object?> fixture) {
  expect(_string(fixture['protocol'], '$id.protocol'), isNotEmpty);
  final expected = _object(fixture['expected'], '$id.expected');
  expect(
    _string(expected['semantic_intent'], '$id.semantic_intent'),
    isNotEmpty,
  );
  expect(_string(expected['state_effect'], '$id.state_effect'), isNotEmpty);
  expect(_string(expected['reply'], '$id.reply'), isNotEmpty);
  expect(expected['must_not_crash'], isTrue);

  final wire = _object(fixture['wire'], '$id.wire');
  final chunksValue = wire['chunks_hex'];
  if (chunksValue == null) {
    _hexBytes(wire['prefix_hex'], '$id.prefix_hex');
    final repeated = _hexBytes(wire['repeat_hex'], '$id.repeat_hex');
    _hexBytes(wire['suffix_hex'], '$id.suffix_hex');
    final count = wire['repeat_count'];
    final limit = wire['declared_payload_limit_bytes'];
    expect(repeated, hasLength(1), reason: id);
    expect(count, isA<int>(), reason: id);
    expect(limit, isA<int>(), reason: id);
    expect(count as int, greaterThan(limit as int), reason: id);
    return;
  }

  final chunks = _objectList(
    chunksValue,
    '$id.chunks_hex',
  ).map((value) => _hexBytes(value, '$id.chunks_hex')).toList(growable: false);
  final stream = chunks.expand((chunk) => chunk).toList(growable: false);
  final terminator = _string(fixture['terminator'], '$id.terminator');
  switch (terminator) {
    case 'BEL':
      expect(stream.last, 0x07, reason: id);
    case 'ST' || 'DCS_ST':
      expect(stream.sublist(stream.length - 2), <int>[0x1b, 0x5c], reason: id);
    case 'mixed':
      expect(wire['sequence_count'], greaterThanOrEqualTo(2), reason: id);
    default:
      fail('$id has unsupported terminator $terminator');
  }

  if (id == 'split_escape_introducer') {
    expect(chunks.first, <int>[0x1b]);
    expect(chunks[1].first, 0x5d);
  } else if (id == 'split_st_terminator') {
    expect(chunks.first.last, 0x1b);
    expect(chunks.last, <int>[0x5c]);
  } else if (id == 'split_utf8_scalar') {
    expect(() => utf8.decode(stream), returnsNormally);
    expect(
      chunks.skip(1).take(chunks.length - 2).any((chunk) {
        try {
          utf8.decode(chunk);
          return false;
        } on FormatException {
          return true;
        }
      }),
      isTrue,
      reason: 'UTF-8 fixture must split inside a scalar',
    );
  }
}

Map<String, Object?> _repoJson(String relativePath) {
  for (final root in <Directory>[
    Directory.current,
    Directory.current.parent,
    Directory.current.parent.parent,
  ]) {
    final file = File('${root.path}/$relativePath');
    if (!file.existsSync()) {
      continue;
    }
    return _object(jsonDecode(file.readAsStringSync()), relativePath);
  }
  throw FileSystemException('Missing repository file', relativePath);
}

Map<String, Object?> _object(Object? value, String label) {
  if (value case final Map<String, Object?> object) {
    return object;
  }
  throw FormatException('$label must be an object');
}

List<Object?> _objectList(Object? value, String label) {
  if (value case final List<Object?> values when values.isNotEmpty) {
    return values;
  }
  throw FormatException('$label must be a non-empty list');
}

String _string(Object? value, String label) {
  if (value case final String text when text.isNotEmpty) {
    return text;
  }
  throw FormatException('$label must be a non-empty string');
}

List<int> _hexBytes(Object? value, String label) {
  final encoded = _string(value, label);
  if (!RegExp(r'^(?:[0-9a-f]{2})+$').hasMatch(encoded)) {
    throw FormatException('$label must contain lowercase byte hex');
  }
  return <int>[
    for (var index = 0; index < encoded.length; index += 2)
      int.parse(encoded.substring(index, index + 2), radix: 16),
  ];
}
