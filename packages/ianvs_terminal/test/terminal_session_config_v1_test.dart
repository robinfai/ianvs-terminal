import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  group('TerminalSessionConfigV1', () {
    test('round-trips the declared config and ignores additive fields', () {
      final wire = TerminalSessionConfigV1(
        sessionId: 'runtime-7',
        displayName: 'zsh',
        config: _config(),
      );
      final json = wire.toJson()..['future_top_level'] = true;
      (json['config']! as Map<String, Object?>)['future_config_field'] =
          <String, Object?>{'value': 1};

      final decoded = TerminalSessionConfigV1.fromJsonString(jsonEncode(json));

      expect(decoded.schemaVersion, 1);
      expect(decoded.contract, 'ianvs-session-config-v1');
      expect(decoded.sessionId, 'runtime-7');
      expect(decoded.displayName, 'zsh');
      expect(decoded.config.launch.program, '/bin/zsh');
      expect(decoded.config.launch.args, <String>['-l']);
      expect(decoded.config.launch.env, <String, String>{'LANG': 'C.UTF-8'});
      expect(decoded.config.scrollbackLines, 1234);
      expect(decoded.config.dragDropEnabled, isTrue);
      expect(decoded.config.display.font.family, 'Menlo');
      expect(decoded.config.interaction.copyOnSelect, isTrue);
    });

    test('returns structured errors for unsupported and oversized input', () {
      expect(
        () => TerminalSessionConfigV1.fromJson(<String, Object?>{
          'schema_version': 2,
        }),
        throwsA(
          isA<TerminalSessionConfigContractException>()
              .having((error) => error.code, 'code', 'unsupported_schema')
              .having((error) => error.path, 'path', r'$.schema_version'),
        ),
      );
      expect(
        () => TerminalSessionConfigV1.fromJsonString(
          ' ' * (TerminalSessionConfigV1.maxEncodedBytes + 1),
        ),
        throwsA(
          isA<TerminalSessionConfigContractException>().having(
            (error) => error.code,
            'code',
            'encoded_config_too_large',
          ),
        ),
      );
    });

    test('rejects missing config and empty launch program', () {
      expect(
        () => TerminalSessionConfigV1.fromJson(<String, Object?>{
          'schema_version': 1,
          'contract': 'ianvs-session-config-v1',
          'session_id': 'runtime-1',
          'display_name': 'shell',
        }),
        throwsA(
          isA<TerminalSessionConfigContractException>().having(
            (error) => error.code,
            'code',
            'missing_field',
          ),
        ),
      );
      final invalid = TerminalSessionConfigV1(
        sessionId: 'runtime-1',
        displayName: 'shell',
        config: const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: ''),
        ),
      ).toJson();
      expect(
        () => TerminalSessionConfigV1.fromJson(invalid),
        throwsA(
          isA<TerminalSessionConfigContractException>().having(
            (error) => error.code,
            'code',
            'invalid_launch_program',
          ),
        ),
      );
    });
  });

  group('TerminalRuntimeController SessionConfig v1 routing', () {
    test('prefers v1 and never calls the Profile-shaped fallback', () {
      final backend = _SessionConfigBackend(supportsV1: true);
      final runtime = _runtime(backend);
      addTearDown(runtime.dispose);

      runtime.createSession(_config());

      expect(backend.v1CreateCalls, 1);
      expect(backend.legacyCreateCalls, 0);
      final payload = jsonDecode(backend.lastV1Json!) as Map<String, dynamic>;
      expect(payload['schema_version'], 1);
      expect(payload['contract'], 'ianvs-session-config-v1');
      expect(payload['session_id'], 'runtime-1');
      expect(payload['display_name'], 'zsh');
      expect(payload, isNot(contains('id')));
      expect(payload, isNot(contains('name')));
    });

    test('uses the exact legacy Profile wire when v1 is unavailable', () {
      final backend = _SessionConfigBackend(supportsV1: false);
      final runtime = _runtime(backend);
      addTearDown(runtime.dispose);

      runtime.createSession(_config());

      expect(backend.v1CreateCalls, 0);
      expect(backend.legacyCreateCalls, 1);
      final payload =
          jsonDecode(backend.lastLegacyJson!) as Map<String, dynamic>;
      expect(payload['id'], 'runtime-1');
      expect(payload['name'], 'zsh');
      expect(payload['launch'], isA<Map<String, dynamic>>());
      expect(payload, isNot(contains('schema_version')));
    });
  });
}

TerminalSessionConfig _config() {
  return const TerminalSessionConfig(
    launch: TerminalLaunchConfig(
      program: '/bin/zsh',
      args: <String>['-l'],
      env: <String, String>{'LANG': 'C.UTF-8'},
      cwd: '/tmp',
    ),
    scrollbackLines: 1234,
    dragDropEnabled: true,
    display: TerminalDisplayConfig(font: TerminalFontConfig(family: 'Menlo')),
    interaction: TerminalInteractionConfig(copyOnSelect: true),
  );
}

TerminalRuntimeController _runtime(PtySessionBackend backend) {
  return TerminalRuntimeController(
    backend: backend,
    copyToClipboard: (_) async {},
    readClipboard: () async => '',
    enableSessionPolling: false,
  );
}

final class _SessionConfigBackend
    implements PtySessionBackend, PtySessionConfigV1Backend {
  _SessionConfigBackend({required this.supportsV1});

  final bool supportsV1;
  int v1CreateCalls = 0;
  int legacyCreateCalls = 0;
  String? lastV1Json;
  String? lastLegacyJson;

  @override
  bool get supportsSessionConfigV1 => supportsV1;

  @override
  String createSessionV1(String sessionConfigV1Json) {
    v1CreateCalls += 1;
    lastV1Json = sessionConfigV1Json;
    return '1';
  }

  @override
  String createSession(String sessionConfigJson) {
    legacyCreateCalls += 1;
    lastLegacyJson = sessionConfigJson;
    return '1';
  }

  @override
  int ping() => 42;

  @override
  void closeSession(String sessionId) {}

  @override
  List<PtyEvent> pollEvents(String sessionId) => const <PtyEvent>[];

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {}

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}

  @override
  String? takeFrameDiffJson(String sessionId) => null;

  @override
  void writeInput(String sessionId, List<int> bytes) {}
}
