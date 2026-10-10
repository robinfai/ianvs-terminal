import 'dart:async';
import 'dart:io';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_message.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';
import 'terminal_ai_test.dart'
    show FakeApi, FakeTerminal, MemoryAiStore, commandReply;

class _Terminal extends FakeTerminal implements AiSubmissionInspector {
  bool unavailable = false;
  bool unknown = false;
  int inspections = 0;

  @override
  Future<AiTerminalContext> readContext() async {
    if (unavailable) throw const AiFailure('session_unavailable');
    return super.readContext();
  }

  @override
  Future<Map<String, Object?>> execute(AiAction action,
      AiTerminalContext expected, AiCancellation cancellation) async {
    if (!unknown) return super.execute(action, expected, cancellation);
    cancellation.check();
    writes.add(action);
    throw const AiFailure('submission_unknown');
  }

  @override
  String? submissionFor(String actionId) => unknown ? 'receipt-1' : null;

  @override
  Future<Map<String, Object?>> inspectSubmission(String id) async {
    inspections++;
    return {'outcome': 'unknown', 'submission_id': id};
  }
}

void main() {
  late AiSettingsController settings;
  late TerminalAiController controller;
  late _Terminal terminal;
  late FakeApi api;
  late int observations;
  late int takeovers;
  late int reconnects;
  Completer<void>? reconnectGate;

  setUp(() async {
    settings = AiSettingsController(MemoryAiStore());
    await settings.loaded;
    terminal = _Terminal();
    api = FakeApi()..respond = (_) async => const AiReply(text: 'Read-only answer.');
    controller = TerminalAiController(settings: settings, terminal: terminal, api: api);
    await controller.refreshContext();
    observations = 0;
    takeovers = 0;
    reconnects = 0;
    reconnectGate = null;
  });

  tearDown(() {
    controller.dispose();
    settings.dispose();
  });

  Future<void> mount(WidgetTester tester, {
    Size size = const Size(390, 844),
    Brightness brightness = Brightness.dark,
    TargetPlatform platform = TargetPlatform.iOS,
    bool active = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpApp(
      TerminalAiWorkspace(
        compactMobile: true,
        active: active,
        controller: controller,
        targetLabel: 'dev@example.test',
        onClose: () => observations++,
        onObserveTerminal: () => observations++,
        onTakeOver: () {
          controller.takeOver();
          takeovers++;
        },
        onConfigureTerminal: () async {},
        onReconnect: () async {
          reconnects++;
          await reconnectGate?.future;
          terminal.unavailable = false;
          await controller.refreshContext();
        },
      ),
      platform: platform,
      brightness: brightness,
      locale: const Locale('zh'),
    );
    await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  }

  TextField field(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(const Key('ai-prompt')));
  FilledButton send(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('ai-send')));

  for (final width in [320.0, 375.0, 390.0, 430.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('empty reading composer $width $brightness is compact', (tester) async {
        await mount(tester, size: Size(width, 844), brightness: brightness);
        final composer = find.byKey(const Key('ai-mobile-composer'));
        expect(tester.getSize(composer).height, lessThanOrEqualTo(56));
        expect(find.byKey(const Key('ai-expand-draft')), findsNothing);
        expect(find.byKey(const Key('ai-show-latest')), findsNothing);
        expect(find.textContaining('dev@example.test'), findsNothing);
        expect(send(tester).onPressed, isNull);
        expect(api.requests, isEmpty);
        expect(terminal.writes, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('focus/draft/rotation retain the editing value and controller', (tester) async {
    await mount(tester);
    final original = field(tester).controller!;
    await tester.tap(find.byKey(const Key('ai-prompt')));
    await tester.pump();
    expect(find.byKey(const Key('ai-expand-draft')), findsOneWidget);
    const value = TextEditingValue(
      text: '保留草稿\n路径 /srv/应用 🧭',
      selection: TextSelection(baseOffset: 2, extentOffset: 5),
    );
    original.value = value;
    await tester.pump();
    expect(field(tester).maxLines, 4);
    field(tester).focusNode!.unfocus();
    await tester.pump();
    expect(field(tester).controller, same(original));
    expect(original.value, value);
    tester.view.physicalSize = const Size(844, 260);
    await tester.pumpAndSettle();
    expect(field(tester).controller, same(original));
    expect(original.value, value);
    expect(field(tester).maxLines, 1);
    expect(find.byKey(const Key('ai-expand-draft')), findsOneWidget);
    expect(api.requests, isEmpty);
    expect(terminal.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IME confirm and software Return do not submit', (tester) async {
    await mount(tester);
    await tester.showKeyboard(find.byKey(const Key('ai-prompt')));
    field(tester).controller!.value = const TextEditingValue(
      text: '分析拼音',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 2, end: 4),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.pump();
    expect(api.requests, isEmpty);
    expect(terminal.writes, isEmpty);
    expect(send(tester).onPressed, isNull);
  });

  testWidgets('offline drafts do not infer; recovery lives in the task strip', (tester) async {
    terminal.unavailable = true;
    await controller.refreshContext();
    await mount(tester);
    expect(find.byKey(const Key('ai-mobile-primary-reconnect')), findsOneWidget);
    expect(find.byKey(const Key('ai-terminal-settings')), findsNothing);
    expect(find.byKey(const Key('ai-terminal-error')), findsNothing);
    await tester.enterText(find.byKey(const Key('ai-prompt')), '保留断线草稿');
    await tester.pump();
    expect(send(tester).onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.draft, '保留断线草稿');
    expect(api.requests, isEmpty);
    expect(terminal.writes, isEmpty);
    await tester.tap(find.byKey(const Key('ai-mobile-recovery-details')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-mobile-details')), findsOneWidget);
    expect(find.byKey(const Key('ai-mobile-detail-ssh-settings')), findsOneWidget);
    expect(find.byKey(const Key('ai-terminal-error')), findsOneWidget);
    expect(api.requests, isEmpty);
    expect(terminal.writes, isEmpty);
  });

  testWidgets('reconnect is single-flight and never submits the retained draft', (tester) async {
    terminal.unavailable = true;
    await controller.refreshContext();
    controller.setDraft('连接恢复后也不要自动发送');
    reconnectGate = Completer<void>();
    await mount(tester);
    final button = find.byKey(const Key('ai-mobile-primary-reconnect'));
    final press = tester.widget<TextButton>(button).onPressed!;
    press();
    press(); // A stale callback is guarded too, not merely a disabled button.
    await tester.pump();
    expect(reconnects, 1);
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    reconnectGate!.complete();
    await tester.pumpAndSettle();
    expect(controller.draft, '连接恢复后也不要自动发送');
    expect(api.requests, isEmpty);
    expect(terminal.writes, isEmpty);
  });

  testWidgets('unknown receipt takes priority over reconnect and only saves supplements', (tester) async {
    terminal.unknown = true;
    api.respond = (_) async => commandReply('pwd');
    await controller.ask('Inspect the working directory');
    await controller.approve(revision: controller.proposalRevision);
    expect(controller.hasUnresolvedSubmission, isTrue);
    terminal.unavailable = true;
    await controller.refreshContext();
    final calls = api.requests.length;
    final writes = terminal.writes.length;
    await mount(tester);
    expect(find.byKey(const Key('ai-mobile-primary-check')), findsOneWidget);
    expect(find.byKey(const Key('ai-mobile-primary-reconnect')), findsNothing);
    await tester.enterText(find.byKey(const Key('ai-prompt')), '稍后解释原结果');
    await tester.pump();
    expect(find.text('仅暂存要求，不会发送或执行'), findsOneWidget);
    expect(send(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('ai-send')));
    await tester.pumpAndSettle();
    expect(api.requests.length, calls);
    expect(terminal.writes.length, writes);
    expect(controller.hasDeferredSupplement, isTrue);
    expect(controller.hasUnresolvedSubmission, isTrue);
  });

  testWidgets('old detail choices cannot affect a different task', (tester) async {
    terminal.unavailable = true;
    await controller.refreshContext();
    await mount(tester);
    await tester.tap(find.byKey(const Key('ai-mobile-recovery-details')));
    await tester.pumpAndSettle();
    final tile = tester.widget<ListTile>(find.byKey(const Key('ai-mobile-detail-reconnect')));
    final oldTap = tile.onTap!;
    controller.newTask();
    await tester.pump();
    oldTap();
    await tester.pumpAndSettle();
    expect(reconnects, 0);
    expect(takeovers, 0);
    expect(terminal.writes, isEmpty);
  });

  testWidgets('old primary callback cannot reconnect a replacement task', (tester) async {
    terminal.unavailable = true;
    await controller.refreshContext();
    await mount(tester);
    final oldPress = tester.widget<TextButton>(
        find.byKey(const Key('ai-mobile-primary-reconnect'))).onPressed!;
    controller.newTask();
    await controller.refreshContext();
    await tester.pump();
    oldPress();
    await tester.pumpAndSettle();
    expect(reconnects, 0);
    expect(api.requests, isEmpty);
    expect(terminal.writes, isEmpty);
  });

  testWidgets('read-only observation is not takeover', (tester) async {
    terminal.unavailable = true;
    await controller.refreshContext();
    await mount(tester);
    await tester.tap(find.byKey(const Key('ai-mobile-recovery-details')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-mobile-detail-observe')));
    await tester.pumpAndSettle();
    expect(observations, 1);
    expect(takeovers, 0);
    expect(terminal.writes, isEmpty);
  });

  testWidgets('pause copy does not claim a ready shell is still running', (tester) async {
    await controller.ask('Explain only');
    controller.takeOver();
    await mount(tester);
    final status = tester.widget<Text>(find.byKey(const Key('ai-task-status')));
    expect(status.data, 'AI 已暂停');
    expect(terminal.writes, isEmpty);
  });

  testWidgets('desktop remains on its existing presentation even with host opt-in', (tester) async {
    await mount(tester, platform: TargetPlatform.macOS, size: const Size(1000, 800));
    expect(find.byKey(const Key('ai-mobile-composer')), findsNothing);
    expect(find.byKey(const Key('ai-close')), findsOneWidget);
    expect(find.byKey(const Key('ai-expand-draft')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile inline code has no opaque background; fenced container remains', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpApp(const TerminalAiMessage(text: 'Use `pwd`.\n\n```sh\npwd\n```'),
        platform: TargetPlatform.iOS);
    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(markdown.styleSheet!.code!.backgroundColor!.a, 0);
    expect((markdown.styleSheet!.codeblockDecoration as BoxDecoration).color!.a, greaterThan(0));
    expect(markdown.data, 'Use `pwd`.\n\n```sh\npwd\n```');
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  test('production host opts in to compact phone navigation', () {
    final source = File('lib/features/shell/shell_screen_ai.dart').readAsStringSync();
    expect(source, contains('compactMobile: paneContext.usesMobileNavigation'));
  });
}
