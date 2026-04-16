import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/ffi/flutterm_core.dart';

import 'support/fake_core_bindings.dart';
import 'support/memory_profile_repository.dart';

void main() {
  testWidgets('shell screen can open tabs from profiles', (tester) async {
    final fakeBindings = FakeCoreBindings();
    final repository = MemoryProfileRepository(
      TerminalProfilesDocument(
        defaultProfileId: 'default',
        profiles: [defaultTerminalProfile()],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          terminalCoreClientProvider.overrideWithValue(
            TerminalCoreClient(fakeBindings),
          ),
          profileRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ShellScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Local Shell'), findsWidgets);
    await tester.tap(find.text('Local Shell').first);
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsWidgets);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets(
    'shell screen Paste button sends clipboard text to the active session',
    (tester) async {
      const clipboardText = '你好, 世界🌟';
      final fakeBindings = FakeCoreBindings();
      final repository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultTerminalProfile()],
        ),
      );

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': clipboardText};
          }
          if (methodCall.method == 'Clipboard.setData') {
            return null;
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

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            terminalCoreClientProvider.overrideWithValue(
              TerminalCoreClient(fakeBindings),
            ),
            profileRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: ShellScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Paste'), findsOneWidget);
      expect(fakeBindings.writes, isEmpty);

      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();

      expect(fakeBindings.writes, isNotEmpty);
      expect(fakeBindings.writes.last, utf8.encode(clipboardText));
    },
  );

  testWidgets(
    'shell screen Copy button writes the selected text to the clipboard',
    (tester) async {
      final fakeBindings = FakeCoreBindings();
      final repository = MemoryProfileRepository(
        TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultTerminalProfile()],
        ),
      );
      String? copiedText;

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': copiedText};
          }
          if (methodCall.method == 'Clipboard.setData') {
            copiedText = (methodCall.arguments as Map)['text'] as String?;
            return null;
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

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            terminalCoreClientProvider.overrideWithValue(
              TerminalCoreClient(fakeBindings),
            ),
            profileRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: ShellScreen()),
        ),
      );

      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.byType(TerminalViewport), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(copiedText, isNull);

      final viewportTopLeft = tester.getTopLeft(find.byType(TerminalViewport));
      final selectionStart = viewportTopLeft + const Offset(1, 9);
      await tester.dragFrom(selectionStart, const Offset(300, 0));
      await tester.pump();

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copiedText, 'flutterm ready');
      expect(fakeBindings.writes, isEmpty);
    },
  );
}
