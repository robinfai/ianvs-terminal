import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';

class _ReplayShellBackend extends FakePtyBackend
    implements
        PtyReplaySessionBackend,
        PtyReplaySessionConfigV1Backend,
        PtyReplayCheckpointBackend {
  _ReplayShellBackend({this.supportsCheckpoints = true});

  final bool supportsCheckpoints;
  int _checkpointSeed = 0;

  @override
  bool get supportsReplayCheckpoints => supportsCheckpoints;

  @override
  int captureReplayCheckpoint(String sessionId) => ++_checkpointSeed;

  @override
  bool restoreReplayCheckpoint(String sessionId, int checkpointId) => true;

  @override
  String createReplaySessionV1(String sessionConfigV1Json) {
    return createSessionV1(sessionConfigV1Json);
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

// Exercise real local files/indexes without spawning worker isolates inside
// the widget fake clock. Background codec workers have repository coverage.
class _PersistentWidgetRecordingRepository
    extends LocalSessionRecordingRepository
    with NoIoLocalSessionRecordingRecovery {
  _PersistentWidgetRecordingRepository({required super.directoryResolver})
    : super(
        encoder: (recording) async =>
            const TerminalRecordingCodec().encode(recording),
        decoder: (source) async =>
            const TerminalRecordingCodec().decode(source),
      );
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

class _WidgetRecordingLibraryRepository extends LocalSessionRecordingRepository
    with NoIoLocalSessionRecordingRecovery {
  _WidgetRecordingLibraryRepository({
    required this.directory,
    required this.recording,
  }) : entry = LocalSessionRecordingEntry(
         path: '${directory.path}/vttest-regression.ndjson',
         displayName: 'vttest regression',
         createdAtUtc: DateTime.utc(2026, 7, 21, 6),
         duration: const Duration(milliseconds: 400),
         fileSizeBytes: 512,
         sessionId: 'recorded-session',
         schemaVersion: terminalRecordingSchemaVersion,
         inputPolicy: TerminalRecordingInputPolicy.redact,
       ),
       super(directoryResolver: () async => directory);

  final Directory directory;
  final TerminalRecording recording;
  final LocalSessionRecordingEntry entry;

  @override
  Future<Directory> ensureRecordingDirectory() {
    return Future<Directory>.value(directory.absolute);
  }

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

class _EmptyRecordingLibraryRepository
    extends _WidgetRecordingLibraryRepository {
  _EmptyRecordingLibraryRepository({
    required super.directory,
    required super.recording,
  });

  @override
  Future<List<LocalSessionRecordingEntry>> listRecordings() async => const [];
}

class _FailingRecordingLibraryRepository
    extends _WidgetRecordingLibraryRepository {
  _FailingRecordingLibraryRepository({
    required super.directory,
    required super.recording,
  });

  @override
  Future<List<LocalSessionRecordingEntry>> listRecordings() async {
    throw const FileSystemException('recording index unavailable');
  }
}

class _MutableRecordingLibraryRepository
    extends _WidgetRecordingLibraryRepository {
  _MutableRecordingLibraryRepository({
    required super.directory,
    required super.recording,
  }) : currentRecording = recording;

  TerminalRecording currentRecording;

  @override
  Future<TerminalRecording> load(String recordingPath) async =>
      currentRecording;
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('TRAIL_REPLAY_CAPTURE')) return;
    final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
    Future<ByteData> font(String path) async =>
        ByteData.sublistView(await File(path).readAsBytes());
    await (FontLoader(
      'ReplayCaptureSans',
    )..addFont(font('/System/Library/Fonts/STHeiti Medium.ttc'))).load();
    await (FontLoader('MaterialIcons')..addFont(
          font(
            '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ),
        ))
        .load();
  });
  testWidgets('recording panel opens a saved recording and a picked file', (
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
    String? pickerInitialDirectory;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(
            _ReplayShellBackend(supportsCheckpoints: false),
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
          shellRecordingFilePickerProvider.overrideWithValue(({
            initialDirectory,
          }) async {
            pickerInitialDirectory = initialDirectory;
            return repository.entry.path;
          }),
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
      'replay',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-open-recording')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('shell-open-recording')));
    await tester.tap(find.byKey(const Key('shell-open-recording')));
    await _pumpUntil(
      tester,
      () =>
          find.byKey(const Key('saved-recordings-shelf')).evaluate().isNotEmpty,
      phase: 'recording panel',
    );
    expect(pickerInitialDirectory, isNull);
    expect(find.text('Replay'), findsWidgets);
    expect(find.text('Recent screen history'), findsOneWidget);
    expect(find.text('Saved Recordings'), findsOneWidget);
    expect(find.text('Open recording file'), findsOneWidget);
    expect(
      find.byKey(const Key('shell-replay-recent-activity')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('recording-library-open-file')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('recording-library-close')), findsOneWidget);
    expect(find.byKey(const Key('recording-library-refresh')), findsOneWidget);
    expect(
      find.byKey(const Key('recording-library-toggle-recording')),
      findsOneWidget,
    );
    final recordingEntryKey = ValueKey<String>(
      'recording-entry-${repository.entry.path}',
    );
    expect(find.byKey(recordingEntryKey), findsOneWidget);
    await tester.tap(find.byKey(recordingEntryKey));
    await _pumpUntil(
      tester,
      () => find
          .byKey(const Key('recording-replay-layout'))
          .evaluate()
          .isNotEmpty,
      phase: 'recording replay layout',
    );
    final expectedRecordingDirectory = directory.absolute;
    expect(expectedRecordingDirectory.existsSync(), isTrue);
    expect(find.byKey(const Key('saved-recordings-shelf')), findsNothing);
    expect(find.text('vttest regression'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(find.byKey(const Key('recording-replay-toggle')), findsOneWidget);
    expect(find.byKey(const Key('recording-replay-stage')), findsOneWidget);
    expect(find.byKey(const Key('recording-replay-fit')), findsOneWidget);
    expect(
      find.byKey(const Key('recording-replay-floating-dock')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('recording-replay-dock-drag-handle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('recording-replay-fit-recorded-size')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('recording-replay-timeline-effects')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('recording-replay-timeline')), findsOneWidget);
    expect(find.byKey(const Key('recording-replay-speed')), findsOneWidget);
    expect(find.byKey(const Key('recording-replay-time-mode')), findsOneWidget);
    expect(find.byTooltip('Play replay'), findsOneWidget);
    expect(find.byTooltip('Replay timing'), findsOneWidget);
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

    await tester.tap(find.byKey(const Key('recording-replay-toggle')));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byTooltip('Pause replay'), findsOneWidget);
    final recordingReplayDockDrag = await tester.startGesture(
      tester.getCenter(
        find.byKey(const Key('recording-replay-dock-drag-handle')),
      ),
    );
    await recordingReplayDockDrag.moveBy(const Offset(0, -24));
    await tester.pump();
    final timelineValueBeforeDockDrag = tester
        .widget<Slider>(find.byKey(const Key('recording-replay-timeline')))
        .value;
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      tester
          .widget<Slider>(find.byKey(const Key('recording-replay-timeline')))
          .value,
      greaterThan(timelineValueBeforeDockDrag),
    );
    await recordingReplayDockDrag.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Play replay'), findsOneWidget);
    expect(
      tester
          .widget<Slider>(find.byKey(const Key('recording-replay-timeline')))
          .value,
      closeTo(400000, 1),
    );

    await tester.tap(find.byKey(const Key('replay-semantic-segment-0')));
    await tester.pump();
    expect(
      tester
          .widget<Slider>(find.byKey(const Key('recording-replay-timeline')))
          .value,
      closeTo(4000, 1),
    );

    await tester.enterText(
      find.byKey(const Key('recording-replay-search')),
      'vttest',
    );
    await tester.pump();
    expect(find.text('1 match across replay'), findsOneWidget);
    expect(
      tester
          .widget<Slider>(find.byKey(const Key('recording-replay-timeline')))
          .value,
      closeTo(400000, 1),
    );
    expect(find.byTooltip('Play replay'), findsOneWidget);
    semantics.dispose();

    await tester.tap(find.byKey(const Key('recording-replay-search')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recording-replay-layout')), findsNothing);
    expect(find.byKey(const Key('shell-chrome-bar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-toolbar-replay')));
    await _pumpUntil(
      tester,
      () =>
          find.byKey(const Key('saved-recordings-shelf')).evaluate().isNotEmpty,
      phase: 'recording panel reopened',
    );
    await tester.tap(find.byKey(const Key('recording-library-open-file')));
    await _pumpUntil(
      tester,
      () => find
          .byKey(const Key('recording-replay-layout'))
          .evaluate()
          .isNotEmpty,
      phase: 'picked recording replay layout',
    );
    expect(pickerInitialDirectory, expectedRecordingDirectory.path);
    expect(find.byKey(const Key('saved-recordings-shelf')), findsNothing);
  });

  testWidgets('compact recording panel shows an empty local library', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _recordingLibraryFixture('compact-empty'),
    ))!;
    addTearDown(() => tester.runAsync(fixture.close));
    final repository = _EmptyRecordingLibraryRepository(
      directory: fixture.directory,
      recording: fixture.recording,
    );
    await _pumpRecordingLibraryShell(
      tester,
      repository: repository,
      size: const Size(390, 844),
      textScaler: const TextScaler.linear(1.5),
    );

    await tester.tap(find.byKey(const Key('shell-toolbar-replay')));
    await _pumpUntil(
      tester,
      () => find
          .byKey(const Key('saved-recordings-shelf-compact'))
          .evaluate()
          .isNotEmpty,
      phase: 'compact recording panel',
    );

    expect(find.byKey(const Key('recording-library-empty')), findsOneWidget);
    expect(find.byKey(const Key('recording-library-error')), findsNothing);
    expect(
      find.byKey(const Key('recording-library-open-file')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await _capturePanelIfEnabled(tester, 'compact-scaled');
  });

  testWidgets('recording panel exposes a recoverable library error', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _recordingLibraryFixture('load-error'),
    ))!;
    addTearDown(() => tester.runAsync(fixture.close));
    final repository = _FailingRecordingLibraryRepository(
      directory: fixture.directory,
      recording: fixture.recording,
    );
    await _pumpRecordingLibraryShell(
      tester,
      repository: repository,
      themeMode: ThemeMode.dark,
    );

    await tester.tap(find.byKey(const Key('shell-toolbar-replay')));
    await _pumpUntil(
      tester,
      () => find
          .byKey(const Key('recording-library-error'))
          .evaluate()
          .isNotEmpty,
      phase: 'recording library error',
    );

    expect(find.byKey(const Key('recording-library-refresh')), findsOneWidget);
    expect(
      find.byKey(const Key('recording-library-open-file')),
      findsOneWidget,
    );
  });

  testWidgets(
    'saved recording survives app rebuild and supports search and copy',
    (tester) async {
      final fixture = (await tester.runAsync(
        () => _recordingLibraryFixture('persisted-rebuild'),
      ))!;
      addTearDown(() => tester.runAsync(fixture.close));
      final seeded = (await tester.runAsync(() async {
        final repository = _PersistentWidgetRecordingRepository(
          directoryResolver: () async => fixture.directory,
        );
        final destination = await repository.reserve(
          runtimeSessionId: fixture.recording.metadata.sessionId,
          createdAtUtc: fixture.recording.metadata.createdAtUtc,
        );
        final path = await repository.save(
          destination,
          fixture.recording,
          displayName: 'Persisted recording',
        );
        return (repository, path);
      }))!;
      final firstRepository = seeded.$1;
      final recordingPath = seeded.$2;

      await _pumpRecordingLibraryShell(
        tester,
        repository: firstRepository,
        themeMode: ThemeMode.dark,
      );
      await tester.tap(find.byKey(const Key('shell-toolbar-replay')));
      await _pumpUntil(
        tester,
        () => find
            .byKey(ValueKey<String>('recording-entry-$recordingPath'))
            .evaluate()
            .isNotEmpty,
        phase: 'newly saved recording entry',
      );
      await _capturePanelIfEnabled(tester, 'desktop-dark');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final rebuiltRepository = _PersistentWidgetRecordingRepository(
        directoryResolver: () async => fixture.directory,
      );
      await _pumpRecordingLibraryShell(tester, repository: rebuiltRepository);
      await tester.tap(find.byKey(const Key('shell-toolbar-replay')));
      final rebuiltEntry = find.byKey(
        ValueKey<String>('recording-entry-$recordingPath'),
      );
      await _pumpUntil(
        tester,
        () => rebuiltEntry.evaluate().isNotEmpty,
        phase: 'persisted recording after app rebuild',
      );
      await tester.tap(rebuiltEntry);
      await _pumpUntil(
        tester,
        () => find
            .byKey(const Key('recording-replay-layout'))
            .evaluate()
            .isNotEmpty,
        phase: 'persisted recording replay',
      );
      expect(find.byKey(const Key('saved-recordings-shelf')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('recording-replay-search')),
        'vttest',
      );
      await tester.pump();
      expect(find.text('1 match across replay'), findsOneWidget);

      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.byTooltip('Copy visible'));
      await tester.pump();
      expect(copiedText, contains(r'$ vttest --replay'));
    },
  );

  testWidgets('closing the panel cancels a pending picked recording', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _recordingLibraryFixture('cancel-picker'),
    ))!;
    addTearDown(() => tester.runAsync(fixture.close));
    final repository = _WidgetRecordingLibraryRepository(
      directory: fixture.directory,
      recording: fixture.recording,
    );
    final pickerResult = Completer<String?>();
    await _pumpRecordingLibraryShell(
      tester,
      repository: repository,
      picker: ({initialDirectory}) => pickerResult.future,
    );

    await tester.tap(find.byKey(const Key('shell-toolbar-replay')));
    await _pumpUntil(
      tester,
      () => find
          .byKey(const Key('recording-library-open-file'))
          .evaluate()
          .isNotEmpty,
      phase: 'recording picker action',
    );
    await tester.tap(find.byKey(const Key('recording-library-open-file')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('recording-library-close')));
    await tester.pump();
    pickerResult.complete(repository.entry.path);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('saved-recordings-shelf')), findsNothing);
    expect(find.byKey(const Key('recording-replay-layout')), findsNothing);
  });

  testWidgets('reselecting the same path rebuilds replay with new content', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _recordingLibraryFixture('same-path-replacement'),
    ))!;
    addTearDown(() => tester.runAsync(fixture.close));
    final repository = _MutableRecordingLibraryRepository(
      directory: fixture.directory,
      recording: const TerminalRecordingCodec().decode(
        _recordingFixture('recorded-session', output: 'first marker'),
      ),
    );
    await _pumpRecordingLibraryShell(tester, repository: repository);

    await _openFirstSavedRecording(tester, repository.entry.path);
    await tester.enterText(
      find.byKey(const Key('recording-replay-search')),
      'first marker',
    );
    await tester.pump();
    expect(find.text('1 match across replay'), findsOneWidget);

    repository.currentRecording = const TerminalRecordingCodec().decode(
      _recordingFixture('recorded-session', output: 'second marker'),
    );
    await _openFirstSavedRecording(tester, repository.entry.path);
    await tester.enterText(
      find.byKey(const Key('recording-replay-search')),
      'second marker',
    );
    await tester.pump();

    expect(find.text('1 match across replay'), findsOneWidget);
  });

  testWidgets('Escape from the panel restores replay search focus', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _recordingLibraryFixture('restore-replay-focus'),
    ))!;
    addTearDown(() => tester.runAsync(fixture.close));
    final repository = _WidgetRecordingLibraryRepository(
      directory: fixture.directory,
      recording: fixture.recording,
    );
    await _pumpRecordingLibraryShell(tester, repository: repository);
    await _openFirstSavedRecording(tester, repository.entry.path);

    await tester.enterText(
      find.byKey(const Key('recording-replay-search')),
      'vttest',
    );
    await tester.pump();
    final replaySearchFocus = FocusManager.instance.primaryFocus;
    expect(replaySearchFocus, isNotNull);
    await tester.tap(find.byKey(const Key('shell-toolbar-replay')));
    await _pumpUntil(
      tester,
      () =>
          find.byKey(const Key('saved-recordings-shelf')).evaluate().isNotEmpty,
      phase: 'panel over recording replay',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('saved-recordings-shelf')), findsNothing);
    expect(FocusManager.instance.primaryFocus, same(replaySearchFocus));
    final search = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('recording-replay-search')),
        matching: find.byType(EditableText),
      ),
    );
    expect(search.controller.text, 'vttest');
    expect(find.text('1 match across replay'), findsOneWidget);
  });

  testWidgets(
    'compact recording replay remains accessible after closing its shelf',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final fixture = (await tester.runAsync(
          () => _recordingLibraryFixture('replay-accessibility'),
        ))!;
        addTearDown(() => tester.runAsync(fixture.close));
        final repository = _WidgetRecordingLibraryRepository(
          directory: fixture.directory,
          recording: fixture.recording,
        );
        await _pumpRecordingLibraryShell(
          tester,
          repository: repository,
          size: const Size(800, 600),
        );
        await _openFirstSavedRecording(tester, repository.entry.path);

        expect(
          find.semantics.byLabel('Replay controls for recording'),
          findsOne,
        );
        tester.semantics.tap(find.semantics.byLabel('Play replay'));
        await tester.pump();
        expect(find.semantics.byLabel('Pause replay'), findsOne);
        tester.semantics.tap(find.semantics.byLabel('Pause replay'));
        await tester.pump();
        expect(find.semantics.byLabel('Play replay'), findsOne);
        tester.semantics.tap(
          find.semantics.byLabel(RegExp('^Playback speed 1 times')),
        );
        await tester.pumpAndSettle();
        tester.semantics.tap(find.semantics.byLabel('2×'));
        await tester.pumpAndSettle();
        expect(
          find.semantics.byLabel(RegExp('^Playback speed 2 times')),
          findsOne,
        );
        tester.semantics.tap(
          find.semantics.byLabel(RegExp('^Smart replay timing')),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        tester.semantics.tap(find.semantics.byLabel('Search replay'));
        await tester.pump();
        tester.semantics.setText(
          find.semantics.byLabel('Search replay'),
          'vttest',
        );
        await tester.pump();
        expect(find.text('1 match across replay'), findsOneWidget);
        tester.semantics.tap(find.semantics.byLabel('Close replay'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('recording-replay-layout')), findsNothing);
        expect(find.semantics.byLabel('Replay'), findsOne);
        tester.semantics.tap(find.semantics.byLabel('Replay'));
        await tester.pumpAndSettle();
        tester.semantics.tap(find.semantics.byLabel('Refresh recordings'));
        await tester.pumpAndSettle();
        tester.semantics.tap(find.semantics.byLabel('Close'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('saved-recordings-shelf')), findsNothing);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'recording replay viewport releases Tab focus and closes with Escape',
    (tester) async {
      final fixture = (await tester.runAsync(
        () => _recordingLibraryFixture('replay-viewport-keyboard'),
      ))!;
      addTearDown(() => tester.runAsync(fixture.close));
      final repository = _WidgetRecordingLibraryRepository(
        directory: fixture.directory,
        recording: fixture.recording,
      );
      await _pumpRecordingLibraryShell(tester, repository: repository);
      await _openFirstSavedRecording(tester, repository.entry.path);

      final viewport = find.byKey(const Key('recording-replay-viewport'));
      await tester.tap(viewport);
      await tester.pump();
      final viewportFocus = FocusManager.instance.primaryFocus;
      expect(viewportFocus?.debugLabel, 'recording-replay');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final controlFocus = FocusManager.instance.primaryFocus;
      expect(controlFocus, isNotNull);
      expect(controlFocus, isNot(same(viewportFocus)));
      final focusedWidget = controlFocus!.context!.widget;
      expect(
        find.ancestor(
          of: find.byWidget(focusedWidget),
          matching: find.byKey(const Key('recording-replay-floating-dock')),
        ),
        findsOneWidget,
      );

      await tester.tap(viewport);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'recording-replay',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recording-replay-layout')), findsNothing);
      expect(find.byKey(const Key('shell-chrome-bar')), findsOneWidget);
    },
  );
}

