import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:app/ui/app_ui.dart';
import 'package:app/ui/previews/composer_preview_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'configuration_capture_binding.dart';
import 'visual_capture_fonts.dart';

void main() {
  if (!Platform.isMacOS) {
    test('Composer layout checks require macOS fonts', () {}, skip: true);
    return;
  }
  ConfigurationCaptureBinding();
  setUpAll(loadVisualCaptureFonts);

  _testMacWidgets(
    'primary action accepts a candidate before executing a command',
    (tester) async {
      final fixture = ComposerRedesignFixture(
        ComposerRedesignScenario.completion,
      );
      await _mount(tester, fixture);
      final controller = fixture.controller;
      expect(controller.completionMenuOpen, isTrue);
      await tester.tap(find.byKey(const Key('composer-primary-action')));
      await tester.pump();
      expect(controller.editor.text, 'git checkout');
      expect(controller.completionMenuOpen, isFalse);
      expect(controller.ownership, ComposerOwnership.ready);
      expect(controller.pendingSubmission, isNull);

      await tester.tap(find.byKey(const Key('composer-primary-action')));
      await tester.pump();
      expect(controller.ownership, ComposerOwnership.running);
      expect(controller.editor.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  _testMacWidgets(
    'history toggle restores its draft and retains editor focus',
    (tester) async {
      final fixture = ComposerRedesignFixture(
        ComposerRedesignScenario.suggestion,
      );
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await _mount(tester, fixture, focus: focus);
      final history = find.byKey(const Key('composer-history-toggle'));
      await tester.tap(history);
      await tester.pump();
      expect(fixture.controller.historyOpen, isTrue);
      await tester.enterText(
        find.byKey(const Key('composer-editor')),
        'status',
      );
      await tester.pump();
      expect(fixture.controller.historyItems, ['git status --short']);
      await tester.tap(history);
      await tester.pump();
      expect(fixture.controller.historyOpen, isFalse);
      expect(fixture.controller.editor.text, 'git');
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  _testMacWidgets(
    'mouse click and text selection across frames keep completion details open',
    (tester) async {
      final fixture = ComposerRedesignFixture(
        ComposerRedesignScenario.completion,
      );
      await _mount(tester, fixture);
      final controller = fixture.controller;
      final draft = controller.editor.text;
      final lease = controller.readyLease;
      final selected = controller.selectedIndex;
      final details = find.byKey(const Key('composer-completion-detail'));
      final selectable = find.descendant(
        of: details,
        matching: find.byType(SelectableText),
      );
      expect(selectable, findsOneWidget);
      final point = tester.getCenter(selectable);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: point);
      addTearDown(mouse.removePointer);
      await tester.pump();
      await mouse.down(point);
      await tester.pump();
      await mouse.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(details, findsOneWidget);
      expect(selectable, findsOneWidget);
      final selectionStart =
          tester.getRect(selectable).topLeft + const Offset(6, 6);
      await mouse.moveTo(selectionStart);
      await tester.pump();
      await mouse.down(selectionStart);
      await tester.pump();
      await mouse.moveTo(selectionStart + const Offset(110, 0));
      await tester.pump();
      await mouse.up();
      await tester.pump();
      final detailEditor = tester.widget<EditableText>(
        find.descendant(of: selectable, matching: find.byType(EditableText)),
      );
      expect(detailEditor.controller.selection.isCollapsed, isFalse);
      expect(detailEditor.focusNode.hasFocus, isTrue);
      expect(details, findsOneWidget);
      expect(find.byKey(const Key('composer-completion-list')), findsOneWidget);
      expect(controller.completionMenuOpen, isTrue);
      expect(controller.selectedIndex, selected);
      expect(controller.editor.text, draft);
      expect(controller.readyLease, lease);
      expect(controller.ownership, ComposerOwnership.ready);
      expect(controller.pendingSubmission, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  _testMacWidgets(
    '320 px at 2x keeps the action rail available and copy exact',
    (tester) async {
      final fixture = ComposerRedesignFixture(
        ComposerRedesignScenario.copyFeedback,
      );
      final focus = FocusNode();
      addTearDown(focus.dispose);
      String? clipboard;
      _mockClipboard(tester, (text) => clipboard = text);
      await _mount(
        tester,
        fixture,
        size: const Size(320, 740),
        textScale: 2,
        focus: focus,
      );
      for (final key in [
        'composer-history-toggle',
        'composer-automatic-suggestions-toggle',
        'composer-more-actions',
        'composer-primary-action',
      ]) {
        final rect = tester.getRect(find.byKey(Key(key)));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.height, greaterThanOrEqualTo(32));
        expect(rect.width, greaterThanOrEqualTo(32));
      }
      expect(fixture.controller.inlineSuggestion, isNotEmpty);
      await tester.tap(find.byKey(const Key('composer-more-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('composer-copy-draft')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(clipboard, 'git');
      expect(fixture.controller.editor.text, 'git');
      expect(find.byKey(const Key('composer-feedback')), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  _testMacWidgets(
    'automatic suggestions remains a reversible explicit preference',
    (tester) async {
      final fixture = ComposerRedesignFixture(ComposerRedesignScenario.empty);
      await _mount(tester, fixture, size: const Size(320, 640));
      final toggle = find.byKey(
        const Key('composer-automatic-suggestions-toggle'),
      );
      expect(fixture.controller.localSuggestions, isFalse);
      await tester.tap(toggle);
      await tester.pump();
      expect(fixture.controller.localSuggestions, isTrue);
      await tester.tap(toggle);
      await tester.pump();
      expect(fixture.controller.localSuggestions, isFalse);
      expect(fixture.controller.editor.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  _testMacWidgets('Escape closes More before handing input back to the terminal', (
    tester,
  ) async {
    final fixture = ComposerRedesignFixture(ComposerRedesignScenario.moreMenu);
    var terminalRequests = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _mount(
      tester,
      fixture,
      focus: focus,
      onUseTerminal: () => terminalRequests++,
    );
    await tester.tap(find.byKey(const Key('composer-more-actions')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('composer-copy-draft')), findsOneWidget);
    final focusBefore = FocusManager.instance.primaryFocus?.debugLabel;
    final editorFocusedBefore = focus.hasFocus;
    final suggestionBefore = fixture.controller.inlineSuggestion;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('composer-copy-draft')),
      findsNothing,
      reason:
          'focus before=$focusBefore, after=${FocusManager.instance.primaryFocus?.debugLabel}; '
          'editor before=$editorFocusedBefore, after=${focus.hasFocus}; '
          'inline before=$suggestionBefore, after=${fixture.controller.inlineSuggestion}; '
          'terminal requests=$terminalRequests',
    );
    expect(terminalRequests, 0);
    expect(focus.hasFocus, isTrue);
    expect(fixture.controller.editor.text, 'git');
    expect(tester.takeException(), isNull);
  });

  _testMacWidgets(
    'copy feedback preserves an unknown outcome until explicit recovery',
    (tester) async {
      final fixture = ComposerRedesignFixture(ComposerRedesignScenario.unknown);
      String? clipboard;
      _mockClipboard(tester, (text) => clipboard = text);
      await _mount(tester, fixture, size: const Size(360, 740), textScale: 2);
      expect(fixture.controller.status, 'unknown_outcome');
      await tester.tap(find.byKey(const Key('composer-more-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('composer-copy-draft')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(clipboard, 'npm run build');
      expect(fixture.controller.status, 'unknown_outcome');
      expect(fixture.controller.ownership, ComposerOwnership.unknown);
      expect(find.byKey(const Key('composer-feedback')), findsOneWidget);
      await tester.tap(find.byKey(const Key('composer-recover-draft')));
      await tester.pump();
      expect(fixture.controller.ownership, ComposerOwnership.draft);
      expect(fixture.controller.editor.text, 'npm run build');
      expect(fixture.controller.pendingSubmission, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scenario in [
    ComposerRedesignScenario.completionDetails,
    ComposerRedesignScenario.shortcutHelp,
  ]) {
    _testMacWidgets(
      '${scenario.name} closes back to the same draft and focus',
      (tester) async {
        final fixture = ComposerRedesignFixture(scenario);
        final focus = FocusNode();
        addTearDown(focus.dispose);
        await _mount(tester, fixture, size: const Size(320, 640), focus: focus);
        final draft = fixture.controller.editor.text;
        if (scenario == ComposerRedesignScenario.shortcutHelp) {
          await tester.tap(find.byKey(const Key('composer-more-actions')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.byKey(const Key('composer-shortcut-help')));
        } else {
          await tester.tap(
            find.byKey(const Key('composer-completion-detail-action')),
          );
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(AlertDialog), findsOneWidget);
        if (scenario == ComposerRedesignScenario.completionDetails) {
          expect(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text(fixture.controller.items.first.label),
            ),
            findsOneWidget,
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(AlertDialog), findsNothing);
        expect(fixture.controller.editor.text, draft);
        expect(fixture.controller.ownership, ComposerOwnership.ready);
        expect(fixture.controller.pendingSubmission, isNull);
        expect(focus.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _mount(
  WidgetTester tester,
  ComposerRedesignFixture fixture, {
  Size size = const Size(856, 460),
  double textScale = 1,
  FocusNode? focus,
  VoidCallback? onUseTerminal,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(fixture.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: withVisualCaptureFonts(
        buildIanvsTerminalTheme(
          Brightness.light,
          platform: TargetPlatform.macOS,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TerminalComposerView(
              controller: fixture.controller,
              targetLabel: fixture.targetLabel,
              focusNode: focus,
              autofocus: true,
              chinese: true,
              onUseTerminal: onUseTerminal ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  fixture.activate();
  await tester.pump(const Duration(milliseconds: 150));
  fixture.revealSelection();
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pump();
  addTearDown(() async {
    fixture.finish();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _mockClipboard(WidgetTester tester, ValueChanged<String> onCopied) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        onCopied((call.arguments as Map)['text'] as String);
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
}

void _testMacWidgets(
  String description,
  Future<void> Function(WidgetTester) callback,
) => testWidgets(
  description,
  callback,
  variant: const TargetPlatformVariant({TargetPlatform.macOS}),
);
