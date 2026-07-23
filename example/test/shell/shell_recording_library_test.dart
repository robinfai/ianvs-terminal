import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';

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

class _RecordingLibraryLayoutRepository extends LocalTerminalLayoutRepository {
  TerminalLayout? layout;

  @override
  Future<TerminalLayout?> load() => Future.value(layout);

  @override
  Future<void> save(TerminalLayout layout) async {
    this.layout = layout;
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

  @override
  Future<LocalSessionOpenedRecording> openRecording(String recordingPath) {
    return Future.value(
      LocalSessionOpenedRecording(entry: entry, recording: recording),
    );
  }
}

void main() {
  testWidgets('open recording loads one file directly into replay', (
    tester,
  ) async {
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
            _RecordingLibraryLayoutRepository(),
          ),
          localSessionRecordingRepositoryProvider.overrideWithValue(repository),
          shellRecordingFilePickerProvider.overrideWithValue(
            () async => repository.entry.path,
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
      () => find.byKey(const Key('shell-chrome-menu')).evaluate().isNotEmpty,
      phase: 'command palette control',
    );
    expect(find.byKey(const Key('shell-chrome-recordings')), findsNothing);
    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('shell-command-search-field')),
      'open recording',
    );
    await tester.pumpAndSettle();
    expect(find.text('Open recording in Replay…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shell-open-recording')));
    await _pumpUntil(
      tester,
      () => find
          .byKey(const Key('recording-replay-layout'))
          .evaluate()
          .isNotEmpty,
      phase: 'recording replay layout',
    );
    expect(find.byKey(const Key('saved-recordings-shelf')), findsNothing);
    expect(find.text('vttest regression'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(find.byKey(const Key('recording-replay-toggle')), findsOneWidget);
    expect(
      find.byKey(const Key('recording-replay-timeline-effects')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('recording-replay-timeline')), findsOneWidget);
    expect(find.byKey(const Key('recording-replay-speed')), findsOneWidget);
    expect(find.byTooltip('Step back in replay'), findsOneWidget);
    expect(find.byTooltip('Step forward in replay'), findsOneWidget);
    expect(find.byTooltip('Copy visible'), findsOneWidget);
    expect(find.byTooltip('Copy selection'), findsOneWidget);
    expect(
      find.byKey(const Key('recording-replay-search-previous')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('recording-replay-search-next')),
      findsOneWidget,
    );
    expect(find.byTooltip('Output event'), findsOneWidget);
    expect(find.text('Replay'), findsOneWidget);
    expect(find.text('Recording'), findsOneWidget);
    expect(find.text('Input redacted'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Replay recording layout for vttest regression',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Replay controls for recording',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Close replay',
      ),
      findsOneWidget,
    );
    semantics.dispose();

    await tester.tap(find.byKey(const Key('recording-replay-search')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recording-replay-layout')), findsNothing);
    expect(find.byKey(const Key('shell-chrome-bar')), findsOneWidget);
  });
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
    'commandMenuButton=${find.byKey(const Key('shell-chrome-menu')).evaluate().length}.',
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
