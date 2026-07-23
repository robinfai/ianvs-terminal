import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
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

class _ReplayShellBackend extends FakePtyBackend
    implements PtyReplaySessionBackend {
  @override
  String createReplaySession(String sessionConfigJson) {
    return createSession(sessionConfigJson);
  }

  @override
  void replayExit(String sessionId, {int? exitCode}) {
    enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'exit',
        sessionId: sessionId,
        payload: <String, Object?>{'code': exitCode ?? 0},
      ),
    );
  }

  @override
  void replayOutput(String sessionId, List<int> bytes) {}
}

class _RecordingLibraryConfigRepository extends LocalTerminalConfigRepository {
  @override
  Future<LocalTerminalConfigDocument?> load() async {
    return const LocalTerminalConfigDocument(
      layout: LocalTerminalLayoutConfig(restoreLayout: true),
    );
  }

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {}
}

class _RecordingLibraryWorkspaceRepository
    extends LocalTerminalLayoutRepository {
  TerminalLayout? workspace;

  @override
  Future<TerminalLayout?> load() => Future.value(workspace);

  @override
  Future<void> save(TerminalLayout workspace) async {
    this.workspace = workspace;
  }
}

class _WidgetRecordingLibraryRepository
    extends LocalSessionRecordingRepository {
  _WidgetRecordingLibraryRepository({
    required Directory directory,
    required this.recording,
  }) : entry = LocalSessionRecordingEntry(
         path: '${directory.path}/vttest-regression.ndjson',
         displayName: 'vttest regression',
         createdAtUtc: DateTime.utc(2026, 7, 21, 6),
         duration: const Duration(milliseconds: 400),
         fileSizeBytes: 512,
         sessionId: 'recorded-session',
         schemaVersion: 1,
         inputPolicy: TerminalRecordingInputPolicy.redact,
       ),
       super(directoryResolver: () async => directory);

  final TerminalRecording recording;
  final LocalSessionRecordingEntry entry;

  @override
  Future<List<LocalSessionRecordingEntry>> listRecordings() {
    return Future.value(<LocalSessionRecordingEntry>[entry]);
  }

  @override
  Future<TerminalRecording> load(String recordingPath) {
    return Future.value(recording);
  }
}

void main() {
  testWidgets(
    'recording shelf opens a recording in the replay theater and closes independently',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'ianvs-recording-library-widget',
      );
      addTearDown(() {
        if (directory.existsSync()) {
          directory.deleteSync(recursive: true);
        }
      });
      final repository = _WidgetRecordingLibraryRepository(
        directory: directory,
        recording: const TerminalRecordingCodec().decode(
          _recordingFixture('recorded-session'),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ptySessionBackendProvider.overrideWithValue(_ReplayShellBackend()),
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
              _RecordingLibraryConfigRepository(),
            ),
            localTerminalLayoutRepositoryProvider.overrideWithValue(
              _RecordingLibraryWorkspaceRepository(),
            ),
            localSessionRecordingRepositoryProvider.overrideWithValue(
              repository,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            home: const ShellScreen(),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => find
            .byKey(const Key('shell-chrome-recordings'))
            .evaluate()
            .isNotEmpty,
        phase: 'recordings chrome control',
      );

      await tester.tap(find.byKey(const Key('shell-chrome-recordings')));
      await _pumpUntil(
        tester,
        () => find
            .byKey(const Key('saved-recordings-shelf'))
            .evaluate()
            .isNotEmpty,
        phase: 'saved recordings shelf',
      );
      expect(find.text('Saved Recordings'), findsOneWidget);
      expect(find.text('vttest regression'), findsOneWidget);
      expect(
        find.byKey(const Key('saved-recordings-shelf-compact')),
        findsOneWidget,
      );

      await tester.tap(find.text('Newest'));
      await tester.pumpAndSettle();
      await tester.tap(_popupItemWithText('Oldest'));
      await tester.pumpAndSettle();
      expect(find.text('Oldest'), findsOneWidget);

      expect(find.text('ALL RECORDINGS'), findsOneWidget);
      expect(find.textContaining('Workspace'), findsNothing);

      await tester.tap(find.text('vttest regression'));
      await _pumpUntil(
        tester,
        () => find
            .byKey(const Key('recording-replay-workspace'))
            .evaluate()
            .isNotEmpty,
        phase: 'recording replay workspace',
      );
      expect(find.byKey(const Key('recording-replay-toggle')), findsOneWidget);
      expect(find.text('Input redacted'), findsOneWidget);

      await tester.tap(find.byKey(const Key('saved-recordings-shelf-close')));
      await tester.pump();
      expect(find.byKey(const Key('saved-recordings-shelf')), findsNothing);
      expect(
        find.byKey(const Key('recording-replay-workspace')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('recording-replay-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('recording-replay-workspace')), findsNothing);
      expect(find.byKey(const Key('shell-chrome-bar')), findsOneWidget);
    },
  );
}

Finder _popupItemWithText(String text) {
  return find
      .ancestor(
        of: find.text(text),
        matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
      )
      .first;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required String phase,
}) async {
  for (var attempt = 0; attempt < 120; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 20));
    if (predicate()) {
      return;
    }
  }
  throw TestFailure(
    'Timed out waiting for $phase. '
    'ShellScreen=${find.byType(ShellScreen).evaluate().length}, '
    'chrome=${find.byKey(const Key('shell-chrome-bar')).evaluate().length}, '
    'recordingButton=${find.byKey(const Key('shell-chrome-session-recording')).evaluate().length}, '
    'recordingsButton=${find.byKey(const Key('shell-chrome-recordings')).evaluate().length}, '
    'recordingsTooltip=${find.byTooltip('Open Saved Recordings').evaluate().length}.',
  );
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
    <String, Object?>{
      'record_type': 'event',
      'schema_version': 1,
      'session_id': sessionId,
      'sequence': 1,
      'monotonic_offset_micros': 400000,
      'event_kind': 'pty_output',
      'payload': <String, Object?>{
        'bytes_base64': base64Encode(utf8.encode(r'$ vttest --replay')),
      },
    },
  ].map(jsonEncode).join('\n');
}
