import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/app.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/recording/recording_retention_surface.dart';
import 'package:app/features/recording/sampled_recording_library.dart';
import 'package:app/features/recording/sampled_recording_search_surface.dart';
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

Future<void> _wait(
  WidgetTester tester,
  FutureOr<bool> Function() condition,
  String description,
) async {
  final clock = Stopwatch()..start();
  while (!await condition() && clock.elapsed < const Duration(seconds: 20)) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(await condition(), isTrue, reason: description);
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

// Full application composition with real native captures in a task-owned library.
// Age cutoff edge cases use explicit timestamp fixtures in library unit tests;
// this scenario exercises persisted settings and real UI protection/cleanup.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'retention UI protects kept, playing and active recordings',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final priorHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      const outputPath = String.fromEnvironment(
        'IANVS_RECORDING_RETENTION_OUTPUT',
      );
      final output = outputPath.isEmpty
          ? await Directory.systemTemp.createTemp('recording-retention-')
          : await Directory(outputPath).create(recursive: true);
      final run = await output.createTemp('run-');
      final api = terminal.NativeRecordingFileApi();
      Future<Directory> root() async => Directory('${run.path}/recordings-v2');
      final library = SampledRecordingLibrary(
        files: api,
        directoryResolver: root,
      );
      final profile = TerminalProfile(
        id: 'retention-acceptance',
        name: 'Retention acceptance',
        shell: '/bin/sh',
        args: [
          '-c',
          r"""
printf 'RETENTION-READY\n'
while IFS= read -r token; do
  printf '\033[2J\033[HRETENTION:%s\n' "$token"
done""",
        ],
      );
      final scope = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(NativePtyBackend.load()),
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
        'passed': false,
        'os': Platform.operatingSystemVersion,
      };
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: scope,
            child: RepaintBoundary(
              key: boundary,
              child: const IanvsTerminalApp(),
            ),
          ),
        );
        await _wait(
          tester,
          () =>
              scope.read(sessionControllerProvider).isReady &&
              scope.read(sessionControllerProvider).activeSessionId != null,
          'app ready',
        );
        await scope
            .read(sessionControllerProvider.notifier)
            .setLanguageMode(TerminalLanguageMode.english);
        final sessionId = scope
            .read(sessionControllerProvider)
            .activeSessionId!;
        final runtime = scope.read(terminalRuntimeControllerProvider);
        final client = scope.read(sampledRecordingCaptureClientProvider)!;
        String liveText() => runtime
            .viewportFor(sessionId)
            .frame
            .rows
            .map((row) => row.text)
            .join('\n');
        await _wait(
          tester,
          () => liveText().contains('RETENTION-READY'),
          'shell ready',
        );
        await _dismissNotices(tester);
        Future<SampledRecordingClaim> start(String label) async {
          runtime.sendInput(
            sessionId,
            Uint8List.fromList(utf8.encode('$label\n')),
          );
          await _wait(
            tester,
            () => liveText().contains('RETENTION:$label'),
            'fixture $label',
          );
          await _action(tester, 'shell-toggle-session-recording');
          await _wait(
            tester,
            () => scope
                .read(sessionControllerProvider)
                .recordingSessionIds
                .contains(sessionId),
            'capture $label',
          );
          final claim = library.activeClaims.single;
          await _wait(
            tester,
            () => client.status(claim.handle).committed.recordCount > 0,
            'committed $label',
          );
          return claim;
        }

        Future<void> stop() async {
          await _action(tester, 'shell-toggle-session-recording');
          await _wait(
            tester,
            () =>
                library.activeClaims.isEmpty &&
                scope
                    .read(sessionControllerProvider)
                    .recordingBusySessionIds
                    .isEmpty &&
                scope
                    .read(sessionControllerProvider)
                    .recordingPendingSaveSessionIds
                    .isEmpty,
            'capture saved',
          );
          await _dismissNotices(tester);
        }

        Future<void> openLibrary() async {
          await _action(tester, 'shell-open-recording');
          await _wait(
            tester,
            () => find
                .byKey(const Key('recording-library-retention'))
                .evaluate()
                .isNotEmpty,
            'library visible',
          );
        }

        Future<void> closeLibrary() async {
          await tester.tap(find.byKey(const Key('recording-library-close')));
          await _wait(
            tester,
            () => find
                .byKey(const Key('saved-recordings-shelf'))
                .evaluate()
                .isEmpty,
            'library closed',
          );
        }

        Future<void> toggleKeep(String path, bool kept) async {
          final button = find.byKey(ValueKey('recording-actions-$path'));
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          await tester.tap(button);
          await tester.pumpAndSettle();
          await tester.tap(
            find
                .text(kept ? 'Keep recording' : 'Allow automatic cleanup')
                .hitTestable(),
          );
          await _wait(
            tester,
            () async =>
                (await library.listRecordings())
                    .singleWhere((e) => e.path == path)
                    .keep ==
                kept,
            'Keep=$kept',
          );
          await tester.pumpAndSettle();
        }

        Future<void> searchOrdinary({required bool present}) async {
          final button = find.byKey(const Key('recording-library-search'));
          await tester.ensureVisible(button);
          await tester.tap(button);
          final surface = find.byType(RecordingSearchSurface);
          await _wait(
            tester,
            () => surface.evaluate().isNotEmpty,
            'search open',
          );
          final query = find
              .descendant(of: surface, matching: find.byType(TextField))
              .first;
          await tester.enterText(query, 'RETENTION:ordinary');
          await _wait(
            tester,
            () =>
                tester.widget<RecordingSearchSurface>(surface).hasCriteria &&
                !tester.widget<RecordingSearchSurface>(surface).loading,
            'search settled',
          );
          final state = tester.widget<RecordingSearchSurface>(surface);
          expect(state.error, isNull);
          expect(state.warning, isNull);
          expect(state.results.isNotEmpty, present);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _wait(
            tester,
            () => surface.evaluate().isEmpty,
            'search closed',
          );
        }

        final paths = <String, String>{};
        for (final label in ['kept', 'ordinary', 'playing']) {
          paths[label] = (await start(label)).entry.path;
          await stop();
        }
        final active = await start('active');
        paths['active'] = active.entry.path;
        report['paths'] = paths;
        await openLibrary();
        await toggleKeep(paths['kept']!, true);
        await searchOrdinary(present: true);
        final selected = find.byKey(
          ValueKey('recording-entry-${paths['playing']}'),
        );
        await tester.ensureVisible(selected);
        await tester.pumpAndSettle();
        await tester.tap(selected);
        final player = find.byType(SampledReplaySurface);
        await _wait(
          tester,
          () =>
              player.evaluate().isNotEmpty &&
              !tester.widget<SampledReplaySurface>(player).loading,
          'reader open',
        );
        await openLibrary();
        final retention = find.byKey(const Key('recording-library-retention'));
        await tester.ensureVisible(retention);
        await tester.tap(retention);
        final form = find.byType(RecordingRetentionSurface);
        await _wait(
          tester,
          () =>
              form.evaluate().isNotEmpty &&
              !tester.widget<RecordingRetentionSurface>(form).loading,
          'retention ready',
        );
        await tester.enterText(
          find.byKey(const Key('recording-retention-days')),
          '14',
        );
        // One byte deliberately makes every real bundle exceed the test budget.
        await tester.enterText(
          find.byKey(const Key('recording-retention-capacity')),
          '${1 / (1024 * 1024 * 1024)}',
        );
        await tester.tap(find.byKey(const Key('recording-retention-save')));
        await _wait(
          tester,
          () => form.evaluate().isEmpty,
          'retention persisted',
        );
        final reloaded = SampledRecordingLibrary(
          files: api,
          directoryResolver: root,
        );
        final policy = await reloaded.loadRetentionPolicy();
        expect(policy.maximumAgeDays, 14);
        expect(policy.maximumBytes, 1);
        expect(await Directory(paths['ordinary']!).exists(), isFalse);
        expect(
          (await library.listRecordings()).map((e) => e.path),
          unorderedEquals([paths['kept'], paths['playing'], paths['active']]),
        );
        for (final name in ['kept', 'playing', 'active']) {
          expect(
            await Directory(paths[name]!).exists(),
            isTrue,
            reason: '$name protection',
          );
        }
        expect(
          client.status(active.handle).phase,
          terminal.SampledCapturePhase.capturing,
        );
        await searchOrdinary(present: false);
        await _capture(boundary, run, 'protected-library');
        report['ordinary_and_index_removed'] = true;
        report['kept_reader_active_protected'] = true;
        report['policy_reloaded'] = policy.toJson();
        await closeLibrary();
        // Closing the player releases its reader lease. Apply the same persisted
        // policy again through the actual dialog; this recording is now eligible.
        await tester.tap(
          find.descendant(of: player, matching: find.byTooltip('Close')),
        );
        await _wait(tester, () => player.evaluate().isEmpty, 'player closed');
        await openLibrary();
        await tester.ensureVisible(retention);
        await tester.tap(retention);
        await _wait(
          tester,
          () =>
              form.evaluate().isNotEmpty &&
              !tester.widget<RecordingRetentionSurface>(form).loading,
          'policy reopened',
        );
        await tester.tap(find.byKey(const Key('recording-retention-save')));
        await _wait(
          tester,
          () => form.evaluate().isEmpty,
          'cleanup after reader release',
        );
        expect(await Directory(paths['playing']!).exists(), isFalse);
        expect(await Directory(paths['kept']!).exists(), isTrue);
        expect(await Directory(paths['active']!).exists(), isTrue);
        await closeLibrary();
        await stop();
        await _action(tester, 'shell-toggle-session-recording');
        await _wait(
          tester,
          () =>
              scope
                  .read(sessionControllerProvider)
                  .lastError
                  ?.contains(
                    'Protected recordings occupy the storage budget',
                  ) ==
              true,
          'protected budget rejects new recording',
        );
        expect(
          scope.read(sessionControllerProvider).recordingSessionIds,
          isEmpty,
        );
        expect(library.activeClaims, isEmpty);
        expect(
          find.textContaining('Protected recordings occupy the storage budget'),
          findsWidgets,
        );
        await _capture(boundary, run, 'protected-budget');
        final viewport = find.byType(TerminalViewport).first;
        await tester.tap(viewport);
        await tester.pump();
        expect(
          tester.widget<TerminalViewport>(viewport).focusNode!.hasPrimaryFocus,
          isTrue,
        );
        tester.testTextInput.enterText('live');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _wait(
          tester,
          () => liveText().contains('RETENTION:live'),
          'terminal still usable',
        );
        await _dismissNotices(tester);
        await openLibrary();
        await toggleKeep(paths['kept']!, false);
        await tester.ensureVisible(retention);
        await tester.tap(retention);
        await _wait(
          tester,
          () =>
              form.evaluate().isNotEmpty &&
              !tester.widget<RecordingRetentionSurface>(form).loading,
          'final cleanup ready',
        );
        await tester.tap(find.byKey(const Key('recording-retention-save')));
        await _wait(
          tester,
          () => form.evaluate().isEmpty,
          'final cleanup finished',
        );
        expect(await library.listRecordings(), isEmpty);
        expect(await reloaded.storageBytes(), 0);
        expect(
          find.byKey(const Key('recording-library-empty')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        report['unkeep_then_cleanup'] = true;
        report['input_after_budget_rejection'] = true;
        report['passed'] = true;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        final shutdown = await scope
            .read(appShutdownCoordinatorProvider)
            .shutdown(bounded: false);
        report['safe_to_terminate'] = shutdown.safeToTerminate;
        scope.dispose();
        api.dispose();
        await File('${run.path}/result.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
          flush: true,
        );
        debugPrint('RECORDING_RETENTION_ACCEPTANCE=${run.path}');
        WidgetController.hitTestWarningShouldBeFatal = priorHitTestPolicy;
      }
    },
    skip: !Platform.isMacOS,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