Future<void> _pumpRecordingLibraryShell(
  WidgetTester tester, {
  required LocalSessionRecordingRepository repository,
  Size size = const Size(1100, 900),
  PtySessionBackend? backend,
  ThemeMode themeMode = ThemeMode.light,
  TextScaler textScaler = TextScaler.noScaling,
  ShellRecordingFilePicker? picker,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(
          backend ?? _ReplayShellBackend(),
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
        if (picker != null)
          shellRecordingFilePickerProvider.overrideWithValue(picker),
      ],
      child: MaterialApp(
        theme: _captureTheme(Brightness.light),
        darkTheme: _captureTheme(Brightness.dark),
        themeMode: themeMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: RepaintBoundary(
            key: const Key('replay-capture-root'),
            child: child,
          ),
        ),
        home: const ShellScreen(),
      ),
    ),
  );
  await _pumpUntil(
    tester,
    () => find.byKey(const Key('shell-toolbar-replay')).evaluate().isNotEmpty,
    phase: 'replay toolbar control',
  );
}

Future<void> _openFirstSavedRecording(
  WidgetTester tester,
  String recordingPath,
) async {
  await tester.tap(find.byKey(const Key('shell-toolbar-replay')));
  final entry = find.byKey(ValueKey<String>('recording-entry-$recordingPath'));
  await _pumpUntil(
    tester,
    () => entry.evaluate().isNotEmpty,
    phase: 'saved recording entry',
  );
  await tester.tap(entry);
  await _pumpUntil(
    tester,
    () =>
        find.byKey(const Key('recording-replay-layout')).evaluate().isNotEmpty,
    phase: 'saved recording replay',
  );
  await tester.pumpAndSettle();
}

