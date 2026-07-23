import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/workspace/local_terminal_layout_models.dart';
import 'package:app/features/workspace/local_terminal_layout_repository.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_profile_repository.dart';

class _RecordingShellBackend extends FakePtyBackend {
  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    return switch (request['kind']) {
      'terminal.recording_start' => jsonEncode(<String, Object?>{
        'ok': true,
        'max_events': 4096,
        'max_payload_bytes': 8 * 1024 * 1024,
      }),
      'terminal.recording_stop' => jsonEncode(<String, Object?>{
        'ok': true,
        'recording_ndjson': _recordingFixture(sessionId),
      }),
      'terminal.recording_cancel' => jsonEncode(const <String, Object?>{
        'ok': true,
      }),
      _ => super.requestSessionJson(sessionId, requestJson),
    };
  }
}

class _RecordingShellConfigRepository extends LocalTerminalConfigRepository {
  @override
  Future<LocalTerminalConfigDocument?> load() async {
    return const LocalTerminalConfigDocument(
      layout: LocalTerminalLayoutConfig(restoreLayout: true),
    );
  }

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {}
}

class _WidgetRecordingRepository extends LocalSessionRecordingRepository {
  _WidgetRecordingRepository(this.directory)
    : super(directoryResolver: () async => directory);

  final Directory directory;
  int _serial = 0;

  @override
  Future<LocalSessionRecordingDestination> reserve({
    required String runtimeSessionId,
    required DateTime createdAtUtc,
  }) {
    final file = File('${directory.path}/widget-recording-${_serial++}.ndjson');
    return Future<LocalSessionRecordingDestination>.value(
      LocalSessionRecordingDestination(file),
    );
  }

  @override
  Future<String> save(
    LocalSessionRecordingDestination destination,
    TerminalRecording recording, {
    String? displayName,
  }) {
    destination.file.writeAsStringSync(
      const TerminalRecordingCodec().encode(recording),
      flush: true,
    );
    return Future<String>.value(destination.file.absolute.path);
  }
}

class _MemoryWorkspaceRepository extends LocalTerminalLayoutRepository {
  TerminalLayout? workspace;

  @override
  Future<TerminalLayout?> load() => Future.value(workspace);

  @override
  Future<void> save(TerminalLayout workspace) {
    this.workspace = workspace;
    return Future<void>.value();
  }
}

void main() {
  testWidgets(
    'title bar starts redacted capture and command palette stops and saves it',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'ianvs terminal-recording-shell',
      );
      addTearDown(() {
        if (directory.existsSync()) {
          directory.deleteSync(recursive: true);
        }
      });
      final recordingRepository = _WidgetRecordingRepository(directory);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ptySessionBackendProvider.overrideWithValue(
              _RecordingShellBackend(),
            ),
            profileRepositoryProvider.overrideWithValue(
              MemoryProfileRepository(
                TerminalProfilesDocument(
                  profiles: <TerminalProfile>[defaultTerminalProfile()],
                ),
              ),
            ),
            appPreferencesRepositoryProvider.overrideWithValue(
              MemoryAppPreferencesRepository(null),
            ),
            localTerminalConfigRepositoryProvider.overrideWithValue(
              _RecordingShellConfigRepository(),
            ),
            localTerminalLayoutRepositoryProvider.overrideWithValue(
              _MemoryWorkspaceRepository(),
            ),
            localSessionRecordingRepositoryProvider.overrideWithValue(
              recordingRepository,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            home: const ShellScreen(),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      await _pumpUntil(
        tester,
        () =>
            find
                .byKey(const Key('shell-chrome-session-recording'))
                .evaluate()
                .isNotEmpty &&
            container.read(sessionControllerProvider).activeSessionId != null,
        phase: 'initial shell recording control',
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      expect(
        find.byKey(const Key('shell-chrome-session-recording')),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Start recording (input redacted)'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('shell-chrome-session-recording')));
      await _pumpUntil(
        tester,
        () => container
            .read(sessionControllerProvider)
            .recordingSessionIds
            .contains(sessionId),
        phase: 'recording start',
      );

      expect(
        container.read(sessionControllerProvider).recordingSessionIds,
        contains(sessionId),
      );
      expect(find.byTooltip('Stop and save recording'), findsOneWidget);

      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await _pumpUntil(
        tester,
        () => find.text('Stop & save recording').evaluate().isNotEmpty,
        phase: 'command palette open',
      );
      await tester.enterText(
        find.byKey(const Key('shell-command-search-field')),
        'recording',
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Stop & save recording'), findsOneWidget);
      final recordingAction = find.byKey(
        const Key('shell-toggle-session-recording'),
      );
      await tester.tap(recordingAction);
      await _pumpUntil(
        tester,
        () => find.textContaining('Recording saved to').evaluate().isNotEmpty,
        phase: 'recording saved feedback',
      );

      final recordingFiles = directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.ndjson'))
          .toList(growable: false);
      expect(recordingFiles, hasLength(1));
      final pane = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .paneFor(sessionId)!;
      expect(pane.relaunchSpec!.toJson(), isNot(contains('recordingPath')));
      expect(
        container.read(sessionControllerProvider).recordingSessionIds,
        isEmpty,
      );
      expect(find.textContaining('Recording saved to'), findsOneWidget);
    },
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required String phase,
}) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 20));
    if (predicate()) {
      return;
    }
  }
  throw TestFailure('Timed out waiting for $phase.');
}

String _recordingFixture(String sessionId) {
  return <Map<String, Object?>>[
    <String, Object?>{
      'record_type': 'metadata',
      'schema_version': 1,
      'session_id': sessionId,
      'created_at_utc': '2026-07-21T06:00:00.000Z',
      'input_policy': 'redact',
    },
    <String, Object?>{
      'record_type': 'event',
      'schema_version': 1,
      'session_id': sessionId,
      'sequence': 0,
      'monotonic_offset_micros': 0,
      'event_kind': 'session_started',
      'payload': <String, Object?>{
        'terminal_emulation': 'xterm256',
        'cols': 80,
        'rows': 24,
      },
    },
  ].map(jsonEncode).join('\n');
}
