import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/ai/ai_approval.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../design/configuration_capture_binding.dart';
import '../design/visual_capture_fonts.dart';
import 'ai_approval_test.dart' show ControlledReviewer;
import 'terminal_ai_recovery_test.dart' show RecoveringTerminal;
import 'terminal_ai_tasks_test.dart' show source;
import 'terminal_ai_test.dart'
    show FakeApi, FakeTerminal, MemoryAiStore, commandReply, contextFor;

const _evidence = String.fromEnvironment('AI_WORKSPACE_EVIDENCE_DIR');

Future<void> _capture(WidgetTester tester, String name) async {
  if (_evidence.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('workspace-capture')),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_evidence).create(recursive: true);
    await File(
      '$_evidence/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  ConfigurationCaptureBinding();
  if (_evidence.isNotEmpty) setUpAll(loadVisualCaptureFonts);
  late AiSettingsController settings;
  late FakeTerminal terminal;
  late FakeApi api;
  late TerminalAiController controller;
  Future<void> prepare({
    AiConfigurationStore? store,
    FakeTerminal? port,
    AiActionReviewer? reviewer,
  }) async {
    settings = AiSettingsController(store ?? MemoryAiStore());
    await settings.loaded;
    terminal = port ?? FakeTerminal();
    api = FakeApi();
    controller = TerminalAiController(
      settings: settings,
      terminal: terminal,
      api: api,
      reviewer: reviewer,
    );
  }

  tearDown(() {
    controller.dispose();
    settings.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(960, 700),
    double scale = 1,
    Brightness brightness = Brightness.light,
    bool highContrast = false,
    AiTimelineBuilder? timelineBuilder,
    VoidCallback? close,
    VoidCallback? observe,
    bool fullScreenTerminal = false,
    TargetPlatform? platform,
    Locale locale = const Locale('en'),
    ValueChanged<AiEvidenceReference>? onShowEvidence,
  }) async {
    tester.view.reset();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var theme = buildIanvsTerminalTheme(
      brightness,
      highContrast: highContrast,
      platform:
          platform ??
          (size.width < 600 ? TargetPlatform.iOS : TargetPlatform.macOS),
    );
    if (_evidence.isNotEmpty) theme = withVisualCaptureFonts(theme);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            highContrast: highContrast,
          ),
          child: RepaintBoundary(
            key: const Key('workspace-capture'),
            child: child,
          ),
        ),
        home: Scaffold(
          body: TerminalAiWorkspace(
            controller: controller,
            onClose: close ?? () {},
            onObserveTerminal: observe,
            timelineBuilder: timelineBuilder,
            fullScreenTerminal: fullScreenTerminal,
            onShowEvidence: onShowEvidence,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(320, 568), const Size(390, 520)]) {
    testWidgets('phone declines from timeline without entering review $size', (
      tester,
    ) async {
      await prepare();
      api.respond = (_) async => commandReply('ls -la');
      await controller.ask('List files');
      await mount(tester, size: size);
      final decline = find.byKey(const Key('ai-reject'));
      await tester.ensureVisible(decline);
      await tester.pumpAndSettle();
      await _capture(tester, 'phone-decline-${size.width.toInt()}');
      await tester.tap(decline);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-review-back')), findsNothing);
      expect(controller.pending, isNull);
      expect(terminal.writes, isEmpty);
      expect(
        controller.transcript.any((e) => e.state == AiEntryState.rejected),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final scene in [
    (
      name: 'desktop-light',
      size: const Size(1100, 900),
      dark: false,
      scale: 1.0,
    ),
    (name: 'desktop-dark', size: const Size(1100, 900), dark: true, scale: 1.0),
    (
      name: 'desktop-wide',
      size: const Size(1728, 1000),
      dark: false,
      scale: 1.0,
    ),
    (
      name: 'desktop-scaled',
      size: const Size(960, 850),
      dark: false,
      scale: 2.0,
    ),
    (name: 'phone-light', size: const Size(390, 720), dark: false, scale: 1.0),
    (
      name: 'phone-dark-small',
      size: const Size(320, 568),
      dark: true,
      scale: 1.0,
    ),
    (
      name: 'phone-landscape',
      size: const Size(680, 320),
      dark: false,
      scale: 1.0,
    ),
  ]) {
    testWidgets('conversation role distinction ${scene.name}', (tester) async {
      await prepare();
      api.respond = (n) async => AiReply(
        text: n == 1
            ? '我会先查看磁盘总体占用，再定位主要目录；只分析，不执行清理。\n\n容量统计只能说明空间分布，不能证明某个文件已经无用。'
            : '建议优先检查以下内容：\n\n- **旧日志**：先核对保留时间与业务要求。\n- **软件缓存**：确认可以重新下载后再制定清理方案。\n\n目前尚未执行清理，也没有修改文件。',
      );
      await mount(
        tester,
        size: scene.size,
        scale: scene.scale,
        brightness: scene.dark ? Brightness.dark : Brightness.light,
        locale: const Locale('zh'),
        platform: scene.name.startsWith('phone')
            ? TargetPlatform.iOS
            : TargetPlatform.macOS,
      );
      await controller.ask('分析磁盘占用，给出清理建议，先不执行清理。');
      await tester.pumpAndSettle();
      await _capture(tester, 'roles-${scene.name}-first');
      await controller.ask('哪些内容通常值得先检查？');
      await tester.pumpAndSettle();
      await _capture(tester, 'roles-${scene.name}-followup');
      expect(find.byIcon(Icons.auto_awesome_outlined), findsWidgets);
      // A short landscape viewport may contain only the latest reply. Inspect
      // the user turn by scrolling rather than requiring offscreen lazy rows.
      final bounds = tester.getRect(find.byType(CommandTimelineView));
      for (
        var attempt = 0;
        attempt < 4 && find.text('你').evaluate().isEmpty;
        attempt++
      ) {
        await tester.timedDragFrom(
          Offset(bounds.center.dx, bounds.top + 8),
          Offset(0, bounds.height - 16),
          const Duration(milliseconds: 300),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('你'), findsWidgets);
      await _capture(tester, 'roles-${scene.name}-history');
      expect(
        controller.transcript.where((e) => e.role == 'user'),
        hasLength(2),
      );
      expect(terminal.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets('manual approval explains how to enable smart review $locale', (
      tester,
    ) async {
      await prepare();
      await mount(tester, locale: locale);
      await controller.ask('Inspect disk usage');
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          locale.languageCode == 'zh'
              ? '当前为「每次确认」'
              : 'Confirm every command is selected.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ai-approve')).hitTestable(), findsOneWidget);
      expect(terminal.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final phone in [false, true]) {
    for (final brightness in Brightness.values) {
      testWidgets('smart review state and reason phone=$phone $brightness', (
        tester,
      ) async {
        final reviewer = ControlledReviewer();
        await prepare(
          store: MemoryAiStore(
            const AiConfiguration.mock(approvalMode: AiApprovalMode.smart),
          ),
          reviewer: reviewer,
        );
        await mount(
          tester,
          size: phone ? const Size(390, 520) : const Size(960, 700),
          brightness: brightness,
        );
        final asking = controller.ask('List files');
        await reviewer.started.future;
        await tester.pump();
        expect(find.text('Reviewing command safety…'), findsWidgets);
        expect(find.byKey(const Key('ai-approve')), findsNothing);
        expect(terminal.writes, isEmpty);
        await _capture(
          tester,
          'smart-reviewing-${phone ? 'phone' : 'desktop'}-${brightness.name}',
        );
        reviewer.result.complete(
          const AiApprovalReview(automatic: false, reason: 'Scope is unclear.'),
        );
        await asking;
        await tester.pumpAndSettle();
        expect(find.textContaining('Scope is unclear.'), findsOneWidget);
        expect(controller.canApprove, isTrue);
        await _capture(
          tester,
          'smart-review-${phone ? 'phone' : 'desktop'}-${brightness.name}',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('desktop header hover explains actions without invoking them', (
    tester,
  ) async {
    await prepare();
    await mount(tester);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    for (final (label, name) in [
      ('Session tasks', 'tasks'),
      ('New task', 'new'),
      ('AI connection', 'connection'),
      ('Take over terminal input', 'return'),
    ]) {
      await mouse.moveTo(tester.getCenter(find.byTooltip(label)));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text(label), findsOneWidget);
      await _capture(tester, 'desktop-tooltip-$name');
      await mouse.moveTo(const Offset(0, 300));
      await tester.pumpAndSettle();
    }
    await mouse.removePointer();
    expect(api.requests, isEmpty);
    expect(terminal.writes, isEmpty);
    expect(controller.tasks, hasLength(1));
  });

  testWidgets(
    'IME commit updates the visible intent without waiting or sending',
    (tester) async {
      await prepare();
      await controller.refreshContext();
      await mount(tester);
      await tester.enterText(find.byKey(const Key('ai-prompt')), 'ls');
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '为什么失败',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 0, end: 5),
        ),
      );
      await tester.pump();
      expect(find.text('Auto · Command'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(terminal.writes, isEmpty);
      expect(api.requests, isEmpty);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '为什么失败',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump();
      expect(find.text('Auto · AI'), findsOneWidget);
      expect(terminal.writes, isEmpty);
      expect(api.requests, isEmpty);
    },
  );

  for (final brightness in Brightness.values) {
    for (final phone in [false, true]) {
      testWidgets(
        'input intent routes commands and keeps manual override ${brightness.name} phone=$phone',
        (tester) async {
          await prepare(store: MemoryAiStore(null));
          await controller.refreshContext();
          await mount(
            tester,
            brightness: brightness,
            size: phone ? const Size(390, 480) : const Size(960, 700),
          );
          final input = find.byKey(const Key('ai-prompt'));
          await tester.enterText(input, 'ls -la');
          await tester.pump();
          expect(api.requests, isEmpty);
          expect(terminal.writes, isEmpty);
          expect(controller.inputIntentDecision().intent, InputIntent.command);
          await tester.pump(const Duration(milliseconds: 250));
          await _capture(
            tester,
            'intent-command-${brightness.name}-${phone ? 'phone' : 'desktop'}',
          );
          await tester.tap(find.byKey(const Key('ai-send')));
          await tester.pumpAndSettle();
          expect(terminal.writes.single.command, 'ls -la');
          expect(api.requests, isEmpty);
          expect(controller.draft, isEmpty);
          await tester.enterText(input, '解释这个命令为什么失败');
          await tester.pump();
          expect(controller.inputIntentDecision().intent, InputIntent.ai);
          await tester.pump(const Duration(milliseconds: 250));
          await _capture(
            tester,
            'intent-ai-${brightness.name}-${phone ? 'phone' : 'desktop'}',
          );
          await tester.tap(find.byKey(const Key('ai-input-intent')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byWidgetPredicate(
              (w) =>
                  w is CheckedPopupMenuItem<InputIntentChoice> &&
                  w.value == InputIntentChoice.command,
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(input, '帮我看一下');
          await tester.pump();
          expect(controller.inputIntentDecision().intent, InputIntent.command);
          await tester.enterText(input, '');
          await tester.pump();
          await tester.enterText(input, '请解释输出');
          await tester.pump();
          expect(controller.inputIntentDecision().intent, InputIntent.ai);
          expect(controller.inputIntentChoice, InputIntentChoice.automatic);
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final layout in [
      (name: 'desktop', size: const Size(1100, 800), scale: 1.0),
      (name: 'desktop-2x', size: const Size(1100, 900), scale: 2.0),
      (name: 'phone-fixed', size: const Size(390, 700), scale: 1.0),
    ]) {
      testWidgets(
        'high contrast and reduced motion ${layout.name} ${brightness.name}',
        (tester) async {
          tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(
                disableAnimations: true,
                highContrast: true,
              );
          addTearDown(
            tester
                .binding
                .platformDispatcher
                .clearAccessibilityFeaturesTestValue,
          );
          await prepare();
          controller.attachContext(source);
          api.respond = (_) async =>
              commandReply(r'printf "review before execution\n"');
          await controller.ask('Inspect the existing output');
          controller.attachContext(source);
          controller.setDraft('Keep this draft');
          await mount(
            tester,
            size: layout.size,
            scale: layout.scale,
            brightness: brightness,
            highContrast: true,
          );
          final name = 'a11y-${layout.name}-${brightness.name}';
          await _capture(tester, '$name-proposal');
          final chip = find.byWidgetPredicate(
            (w) => w is InputChip && w.onDeleted != null,
          );
          await tester.tap(chip);
          await tester.pump();
          expect(
            ModalRoute.of(
              tester.element(find.byType(AlertDialog)),
            )!.animation!.isCompleted,
            true,
          );
          await tester.pumpAndSettle();
          expect(find.text('Attached output snapshot'), findsOneWidget);
          await _capture(tester, '$name-snapshot');
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          if (layout.name == 'phone-fixed') {
            await tester.tap(find.byKey(const Key('ai-review-action')));
            await tester.pump();
            await tester.pump();
            final action = find.byKey(const Key('ai-approve'));
            expect(action.hitTestable(), findsOneWidget);
            final origin = tester.getRect(action);
            await tester.pump(const Duration(milliseconds: 1));
            expect(tester.getRect(action), origin);
            await tester.pumpAndSettle();
            await _capture(tester, '$name-review');
            await tester.tap(find.byKey(const Key('ai-review-back')));
            await tester.pumpAndSettle();
          } else {
            await tester.tap(find.byKey(const Key('ai-edit-action')));
            await tester.pump();
            expect(
              ModalRoute.of(
                tester.element(find.byType(AlertDialog)),
              )!.animation!.isCompleted,
              true,
            );
            await tester.pumpAndSettle();
            await _capture(tester, '$name-edit');
            await tester.tap(find.text('Cancel'));
            await tester.pumpAndSettle();
            await tester.pump(const Duration(milliseconds: 300));
          }
          if (layout.name == 'phone-fixed') {
            await tester.tap(find.byTooltip('Session tasks'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('AI connection'));
          } else {
            await tester.tap(find.byKey(const Key('ai-open-settings')));
          }
          await tester.pump();
          expect(
            ModalRoute.of(
              tester.element(find.byType(AlertDialog)),
            )!.animation!.isCompleted,
            true,
          );
          await tester.pumpAndSettle();
          await _capture(tester, '$name-settings');
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(controller.draft, 'Keep this draft');
          expect(controller.attachments, [source]);
          expect(controller.canApprove, true);
          expect(terminal.writes, isEmpty);
          expect(api.requests, hasLength(1));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final empty in [true, false]) {
    testWidgets('source markers render only valid original lines: empty=$empty', (
      tester,
    ) async {
      await prepare();
      terminal.context = contextFor(
        lastBlock: AiBlockContext(
          id: 'original',
          command: empty ? 'true' : 'read',
          output: empty ? '' : 'one\ntwo\nthree',
          exitCode: 0,
          cwd: '/tmp',
          totalLines: empty ? 0 : 3,
          outputEndLine: empty ? 0 : 3,
        ),
      );
      const raw =
          'Command finished. [block:original:1-3] '
          '[block:original:无输出；退出码 0] [block:original:4-9] [block:unknown:1-1]';
      api.respond = (_) async => const AiReply(text: raw);
      await controller.ask('Explain');
      final opened = <(String, int)>[];
      await mount(
        tester,
        onShowEvidence: (reference) =>
            opened.add((reference.id, reference.startLine)),
      );
      expect(controller.transcript.last.text, raw);
      expect(find.textContaining('[block:'), findsNothing);
      if (empty) {
        expect(find.byKey(const Key('ai-evidence-original-0-3')), findsNothing);
      } else {
        await tester.tap(find.byKey(const Key('ai-evidence-original-0-3')));
        expect(opened, [('original', 0)]);
      }
      expect(find.byKey(const Key('ai-evidence-original-3-9')), findsNothing);
      expect(find.byKey(const Key('ai-evidence-unknown-0-1')), findsNothing);
    });
  }

  testWidgets(
    'truncated citations keep source numbering after new output arrives',
    (tester) async {
      await prepare();
      terminal.context = contextFor(
        lastBlock: const AiBlockContext(
          id: 'tail',
          command: 'logs',
          output: 'retained tail',
          exitCode: 0,
          cwd: '/tmp',
          totalLines: 600,
          outputStartLine: 466,
          outputEndLine: 600,
        ),
      );
      api.respond = (_) async => const AiReply(
        text: 'Limited evidence. [block:tail:467-600] [block:tail:1-135]',
      );
      await controller.ask('Explain');
      terminal.context = contextFor(
        lastBlock: const AiBlockContext(
          id: 'next',
          command: 'true',
          output: '',
          exitCode: 0,
          cwd: '/tmp',
          totalLines: 0,
          outputEndLine: 0,
        ),
      );
      await controller.refreshContext();
      final opened = <(String, int)>[];
      await mount(
        tester,
        onShowEvidence: (reference) =>
            opened.add((reference.id, reference.startLine)),
      );
      expect(find.byKey(const Key('ai-evidence-tail-0-135')), findsNothing);
      await tester.tap(find.byKey(const Key('ai-evidence-tail-466-600')));
      expect(opened, [('tail', 466)]);
    },
  );

  for (final brightness in Brightness.values) {
    for (final size in [
      const Size(960, 700),
      const Size(390, 480),
      const Size(320, 260),
    ]) {
      for (final scale in size.width < 600 ? [1.0] : [1.0, 2.0]) {
        testWidgets('workspace layout ${brightness.name} $size scale $scale', (
          tester,
        ) async {
          await prepare();
          controller.attachContext(source);
          controller.setDraft('Keep my draft');
          await mount(tester, size: size, scale: scale, brightness: brightness);
          expect(
            find.byKey(const Key('ai-send')).hitTestable(),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('ai-close')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }

  testWidgets('short phone keeps draft usable with a proposal and attachment', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await prepare();
    await controller.ask('Inspect files');
    controller.attachContext(source);
    controller.setDraft('Keep this constraint');
    await mount(
      tester,
      size: const Size(320, 460),
      platform: TargetPlatform.iOS,
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(controller.canApprove, isTrue);
    expect(
      tester.getSize(find.byKey(const Key('ai-prompt'))).width,
      greaterThanOrEqualTo(80),
    );
    expect(find.byKey(const Key('ai-send')).hitTestable(), findsOneWidget);
    expect(
      find.byKey(const Key('ai-pending-contexts')).hitTestable(),
      findsOneWidget,
    );
    await _capture(tester, 'M06-short-touch-theme');
    await tester.tap(find.byKey(const Key('ai-task-actions')));
    await tester.pumpAndSettle();
    expect(find.text('Locate pending proposal'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai-take-over')));
    await tester.pumpAndSettle();
    expect(controller.canApprove, isFalse);
    expect(controller.takenOver, isTrue);
    expect(controller.draft, 'Keep this constraint');
    expect(controller.attachments, [source]);
    expect(tester.takeException(), isNull);
    expect(terminal.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('long command keeps its source range visible on a phone', (
    tester,
  ) async {
    await prepare();
    controller.attachContext(
      AiBlockContext(
        command: 'printf ${'long-command-' * 40}',
        output: 'selected output',
        exitCode: 0,
        cwd: '/tmp',
        totalLines: 600,
        outputStartLine: 440,
        outputEndLine: 600,
      ),
    );
    await mount(tester, size: const Size(320, 480));
    final chip = find.byWidgetPredicate(
      (w) => w is InputChip && w.onDeleted != null,
    );
    final range = find.descendant(
      of: chip,
      matching: find.byKey(const Key('ai-context-range')),
    );
    expect(tester.widget<Text>(range).data, 'Lines 441–600 of 600');
    expect(tester.widget<Text>(range).overflow, isNot(TextOverflow.ellipsis));
    final bounds = tester.getRect(range);
    expect(bounds.right, lessThanOrEqualTo(320));
    expect(bounds.bottom, lessThanOrEqualTo(480));
    await _capture(tester, 'D07-phone-touch-range');
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('Attached output snapshot'), findsOneWidget);
    expect(find.text('selected output'), findsOneWidget);
    expect(terminal.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'IME does not send; sent context stays frozen and draft is separate',
    (tester) async {
      await prepare();
      controller.attachContext(source);
      api.respond = (_) async => const AiReply(text: 'Explanation only');
      await mount(tester);
      await tester.tap(find.byKey(const Key('ai-prompt')));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '解释',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(api.requests, isEmpty);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '解释',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(api.requests, hasLength(1));
      expect(terminal.writes, isEmpty);
      expect(controller.transcript.first.contexts.single, source);
      expect(controller.attachments, isEmpty);
      await tester.enterText(
        find.byKey(const Key('ai-prompt')),
        'Follow-up draft',
      );
      expect(controller.draft, 'Follow-up draft');
    },
  );

  testWidgets(
    'mobile review has full command and fixed footer; stale target revokes',
    (tester) async {
      await prepare();
      final command = List.generate(60, (i) => 'printf line-$i').join('\n');
      api.respond = (_) async => commandReply(command);
      await controller.ask('Inspect logs');
      await mount(tester, size: const Size(390, 700));
      expect(find.byKey(const Key('ai-approve')), findsNothing);
      await tester.tap(find.byKey(const Key('ai-review-action')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SelectableText>(find.byKey(const Key('ai-action-preview')))
            .maxLines,
        isNull,
      );
      expect(find.byKey(const Key('ai-approve')).hitTestable(), findsOneWidget);
      expect(terminal.writes, isEmpty);
      terminal.context = contextFor(guard: 'changed');
      await controller.refreshContext();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-approve')), findsNothing);
      expect(terminal.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new response preserves reading; latest and return are explicit',
    (tester) async {
      await prepare();
      api.respond = (step) async =>
          AiReply(text: 'Response $step\n${'evidence\n' * 25}');
      for (var i = 0; i < 4; i++) {
        await controller.ask('Read $i');
      }
      await mount(tester);
      final scroll = tester
          .widget<CommandTimelineView>(find.byType(CommandTimelineView).first)
          .controller;
      scroll.jumpTo(100);
      await tester.pump();
      await controller.ask('More evidence');
      await tester.pumpAndSettle();
      expect(scroll.offset, 100);
      await tester.tap(find.byKey(const Key('ai-show-latest')));
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, lessThan(1));
      await tester.tap(find.byKey(const Key('ai-return-reading')));
      await tester.pumpAndSettle();
      expect(scroll.offset, 100);
      expect(tester.takeException(), isNull);
    },
  );

  for (final variant in [
    (
      name: 'wide-en',
      size: const Size(1280, 800),
      language: 'en',
      scale: 1.0,
      dark: false,
      phone: false,
    ),
    (
      name: 'wide-zh-dark',
      size: const Size(960, 800),
      language: 'zh',
      scale: 1.0,
      dark: true,
      phone: false,
    ),
    (
      name: 'desktop-2x',
      size: const Size(960, 800),
      language: 'en',
      scale: 2.0,
      dark: false,
      phone: false,
    ),
    (
      name: 'narrow-desktop-2x',
      size: const Size(600, 700),
      language: 'en',
      scale: 2.0,
      dark: true,
      phone: false,
    ),
    (
      name: 'phone-fixed',
      size: const Size(320, 568),
      language: 'zh',
      scale: 1.0,
      dark: false,
      phone: true,
    ),
  ]) {
    testWidgets(
      'navigation labels fit and preserve pending reading ${variant.name}',
      (tester) async {
        await prepare();
        api.respond = (step) async =>
            AiReply(text: 'Result $step\n${'original evidence\n' * 25}');
        for (var i = 0; i < 3; i++) {
          await controller.ask('Inspect $i');
        }
        await mount(
          tester,
          size: variant.size,
          scale: variant.scale,
          brightness: variant.dark ? Brightness.dark : Brightness.light,
          platform: variant.phone ? TargetPlatform.iOS : TargetPlatform.macOS,
          locale: Locale(variant.language),
        );
        final scroll =
            tester
                    .widget<CommandTimelineView>(
                      find.byType(CommandTimelineView),
                    )
                    .controller
                as CommandTimelineScrollController;
        scroll.jumpTo(100);
        await tester.pumpAndSettle();
        final anchor = scroll.readingAnchor!;
        api.respond = (_) async => commandReply('printf pending');
        await controller.ask('Propose a check');
        await tester.pumpAndSettle();
        expect(scroll.readingAnchor!.itemId, anchor.itemId);
        expect(scroll.readingAnchor!.offset, closeTo(anchor.offset, .1));
        final latest = find.byKey(const Key('ai-show-latest'));
        final label = variant.language == 'zh'
            ? '定位待确认提案'
            : 'Locate pending proposal';
        if (variant.name.startsWith('wide')) {
          expect(
            find.descendant(of: latest, matching: find.text(label)),
            findsOneWidget,
          );
          expect(tester.widget(latest), isA<TextButton>());
        }
        await _capture(tester, 'D13-${variant.name}-reading');
        await tester.tap(latest);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('ai-action-preview')).hitTestable(),
          findsOneWidget,
        );
        expect(controller.canApprove, isTrue);
        expect(terminal.writes, isEmpty);
        await _capture(tester, 'D13-${variant.name}-located');
        if (variant.phone) {
          await tester.tap(find.byKey(const Key('ai-task-actions')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('返回阅读位置'));
        } else {
          final back = find.byKey(const Key('ai-return-reading'));
          if (variant.name.startsWith('wide')) {
            expect(tester.widget(back), isA<TextButton>());
          }
          await tester.tap(back);
        }
        await tester.pumpAndSettle();
        expect(scroll.readingAnchor!.itemId, anchor.itemId);
        expect(scroll.readingAnchor!.offset, closeTo(anchor.offset, .1));
        expect(api.requests, hasLength(4));
        expect(terminal.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('latest cancels an unfinished return to the reading anchor', (
    tester,
  ) async {
    await prepare();
    api.respond = (step) async =>
        AiReply(text: 'Response $step\n${'evidence\n' * 25}');
    for (var i = 0; i < 5; i++) {
      await controller.ask('Read $i');
    }
    await mount(tester);
    final scroll = tester
        .widget<CommandTimelineView>(find.byType(CommandTimelineView))
        .controller;
    for (var frames = 0; frames < 3; frames++) {
      scroll.jumpTo(100);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-show-latest')));
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, lessThan(1));
      await tester.tap(find.byKey(const Key('ai-return-reading')));
      for (var i = 0; i < frames; i++) {
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('ai-show-latest')));
      await tester.pumpAndSettle();
      expect(
        scroll.position.extentAfter,
        lessThan(1),
        reason: 'Latest wins after $frames restoration frames',
      );
      expect(controller.followingOutput, true);
    }
    expect(terminal.writes, isEmpty);
    expect(api.requests, hasLength(5));
  });

  for (final phone in [false, true]) {
    testWidgets(
      'live status announces phase changes without elapsed time or output (phone $phone)',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final port = RecoveringTerminal();
          await prepare(port: port);
          AiTerminalContext running(String screen) => AiTerminalContext(
            sessionId: 'one',
            contextId: 'root',
            guard: 'running',
            screen: screen,
            cwd: '/tmp',
            runningCommand: 'stream logs',
          );
          port.context = running('line 1');
          api.respond = (_) async => AiReply(
            text: 'Observing the existing command',
            action: AiAction.fromToolCall({
              'id': 'observe-existing',
              'function': {
                'name': 'read_screen',
                'arguments': jsonEncode({
                  'reason': 'Wait for existing output',
                  'wait_ms': 30000,
                }),
              },
            }),
          );
          final turn = controller.ask('Observe only');
          await mount(
            tester,
            size: phone ? const Size(390, 700) : const Size(960, 700),
          );
          expect(controller.phase, AiPhase.observing);
          final status = find.byKey(const Key('ai-task-status'));
          final initialText = tester.widget<Text>(status).data;
          final initialNode = tester.getSemantics(status);
          expect(
            initialNode.getSemanticsData().flagsCollection.isLiveRegion,
            true,
          );
          expect(initialNode.label, 'AI is observing the terminal');
          port.context = running('line 1\nline 2\nline 3');
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1100)),
          );
          await tester.pump(const Duration(seconds: 2));
          expect(controller.lastOutputAt, isNotNull);
          expect(tester.widget<Text>(status).data, isNot(initialText));
          expect(tester.widget<Text>(status).data, contains('last output'));
          final updatedNode = tester.getSemantics(status);
          expect(updatedNode.id, initialNode.id);
          expect(updatedNode.label, 'AI is observing the terminal');
          await tester.tap(find.byKey(const Key('ai-take-over')));
          await tester.pump(const Duration(milliseconds: 150));
          await turn;
          expect(
            tester.getSemantics(status).label,
            'AI paused · command is not interrupted',
          );
          expect(port.writes, isEmpty);
          expect(port.context.runningCommand, 'stream logs');
          port.disconnected = true;
          await controller.refreshContext();
          await tester.pump();
          expect(
            tester.getSemantics(status).label,
            'Terminal unavailable · check its status',
          );
          expect(api.requests, hasLength(1));
          port.disconnected = false;
          port.context = const AiTerminalContext(
            sessionId: 'new-session',
            contextId: 'root',
            guard: 'new-session:1',
            screen: 'ready',
            cwd: '/changed/path',
            readyLease: 'new-lease',
            canRunCommand: true,
          );
          await controller.refreshContext();
          await tester.pumpAndSettle();
          final target = find.text('Execution target changed');
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          final targetNode = tester.getSemantics(target);
          expect(
            targetNode.getSemanticsData().flagsCollection.isLiveRegion,
            true,
          );
          expect(targetNode.label, 'Execution target changed');
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'each consecutive proposal needs its own UI approval (phone $phone)',
      (tester) async {
        await prepare();
        api.respond = (step) async => commandReply(
          ['pwd', 'ls -a', 'git status'][step - 1],
          id: 'proposal-$step',
        );
        await controller.ask('Inspect without changing files');
        await mount(
          tester,
          size: phone ? const Size(390, 700) : const Size(960, 700),
        );
        final task = controller.taskId;
        Future<void> review() async {
          if (phone) {
            await tester.ensureVisible(
              find.byKey(const Key('ai-review-action')),
            );
            await tester.tap(find.byKey(const Key('ai-review-action')));
            await tester.pumpAndSettle();
          } else {
            await tester.ensureVisible(find.byKey(const Key('ai-approve')));
          }
        }

        await review();
        final firstRevision = controller.proposalRevision;
        final approvePosition = tester.getCenter(
          find.byKey(const Key('ai-approve')),
        );
        await tester.tap(find.byKey(const Key('ai-approve')));
        await tester.tapAt(approvePosition);
        await tester.pumpAndSettle();
        expect(terminal.writes.map((a) => a.command), ['pwd']);
        expect(controller.pending!.command, 'ls -a');
        expect(controller.proposalRevision, greaterThan(firstRevision));
        expect(controller.taskId, task);
        expect(find.byType(TerminalAiWorkspace), findsOneWidget);
        await review();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(terminal.writes, hasLength(1));
        await tester.tap(find.byKey(const Key('ai-approve')));
        await tester.pumpAndSettle();
        expect(terminal.writes.map((a) => a.command), ['pwd', 'ls -a']);
        expect(controller.pending!.command, 'git status');
        await review();
        await tester.tap(find.byKey(const Key('ai-reject')));
        await tester.pumpAndSettle();
        expect(terminal.writes, hasLength(2));
        expect(api.requests, hasLength(3));
        expect(controller.taskId, task);
        expect(
          controller.transcript.where((e) => e.state == AiEntryState.accepted),
          hasLength(2),
        );
        expect(
          controller.transcript.where((e) => e.state == AiEntryState.rejected),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('editing requires a fresh revision and one approval sends once', (
    tester,
  ) async {
    await prepare();
    await controller.ask('Inspect files');
    await mount(tester);
    await tester.tap(find.byKey(const Key('ai-edit-action')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ai-edit-command')), 'ls -a');
    await tester.tap(find.text('Save for review'));
    await tester.pumpAndSettle();
    expect(terminal.writes, isEmpty);
    expect(controller.pending!.command, 'ls -a');
    api.respond = (_) async => const AiReply(text: 'Done observing');
    await tester.tap(find.byKey(const Key('ai-approve')));
    await tester.pumpAndSettle();
    expect(terminal.writes.single.command, 'ls -a');
  });

  testWidgets('task switch restores the same message after width reflow', (
    tester,
  ) async {
    await prepare();
    api.respond = (step) async =>
        AiReply(text: 'Reply $step ${'retained evidence ' * 100}');
    for (var i = 0; i < 6; i++) {
      await controller.ask('Read evidence $i');
    }
    final first = controller.taskId;
    await mount(tester);
    var scroll =
        tester
                .widget<CommandTimelineView>(find.byType(CommandTimelineView))
                .controller
            as CommandTimelineScrollController;
    scroll.jumpTo(700);
    await tester.pumpAndSettle();
    final anchor = scroll.readingAnchor!;
    controller.setDraft('First task draft');
    controller.newTask();
    await controller.ask('A separate task');
    await tester.pumpAndSettle();
    await mount(tester, size: const Size(640, 700));
    controller.selectTask(first);
    await tester.pumpAndSettle();
    scroll =
        tester
                .widget<CommandTimelineView>(find.byType(CommandTimelineView))
                .controller
            as CommandTimelineScrollController;
    expect(scroll.readingAnchor!.itemId, anchor.itemId);
    expect(scroll.readingAnchor!.offset, closeTo(anchor.offset, .1));
    expect(controller.draft, 'First task draft');
    expect(terminal.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop keyboard review requires focus on the approval button', (
    tester,
  ) async {
    await prepare();
    await controller.ask('Inspect files');
    await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(terminal.writes, isEmpty);
    final approve = find.byKey(const Key('ai-approve'));
    bool approvalHasFocus() {
      final button = tester.element(approve);
      var found = false;
      FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
        if (e == button) found = true;
        return !found;
      });
      return found;
    }

    for (var i = 0; i < 30 && !approvalHasFocus(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(terminal.writes, isEmpty);
    }
    expect(
      approvalHasFocus(),
      true,
      reason: 'The approval must be reachable with ordinary Tab traversal',
    );
    api.respond = (_) async => const AiReply(text: 'Observed');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(terminal.writes, hasLength(1));
    expect(terminal.writes.single.command, 'ls -la');
  });

  testWidgets(
    'clarification stays in one task and pause preserves a new draft',
    (tester) async {
      await prepare();
      final lateReply = Completer<AiReply>();
      api.respond = (step) => step == 1
          ? Future.value(
              const AiReply(text: 'Which directory should I inspect?'),
            )
          : lateReply.future;
      await mount(tester);
      await tester.enterText(
        find.byKey(const Key('ai-prompt')),
        'Inspect the failure, analysis only; do not edit files.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai-send')));
      await tester.pumpAndSettle();
      final taskId = controller.taskId;
      expect(find.text('Which directory should I inspect?'), findsOneWidget);
      expect(terminal.writes, isEmpty);
      await tester.enterText(
        find.byKey(const Key('ai-prompt')),
        '/srv/project',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai-send')));
      await tester.pump();
      expect(controller.taskId, taskId);
      expect(controller.phase, AiPhase.thinking);
      expect(jsonEncode(api.requests.last), contains('do not edit files'));
      expect(jsonEncode(api.requests.last), contains('/srv/project'));
      await tester.enterText(
        find.byKey(const Key('ai-prompt')),
        'Unsent detail',
      );
      await tester.tap(find.byKey(const Key('ai-take-over')));
      lateReply.complete(commandReply('touch should-not-run'));
      await tester.pumpAndSettle();
      expect(controller.taskId, taskId);
      expect(controller.draft, 'Unsent detail');
      expect(controller.canApprove, false);
      expect(terminal.writes, isEmpty);
    },
  );

  for (final size in [const Size(390, 480), const Size(844, 300)]) {
    testWidgets('phone long-command review scrolls without approving $size', (
      tester,
    ) async {
      await prepare();
      final command = [
        for (var i = 0; i < 60; i++) 'printf "review line $i\\n"',
      ].join('\n');
      api.respond = (_) async => commandReply(command);
      await controller.ask('Review the entire command');
      await mount(tester, size: size, platform: TargetPlatform.iOS);
      final review = find.byKey(const Key('ai-review-action'));
      await tester.ensureVisible(review);
      expect(find.byKey(const Key('ai-approve')), findsNothing);
      await tester.tap(review);
      await tester.pumpAndSettle();
      final preview = tester.widget<SelectableText>(
        find.descendant(
          of: find.byKey(const Key('ai-review-scroll')),
          matching: find.byKey(const Key('ai-action-preview')),
        ),
      );
      expect(preview.data, command);
      expect(preview.maxLines, isNull);
      final approval = find.byKey(const Key('ai-approve'));
      final fixedPosition = tester.getRect(approval);
      final scroll = find.byKey(const Key('ai-review-scroll'));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(size.height));
      await tester.fling(scroll, const Offset(0, -3000), 4000);
      await tester.pumpAndSettle();
      expect(scrollable.position.extentAfter, lessThan(1));
      expect(tester.getRect(approval), fixedPosition);
      expect(approval.hitTestable(), findsOneWidget);
      expect(terminal.writes, isEmpty);
      await tester.tap(find.byKey(const Key('ai-review-back')));
      await tester.pumpAndSettle();
      expect(controller.pending!.command, command);
      expect(terminal.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'mobile live block keeps six rows, reading and paused task ${brightness.name}',
      (tester) async {
        await prepare();
        api.respond = (step) async =>
            AiReply(text: 'Earlier evidence $step\n${'history line\n' * 12}');
        for (var i = 0; i < 3; i++) {
          await controller.ask('Keep earlier result $i');
        }
        var rows = 60;
        final commandStartedAt = DateTime.now().millisecondsSinceEpoch - 90000;
        int? commandFinishedAt;
        Map<String, Object?> snapshot() => {
          'id': 'live-output',
          'command': 'stream logs',
          'cwd': '/tmp',
          'running': commandFinishedAt == null,
          'exitCode': commandFinishedAt == null ? null : 0,
          'startedAt': commandStartedAt,
          'finishedAt': commandFinishedAt,
          'columns': 32,
          'totalLines': rows,
          'matchingLines': rows,
          'lines': [
            for (var i = 0; i < rows; i++)
              {
                'index': i,
                'source_row': i,
                'text': 'output ${i + 1}',
                'wrapped': false,
              },
          ],
        };
        final blocks = CommandBlockController(
          request: (args) => args['id'] == null
              ? {
                  'blocks': [snapshot()],
                }
              : {'block': snapshot()},
        )..refresh();
        addTearDown(blocks.dispose);
        const contextBlock = AiBlockContext(
          id: 'live-output',
          command: 'stream logs',
          output:
              'output 55\noutput 56\noutput 57\noutput 58\noutput 59\noutput 60',
          exitCode: null,
          running: true,
          cwd: '/tmp',
          totalLines: 60,
          outputStartLine: 54,
          outputEndLine: 60,
        );
        terminal.context = const AiTerminalContext(
          sessionId: 'one',
          contextId: 'root',
          guard: 'running',
          screen: 'output 60',
          runningCommand: 'stream logs',
          cwd: '/tmp',
          lastBlock: contextBlock,
        );
        controller.attachContext(contextBlock);
        api.respond = (_) async => AiReply(
          text: 'Observe the existing log without sending another command.',
          action: AiAction.fromToolCall({
            'id': 'mobile-observe',
            'function': {
              'name': 'read_screen',
              'arguments': jsonEncode({
                'reason': 'Observe logs',
                'wait_ms': 30000,
              }),
            },
          }),
        );
        final turn = controller.ask('Keep observing this log');
        late CommandTimelineScrollController scroll;
        await mount(
          tester,
          size: const Size(390, 700),
          brightness: brightness,
          timelineBuilder: (items, scroller, following) {
            scroll = scroller as CommandTimelineScrollController;
            return TerminalCommandBlocksView(
              controller: blocks,
              font: const TerminalFontConfig(family: 'monospace'),
              timeline: items,
              scrollController: scroller,
              followTail: following,
              showToolbar: false,
              onReinput: (_) => fail('Reading must not execute'),
            );
          },
        );
        controller.setDraft('Keep the log running');
        await tester.pumpAndSettle();
        final startedAt = controller.waitStartedAt;
        expect(startedAt, isNotNull);
        final requests = api.requests.length;
        final preview = find.byKey(
          const ValueKey('block-terminal-live-output'),
        );
        TerminalFrameDiff frame() => tester
            .widget<TerminalViewport>(
              find.descendant(
                of: preview,
                matching: find.byType(TerminalViewport),
              ),
            )
            .controller
            .frame;
        expect(frame().rows, hasLength(6));
        expect(frame().rows.first.text, 'output 55');
        expect(frame().rows.last.text, 'output 60');
        await _capture(tester, 'M03-live-six-rows-${brightness.name}');
        await tester.dragFrom(tester.getCenter(preview), const Offset(0, 280));
        await tester.pumpAndSettle();
        expect(controller.followingOutput, false);
        final anchor = scroll.readingAnchor!;
        rows = 120;
        blocks.refresh();
        await tester.pumpAndSettle();
        expect(scroll.readingAnchor!.itemId, anchor.itemId);
        expect(scroll.readingAnchor!.offset, closeTo(anchor.offset, .1));
        await _capture(tester, 'M03-live-history-stays-${brightness.name}');
        await tester.tap(find.byKey(const Key('ai-show-latest')));
        await tester.pumpAndSettle();
        expect(frame().rows, hasLength(6));
        expect(frame().rows.first.text, 'output 115');
        expect(frame().rows.last.text, 'output 120');
        final elapsed = find.byKey(const ValueKey('block-elapsed-live-output'));
        expect(tester.widget<Text>(elapsed).data, startsWith('1m '));
        if (brightness == Brightness.dark) {
          await tester.tap(find.byKey(const Key('ai-take-over')));
          await tester.pumpAndSettle();
          await turn;
          expect(tester.widget<Text>(elapsed).data, startsWith('1m '));
        }
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump(const Duration(milliseconds: 150));
        await turn;
        rows = 180;
        blocks.refresh();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(controller.busy, false);
        expect(controller.canApprove, false);
        expect(controller.waitStartedAt, startedAt);
        expect(controller.draft, 'Keep the log running');
        expect(frame().rows.last.text, 'output 180');
        expect(api.requests, hasLength(requests));
        expect(terminal.writes, isEmpty);
        expect(tester.widget<Text>(elapsed).data, startsWith('1m '));
        await _capture(
          tester,
          'M03-live-paused-after-background-${brightness.name}',
        );
        commandFinishedAt = commandStartedAt + 92400;
        blocks.refresh();
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(elapsed).data, '1m 32s');
        expect(frame().rows.last.text, 'output 180');
        expect(api.requests, hasLength(requests));
        expect(terminal.writes, isEmpty);
        await _capture(tester, 'M03-completed-elapsed-${brightness.name}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'mobile proposal survives a long background wait and resumes without sending',
    (tester) async {
      await prepare();
      await controller.ask('Inspect files');
      await mount(tester, size: const Size(390, 700));
      final proposal = controller.pending;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(controller.canApprove, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 30));
      expect(controller.pending, same(proposal));
      await controller.approve();
      expect(terminal.writes, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(controller.canApprove, isTrue);
      expect(controller.pending, same(proposal));
      expect(terminal.writes, isEmpty);
      expect(api.requests, hasLength(1));
    },
  );

  testWidgets(
    'reopening a mobile workspace revalidates a controller left in background',
    (tester) async {
      await prepare();
      await controller.ask('Inspect files');
      controller.suspendForBackground();
      expect(controller.canApprove, false);
      await mount(tester, size: const Size(390, 700));
      await tester.pumpAndSettle();
      expect(controller.canApprove, true);
      expect(terminal.writes, isEmpty);
      expect(api.requests, hasLength(1));
    },
  );

  testWidgets(
    'TUI Escape observes without taking over and approved keys return only once',
    (tester) async {
      await prepare();
      terminal.context = const AiTerminalContext(
        sessionId: 'one',
        contextId: 'root',
        guard: 'vim',
        screen: '~',
        cwd: '/tmp',
        canRunCommand: false,
        alternateScreen: true,
        runningCommand: 'vim',
      );
      api.respond = (_) async => AiReply(
        text: 'Leave insert mode',
        action: AiAction.fromToolCall({
          'id': 'vim-escape',
          'type': 'function',
          'function': {
            'name': 'send_keys',
            'arguments': jsonEncode({
              'keys': [
                {'key': 'ESC'},
              ],
              'reason': 'Leave insert mode',
            }),
          },
        }),
      );
      var closes = 0;
      var observations = 0;
      await controller.ask('Leave insert mode');
      await mount(
        tester,
        fullScreenTerminal: true,
        close: () => closes++,
        observe: () => observations++,
      );
      expect(find.text('Terminal program: vim'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(observations, 1);
      expect(closes, 0);
      expect(controller.canApprove, isTrue);
      expect(controller.takenOver, isFalse);
      expect(terminal.writes, isEmpty);
      api.respond = (_) async => const AiReply(text: 'Screen inspected');
      await tester.tap(find.byKey(const Key('ai-approve')));
      await tester.pumpAndSettle();
      expect(closes, 1);
      expect(observations, 1);
      expect(terminal.writes.single.kind, AiActionKind.sendKeys);
      await tester.pumpWidget(const SizedBox());
      await mount(
        tester,
        fullScreenTerminal: true,
        close: () => closes++,
        observe: () => observations++,
      );
      expect(
        closes,
        1,
        reason: 'Old accepted keys must not close a reopened task',
      );
    },
  );

  testWidgets('TUI exit before its receipt still returns input once', (
    tester,
  ) async {
    await prepare();
    terminal.context = const AiTerminalContext(
      sessionId: 'one',
      contextId: 'root',
      guard: 'vim',
      screen: '~',
      cwd: '/tmp',
      canRunCommand: false,
      alternateScreen: true,
      runningCommand: 'vim',
    );
    api.respond = (_) async => AiReply(
      text: 'Exit vim',
      action: AiAction.fromToolCall({
        'id': 'exit-vim',
        'function': {
          'name': 'send_keys',
          'arguments': jsonEncode({
            'keys': [
              {'key': 'ESC'},
              {'text': ':q!'},
              {'key': 'ENTER'},
            ],
            'reason': 'Exit vim',
          }),
        },
      }),
    );
    await controller.ask('Exit vim');
    var closes = 0;
    await mount(tester, fullScreenTerminal: true, close: () => closes++);
    terminal.execution = Completer<Map<String, Object?>>();
    api.respond = (_) async => const AiReply(text: 'Returned to shell');
    await tester.tap(find.byKey(const Key('ai-approve')));
    await tester.pump();
    expect(terminal.writes, hasLength(1));
    terminal.context = contextFor();
    await mount(tester, fullScreenTerminal: false, close: () => closes++);
    expect(closes, 0);
    terminal.execution!.complete({'status': 'input_sent'});
    await tester.pumpAndSettle();
    expect(closes, 1);
    expect(terminal.writes, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await mount(tester, close: () => closes++);
    expect(closes, 1, reason: 'Reopening the completed task stays open');
  });

  testWidgets('entering full-screen returns the input owner to the terminal', (
    tester,
  ) async {
    await prepare();
    var closes = 0;
    await mount(tester, close: () => closes++);
    await tester.tap(find.byKey(const Key('ai-prompt')));
    await tester.enterText(
      find.byKey(const Key('ai-prompt')),
      'Retained task draft',
    );
    await mount(tester, fullScreenTerminal: true, close: () => closes++);
    expect(closes, 1);
    expect(controller.draft, 'Retained task draft');
    expect(terminal.writes, isEmpty);
  });

  for (final variant in [
    (
      name: 'desktop-light',
      size: const Size(960, 800),
      scale: 1.0,
      brightness: Brightness.light,
      locale: const Locale('en'),
      phone: false,
    ),
    (
      name: 'desktop-dark-2x',
      size: const Size(680, 700),
      scale: 2.0,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      phone: false,
    ),
    (
      name: 'phone-light',
      size: const Size(320, 568),
      scale: 1.0,
      brightness: Brightness.light,
      locale: const Locale('zh'),
      phone: true,
    ),
    (
      name: 'phone-landscape',
      size: const Size(568, 320),
      scale: 1.0,
      brightness: Brightness.dark,
      locale: const Locale('zh'),
      phone: true,
    ),
  ]) {
    testWidgets(
      'workspace configuration failure preserves draft and save never sends it ${variant.name}',
      (tester) async {
        final store = MemoryAiStore(null)..fail = true;
        await prepare(store: store);
        controller.attachContext(source);
        controller.setDraft('Explain this failure, analysis only');
        await mount(
          tester,
          size: variant.size,
          scale: variant.scale,
          brightness: variant.brightness,
          locale: variant.locale,
          platform: variant.phone ? TargetPlatform.iOS : TargetPlatform.macOS,
        );
        await tester.tap(find.byKey(const Key('ai-send')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ai-settings-dialog')), findsOneWidget);
        expect(api.requests, isEmpty);
        await _capture(tester, 'D14-missing-${variant.name}');
        await tester.enterText(
          find.byKey(const Key('ai-model')),
          'cancelled-model',
        );
        await tester.tap(
          find.descendant(
            of: find.byKey(const Key('ai-settings-dialog')),
            matching: find.text(
              variant.locale.languageCode == 'zh' ? '取消' : 'Cancel',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.draft, 'Explain this failure, analysis only');
        expect(controller.attachments.single, source);
        expect(settings.configuration, isNull);
        await tester.tap(find.byKey(const Key('ai-send')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('ai-model')))
              .controller!
              .text,
          isEmpty,
        );
        expect(api.requests, isEmpty);
        final mock = find.byKey(const Key('ai-use-mock'));
        await tester.ensureVisible(mock);
        await tester.tap(mock);
        await tester.tap(find.byKey(const Key('ai-save-settings')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ai-settings-dialog')), findsOneWidget);
        expect(settings.configuration, isNull);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('ai-model')))
              .controller!
              .text,
          'trail-mock',
        );
        expect(controller.draft, 'Explain this failure, analysis only');
        expect(controller.attachments.single, source);
        await _capture(tester, 'D14-save-failed-${variant.name}');
        expect(
          find.text(
            variant.locale.languageCode == 'zh'
                ? '无法保存配置。编辑内容已保留，请重试。'
                : 'Could not save configuration. Your edits are kept here. Try again.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        store.fail = false;
        await tester.tap(find.byKey(const Key('ai-save-settings')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ai-settings-dialog')), findsNothing);
        expect(settings.configuration!.model, 'trail-mock');
        expect(controller.draft, 'Explain this failure, analysis only');
        expect(controller.attachments.single, source);
        expect(api.requests, isEmpty);
        expect(terminal.writes, isEmpty);
        await _capture(tester, 'D14-saved-${variant.name}');
        expect(tester.takeException(), isNull);
        api.respond = (_) async => const AiReply(text: 'Analysis only');
        await tester.tap(find.byKey(const Key('ai-send')));
        await tester.pumpAndSettle();
        expect(api.requests, hasLength(1));
        expect(controller.transcript.first.contexts.single, source);
        expect(terminal.writes, isEmpty);
      },
    );
  }

  testWidgets('authentication recovery saves without sending or losing task', (
    tester,
  ) async {
    await prepare();
    api.respond = (_) async => throw const AiFailure('authentication');
    await controller.ask('Inspect without changes');
    final originalTask = controller.taskId;
    controller.setDraft('Keep this follow-up');
    controller.attachContext(source);
    await mount(tester);
    expect(find.byKey(const Key('ai-resume')), findsNothing);
    await tester.tap(find.byKey(const Key('ai-recovery-settings')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ai-api-key')),
      'replaced-test-key',
    );
    await tester.tap(find.byKey(const Key('ai-save-settings')));
    await tester.pumpAndSettle();
    expect(find.text('AI connection saved. Task not sent.'), findsOneWidget);
    expect(controller.taskId, originalTask);
    expect(controller.draft, 'Keep this follow-up');
    expect(controller.attachments, [source]);
    expect(api.requests, hasLength(1));
    expect(terminal.writes, isEmpty);
    api.respond = (_) async => const AiReply(text: 'Observed fresh state');
    await tester.tap(find.byKey(const Key('ai-resume')));
    await tester.pumpAndSettle();
    expect(api.requests, hasLength(2));
    expect(controller.draft, 'Keep this follow-up');
    expect(terminal.writes, isEmpty);
  });

  testWidgets(
    'phone disconnect recovery is explicit and revokes old approval',
    (tester) async {
      final port = RecoveringTerminal();
      await prepare(port: port);
      await controller.ask('Inspect without changes');
      controller.setDraft('Keep mobile draft');
      var closes = 0;
      await mount(tester, size: const Size(320, 480), close: () => closes++);
      port.disconnected = true;
      await controller.refreshContext();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-review-action')), findsNothing);
      expect(find.byKey(const Key('ai-resume')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('ai-inspect-terminal')));
      await tester.tap(find.byKey(const Key('ai-inspect-terminal')));
      expect(closes, 1);
      port.disconnected = false;
      port.contextRead = Completer();
      await tester.tap(find.byKey(const Key('ai-check-terminal')));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('ai-check-terminal')))
            .onPressed,
        isNull,
      );
      port.contextRead!.complete(port.context);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-terminal-error')), findsNothing);
      expect(find.byKey(const Key('ai-resume')).hitTestable(), findsOneWidget);
      expect(controller.draft, 'Keep mobile draft');
      expect(controller.canApprove, false);
      expect(api.requests, hasLength(1));
      expect(port.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown submission checks its receipt without retrying the command',
    (tester) async {
      final port = RecoveringTerminal();
      await prepare(port: port);
      await controller.ask('Run only once');
      port.execution = Completer();
      final run = controller.approve();
      port.execution!.completeError(const AiFailure('submission_unknown'));
      await run;
      controller.setDraft('Keep receipt draft');
      await mount(tester);
      expect(find.textContaining('Confirmed by you'), findsOneWidget);
      expect(find.textContaining('Your confirmation is needed'), findsNothing);
      expect(find.byKey(const Key('ai-resume')), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('ai-send'))).onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('ai-check-terminal')));
      await tester.pumpAndSettle();
      expect(port.inspected, ['original-submission']);
      expect(find.byKey(const Key('ai-resume')), findsNothing);
      expect(
        find.textContaining('inspect the terminal manually'),
        findsOneWidget,
      );
      port.receipt = {'outcome': 'accepted', 'blockId': 'original-block'};
      await tester.tap(find.byKey(const Key('ai-check-terminal')));
      await tester.pumpAndSettle();
      expect(controller.transcript.last.blockId, 'original-block');
      expect(find.byKey(const Key('ai-error')), findsNothing);
      expect(find.byKey(const Key('ai-resume')), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('ai-send'))).onPressed,
        isNotNull,
      );
      expect(port.writes, hasLength(1));
      expect(api.requests, hasLength(1));
      expect(controller.draft, 'Keep receipt draft');
    },
  );

  for (final language in ['en', 'zh']) {
    for (final variant in [
      (
        name: 'desktop-light',
        phone: false,
        size: const Size(960, 800),
        scale: 1.0,
        brightness: Brightness.light,
      ),
      (
        name: 'desktop-dark',
        phone: false,
        size: const Size(960, 800),
        scale: 1.0,
        brightness: Brightness.dark,
      ),
      (
        name: 'desktop-2x',
        phone: false,
        size: const Size(680, 700),
        scale: 2.0,
        brightness: Brightness.dark,
      ),
      (
        name: 'phone-light',
        phone: true,
        size: const Size(320, 568),
        scale: 1.0,
        brightness: Brightness.light,
      ),
      (
        name: 'phone-dark',
        phone: true,
        size: const Size(390, 700),
        scale: 1.0,
        brightness: Brightness.dark,
      ),
      (
        name: 'phone-landscape',
        phone: true,
        size: const Size(568, 320),
        scale: 1.0,
        brightness: Brightness.dark,
      ),
    ]) {
      testWidgets(
        'unknown submission explains possible execution after reconnect $language ${variant.name}',
        (tester) async {
          final port = RecoveringTerminal();
          await prepare(port: port);
          await controller.ask('Run only once');
          port.execution = Completer();
          final run = controller.approve();
          controller.setDraft('  Keep receipt draft  ');
          port.disconnected = true;
          await controller.refreshContext();
          port.execution!.completeError(const AiFailure('submission_unknown'));
          await run;
          expect(controller.transcript.last.statusReason, isNotNull);
          port.disconnected = false;
          port.context = const AiTerminalContext(
            sessionId: 'new-connection',
            contextId: 'root',
            guard: 'new-connection:1',
            screen: 'shell> ',
            cwd: '/tmp',
            canRunCommand: true,
            readyLease: 'new-lease',
          );
          await controller.refreshContext();
          await mount(
            tester,
            size: variant.size,
            scale: variant.scale,
            brightness: variant.brightness,
            platform: variant.phone ? TargetPlatform.iOS : TargetPlatform.macOS,
            locale: Locale(language),
          );
          final entry = controller.transcript.last;
          final note = find.byKey(ValueKey('ai-proposal-status-${entry.id}'));
          final card = find.byKey(ValueKey('ai-proposal-${entry.id}'));
          await tester.scrollUntilVisible(
            card,
            -200,
            scrollable: find
                .descendant(
                  of: find.byType(CommandTimelineView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await Scrollable.ensureVisible(tester.element(card));
          await tester.pumpAndSettle();
          expect(
            tester.widget<Text>(note).data,
            contains(language == 'zh' ? '可能已经执行' : 'may already have run'),
          );
          expect(
            find.textContaining(language == 'zh' ? '提案已失效' : 'proposal cannot'),
            findsNothing,
          );
          await _capture(tester, 'D10-unknown-card-$language-${variant.name}');
          final target = find.byKey(const Key('ai-target-continue'));
          await tester.scrollUntilVisible(
            target,
            180,
            scrollable: find
                .descendant(
                  of: find.byType(CommandTimelineView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(tester.widget<FilledButton>(target).onPressed, isNull);
          expect(
            find.textContaining(
              language == 'zh'
                  ? '原连接仍有结果未知'
                  : 'original connection is still unknown',
            ),
            findsOneWidget,
          );
          final send = tester.widget(find.byKey(const Key('ai-send')));
          expect(
            send is IconButton
                ? send.onPressed
                : (send as FilledButton).onPressed,
            isNull,
          );
          await tester.tap(find.byKey(const Key('ai-prompt')));
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(controller.draft, '  Keep receipt draft  ');
          expect(port.writes, hasLength(1));
          expect(api.requests, hasLength(1));
          await tester.scrollUntilVisible(
            find.byKey(const Key('ai-check-terminal')),
            180,
            scrollable: find
                .descendant(
                  of: find.byType(CommandTimelineView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await _capture(
            tester,
            'D10-unknown-recovery-$language-${variant.name}',
          );
          final inspectedBefore = port.inspected.length;
          await tester.tap(find.byKey(const Key('ai-check-terminal')));
          await tester.pumpAndSettle();
          expect(port.inspected.length, greaterThan(inspectedBefore));
          expect(port.inspected.toSet(), {'original-submission'});
          expect(controller.hasUnresolvedSubmission, isTrue);
          expect(controller.canApprove, isFalse);
          expect(controller.draft, '  Keep receipt draft  ');
          expect(port.writes, hasLength(1));
          expect(api.requests, hasLength(1));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'target dialog never transfers approval and rechecks changed target',
    (tester) async {
      await prepare();
      await controller.ask('Inspect original target');
      final oldProposal = controller.pending!;
      var closes = 0;
      await mount(tester, close: () => closes++);
      terminal.context = const AiTerminalContext(
        sessionId: 'one',
        contextId: 'ssh:first',
        guard: 'ssh:first:1',
        screen: 'first> ',
        cwd: '/srv/first',
        targetLabel: 'SSH first',
        canRunCommand: true,
        readyLease: 'first-lease',
      );
      await controller.refreshContext();
      await tester.pumpAndSettle();
      expect(controller.canApprove, false);
      expect(
        find.text('Original target  one', findRichText: true),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ai-error')), findsNothing);
      await _capture(tester, '01-target-change');
      await tester.tap(find.byKey(const Key('ai-resume')));
      await tester.pumpAndSettle();
      expect(find.text('Choose execution target'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('/srv/first'),
        ),
        findsOneWidget,
      );
      expect(api.requests, hasLength(1));
      expect(terminal.writes, isEmpty);
      await _capture(tester, '02-target-choice');
      await tester.tap(find.text('Return to terminal'));
      await tester.pumpAndSettle();
      expect(closes, 1);
      expect(api.requests, hasLength(1));
      await tester.tap(find.byKey(const Key('ai-resume')));
      await tester.pumpAndSettle();
      terminal.context = const AiTerminalContext(
        sessionId: 'one',
        contextId: 'ssh:second',
        guard: 'ssh:second:1',
        screen: 'second> ',
        cwd: '/srv/second',
        targetLabel: 'SSH second',
        canRunCommand: true,
        readyLease: 'second-lease',
      );
      await tester.tap(find.byKey(const Key('ai-target-dialog-continue')));
      await tester.pumpAndSettle();
      expect(api.requests, hasLength(1));
      expect(terminal.writes, isEmpty);
      expect(controller.canApprove, false);
      await _capture(tester, '03-stale-choice');
      await tester.tap(find.byKey(const Key('ai-resume')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('/srv/second'),
        ),
        findsOneWidget,
      );
      api.respond = (_) async => commandReply('pwd', id: 'fresh-target');
      await tester.tap(find.byKey(const Key('ai-target-dialog-continue')));
      await tester.pumpAndSettle();
      expect(api.requests, hasLength(2));
      expect(controller.pending!.id, isNot(oldProposal.id));
      expect(controller.context!.contextId, 'ssh:second');
      expect(controller.canApprove, true);
      expect(terminal.writes, isEmpty);
      await _capture(tester, '04-fresh-proposal');
    },
  );

  const nextTarget = AiTerminalContext(
    sessionId: 'one',
    contextId: 'ssh:first',
    guard: 'ssh:first:1',
    screen: 'first> ',
    cwd: '/srv/first',
    targetLabel: 'SSH first',
    canRunCommand: true,
    readyLease: 'first-lease',
  );

  testWidgets(
    'target resume double click opens one dialog and one model turn',
    (tester) async {
      await prepare();
      await controller.ask('Inspect original target');
      controller.setDraft('Keep my next question');
      controller.attachContext(source);
      terminal.context = nextTarget;
      await controller.refreshContext();
      await mount(tester);
      // Invoke both callbacks before the button has rebuilt as disabled.
      final resume = tester.widget<IconButton>(
        find.byKey(const Key('ai-resume')),
      );
      resume.onPressed!();
      resume.onPressed!();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
      final answer = Completer<AiReply>();
      api.respond = (_) => answer.future;
      await tester.tap(find.byKey(const Key('ai-target-dialog-continue')));
      await tester.pumpAndSettle();
      expect(api.requests, hasLength(2));
      expect(terminal.writes, isEmpty);
      expect(controller.draft, 'Keep my next question');
      answer.complete(commandReply('pwd', id: 'resumed'));
      await tester.pumpAndSettle();
      expect(controller.canApprove, true);
      expect(controller.draft, 'Keep my next question');
      expect(controller.attachments, [source]);
      expect(controller.transcript.last.contexts, isEmpty);
      expect(terminal.writes, isEmpty);
    },
  );

  testWidgets('target choice cannot resume another task', (tester) async {
    await prepare();
    await controller.ask('Inspect original target');
    terminal.context = nextTarget;
    await controller.refreshContext();
    await mount(tester);
    await tester.tap(find.byKey(const Key('ai-resume')));
    await tester.pumpAndSettle();
    controller.newTask();
    await controller.ask('Different task');
    controller.takeOver();
    expect(controller.canResume, true);
    final count = api.requests.length;
    await tester.tap(find.byKey(const Key('ai-target-dialog-continue')));
    await tester.pumpAndSettle();
    expect(api.requests, hasLength(count));
    expect(controller.taskTitle, 'Different task');
    expect(terminal.writes, isEmpty);
  });

  testWidgets(
    'inline target choice rejects an unseen hop and preserves draft',
    (tester) async {
      await prepare();
      await controller.ask('Inspect original target');
      controller.setDraft('Only inspect, do not change files');
      terminal.context = nextTarget;
      await controller.refreshContext();
      await mount(tester);
      // A different target is discovered only when the click refreshes state.
      terminal.context = const AiTerminalContext(
        sessionId: 'one',
        contextId: 'ssh:second',
        guard: 'ssh:second:1',
        screen: 'second> ',
        cwd: '/srv/second',
        canRunCommand: true,
        readyLease: 'second-lease',
      );
      await tester.tap(find.byKey(const Key('ai-target-continue')));
      await tester.pumpAndSettle();
      expect(api.requests, hasLength(1));
      expect(terminal.writes, isEmpty);
      expect(controller.canApprove, false);
      expect(find.text('Shell context: ssh:second'), findsOneWidget);
      expect(controller.draft, 'Only inspect, do not change files');
      final answer = Completer<AiReply>();
      api.respond = (_) => answer.future;
      final continueButton = tester.widget<FilledButton>(
        find.byKey(const Key('ai-target-continue')),
      );
      continueButton.onPressed!();
      continueButton.onPressed!();
      await tester.pumpAndSettle();
      expect(api.requests, hasLength(2));
      answer.complete(commandReply('pwd', id: 'inline'));
      await tester.pumpAndSettle();
      expect(controller.canApprove, true);
      expect(controller.originalTarget!.contextId, 'ssh:second');
      expect(controller.draft, 'Only inspect, do not change files');
      expect(terminal.writes, isEmpty);
    },
  );

  for (final variant in [
    (name: 'desktop', size: const Size(960, 700), scale: 1.0, locale: 'en'),
    (name: 'desktop-zh', size: const Size(960, 700), scale: 1.0, locale: 'zh'),
    (
      name: 'desktop-large',
      size: const Size(960, 700),
      scale: 2.0,
      locale: 'en',
    ),
    (name: 'phone', size: const Size(390, 620), scale: 1.0, locale: 'zh'),
    (name: 'phone-short', size: const Size(320, 260), scale: 1.0, locale: 'en'),
    (
      name: 'phone-landscape',
      size: const Size(844, 300),
      scale: 1.0,
      locale: 'zh',
    ),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets('target long labels ${variant.name} ${brightness.name}', (
        tester,
      ) async {
        await prepare();
        await controller.ask('Inspect original target');
        controller.setDraft('Keep this draft');
        terminal.context = const AiTerminalContext(
          sessionId: 'one',
          contextId: 'ssh:cloud:node-b:production-check-20261003',
          guard: 'long-target:1',
          screen: 'node-b> ',
          targetLabel: 'Cloud / production / node-b / diagnostics',
          cwd: '/srv/workspaces/application/packages/terminal/diagnostics',
          canRunCommand: true,
          readyLease: 'long-target-lease',
        );
        await controller.refreshContext();
        await mount(
          tester,
          size: variant.size,
          scale: variant.scale,
          brightness: brightness,
          platform: variant.name.startsWith('phone')
              ? TargetPlatform.iOS
              : TargetPlatform.macOS,
          locale: Locale(variant.locale),
        );
        // The notice shares the timeline's single scroll owner.
        await tester.ensureVisible(find.byKey(const Key('ai-target-continue')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('ai-target-continue')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _capture(tester, '${variant.name}-${brightness.name}-notice');
        if (variant.name.startsWith('phone') && variant.size.height < 320) {
          final menu = find.byKey(const Key('ai-task-actions')).hitTestable();
          expect(menu, findsOneWidget);
          await tester.tap(menu);
          await tester.pumpAndSettle();
        }
        final resume = find.byKey(const Key('ai-resume')).hitTestable();
        expect(resume, findsOneWidget);
        await tester.tap(resume);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('ai-target-dialog-continue')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('ai-target-dialog-return')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _capture(tester, '${variant.name}-${brightness.name}-dialog');
        // Reading and cancelling never starts inference or terminal input.
        final dialog = find.byType(AlertDialog);
        final scroller = find.descendant(
          of: dialog,
          matching: find.byType(SingleChildScrollView),
        );
        await tester.drag(scroller, const Offset(0, -300));
        await tester.pumpAndSettle();
        if (variant.size.height < 360 || variant.scale > 1) {
          final scrollState = tester.state<ScrollableState>(
            find.descendant(of: scroller, matching: find.byType(Scrollable)),
          );
          expect(scrollState.position.pixels, greaterThan(0));
          await _capture(
            tester,
            '${variant.name}-${brightness.name}-dialog-scrolled',
          );
        }
        if (variant.name.startsWith('phone')) {
          expect(
            tester
                .getSize(find.byKey(const Key('ai-target-dialog-continue')))
                .height,
            greaterThanOrEqualTo(44),
          );
          expect(
            tester
                .getSize(find.byKey(const Key('ai-target-dialog-return')))
                .height,
            greaterThanOrEqualTo(44),
          );
        }
        await tester.tap(find.byKey(const Key('ai-target-dialog-return')));
        await tester.pumpAndSettle();
        expect(controller.draft, 'Keep this draft');
        expect(api.requests, hasLength(1));
        expect(terminal.writes, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'canonical block replaces accepted proposal without copied output',
    (tester) async {
      await prepare();
      controller.attachContext(source);
      terminal.execution = Completer();
      await controller.ask('Inspect files');
      final turn = controller.approve();
      api.respond = (_) async =>
          const AiReply(text: 'See block receipt-1 lines 1–2');
      terminal.execution!.complete({
        'status': 'input_sent',
        'submission_id': 'sent-1',
        'block_id': 'receipt-1',
      });
      await turn;
      controller.attachContext(source);
      List<CommandBlockTimelineItem> observed = [];
      await mount(
        tester,
        timelineBuilder: (items, scroll, followTail) {
          observed = items;
          return ListView(
            controller: scroll,
            children: [
              for (final item in items)
                if (item.blockId != null)
                  Text('Canonical ${item.blockId}')
                else
                  Builder(builder: item.builder!),
            ],
          );
        },
      );
      expect(
        observed.where((item) => item.blockId == 'receipt-1'),
        hasLength(1),
      );
      expect(
        observed.singleWhere((item) => item.blockId == 'receipt-1').id,
        controller.transcript
            .singleWhere((entry) => entry.blockId == 'receipt-1')
            .id,
        reason: 'Accepted output retains the proposal position in the timeline',
      );
      expect(find.text('Canonical receipt-1'), findsOneWidget);
      expect(
        observed.where((item) => item.blockId == source.id),
        hasLength(1),
        reason:
            'Original failure survives submission and reattachment without duplicate output',
      );
      expect(find.text('Input submitted'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
