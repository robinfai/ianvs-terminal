import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/app.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/recording/sampled_recording_library.dart';
import 'package:app/features/recording/sampled_replay_surface.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart'
    show TerminalViewport;
import 'package:app/platform/app_shutdown_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;
import 'package:integration_test/integration_test.dart';

import '../test/support/macos_integration_test_lifecycle.dart';
import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_local_terminal_config_repository.dart';
import '../test/support/memory_paste_history_repository.dart';
import '../test/support/memory_profile_repository.dart';

// Real macOS product composition. The deterministic PTY script emits explicit
// hook fixtures; installed-shell hook coverage and the >24-hour run are separate.
const _command = "printf '%s' 'recorded command 雪'";

String _hook(Map<String, Object?> value) {
  final hex = utf8
      .encode(jsonEncode(value))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return "printf '\\033Phook;$hex\\033\\\\'";
}

String _script() => [
  r"printf '\033[?1049h\033[2J\033[HREADY-MID-TUI 雪\n'",
  'IFS= read -r gate',
  _hook({'hook': 'preexec', 'command': _command, 'context_id': 'root'}),
  r"printf '\033[2J\033[H\033[31mCAPTURED-TUI 雪\033[0m\n'",
  r"printf '\033]8;;https://example.com/recording\033\\retained link\033]8;;\033\\\n'",
  r"printf '\033_Ga=T,q=2,f=32,s=2,v=1,i=73,c=8,r=3;/wAA/wD/AP8=\033\\'",
  'IFS= read -r resize_gate',
  _hook({
    'hook': 'command_finished',
    'command': _command,
    'context_id': 'root',
    'exit_code': 7,
  }),
  r"printf '\033[?1049l\033[2J\033[HFINISHED-RECORDING 雪\n'",
  r"printf '\033_Ga=d,d=A\033\\'",
  'IFS= read -r exit_gate',
  "printf 'READ-ONLY-FAILED:%s\\n' \"\$exit_gate\"",
  'IFS= read -r final_gate',
].join('\n');

Future<void> _wait(
  WidgetTester tester,
  bool Function() condition,
  String description,
) async {
  final clock = Stopwatch()..start();
  while (!condition() && clock.elapsed < const Duration(seconds: 20)) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue, reason: description);
}

Future<void> _action(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(const Key('shell-chrome-menu')));
  await tester.pumpAndSettle();
  final item = find.byKey(Key(key));
  await _wait(tester, () => item.evaluate().isNotEmpty, 'command $key');
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await _wait(
    tester,
    () => item.hitTestable().evaluate().isNotEmpty,
    'visible command $key',
  );
  await tester.tap(item);
}

Future<void> _dismissNotices(WidgetTester tester) async {
  // Called only while the live terminal is shown, before opening any replay or
  // shelf. These Close controls belong to the visible notification cards.
  expect(find.byType(SampledReplaySurface), findsNothing);
  expect(find.byKey(const Key('saved-recordings-shelf')), findsNothing);
  await tester.pump(const Duration(milliseconds: 200));
  for (var i = 0; i < 6; i++) {
    final close = find.byTooltip('Close').hitTestable();
    if (close.evaluate().isEmpty) return;
    await tester.tap(close.first);
    await tester.pump();
  }
  expect(find.byTooltip('Close').hitTestable(), findsNothing);
}

