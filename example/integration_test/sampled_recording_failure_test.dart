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

// Full product failure acceptance. Only this test's bounded APFS image is
// filled, and it is detached after application shutdown even when assertions fail.

String _hook(Map<String, Object?> value) {
  final hex = utf8
      .encode(jsonEncode(value))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return "printf '\\033Phook;$hex\\033\\\\'";
}

String _script() => [
  r"printf 'READY-FOR-DISK-FAILURE\n'",
  'while IFS= read -r token; do',
  'n=0',
  r'while [ "$n" -lt 128 ]; do',
  _hook({
    'hook': 'preexec',
    'command': 'filesystem-full-${'x' * 1024}',
    'context_id': 'root',
  }),
  'sleep 0.02',
  r'n=$((n + 1))',
  'done',
  r'''printf '\033[2J\033[HLIVE-AFTER-FAILURE:%s\n' "$token"''',
  'done',
].join('\n');

Future<void> _command(
  Directory output,
  String name,
  List<String> command,
) async {
  final result = await Process.run(command.first, command.sublist(1));
  await File(
    '${output.path}/$name.log',
  ).writeAsString('${result.stdout}\n${result.stderr}');
  if (result.exitCode != 0) {
    throw StateError('$name failed (${result.exitCode}): ${result.stderr}');
  }
}

Future<String> _attachVolume(
  Directory output,
  Directory mount,
  void Function(String) onDevice,
) async {
  final disk = await Process.run('/bin/df', ['-Pk', output.path]);
  expect(disk.exitCode, 0);
  final freeKiB = int.parse(
    disk.stdout
        .toString()
        .trim()
        .split('\n')
        .last
        .trim()
        .split(RegExp(r'\s+'))[3],
  );
  expect(freeKiB, greaterThan(2 * 1024 * 1024));
  await mount.create();
  final image = '${output.path}/fixture.dmg';
  await _command(output, 'create', [
    'hdiutil',
    'create',
    '-size',
    '128m',
    '-fs',
    'APFS',
    '-volname',
    'IANVS-App-Failure',
    '-type',
    'UDIF',
    '-nospotlight',
    image,
  ]);
  final attached = await Process.run('hdiutil', [
    'attach',
    '-nobrowse',
    '-mountpoint',
    mount.path,
    '-plist',
    image,
  ]);
  if (attached.exitCode != 0) {
    throw StateError('attach failed: ${attached.stderr}');
  }
  final plist = File('${output.path}/attachment.plist');
  await plist.writeAsString(attached.stdout.toString());
  final converted = '${output.path}/attachment.json';
  await _command(output, 'attachment-conversion', [
    '/usr/bin/plutil',
    '-convert',
    'json',
    '-o',
    converted,
    plist.path,
  ]);
  final data = jsonDecode(await File(converted).readAsString()) as Map;
  final entities = data['system-entities'] as List;
  expect(
    entities.where((e) => (e as Map)['mount-point'] == mount.path),
    hasLength(1),
  );
  final device =
      (entities.singleWhere(
                (entry) =>
                    (entry as Map)['content-hint'] == 'GUID_partition_scheme',
              )
              as Map)['dev-entry']
          as String;
  onDevice(device);
  expect(RegExp(r'^/dev/disk[0-9]+$').hasMatch(device), isTrue);
  return device;
}

