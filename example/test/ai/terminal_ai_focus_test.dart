import 'dart:async';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'terminal_ai_test.dart'
    show FakeApi, FakeTerminal, MemoryAiStore, commandReply;

void main() {
  late AiSettingsController settings;
  late FakeTerminal terminal;
  late FakeApi api;
  late TerminalAiController controller;
  late Completer<AiReply> reply;

  Future<void> prepare() async {
    settings = AiSettingsController(MemoryAiStore());
    await settings.loaded;
    terminal = FakeTerminal();
    api = FakeApi();
    controller = TerminalAiController(
      settings: settings,
      terminal: terminal,
      api: api,
    );
    reply = Completer<AiReply>();
  }

  tearDown(() {
    controller.dispose();
    settings.dispose();
  });

  Future<void> mount(WidgetTester tester, {bool phone = false}) async {
    tester.view.physicalSize = phone
        ? const Size(390, 700)
        : const Size(960, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildIanvsTerminalTheme(
          Brightness.light,
          platform: phone ? TargetPlatform.iOS : TargetPlatform.macOS,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TerminalAiWorkspace(controller: controller, onClose: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FocusNode inputFocus(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(const Key('ai-prompt'))).focusNode!;

  bool controlHasFocus(WidgetTester tester, Key key) {
    final control = tester.element(find.byKey(key));
    var found = false;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
      found = e == control;
      return !found;
    });
    return found;
  }

  Future<void> focusControl(WidgetTester tester, Key key) async {
    for (var i = 0; i < 40 && !controlHasFocus(tester, key); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(controlHasFocus(tester, key), true);
  }

  Future<void> startApproval(WidgetTester tester, {bool phone = false}) async {
    api.respond = (_) async => commandReply('cat status.txt');
    await controller.ask('Inspect the status, analysis only.');
    await mount(tester, phone: phone);
    api.respond = (_) => reply.future;
    if (phone) {
      await tester.tap(find.byKey(const Key('ai-review-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-approve')));
    } else {
      await focusControl(tester, const Key('ai-approve'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.busy, true);
    expect(terminal.writes, hasLength(1));
  }

  Future<void> finish(WidgetTester tester, {int writes = 1}) async {
    reply.complete(
      const AiReply(text: 'The file was read. Service health is unverified.'),
    );
    await tester.pumpAndSettle();
    expect(controller.phase, AiPhase.idle);
    expect(terminal.writes, hasLength(writes));
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'approved desktop result restores input for a same-task follow-up',
    (tester) async {
      await prepare();
      await startApproval(tester);
      final task = controller.taskId;
      await finish(tester);
      expect(inputFocus(tester).hasFocus, true);
      tester.testTextInput.enterText('Explain the remaining uncertainty');
      await tester.pump();
      expect(controller.draft, 'Explain the remaining uncertainty');
      expect(controller.taskId, task);
      expect(api.requests, hasLength(2));
    },
  );

  testWidgets(
    'finished result preserves historical reading and keyboard owner',
    (tester) async {
      await prepare();
      api.respond = (_) async =>
          AiReply(text: 'Earlier evidence\n${'line\n' * 50}');
      await controller.ask('Read the earlier evidence');
      await startApproval(tester);
      final scroll =
          tester
                  .widget<CommandTimelineView>(find.byType(CommandTimelineView))
                  .controller
              as CommandTimelineScrollController;
      scroll.jumpTo(40);
      await tester.pump();
      final anchor = scroll.readingAnchor;
      final owner = FocusManager.instance.primaryFocus;
      expect(controller.followingOutput, false);
      await finish(tester);
      expect(inputFocus(tester).hasFocus, false);
      expect(FocusManager.instance.primaryFocus, same(owner));
      expect(scroll.readingAnchor?.itemId, anchor?.itemId);
      expect(scroll.offset, closeTo(40, 1));
    },
  );

  testWidgets('finished result preserves selected assistant text', (
    tester,
  ) async {
    await prepare();
    await startApproval(tester);
    await tester.tap(find.text('Proposed command', findRichText: true));
    await tester.pump();
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion).first,
    );
    region.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    final owner = FocusManager.instance.primaryFocus;
    await finish(tester);
    expect(inputFocus(tester).hasFocus, false);
    expect(FocusManager.instance.primaryFocus, same(owner));
    expect(
      region.contextMenuButtonItems.any(
        (item) => item.type == ContextMenuButtonType.copy,
      ),
      true,
    );
  });

  testWidgets('finished result never moves focus out of connection settings', (
    tester,
  ) async {
    await prepare();
    await startApproval(tester);
    await tester.tap(find.byKey(const Key('ai-open-settings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final editor = find
        .descendant(of: find.byType(Dialog), matching: find.byType(TextField))
        .first;
    await tester.tap(editor);
    await tester.pump();
    final owner = FocusManager.instance.primaryFocus;
    await finish(tester);
    expect(FocusManager.instance.primaryFocus, same(owner));
    expect(inputFocus(tester).hasFocus, false);
  });

  testWidgets(
    'phone result does not reopen the keyboard after command review',
    (tester) async {
      await prepare();
      await startApproval(tester, phone: true);
      expect(inputFocus(tester).hasFocus, false);
      await finish(tester);
      expect(inputFocus(tester).hasFocus, false);
      expect(tester.testTextInput.isVisible, false);
    },
  );

  testWidgets('desktop background completion does not take keyboard focus', (
    tester,
  ) async {
    await prepare();
    await startApproval(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    final owner = FocusManager.instance.primaryFocus;
    await finish(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(owner));
    expect(inputFocus(tester).hasFocus, false);
  });

  testWidgets('desktop keyboard send restores the input without a command', (
    tester,
  ) async {
    await prepare();
    await mount(tester);
    api.respond = (_) => reply.future;
    await tester.enterText(find.byKey(const Key('ai-prompt')), 'Explain this');
    await focusControl(tester, const Key('ai-send'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.busy, true);
    await finish(tester, writes: 0);
    expect(inputFocus(tester).hasFocus, true);
  });

  for (final phone in [false, true]) {
    testWidgets(
      'reply preserves an active draft and composition phone=$phone',
      (tester) async {
        await prepare();
        await startApproval(tester, phone: phone);
        await tester.tap(find.byKey(const Key('ai-prompt')));
        const editing = TextEditingValue(
          text: '检查证据',
          selection: TextSelection(baseOffset: 2, extentOffset: 4),
          composing: TextRange(start: 2, end: 4),
        );
        tester.testTextInput.updateEditingValue(editing);
        await tester.pump();
        await finish(tester);
        expect(inputFocus(tester).hasFocus, true);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('ai-prompt')))
              .controller!
              .value,
          editing,
        );
      },
    );
  }

  testWidgets('reply preserves keyboard traversal to another task control', (
    tester,
  ) async {
    await prepare();
    await startApproval(tester);
    await focusControl(tester, const Key('ai-open-settings'));
    final owner = FocusManager.instance.primaryFocus;
    await finish(tester);
    expect(FocusManager.instance.primaryFocus, same(owner));
    expect(inputFocus(tester).hasFocus, false);
  });

  testWidgets('late reply does not focus a different task', (tester) async {
    await prepare();
    await startApproval(tester);
    controller.newTask();
    controller.setDraft('New task draft');
    await tester.pump();
    final task = controller.taskId;
    final owner = FocusManager.instance.primaryFocus;
    await finish(tester);
    expect(controller.taskId, task);
    expect(controller.draft, 'New task draft');
    expect(controller.transcript, isEmpty);
    expect(FocusManager.instance.primaryFocus, same(owner));
    expect(inputFocus(tester).hasFocus, false);
  });
}