ThemeData _captureTheme(Brightness brightness) {
  final theme = buildIanvsTerminalTheme(
    brightness,
    platform: TargetPlatform.macOS,
  );
  if (!const bool.fromEnvironment('TRAIL_REPLAY_CAPTURE')) return theme;
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'ReplayCaptureSans'),
    primaryTextTheme: theme.primaryTextTheme.apply(
      fontFamily: 'ReplayCaptureSans',
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: theme.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll(
          theme.textTheme.labelLarge!.copyWith(fontFamily: 'ReplayCaptureSans'),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: theme.outlinedButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll(
          theme.textTheme.labelLarge!.copyWith(fontFamily: 'ReplayCaptureSans'),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: theme.textButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll(
          theme.textTheme.labelLarge!.copyWith(fontFamily: 'ReplayCaptureSans'),
        ),
      ),
    ),
  );
}

Future<void> _capturePanelIfEnabled(WidgetTester tester, String label) async {
  if (!const bool.fromEnvironment('TRAIL_REPLAY_CAPTURE')) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('replay-capture-root')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await File(
      '/tmp/trail-replay-$label.png',
    ).writeAsBytes(data!.buffer.asUint8List(), flush: true);
  });
}

Future<
  ({
    Directory directory,
    TerminalRecording recording,
    Future<void> Function() close,
  })
>
_recordingLibraryFixture(String label) async {
  final directory = await Directory.systemTemp.createTemp(
    'ianvs-recording-library-$label-',
  );
  final recording = const TerminalRecordingCodec().decode(
    _recordingFixture('recorded-session'),
  );
  return (
    directory: directory,
    recording: recording,
    close: () async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    },
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required String phase,
}) async {
  for (var attempt = 0; attempt < 120; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
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

String _recordingFixture(
  String sessionId, {
  String output = r'$ vttest --replay',
}) {
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
        'bytes_base64': base64Encode(utf8.encode(output)),
      },
    },
  ].map(jsonEncode).join('\n');
}
