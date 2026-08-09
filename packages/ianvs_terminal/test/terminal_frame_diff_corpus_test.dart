import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/runtime/terminal_frame_decoder.dart';

import 'support/terminal_frame_wire_fixture.dart';

void main() {
  group('terminal frame diff wire corpus', () {
    test('fixtures match the documented schema and Dart parser', () {
      const decoder = TerminalFrameDecoder();
      final schema = _jsonObjectFromRepoFile(
        'tools/bench/schemas/terminal_frame_diff.schema.json',
      );
      final corpusDir = _repoDirectory(
        'packages/ianvs_terminal/test/fixtures/frame_diff_corpus',
      );
      final fixtures =
          corpusDir
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.json'))
              .toList(growable: false)
            ..sort((a, b) => a.path.compareTo(b.path));

      expect(fixtures, isNotEmpty);
      for (final fixture in fixtures) {
        final corpus = _jsonObject(fixture);
        final frameJson = _objectField(corpus, 'frame');
        final expected = _objectField(corpus, 'expected');

        expect(_schemaCompatibilityFailures(schema, frameJson), isEmpty);
        final frame = TerminalFrameDiff.fromJson(frameJson);

        expect(
          frame.frameSchemaVersion,
          expected['frame_schema_version'],
          reason: fixture.path,
        );
        expect(
          frame.frameKind.name,
          expected['frame_kind'],
          reason: fixture.path,
        );
        expect(
          frame.viewportRows,
          expected['viewport_rows'],
          reason: fixture.path,
        );
        expect(
          frame.viewportCols,
          expected['viewport_cols'],
          reason: fixture.path,
        );
        expect(
          frame.rows.map((row) => row.text).toList(growable: false),
          expected['row_texts'],
          reason: fixture.path,
        );
        expect(
          frame.dirtyRanges
              .map((range) => <int>[range.start, range.end])
              .toList(growable: false),
          expected['dirty_ranges'],
          reason: fixture.path,
        );
        expect(
          frame.graphics.length,
          expected['graphics_count'],
          reason: fixture.path,
        );
        expect(
          frame.blocks.length,
          expected['blocks_count'],
          reason: fixture.path,
        );
        expect(
          frame.hyperlinks.length,
          expected['hyperlinks_count'],
          reason: fixture.path,
        );
        expect(
          terminalFrameProjection(
            decoder.decodeJson(jsonEncode(frameJson))!.frame,
          ),
          terminalFrameProjection(frame),
          reason: '${fixture.path} public factory/facade mismatch',
        );
      }
    });

    test('schema check catches incompatible required field types', () {
      final schema = _jsonObjectFromRepoFile(
        'tools/bench/schemas/terminal_frame_diff.schema.json',
      );
      final corpus = _jsonObjectFromRepoFile(
        'packages/ianvs_terminal/test/fixtures/frame_diff_corpus/'
        'snapshot_basic_v1.json',
      );
      final invalidFrame = Map<String, Object?>.of(
        _objectField(corpus, 'frame'),
      )..['viewport_rows'] = '3';

      expect(
        _schemaCompatibilityFailures(schema, invalidFrame),
        contains('viewport_rows must be integer'),
      );
    });

    test('public terminal surface retains compatibility entry points', () {
      final fromJson = TerminalFrameDiff.fromJson(const <String, Object?>{});
      final fromProtobuf = TerminalFrameDiff.fromProtobufBytes(const <int>[]);
      const preference = TerminalFrameWireFormatPreference.automatic;
      const viewport = TerminalViewportState.empty;
      const renderIntent = TerminalRenderIntent.none;
      const runtimeType = TerminalRuntimeController;

      expect(fromJson.frameSchemaVersion, 'terminal-frame-diff-v1');
      expect(fromProtobuf.frameSchemaVersion, 'terminal-frame-diff-v1');
      expect(preference, TerminalFrameWireFormatPreference.automatic);
      expect(viewport.frame, same(TerminalFrameDiff.empty));
      expect(renderIntent, same(TerminalRenderIntent.none));
      expect(runtimeType, TerminalRuntimeController);
    });
  });
}

Map<String, Object?> _jsonObjectFromRepoFile(String relativePath) {
  return _jsonObject(_repoFile(relativePath));
}

File _repoFile(String relativePath) {
  for (final root in _candidateRepoRoots()) {
    final file = File('${root.path}/$relativePath');
    if (file.existsSync()) {
      return file;
    }
  }
  throw FileSystemException('Missing repository file', relativePath);
}

Directory _repoDirectory(String relativePath) {
  for (final root in _candidateRepoRoots()) {
    final directory = Directory('${root.path}/$relativePath');
    if (directory.existsSync()) {
      return directory;
    }
  }
  throw FileSystemException('Missing repository directory', relativePath);
}

List<Directory> _candidateRepoRoots() {
  final cwd = Directory.current;
  return <Directory>[cwd, cwd.parent, cwd.parent.parent];
}

Map<String, Object?> _jsonObject(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is Map<String, Object?>) {
    return decoded;
  }
  throw FormatException('Expected JSON object in ${file.path}');
}

Map<String, Object?> _objectField(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map<String, Object?>) {
    return value;
  }
  throw FormatException('Expected object field "$key"');
}

List<String> _schemaCompatibilityFailures(
  Map<String, Object?> schema,
  Map<String, Object?> json,
) {
  final failures = <String>[];
  final required = schema['required'];
  if (required is! List<Object?>) {
    return const <String>['schema.required must be array'];
  }
  for (final key in required.whereType<String>()) {
    if (!json.containsKey(key)) {
      failures.add('$key is required');
    }
  }

  final properties = schema['properties'];
  if (properties is! Map<String, Object?>) {
    return failures;
  }
  for (final entry in properties.entries) {
    if (!json.containsKey(entry.key)) {
      continue;
    }
    final property = entry.value;
    if (property is! Map<String, Object?>) {
      continue;
    }
    final value = json[entry.key];

    if (property.containsKey('const') && value != property['const']) {
      failures.add('${entry.key} must equal ${property['const']}');
    }

    final enumValues = property['enum'];
    if (enumValues is List<Object?> && !enumValues.contains(value)) {
      failures.add('${entry.key} must be one of ${enumValues.join(', ')}');
    }

    final types = _schemaTypes(property['type']);
    if (types.isNotEmpty && !_matchesSchemaType(value, types)) {
      failures.add('${entry.key} must be ${types.join(' or ')}');
    }
  }
  return failures;
}

List<String> _schemaTypes(Object? type) {
  return switch (type) {
    final String name => <String>[name],
    final List<Object?> names => names.whereType<String>().toList(
      growable: false,
    ),
    _ => const <String>[],
  };
}

bool _matchesSchemaType(Object? value, List<String> types) {
  return types.any((type) {
    return switch (type) {
      'array' => value is List<Object?>,
      'boolean' => value is bool,
      'integer' => value is int,
      'null' => value == null,
      'number' => value is num,
      'object' => value is Map<String, Object?>,
      'string' => value is String,
      _ => true,
    };
  });
}