Future<void> _capture(GlobalKey key, Directory output, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File(
      '${output.path}/$name.png',
    ).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  } finally {
    image.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'macOS recording controls capture a populated TUI and replay without host input',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      final oldHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      const outputPath = String.fromEnvironment(
        'IANVS_RECORDING_ACCEPTANCE_OUTPUT',
      );
      final output = outputPath.isEmpty
          ? await Directory.systemTemp.createTemp('sampled-macos-acceptance-')
          : await Directory(outputPath).create(recursive: true);
      final run = await output.createTemp('run-');
      final backend = NativePtyBackend.load();
      final api = terminal.NativeRecordingFileApi();
      final library = SampledRecordingLibrary(
        files: api,
        directoryResolver: () async => Directory('${run.path}/recordings-v2'),
      );
      final profile = TerminalProfile(
        id: 'sampled-macos-acceptance',
        name: 'Sampled recording acceptance',
        shell: '/bin/sh',
        args: ['-c', _script()],
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(backend),
          sampledRecordingLibraryProvider.overrideWithValue(library),
          sampledRecordingFileApiProvider.overrideWithValue(api),
          profileRepositoryProvider.overrideWithValue(
            MemoryProfileRepository(
              TerminalProfilesDocument(profiles: [profile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            MemoryAppPreferencesRepository(null),
          ),
          pasteHistoryRepositoryProvider.overrideWithValue(
            MemoryPasteHistoryRepository(),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            MemoryLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                layout: LocalTerminalLayoutConfig(restoreLayout: false),
              ),
            ),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            LocalTerminalLayoutRepository(directoryResolver: () async => run),
          ),
          shellAnimationsEnabledProvider.overrideWithValue(false),
        ],
      );
      final boundary = GlobalKey();
      final report = <String, Object?>{
        'os': Platform.operatingSystemVersion,
        'passed': false,
      };
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
              key: boundary,
              child: const IanvsTerminalApp(),
            ),
          ),
        );
        await _wait(
          tester,
          () => container.read(sessionControllerProvider).isReady,
          'app bootstrap',
        );
        final controller = container.read(sessionControllerProvider.notifier);
        await controller.setLanguageMode(TerminalLanguageMode.english);
        final runtime = container.read(terminalRuntimeControllerProvider);
        final sessionId = container
            .read(sessionControllerProvider)
            .activeSessionId!;
        String liveText() => runtime
            .viewportFor(sessionId)
            .frame
            .rows
            .map((row) => row.text)
            .join('\n');
        await _wait(
          tester,
          () => liveText().contains('READY-MID-TUI'),
          'populated TUI before recording',
        );
        expect(
          runtime.viewportFor(sessionId).frame.modes.alternateScreen,
          isTrue,
        );
        await _action(tester, 'shell-toggle-session-recording');
        await _wait(
          tester,
          () => container
              .read(sessionControllerProvider)
              .recordingSessionIds
              .contains(sessionId),
          'recording start',
        );
        final claim = library.activeClaims.single;
        final client = container.read(sampledRecordingCaptureClientProvider)!;
        await _wait(
          tester,
          () =>
              client.status(claim.handle).phase ==
              terminal.SampledCapturePhase.capturing,
          'native capture settlement',
        );
        await _dismissNotices(tester);
        runtime.sendInput(
          sessionId,
          Uint8List.fromList(utf8.encode('capture\n')),
        );
        await _wait(
          tester,
          () => liveText().contains('CAPTURED-TUI'),
          'recorded styled TUI',
        );
        final columns = runtime.viewportFor(sessionId).frame.viewportCols;
        controller.resizeSession(sessionId, const Size(620, 360), 1);
        await _wait(
          tester,
          () => runtime.viewportFor(sessionId).frame.viewportCols != columns,
          'native viewport resize',
        );
        await tester.pump(const Duration(milliseconds: 1200));
        await _capture(boundary, run, 'live-tui');
        runtime.sendInput(
          sessionId,
          Uint8List.fromList(utf8.encode('finish\n')),
        );
        await _wait(
          tester,
          () => liveText().contains('FINISHED-RECORDING'),
          'return to primary screen',
        );
        await _action(tester, 'shell-toggle-session-recording');
        await _wait(
          tester,
          () =>
              !container
                  .read(sessionControllerProvider)
                  .recordingSessionIds
                  .contains(sessionId) &&
              library.activeClaims.isEmpty,
          'durable recording stop',
        );
        await _dismissNotices(tester);
        final entry = (await library.listRecordings()).single;
        Duration? tuiOffset;
        Duration? commandOffset;
        final opened = await library.openRecording(entry.path);
        try {
          expect(
            opened.recording.info.completion,
            terminal.SampledRecordingCompletion.finished,
          );
          final first = (await opened.recording.seek(Duration.zero))!;
          expect(first.frame.modes.alternateScreen, isTrue);
          expect(
            first.frame.rows.any((row) => row.text.contains('READY-MID-TUI')),
            isTrue,
          );
          final last = (await opened.recording.seek(
            opened.recording.info.duration,
          ))!;
          expect(last.frame.modes.alternateScreen, isFalse);
          expect(
            last.frame.rows.any(
              (row) => row.text.contains('FINISHED-RECORDING'),
            ),
            isTrue,
          );
          final retained = await opened.recording.search(
            query: 'CAPTURED-TUI',
            kind: terminal.SampledRecordingSearchKind.screen,
          );
          for (final hit in retained.hits.reversed) {
            final sampled = (await opened.recording.seek(hit.offset))!;
            if (sampled.assets.isEmpty) continue;
            expect(sampled.frame.modes.alternateScreen, isTrue);
            final image = await opened.recording.loadAsset(
              sampled.assets.single,
            );
            expect(image.rgba, [255, 0, 0, 255, 0, 255, 0, 255]);
            tuiOffset = hit.offset;
            break;
          }
          expect(
            tuiOffset,
            isNotNull,
            reason: 'TUI image must remain after deleting live image data',
          );
          final timeline = await opened.recording.timeline();
          commandOffset = timeline.events
              .singleWhere(
                (event) =>
                    event.kind == terminal.SampledTimelineKind.commandStarted &&
                    event.command == _command,
              )
              .offset;
          expect(
            timeline.events.any(
              (event) =>
                  event.kind == terminal.SampledTimelineKind.commandFinished &&
                  event.command == _command &&
                  event.exitCode == 7,
            ),
            isTrue,
          );
          report.addAll({
            'recording_id': entry.id,
            'duration_micros': opened.recording.info.duration.inMicroseconds,
            'source_bytes': opened.recording.info.sourceBytes,
          });
        } finally {
          await opened.close();
        }
        await _action(tester, 'shell-open-recording');
        final selected = find.byKey(ValueKey('recording-entry-${entry.path}'));
        await _wait(
          tester,
          () => selected.evaluate().isNotEmpty,
          'saved library entry',
        );
        await tester.ensureVisible(selected);
        await tester.tap(selected);
        final player = find.byType(SampledReplaySurface);
        await _wait(
          tester,
          () =>
              player.evaluate().isNotEmpty &&
              !tester.widget<SampledReplaySurface>(player).loading,
          'replay initial frame',
        );
        await _capture(boundary, run, 'replay-initial-light');
        await tester.tap(find.byTooltip('Commands'));
        final command = find.byWidgetPredicate(
          (widget) =>
              widget is ListTile &&
              widget.title is Text &&
              (widget.title! as Text).data == _command &&
              widget.subtitle is Text &&
              (widget.subtitle! as Text).data!.contains('Started'),
        );
        await _wait(
          tester,
          () => command.evaluate().isNotEmpty,
          'recorded hook command list',
        );
        await tester.ensureVisible(command);
        await tester.tap(command);
        await _wait(
          tester,
          () =>
              !tester.widget<SampledReplaySurface>(player).loading &&
              tester.widget<SampledReplaySurface>(player).position ==
                  commandOffset,
          'command tap seeks to its exact time',
        );
        tester.widget<SampledReplaySurface>(player).onSeek(tuiOffset!);
        await _wait(
          tester,
          () =>
              !tester.widget<SampledReplaySurface>(player).loading &&
              tester.widget<SampledReplaySurface>(player).position == tuiOffset,
          'seek retained TUI image',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await _capture(boundary, run, 'replay-tui-light');
        final replay = tester.widget<SampledReplaySurface>(player);
        replay.onSeek(replay.duration);
        await _wait(
          tester,
          () =>
              !tester.widget<SampledReplaySurface>(player).loading &&
              tester.widget<SampledReplaySurface>(player).position ==
                  replay.duration,
          'seek final frame',
        );
        final replayViewport = tester.widget<TerminalViewport>(
          find.byKey(const Key('recording-replay-viewport')),
        );
        expect(
          replayViewport.controller.frame.rows.any(
            (row) => row.text.contains('FINISHED-RECORDING'),
          ),
          isTrue,
        );
        await controller.setThemeMode(TerminalThemeMode.dark);
        await _wait(
          tester,
          () => Theme.of(tester.element(player)).brightness == Brightness.dark,
          'dark theme applied',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await _capture(boundary, run, 'replay-final-dark');
        await tester.tap(find.byKey(const Key('recording-replay-viewport')));
        await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(milliseconds: 500));
        expect(runtime.hasSession(sessionId), isTrue);
        expect(liveText(), isNot(contains('READ-ONLY-FAILED')));
        expect(container.read(sessionControllerProvider).tabs, hasLength(1));
        expect(tester.takeException(), isNull);
        report['passed'] = true;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        final result = await container
            .read(appShutdownCoordinatorProvider)
            .shutdown(bounded: false);
        report['safe_to_terminate'] = result.safeToTerminate;
        container.dispose();
        api.dispose();
        await File('${run.path}/result.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
          flush: true,
        );
        debugPrint('SAMPLED_RECORDING_ACCEPTANCE=${run.path}');
        WidgetController.hitTestWarningShouldBeFatal = oldHitTestPolicy;
      }
    },
    skip: !Platform.isMacOS,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
