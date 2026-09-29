import 'dart:io';

import 'package:app/app.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
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
      await File(
        '${home.path}/.zshrc',
      ).writeAsString("PROMPT='composer> '\nRPROMPT=''\n");
      await File('${home.path}/hello world.txt').writeAsString('fixture');
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
      await tester.enterText(editor, 'git che --help');
      model.editor.selection = const TextSelection.collapsed(offset: 7);
      await until(tester, () => model.items.any((e) => e.label == 'checkout'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(model.editor.text, 'git checkout --help');
      expect(model.ownership, ComposerOwnership.ready);
      model.toggleLocalSuggestions();
      await tester.enterText(editor, 'cat he');
      await until(
        tester,
        () => model.items.any((e) => e.label == 'hello world.txt'),
      );
      expect(model.items.first.source, 'local:files');
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

Future<void> until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('Composer state did not settle');
    await tester.pump(const Duration(milliseconds: 50));
  }
}
