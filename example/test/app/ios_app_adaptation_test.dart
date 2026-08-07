import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/app.dart';
import 'package:app/features/pty/pty.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_ports.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/main.dart';

import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';

void main() {
  test('iOS selects the on-device sandbox shell', () {
    expect(usesIosSandboxShell(TargetPlatform.iOS), isTrue);
    expect(usesIosSandboxShell(TargetPlatform.macOS), isFalse);
    expect(usesIosSandboxShell(TargetPlatform.android), isFalse);
  });

  testWidgets(
    'iPhone shell accepts keyboard input and exposes responsive terminal keys',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('ianvs-ios-widget-');
      addTearDown(() {
        if (root.existsSync()) {
          root.deleteSync(recursive: true);
        }
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ptySessionBackendProvider.overrideWithValue(
              IosSandboxShellBackend(rootDirectory: root),
            ),
            profileRepositoryProvider.overrideWithValue(
              MemoryProfileRepository(
                TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
              ),
            ),
            pasteHistoryRepositoryProvider.overrideWithValue(
              MemoryPasteHistoryRepository(),
            ),
            appPreferencesRepositoryProvider.overrideWithValue(
              MemoryAppPreferencesRepository(null),
            ),
            localTerminalConfigRepositoryProvider.overrideWithValue(
              MemoryLocalTerminalConfigRepository(null),
            ),
            sessionPollingEnabledProvider.overrideWithValue(false),
            sessionDemoFixtureProvider.overrideWithValue(null),
          ],
          child: const IanvsTerminalApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shell-chrome-bar')), findsOneWidget);
      expect(find.byKey(const Key('ios-sandbox-shell-notice')), findsOneWidget);
      expect(find.byType(TerminalViewport), findsOneWidget);
      expect(find.byKey(const Key('ios-terminal-input-bar')), findsOneWidget);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      tester.testTextInput.hide();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      expect(
        tester.getSize(find.byKey(const Key('shell-chrome-bar'))).height,
        96,
      );
      expect(
        tester.getSize(find.byKey(const Key('ios-terminal-key-Escape'))).height,
        greaterThanOrEqualTo(44),
      );
      expect(
        tester.getSize(find.byKey(const Key('ios-terminal-key-Escape'))).width,
        greaterThanOrEqualTo(44),
      );

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'echo hello-ios',
          selection: TextSelection.collapsed(offset: 14),
        ),
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pump(const Duration(milliseconds: 80));

      var viewport = tester.widget<TerminalViewport>(
        find.byType(TerminalViewport),
      );
      expect(
        viewport.controller.frame.rows.map((row) => row.text).join('\n'),
        contains('hello-ios'),
      );

      final dollarKey = find.byKey(const Key('ios-terminal-key-Dollar sign'));
      await tester.scrollUntilVisible(
        dollarKey,
        240,
        scrollable: find.descendant(
          of: find.byKey(const Key('ios-terminal-character-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(dollarKey);
      await tester.pump(const Duration(milliseconds: 40));
      viewport = tester.widget<TerminalViewport>(find.byType(TerminalViewport));
      expect(
        viewport.controller.frame.rows.any((row) => row.text.endsWith(r'$')),
        isTrue,
      );

      final initialFontSize = viewport.font.size;
      final center = tester.getCenter(find.byType(TerminalViewport));
      final first = await tester.startGesture(
        center - const Offset(18, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(18, 0),
        pointer: 2,
      );
      await tester.pump();
      await first.moveTo(center - const Offset(70, 0));
      await second.moveTo(center + const Offset(70, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pump();

      viewport = tester.widget<TerminalViewport>(find.byType(TerminalViewport));
      expect(viewport.font.size, greaterThan(initialFontSize));

      await tester.tap(find.byKey(const Key('ios-terminal-font-reset')));
      await tester.pump();
      viewport = tester.widget<TerminalViewport>(find.byType(TerminalViewport));
      expect(viewport.font.size, closeTo(initialFontSize, 0.01));

      tester.view.physicalSize = const Size(375, 667);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ios-terminal-input-bar')), findsOneWidget);

      tester.view.physicalSize = const Size(667, 375);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(TerminalViewport)).height,
        greaterThan(80),
      );

      debugDefaultTargetPlatformOverride = null;
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    },
  );
}