Future<int> _fillVolume(File filler) async {
  final file = await filler.open(mode: FileMode.write);
  var written = 0;
  var sawFull = false;
  final block = Uint8List.fromList(
    List<int>.generate(1024 * 1024, (n) => n % 251),
  );
  try {
    for (final length in [block.length, 4096]) {
      while (written < 128 * 1024 * 1024) {
        try {
          await file.writeFrom(block, 0, length);
          written += length;
        } on FileSystemException catch (error) {
          if (error.osError?.errorCode != 28) rethrow;
          sawFull = true;
          break;
        }
      }
    }
    try {
      await file.flush();
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode != 28) rethrow;
    }
  } finally {
    await file.close();
  }
  expect(
    sawFull,
    isTrue,
    reason: 'The owned APFS filesystem must actually reach ENOSPC',
  );
  return written;
}

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
    'real APFS full is visible, stops capture and leaves the terminal usable',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      // Flutter's synthetic key event does not produce macOS's separate text
      // commit. Drive both framework inputs while retaining the real PTY.
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final previousHitTestPolicy =
          WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      const outputPath = String.fromEnvironment(
        'IANVS_RECORDING_FAILURE_OUTPUT',
      );
      final output = outputPath.isEmpty
          ? await Directory.systemTemp.createTemp('recording-app-failure-')
          : await Directory(outputPath).create(recursive: true);
      final run = await output.createTemp('run-');
      final mount = Directory('${run.path}/volume');
      String? device;
      ProviderContainer? container;
      terminal.NativeRecordingFileApi? api;
      final filler = File('${mount.path}/owned-filler.bin');
      final report = <String, Object?>{
        'passed': false,
        'os': Platform.operatingSystemVersion,
      };
      try {
        device = await _attachVolume(run, mount, (value) => device = value);
        api = terminal.NativeRecordingFileApi();
        final library = SampledRecordingLibrary(
          files: api,
          directoryResolver: () async =>
              Directory('${mount.path}/recordings-v2'),
        );
        final script = File('${run.path}/pty-fixture.sh');
        await script.writeAsString(_script());
        final profile = TerminalProfile(
          id: 'disk-full',
          name: 'Disk-full acceptance',
          shell: '/bin/sh',
          args: [script.path],
        );
        final scope = ProviderContainer(
          overrides: [
            ptySessionBackendProvider.overrideWithValue(
              NativePtyBackend.load(),
            ),
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
        container = scope;
        final boundary = GlobalKey();
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
          'application ready',
        );
        final controller = scope.read(sessionControllerProvider.notifier);
        await controller.setLanguageMode(TerminalLanguageMode.english);
        final runtime = scope.read(terminalRuntimeControllerProvider);
        final sessionId = scope
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
          () => liveText().contains('READY-FOR-DISK-FAILURE'),
          'live shell ready',
        );
        await _action(tester, 'shell-toggle-session-recording');
        await _wait(
          tester,
          () => scope
              .read(sessionControllerProvider)
              .recordingSessionIds
              .contains(sessionId),
          'recording active',
        );
        final claim = library.activeClaims.single;
        final client = scope.read(sampledRecordingCaptureClientProvider)!;
        await _wait(
          tester,
          () => client.status(claim.handle).committed.recordCount > 0,
          'initial frame durably committed',
        );
        final acknowledged = client.status(claim.handle).committed.recordCount;
        await _dismissNotices(tester);
        report['filler_bytes'] = await _fillVolume(filler);
        runtime.sendInput(
          sessionId,
          Uint8List.fromList(utf8.encode('fault\n')),
        );
        terminal.SampledCaptureStatus? failed;
        await _wait(tester, () {
          final status = client.status(claim.handle);
          report['last_native_phase'] = status.phase.name;
          report['last_native_error'] = status.error;
          report['written_records'] = status.written.recordCount;
          report['application_error'] = scope
              .read(sessionControllerProvider)
              .lastError;
          report['live_text'] = liveText();
          if (status.phase != terminal.SampledCapturePhase.failed) return false;
          failed = status;
          return status.settled;
        }, 'real native disk-full failure');
        expect(failed!.error, contains('os error 28'));
        report['native_error'] = failed!.error;
        await _wait(
          tester,
          () =>
              scope
                      .read(sessionControllerProvider)
                      .lastError
                      ?.contains('os error 28') ==
                  true &&
              scope
                  .read(sessionControllerProvider)
                  .recordingPendingSaveSessionIds
                  .contains(sessionId),
          'visible application failure and pending save',
        );
        final failure = scope.read(sessionControllerProvider).lastError!;
        expect(find.text(failure), findsWidgets);
        report['visible_error'] = failure;
        report['still_marked_recording'] = scope
            .read(sessionControllerProvider)
            .recordingSessionIds
            .contains(sessionId);
        await _capture(boundary, run, 'disk-full-visible');
        expect(
          scope.read(sessionControllerProvider).recordingSessionIds,
          isNot(contains(sessionId)),
          reason: 'A failed native writer must never remain shown as recording',
        );
        expect(
          scope.read(sessionControllerProvider).recordingPendingSaveSessionIds,
          contains(sessionId),
        );
        await tester.tap(find.byKey(const Key('shell-chrome-menu')));
        await tester.pumpAndSettle();
        final retry = find.byKey(const Key('shell-toggle-session-recording'));
        await tester.ensureVisible(retry);
        await tester.pumpAndSettle();
        expect(
          find
              .descendant(
                of: retry,
                matching: find.text('Retry saving recording'),
              )
              .hitTestable(),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _wait(
          tester,
          () => retry.evaluate().isEmpty,
          'recording menu closes with Escape',
        );
        final liveViewport = find.byType(TerminalViewport).first;
        await tester.tap(liveViewport);
        await tester.pump();
        expect(
          tester
              .widget<TerminalViewport>(liveViewport)
              .focusNode!
              .hasPrimaryFocus,
          isTrue,
        );
        expect(tester.testTextInput.hasAnyClients, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK, character: 'k');
        tester.testTextInput.enterText('k');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _wait(tester, () {
          report['live_text_after_keyboard'] = liveText();
          report['input_focus'] =
              FocusManager.instance.primaryFocus?.debugLabel;
          return liveText().contains('LIVE-AFTER-FAILURE:k');
        }, 'keyboard input remains live while disk is full');
        report['keyboard_after_failure'] = true;
        report['input_driver'] =
            'Flutter key events and platform text commit, real PTY';
        await filler.delete();
        await _wait(
          tester,
          () => library.activeClaims.isEmpty,
          'background settlement after space returns',
        );
        final entry = (await library.listRecordings()).single;
        expect(entry.state, 'interrupted');
        final opened = await library.openRecording(entry.path);
        try {
          expect(
            opened.recording.info.visualCount +
                opened.recording.info.semanticCount,
            greaterThanOrEqualTo(acknowledged),
          );
          final frame = (await opened.recording.seek(Duration.zero))!;
          expect(
            frame.frame.rows.any(
              (row) => row.text.contains('READY-FOR-DISK-FAILURE'),
            ),
            isTrue,
          );
          report['recovered_records'] =
              opened.recording.info.visualCount +
              opened.recording.info.semanticCount;
        } finally {
          await opened.close();
        }
        await _dismissNotices(tester);
        await _action(tester, 'shell-open-recording');
        final selected = find.byKey(ValueKey('recording-entry-${entry.path}'));
        await _wait(
          tester,
          () => selected.evaluate().isNotEmpty,
          'recovered entry in library',
        );
        await tester.ensureVisible(selected);
        await tester.tap(selected);
        final player = find.byType(SampledReplaySurface);
        await _wait(
          tester,
          () =>
              player.evaluate().isNotEmpty &&
              !tester.widget<SampledReplaySurface>(player).loading,
          'recovered prefix visible in replay',
        );
        expect(tester.widget<SampledReplaySurface>(player).interrupted, isTrue);
        expect(find.textContaining('Recording interrupted'), findsWidgets);
        await _capture(boundary, run, 'recovered-prefix');
        expect(scope.read(sessionControllerProvider).tabs, hasLength(1));
        expect(tester.takeException(), isNull);
        report['passed'] = true;
      } finally {
        if (await filler.exists()) await filler.delete();
        await tester.pumpWidget(const SizedBox.shrink());
        if (container != null) {
          final shutdown = await container
              .read(appShutdownCoordinatorProvider)
              .shutdown(bounded: false);
          report['safe_to_terminate'] = shutdown.safeToTerminate;
          container.dispose();
        }
        api?.dispose();
        final mountedDevice = device;
        if (mountedDevice != null) {
          await _command(run, 'detach', [
            'hdiutil',
            'detach',
            mountedDevice,
            '-force',
          ]);
        }
        await File('${run.path}/result.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
          flush: true,
        );
        debugPrint('RECORDING_FAILURE_ACCEPTANCE=${run.path}');
        WidgetController.hitTestWarningShouldBeFatal = previousHitTestPolicy;
      }
    },
    skip: !Platform.isMacOS,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
