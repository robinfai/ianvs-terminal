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

import 'terminal_ai_recovery_test.dart' show RecoveringTerminal;
import 'terminal_ai_test.dart'
    show FakeApi, MemoryAiStore, commandReply, contextFor;

void main() {
  late AiSettingsController settings;
  late RecoveringTerminal terminal;
  late FakeApi api;
  late TerminalAiController controller;
  late ValueNotifier<bool> active;
  late TextEditingController neighbor;
  var observations = 0;

  setUp(() async {
    settings = AiSettingsController(MemoryAiStore());
    await settings.loaded;
    terminal = RecoveringTerminal();
    api = FakeApi()
      ..respond = (n) async => n == 1
          ? commandReply('printf "original target only"')
          : const AiReply(text: 'Observed original result');
    controller = TerminalAiController(
      settings: settings,
      terminal: terminal,
      api: api,
    );
    active = ValueNotifier(true);
    neighbor = TextEditingController();
    observations = 0;
    await controller.ask('Inspect the original target');
  });

  tearDown(() {
    controller.dispose();
    settings.dispose();
    active.dispose();
    neighbor.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    bool openReview = true,
    double paneWidth = 480,
    Size size = const Size(1100, 760),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildIanvsTerminalTheme(
          Brightness.light,
          platform: TargetPlatform.macOS,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: paneWidth,
                child: ValueListenableBuilder<bool>(
                  valueListenable: active,
                  builder: (_, value, _) => TerminalAiWorkspace(
                    controller: controller,
                    active: value,
                    onClose: () => observations++,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    TextButton(
                      key: const Key('select-neighbor'),
                      onPressed: () => active.value = false,
                      child: const Text('Select other pane'),
                    ),
                    TextField(
                      key: const Key('neighbor-editor'),
                      controller: neighbor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (openReview) {
      await tester.ensureVisible(find.byKey(const Key('ai-review-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-review-action')));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'desktop review remains in its pane while a neighbor stays editable',
    (tester) async {
      await mount(tester);
      final review = find.byKey(const Key('ai-desktop-review'));
      expect(tester.getRect(review).right, 480);
      expect(
        find.byKey(const Key('neighbor-editor')).hitTestable(),
        findsOneWidget,
      );
      final oldApprove = tester
          .widget<FilledButton>(find.byKey(const Key('ai-approve')))
          .onPressed!;
      await tester.tap(find.byKey(const Key('select-neighbor')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('neighbor-editor')),
        'Independent pane draft',
      );
      oldApprove();
      await tester.pump();
      expect(terminal.writes, isEmpty);
      expect(
        controller.canApprove,
        isTrue,
        reason: 'Only UI ownership changes; the proposal stays retained.',
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-approve')))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Select this pane'), findsOneWidget);

      final read = terminal.contextRead = Completer<AiTerminalContext>();
      active.value = true;
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-approve')))
            .onPressed,
        isNull,
      );
      oldApprove();
      expect(terminal.writes, isEmpty);
      terminal.contextRead = null;
      read.complete(terminal.context);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-approve')));
      await tester.pumpAndSettle();
      expect(terminal.writes.single.command, 'printf "original target only"');
      expect(neighbor.text, 'Independent pane draft');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reactivating a changed target never revives a captured approval',
    (tester) async {
      await mount(tester);
      final oldApprove = tester
          .widget<FilledButton>(find.byKey(const Key('ai-approve')))
          .onPressed!;
      active.value = false;
      await tester.pump();
      terminal.context = contextFor(guard: 'changed-while-away');
      active.value = true;
      await tester.pumpAndSettle();
      oldApprove();
      await tester.pump();
      expect(controller.pending, isNull);
      expect(terminal.writes, isEmpty);
      expect(find.textContaining('The proposal changed.'), findsOneWidget);
      expect(find.byKey(const Key('ai-approve')), findsNothing);
    },
  );

  testWidgets(
    'switching away during approval preflight cannot submit on return',
    (tester) async {
      await mount(tester);
      final proposal = controller.pending;
      final read = terminal.contextRead = Completer<AiTerminalContext>();
      await tester.tap(find.byKey(const Key('ai-approve')));
      await tester.pump();
      expect(controller.pending, same(proposal));
      active.value = false;
      await tester.pump();
      active.value = true;
      await tester.pump();
      terminal.contextRead = null;
      read.complete(terminal.context);
      await tester.pumpAndSettle();
      expect(controller.pending, same(proposal));
      expect(controller.canApprove, isTrue);
      expect(terminal.writes, isEmpty);
      expect(api.requests, hasLength(1));
      await tester.tap(find.byKey(const Key('ai-review-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-approve')));
      await tester.pumpAndSettle();
      expect(terminal.writes.single.command, 'printf "original target only"');
    },
  );

  testWidgets('switching away during resume preflight keeps the task paused', (
    tester,
  ) async {
    controller.takeOver();
    await mount(tester, openReview: false);
    final read = terminal.contextRead = Completer<AiTerminalContext>();
    await tester.tap(find.byKey(const Key('ai-resume')));
    await tester.pump();
    active.value = false;
    await tester.pump();
    active.value = true;
    await tester.pump();
    terminal.contextRead = null;
    read.complete(terminal.context);
    await tester.pumpAndSettle();
    expect(api.requests, hasLength(1));
    expect(controller.canResume, isTrue);
    expect(terminal.writes, isEmpty);
  });

  testWidgets('narrow desktop review at 2x keeps actions in its own pane', (
    tester,
  ) async {
    await mount(
      tester,
      paneWidth: 340,
      size: const Size(1000, 400),
      textScale: 2,
    );
    expect(
      tester.getRect(find.byKey(const Key('ai-desktop-review'))).right,
      340,
    );
    expect(find.byKey(const Key('ai-approve')).hitTestable(), findsOneWidget);
    expect(
      find.byKey(const Key('neighbor-editor')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes desktop review before observing the terminal', (
    tester,
  ) async {
    await mount(tester);
    final pending = controller.pending;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-desktop-review')), findsNothing);
    expect(controller.pending, same(pending));
    expect(observations, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(observations, 1);
    expect(terminal.writes, isEmpty);
  });
}
