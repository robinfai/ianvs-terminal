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
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';

class _ReplayShellBackend extends FakePtyBackend
    implements PtyReplaySessionBackend, PtyReplayCheckpointBackend {
  int _checkpointSeed = 0;

  @override
  bool get supportsReplayCheckpoints => true;

  @override
  int captureReplayCheckpoint(String sessionId) => ++_checkpointSeed;

  @override
  bool restoreReplayCheckpoint(String sessionId, int checkpointId) => true;

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
  void replayOutput(String sessionId, List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    setFrame(sessionId, <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'index': 0,
          'text': text,
          'style_runs': <Object?>[
            <String, Object?>{
              'start': 0,
              'end': text.length,
              'foreground': '#1f2937',
              'background': null,
              'bold': false,
              'italic': false,
              'underline': false,
              'inverse': false,
            },
          ],
        },
      ],
      'cursor': <String, Object?>{'row': 1, 'col': 0, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[
        <String, Object?>{'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'window_title': null,
      'window_icon_name': null,
    });
  }
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
         schemaVersion: terminalRecordingSemanticSchemaVersion,
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
    final sourceRecording = const TerminalRecordingCodec().decode(
      _recordingFixture('recorded-session'),
    );
    final recording = const TerminalRecordingSemanticMerger()
        .merge(sourceRecording, const <TerminalRecordingSemanticEvent>[
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(milliseconds: 1),
            kind: TerminalRecordingSemanticKind.commandStarted,
            cwd: '~/project',
          ),
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(milliseconds: 2),
            kind: TerminalRecordingSemanticKind.commandFinished,
            cwd: '~/project',
            exitCode: 0,
          ),
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(milliseconds: 4),
            kind: TerminalRecordingSemanticKind.commandStarted,
            cwd: '~/project',
          ),
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(milliseconds: 5),
            kind: TerminalRecordingSemanticKind.commandStarted,
            command: 'pwd',
            cwd: '~/project',
          ),
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(milliseconds: 45),
            kind: TerminalRecordingSemanticKind.commandFinished,
            command: 'pwd',
            cwd: '~/project',
            exitCode: 0,
          ),
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(milliseconds: 46),
            kind: TerminalRecordingSemanticKind.commandFinished,
            cwd: '~/project',
            exitCode: 0,
          ),
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(milliseconds: 55),
            kind: TerminalRecordingSemanticKind.commandStarted,
            command: 'cd src',
            cwd: '~/project',
          ),
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(milliseconds: 95),
            kind: TerminalRecordingSemanticKind.commandFinished,
            command: 'cd src',
            cwd: '~/project/src',
            exitCode: 0,
          ),
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(milliseconds: 96),
            kind: TerminalRecordingSemanticKind.directoryChanged,
            cwd: '~/project/src',
          ),
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(milliseconds: 100),
            kind: TerminalRecordingSemanticKind.commandStarted,
            cwd: '~/project/src',
          ),
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(milliseconds: 110),
            kind: TerminalRecordingSemanticKind.remoteSessionStarted,
            command: 'ssh prod-server',
            cwd: '~/project/src',
          ),
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(milliseconds: 150),
            kind: TerminalRecordingSemanticKind.commandStarted,
            command: 'ls -la',
            cwd: '/srv/app',
            remote: true,
          ),
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(milliseconds: 260),
            kind: TerminalRecordingSemanticKind.commandFinished,
            command: 'ls -la',
            cwd: '/srv/app',
            exitCode: 0,
            remote: true,
          ),
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(milliseconds: 360),
            kind: TerminalRecordingSemanticKind.remoteSessionFinished,
            command: 'ssh prod-server',
            exitCode: 0,
          ),
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(milliseconds: 365),
            kind: TerminalRecordingSemanticKind.commandFinished,
            cwd: '~/project/src',
            exitCode: 0,
          ),
        ]);
    final repository = _WidgetRecordingLibraryRepository(
      directory: directory,
      recording: recording,
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
          pasteHistoryRepositoryProvider.overrideWithValue(
            MemoryPasteHistoryRepository(),
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
    expect(
      find.textContaining('Keystrokes redacted · command metadata included'),
      findsOneWidget,
    );
    expect(find.text('pwd'), findsWidgets);
    expect(find.text('cd src'), findsOneWidget);
    expect(find.text('ssh prod-server'), findsWidgets);
    expect(find.text('ls -la'), findsOneWidget);
    expect(find.byKey(const Key('replay-semantic-segment-0')), findsOneWidget);
    expect(find.byKey(const Key('replay-semantic-segment-1')), findsOneWidget);
    expect(find.byKey(const Key('replay-semantic-segment-2')), findsOneWidget);
    expect(find.byKey(const Key('replay-semantic-segment-3')), findsOneWidget);
    expect(find.byKey(const Key('replay-semantic-segment-4')), findsNothing);
    expect(find.text('Command 1'), findsNothing);
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
    await tester.tap(find.byKey(const Key('replay-semantic-segment-0')));
    await tester.pump();
    expect(
      tester
          .widget<Slider>(find.byKey(const Key('recording-replay-timeline')))
          .value,
      closeTo(4000, 1),
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
