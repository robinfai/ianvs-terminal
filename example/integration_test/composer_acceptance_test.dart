import 'dart:io';

import 'package:app/app.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/macos_integration_test_lifecycle.dart';
import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_local_terminal_config_repository.dart';
import '../test/support/memory_profile_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Composer edits locally, accepts candidates, submits and recovers focus',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      final home = await Directory.systemTemp.createTemp('composer-ui-');
      await File('${home.path}/.zshrc').writeAsString(
        "PROMPT='composer> '\nRPROMPT=''\nHISTSIZE=100\nalias gc='git checkout'\n"
        'for i in {1..60}; do print -s -- "echo scroll-fixture-\$i"; done\n'
        "print -s -- 'printf history-example'\n",
      );
      await File('${home.path}/hello world.txt').writeAsString('fixture');
      await Directory(
        '${home.path}/documents/nested folder',
      ).create(recursive: true);
      await Directory(
        '${home.path}/pkg/application/handlers',
      ).create(recursive: true);
      await Directory('${home.path}/My files/中文目录').create(recursive: true);
      final profile = TerminalProfile(
        id: 'composer-test',
        name: 'Composer Test',
        shell: '/bin/zsh',
        cwd: home.path,
        env: {'HOME': home.path, 'ZDOTDIR': home.path, 'LANG': 'en_US.UTF-8'},
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(NativePtyBackend.load()),
          profileRepositoryProvider.overrideWithValue(
            MemoryProfileRepository(
              TerminalProfilesDocument(profiles: [profile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            MemoryAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            MemoryLocalTerminalConfigRepository(null),
          ),
          shellAnimationsEnabledProvider.overrideWithValue(false),
          shellNotificationSenderProvider.overrideWithValue(
            ({required title, body, identifier, expiresAfterMs}) async {},
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        final sessionId = container
            .read(sessionControllerProvider)
            .activeSessionId;
        if (sessionId != null) {
          await container
              .read(sessionControllerProvider.notifier)
              .closeSession(sessionId);
        }
        container.dispose();
        await home.delete(recursive: true);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const IanvsTerminalApp(),
        ),
      );
      await until(
        tester,
        () => container.read(sessionControllerProvider).activeSessionId != null,
      );
      final id = container.read(sessionControllerProvider).activeSessionId!;
      await until(
        tester,
        () => find.byKey(Key('composer-toggle-$id')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(Key('composer-toggle-$id')));
      await tester.pump();
      final editor = find.byKey(const Key('composer-editor'));
      await until(
        tester,
        () => find.byType(TerminalComposerView).evaluate().isNotEmpty,
      );
      final model = tester
          .widget<TerminalComposerView>(find.byType(TerminalComposerView))
          .controller;
      await until(tester, () => model.ownership == ComposerOwnership.ready);
      // History comes from this shell, before Composer has submitted anything.
      final initialLease = model.readyLease;
      await tester.enterText(editor, 'printf');
      await until(tester, () => model.inlineSuggestion == ' history-example');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(model.editor.text, 'printf history-example');
      expect(model.readyLease, initialLease);
      await tester.enterText(editor, 'history-example');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(model.historyItems, ['printf history-example']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(model.editor.text, 'history-example');
      await tester.enterText(editor, 'printf');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(model.editor.text, 'printf history-example');
      expect(model.readyLease, initialLease);
      await tester.enterText(editor, 'g');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await until(
        tester,
        () => model.items.any(
          (item) => item.kind == 'alias' && item.label == 'gc',
        ),
      );
      final alias = model.items.firstWhere((item) => item.label == 'gc');
      expect(alias.detail, 'git checkout');
      model.highlightCompletion(alias);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(model.editor.text, 'gc');
      expect(model.readyLease, initialLease);
      await tester.enterText(editor, 'git che --help');
      model.editor.selection = const TextSelection.collapsed(offset: 7);
      await until(tester, () => model.items.any((e) => e.label == 'checkout'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(model.editor.text, 'git checkout --help');
      expect(model.ownership, ComposerOwnership.ready);

      // Explicit Tab works with automatic local suggestions still disabled.
      final lease = model.readyLease;
      expect(model.localSuggestions, isFalse);
      await tester.enterText(editor, 'ls ./');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await until(tester, () => !model.loading && model.selectedIndex >= 0);
      expect(model.editor.text, 'ls ./');
      expect(model.items.any((e) => e.label == './documents/'), isTrue);
      expect(model.items.any((e) => e.label == './hello world.txt'), isTrue);
      while (model.items[model.selectedIndex].label != './documents/') {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(model.editor.text, 'ls ./documents/');
      // A unique nested directory inserts immediately, including safe quoting.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await until(tester, () => model.editor.text.contains('nested'));
      expect(model.editor.text, "ls './documents/nested folder/'");
      expect(model.localSuggestions, isFalse);
      expect(model.ownership, ComposerOwnership.ready);
      expect(model.readyLease, lease);

      model.toggleLocalSuggestions();
      await tester.enterText(editor, 'cat he');
      await until(
        tester,
        () => model.items.any((e) => e.label == 'hello world.txt'),
      );
      expect(model.items.first.source, 'local:files');
      model.toggleLocalSuggestions();
      await tester.enterText(editor, 'cd pkg/application/handlers');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await until(
        tester,
        () =>
            model.ownership == ComposerOwnership.ready &&
            model.editor.text.isEmpty &&
            model.cwd.endsWith('/pkg/application/handlers'),
      );
      final pathLease = model.readyLease;
      await tester.enterText(editor, 'cd ../../../');
      model.editor.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 12,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(model.status, 'completion_selection');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      // Integration-test key events do not pass through NSTextInputContext.
      // Deliver the native macOS selector as the platform would for this key.
      tester
          .state<EditableTextState>(
            find.descendant(of: editor, matching: find.byType(EditableText)),
          )
          .performSelector('moveRight:');
      expect(model.editor.selection, const TextSelection.collapsed(offset: 12));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await until(
        tester,
        () =>
            !model.loading &&
            model.items.any((item) => item.label == '../../../documents/'),
        diagnostics: () =>
            'text=${model.editor.text}; selection=${model.editor.selection}; status=${model.status}; owner=${model.ownership}; candidates=${model.items.map((i) => i.label).join(', ')}',
      );
      expect(model.items.every((item) => item.kind == 'directory'), isTrue);
      await tester.enterText(editor, 'cd ../../../docu');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await until(tester, () => model.editor.text == 'cd ../../../documents/');
      expect(model.readyLease, pathLease);
      await tester.enterText(editor, 'cd ${home.path}/docu');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await until(
        tester,
        () => model.editor.text == 'cd ${home.path}/documents/',
      );
      expect(model.readyLease, pathLease);
      await tester.enterText(editor, 'cd ~/My');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await until(tester, () => model.editor.text == "cd ~/'My files/'");
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await until(tester, () => model.editor.text == "cd ~/'My files/中文目录/'");
      expect(model.localSuggestions, isFalse);
      expect(model.readyLease, pathLease);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await until(
        tester,
        () =>
            model.ownership == ComposerOwnership.ready &&
            model.cwd.endsWith('/My files/中文目录'),
      );
      await tester.enterText(
        editor,
        "export COMPOSER_TEST=retained; print 'Composer 中文 😀'",
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await until(
        tester,
        () =>
            model.ownership == ComposerOwnership.ready &&
            model.editor.text.isEmpty,
      );
      String terminalText() => container
          .read(sessionControllerProvider.notifier)
          .viewportFor(id)
          .frame
          .rows
          .map((r) => r.text)
          .join('\n');
      await until(tester, () => terminalText().contains('Composer 中文 😀'));
      expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);
      await tester.enterText(editor, r'print COMPOSER_VALUE:$COMPOSER_TEST');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await until(
        tester,
        () => terminalText().contains('COMPOSER_VALUE:retained'),
      );
      await until(tester, () => model.ownership == ComposerOwnership.ready);
      await tester.enterText(editor, '');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(model.historyItems.length, greaterThan(50));
      final historyList = find.byKey(const Key('composer-history-list'));
      final historyScroll = tester.widget<ListView>(historyList).controller!;
      final historyPoint = tester.getCenter(historyList);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: historyPoint);
      await mouse.moveTo(historyPoint + const Offset(1, 0));
      await tester.pumpAndSettle();
      final historySelection = model.historySelectedIndex;
      final trackpad = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await trackpad.panZoomStart(historyPoint);
      await trackpad.panZoomUpdate(
        historyPoint,
        pan: const Offset(0, 40),
        timeStamp: const Duration(milliseconds: 16),
      );
      await tester.pump(const Duration(milliseconds: 16));
      var previousOffset = historyScroll.offset;
      for (var step = 1; step <= 3; step++) {
        await trackpad.panZoomUpdate(
          historyPoint,
          pan: Offset(0, 40.0 + 60 * step),
          timeStamp: Duration(milliseconds: 16 + 16 * step),
        );
        await tester.pump(const Duration(milliseconds: 16));
        expect(historyScroll.offset, lessThan(previousOffset - 40));
        previousOffset = historyScroll.offset;
      }
      expect(model.historySelectedIndex, historySelection);
      expect(model.editor.text, isEmpty);
      await trackpad.panZoomEnd(timeStamp: const Duration(milliseconds: 80));
      await mouse.removePointer();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        find
            .text(
              model.historyItems[model.historySelectedIndex],
              findRichText: true,
            )
            .hitTestable(),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.enterText(editor, 'saved draft');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(editor, findsNothing);
      await tester.tap(find.byKey(Key('composer-toggle-$id')));
      await tester.pump();
      expect(model.editor.text, 'saved draft');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !Platform.isMacOS,
  );
}

Future<void> until(
  WidgetTester tester,
  bool Function() ready, {
  String Function()? diagnostics,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Composer state did not settle: ${diagnostics?.call() ?? ''}');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}
