import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/app.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal_composer/terminal_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_local_terminal_config_repository.dart';
import '../test/support/memory_paste_history_repository.dart';
import '../test/support/memory_profile_repository.dart';
import '../test/support/no_io_local_session_recording_repository.dart';
import '../test/support/no_io_local_terminal_layout_repository.dart';
import 'composer_acceptance_test.dart' show until;

/// Install in place under the existing app identity. Reuse its saved Cloud
/// profile on device, then keep all test sessions and settings in memory.
/// Credentials never leave the phone and are never included in evidence.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory documents;
  late Directory evidence;
  setUpAll(() async {
    documents = await getApplicationDocumentsDirectory();
    evidence = Directory('${documents.path}/mobile-blocks-acceptance');
    await evidence.create(recursive: true);
  });
  final observations = <String, Object?>{};
  final previousReporter = reportTestException;
  reportTestException = (details, description) {
    observations['failure'] = details.exceptionAsString();
    observations['stack'] = details.stack?.toString();
    previousReporter(details, description);
  };
  Future<void> report(String stage) {
    if (stage != 'failed' && stage != 'passed') {
      observations['lastStage'] = stage;
    }
    return File(
      '${evidence.path}/results.json',
    ).writeAsString(jsonEncode({'stage': stage, ...observations}));
  }

  tearDownAll(() async {
    observations['results'] = {
      for (final entry in binding.results.entries)
        entry.key: entry.value.toString(),
    };
    await report(binding.failureMethodsDetails.isEmpty ? 'passed' : 'failed');
  });
  testWidgets(
    'physical iPhone SSH command block reading',
    (tester) async {
      await report('connecting');
      final support = await getApplicationSupportDirectory();
      expect(
        await File('${support.path}/ianvs_profiles.json').exists(),
        isTrue,
        reason: 'The existing app must have a saved Cloud profile.',
      );
      final saved = await ProfileRepository().load();
      await report('profiles-loaded');
      final profile = saved.profiles
          .where((profile) => profile.name.toLowerCase().contains('cloud'))
          .firstOrNull;
      expect(
        profile,
        isNotNull,
        reason: 'No saved Cloud profile on this iPhone.',
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(NativePtyBackend.load()),
          profileRepositoryProvider.overrideWithValue(
            MemoryProfileRepository(
              TerminalProfilesDocument(profiles: [profile!]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            MemoryAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            MemoryLocalTerminalConfigRepository(null),
          ),
          pasteHistoryRepositoryProvider.overrideWithValue(
            MemoryPasteHistoryRepository(),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            noIoLocalTerminalLayoutRepository(),
          ),
          localSessionRecordingRepositoryProvider.overrideWithValue(
            noIoLocalSessionRecordingRepository(),
          ),
          shellAnimationsEnabledProvider.overrideWithValue(false),
          shellNotificationSenderProvider.overrideWithValue(
            ({required title, body, identifier, expiresAfterMs}) async {},
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final tab in container.read(sessionControllerProvider).tabs) {
          for (final pane in tab.effectivePanes) {
            await container
                .read(sessionControllerProvider.notifier)
                .closeSession(pane.sessionId);
          }
        }
        container.dispose();
      });
      final captureKey = GlobalKey();
      Future<void> capture(String name) async {
        await tester.pump();
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${evidence.path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: captureKey,
            child: const IanvsTerminalApp(),
          ),
        ),
      );
      await report('app-mounted');
      await until(
        tester,
        () => container.read(sessionControllerProvider).profiles.isNotEmpty,
      );
      if (container.read(sessionControllerProvider).activeSessionId == null) {
        container
            .read(sessionControllerProvider.notifier)
            .createSession(profile);
      }
      await report('session-started');
      await until(
        tester,
        () => find.byType(TerminalCommandBlocksView).evaluate().isNotEmpty,
        diagnostics: () => container
            .read(sessionControllerProvider)
            .tabs
            .map((tab) => tab.activePane.terminalMode.unavailableReason)
            .join(', '),
      );
      final blocks = tester
          .widget<TerminalCommandBlocksView>(
            find.byType(TerminalCommandBlocksView),
          )
          .controller;
      final composer = tester
          .widget<TerminalComposerView>(find.byType(TerminalComposerView))
          .controller;
      final sessions = container.read(sessionControllerProvider.notifier);
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      TerminalModeState mode() => container
          .read(sessionControllerProvider)
          .tabs
          .first
          .activePane
          .terminalMode;
      String terminalText() => sessions
          .viewportFor(sessionId)
          .frame
          .rows
          .map((row) => row.text)
          .join('\n');
      final editor = find.byKey(const Key('composer-editor'));
      Future<void> enter(String text) async {
        await tester.tap(editor);
        await tester.pump(const Duration(milliseconds: 600));
        // TestTextInput uses client -1, which is accepted only in debug builds.
        // Exercise the real EditableText input client in signed Release too.
        tester
            .state<EditableTextState>(
              find.descendant(of: editor, matching: find.byType(EditableText)),
            )
            .updateEditingValue(
              TextEditingValue(
                text: text,
                selection: TextSelection.collapsed(offset: text.length),
              ),
            );
        await tester.pump(const Duration(milliseconds: 300));
        expect(composer.editor.text, text);
        composer.dismissCompletions();
        await tester.pump();
      }

      Future<void> run(String command, {bool expectBlock = true}) async {
        await until(
          tester,
          () => composer.ownership == ComposerOwnership.ready,
        );
        final previousCount = blocks.blocks.length;
        await enter(command);
        final action = find.byKey(const Key('composer-primary-action'));
        await tester.ensureVisible(action);
        await tester.tap(action);
        await until(
          tester,
          () =>
              blocks.blocks.length > previousCount ||
              !expectBlock &&
                  mode().unavailableReason == BlockUnavailableReason.fullScreen,
          diagnostics: () =>
              'command=$command, state=${composer.ownership}, '
              'blocks=${blocks.blocks.length}, mode=${mode().mode}',
        );
      }

      await report('connected');

      Future<void> openReader(String id) async {
        final action = find.byKey(ValueKey('block-expand-$id'));
        await tester.ensureVisible(action);
        await tester.pump(const Duration(milliseconds: 400));
        expect(action.hitTestable(), findsOneWidget);
        await tester.tap(action);
        await until(
          tester,
          () => find
              .byKey(const Key('block-reader-scroll'))
              .evaluate()
              .isNotEmpty,
        );
        await until(tester, () => tester.view.viewInsets.bottom == 0);
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> closeReader() async {
        await tester.tap(find.byKey(const Key('block-reader-close')));
        await until(
          tester,
          () => find.byKey(const Key('block-reader')).evaluate().isEmpty,
        );
        await until(tester, () => tester.view.viewInsets.bottom == 0);
        await tester.pump(const Duration(milliseconds: 400));
      }

      for (var i = 1; i <= 2; i++) {
        await run('ls');
        await until(
          tester,
          () =>
              blocks.blocks
                  .where(
                    (b) => b.command == 'ls' && !b.running && b.exitCode == 0,
                  )
                  .length ==
              i,
        );
      }
      observations['consecutiveLsBlocks'] = 2;
      await report('consecutive-ls');
      const command =
          r'''i=1; while [ "$i" -le 240 ]; do printf 'Trail scroll %03d\n' "$i"; i=$((i+1)); done''';
      await run(command);
      await until(
        tester,
        () =>
            blocks.blocks.last.command == command &&
            !blocks.blocks.last.running,
      );
      final id = blocks.blocks.last.id;
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tester.pumpAndSettle();
      await capture('list-preview');
      final card = find.byKey(ValueKey('command-block-$id'));
      final previewHeight = tester.getSize(card).height;
      observations['screen'] = {
        'width': tester.view.physicalSize.width / tester.view.devicePixelRatio,
        'height':
            tester.view.physicalSize.height / tester.view.devicePixelRatio,
        'os': Platform.operatingSystemVersion,
      };
      await enter('echo reader draft');
      final keyboardInset =
          tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
      expect(keyboardInset, greaterThan(0));
      expect(tester.getSize(card).height, closeTo(previewHeight, .1));
      observations['previewHeight'] = previewHeight;
      observations['keyboardInset'] = keyboardInset;
      await capture('keyboard-preview');
      await openReader(id);
      expect(tester.view.viewInsets.bottom, 0);
      expect(composer.editor.text, 'echo reader draft');
      await capture('expanded-before-scroll');
      final scrollFinder = find.byKey(const Key('block-reader-scroll'));
      final list = tester.widget<ListView>(scrollFinder);
      final scroll = list.controller!;
      final offsets = <double>[scroll.offset];
      for (var index = 0; index < 8; index++) {
        final rect = tester.getRect(scrollFinder);
        await tester.timedDragFrom(
          Offset(rect.center.dx, rect.top + rect.height * .75),
          Offset(0, -rect.height * .45),
          const Duration(milliseconds: 420),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(scroll.offset, greaterThanOrEqualTo(offsets.last - .1));
        offsets.add(scroll.offset);
      }
      observations['forwardOffsets'] = offsets;
      await capture('expanded-after-scroll');
      await report('scrolled');
      expect(offsets.last, greaterThan(offsets.first + 2000));
      expect(find.byKey(ValueKey('$id-reader-1')), findsOneWidget);
      await until(tester, () => !scroll.position.isScrollingNotifier.value);
      final retained = scroll.offset;
      await tester.pump(const Duration(milliseconds: 500));
      expect(scroll.offset, closeTo(retained, 1));
      await closeReader();
      expect(composer.editor.text, 'echo reader draft');
      expect(tester.view.viewInsets.bottom, 0);
      await capture('reader-returned-to-list');
      await report('reader-closed');
      await openReader(id);
      expect(
        tester.widget<ListView>(scrollFinder).controller!.offset,
        closeTo(retained, 1),
      );
      await closeReader();
      observations['restoredReaderOffset'] = retained;
      await report('reading-position-restored');

      const streamCommand =
          r'''i=1; while [ "$i" -le 200 ]; do printf 'Trail live %03d\n' "$i"; i=$((i+1)); sleep 0.05; done''';
      await run(streamCommand);
      await until(tester, () => blocks.blocks.last.totalLines >= 60);
      final liveId = blocks.blocks.last.id;
      await openReader(liveId);
      final liveScroll = tester.widget<ListView>(scrollFinder).controller!;
      final liveRect = tester.getRect(scrollFinder);
      await tester.timedDragFrom(
        liveRect.center,
        const Offset(0, 180),
        const Duration(milliseconds: 450),
      );
      await tester.pump(const Duration(milliseconds: 800));
      await until(tester, () => !liveScroll.position.isScrollingNotifier.value);
      final pausedAt = liveScroll.offset;
      final linesBefore = blocks.blocks.last.totalLines;
      await tester.pump(const Duration(milliseconds: 1200));
      expect(blocks.blocks.last.totalLines, greaterThan(linesBefore));
      expect(liveScroll.offset, closeTo(pausedAt, 1));
      observations['livePausedOffset'] = pausedAt;
      await capture('live-reading-paused');
      await tester.tap(find.byKey(const Key('block-reader-latest')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(liveScroll.position.extentAfter, lessThan(1));
      await until(tester, () => !blocks.blocks.last.running);
      await closeReader();
      await report('live-output-follow-verified');

      Future<void> choose(TerminalViewMode selection) async {
        await tester.tap(find.byKey(const Key('shell-chrome-menu')));
        await tester.pumpAndSettle();
        final item = find.byKey(
          Key('terminal-mode-${selection.name}-$sessionId'),
        );
        await tester.ensureVisible(item);
        await tester.tap(item);
        await tester.pumpAndSettle();
      }

      Future<void> hideTerminalKeyboard() async {
        await tester.pump(const Duration(milliseconds: 400));
        final dismiss = find.byKey(const Key('ios-terminal-dismiss-keyboard'));
        if (dismiss.hitTestable().evaluate().isNotEmpty) {
          await tester.tap(dismiss);
        } else {
          FocusManager.instance.primaryFocus?.unfocus();
          await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        }
        await until(tester, () => tester.view.viewInsets.bottom == 0);
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> verifyGrid(String label, Size size) async {
        final terminal = tester.widget<TerminalViewport>(
          find.byType(TerminalViewport),
        );
        final cell = terminal.controller.measuredCellSize!;
        final rows =
            ((size.height - terminal.contentPadding.vertical) / cell.height)
                .floor();
        final cols =
            ((size.width - terminal.contentPadding.horizontal) / cell.width)
                .floor();
        await until(
          tester,
          () {
            final frame = terminal.controller.frame;
            return frame.viewportRows == rows && frame.viewportCols == cols;
          },
          diagnostics: () =>
              'Expected grid $cols x $rows, got '
              '${terminal.controller.frame.viewportCols} x ${terminal.controller.frame.viewportRows}',
        );
        observations['${label}Grid'] = [cols, rows];
      }

      await choose(TerminalViewMode.normal);
      await hideTerminalKeyboard();
      final fullSize = tester.getSize(find.byType(TerminalViewport));
      observations['normalTerminalSize'] = [fullSize.width, fullSize.height];
      await verifyGrid('normal', fullSize);
      await capture('normal-terminal');
      await choose(TerminalViewMode.blocks);
      for (final program in [
        (name: 'top', command: 'top -d 1', ready: 'top -', quit: 'q'),
        (
          name: 'vim',
          command: 'vim -Nu NONE -i NONE -n',
          ready: 'VIM',
          quit: ':q!\r',
        ),
      ]) {
        await run(program.command, expectBlock: false);
        await until(
          tester,
          () =>
              mode().mode == TerminalViewMode.normal &&
              (program.name == 'vim'
                  ? sessions.viewportFor(sessionId).frame.modes.alternateScreen
                  : terminalText().contains(program.ready)),
          diagnostics: () =>
              'program=${program.name}, mode=${mode().mode}, '
              'reason=${mode().unavailableReason}',
        );
        await hideTerminalKeyboard();
        expect(find.byType(TerminalCommandBlocksView), findsNothing);
        expect(find.byType(TerminalComposerView), findsNothing);
        final actualSize = tester.getSize(find.byType(TerminalViewport));
        observations['${program.name}TerminalSize'] = [
          actualSize.width,
          actualSize.height,
        ];
        await verifyGrid(program.name, actualSize);
        final terminal = tester.widget<TerminalViewport>(
          find.byType(TerminalViewport),
        );
        if (program.name == 'vim') {
          terminal.inputController.sendText('iTRAIL_VIM_INPUT\x1b');
          await until(tester, () => terminalText().contains('TRAIL_VIM_INPUT'));
        }
        await capture('fullscreen-${program.name}');
        await report('${program.name}-fullscreen');
        expect(actualSize.width, closeTo(fullSize.width, .1));
        expect(actualSize.height, closeTo(fullSize.height, .1));
        terminal.inputController.sendText(program.quit);
        await until(tester, () => mode().canUseBlocks);
        expect(mode().mode, TerminalViewMode.normal);
        expect(mode().notice, TerminalModeNotice.blocksRestored);
        await choose(TerminalViewMode.blocks);
      }
      observations['fullscreenPrograms'] = ['top', 'vim'];
      await report('fullscreen-verified');
      expect(tester.takeException(), isNull);
    },
    skip: !Platform.isIOS,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
