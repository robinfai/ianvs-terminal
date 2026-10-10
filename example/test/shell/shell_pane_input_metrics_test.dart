import 'dart:convert';

import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal_viewport.dart' as app_terminal;
import 'package:app/features/terminal_composer/composer_pane.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_profile_repository.dart';
import 'shell_screen_phase1b_test.dart' show pumpShellScreen;

typedef _NativeResize = ({
  String sessionId,
  int cols,
  int rows,
  int pixelWidth,
  int pixelHeight,
  int cellWidth,
  int cellHeight,
});

class _Backend extends FakePtyBackend {
  final metrics = <_NativeResize>[];
  final submissions = <String>[];

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {
    metrics.add((
      sessionId: sessionId,
      cols: cols,
      rows: rows,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
    ));
    super.resizeSession(
      sessionId,
      cols: cols,
      rows: rows,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
    );
  }

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    switch (request['kind']) {
      case 'composer.state':
        return jsonEncode({
          'state': 'ready',
          'lease': 'lease-$sessionId',
          'contextId': 'root',
          'transport': 'shell',
          'cwd': '/fixture',
          'dialect': 'zsh',
        });
      case 'composer.submit':
        submissions.add(sessionId);
        return jsonEncode({'outcome': 'unknown'});
      case 'completion.query':
        return jsonEncode({
          'schemaVersion': 1,
          'query': {...request}..remove('kind'),
          'status': 'ok',
          'items': <Object?>[],
        });
      case 'terminal.command_blocks':
        return jsonEncode({'blocks': <Object?>[]});
    }
    return super.requestSessionJson(sessionId, requestJson);
  }
}

Future<void> _settleMetrics(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void _setDpr(WidgetTester tester, double ratio) {
  tester.view.devicePixelRatio = ratio;
  tester.view.physicalSize = Size(1200 * ratio, 800 * ratio);
}

Future<ProviderContainer> _mount(WidgetTester tester, _Backend backend) async {
  _setDpr(tester, 1);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.reset();
  });
  await pumpShellScreen(
    tester,
    fakeBindings: backend,
    repository: MemoryProfileRepository(
      TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
    ),
  );
  await _settleMetrics(tester);
  return ProviderScope.containerOf(tester.element(find.byType(ShellScreen)));
}

Finder _viewportFinder(String id) => find.descendant(
  of: find.byKey(Key('shell-pane-$id')),
  matching: find.byType(app_terminal.TerminalViewport),
);

Future<({String left, String right, ComposerPaneSession composer})>
_splitWithDraft(WidgetTester tester, ProviderContainer container) async {
  final controller = container.read(sessionControllerProvider.notifier);
  final left = container.read(sessionControllerProvider).activeSessionId!;
  controller.splitActiveSession(
    defaultTerminalProfile(),
    TerminalSplitAxis.horizontal,
  );
  final right = container.read(sessionControllerProvider).activeSessionId!;
  controller.activateSession(left);
  await tester.pumpAndSettle();
  final tabId = container.read(sessionControllerProvider).tabs.single.sessionId;
  await tester.tap(
    find.byKey(Key('shell-tab-$tabId')),
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('terminal-mode-blocks-$left')));
  await tester.pumpAndSettle();
  final pane = find.byWidgetPredicate(
    (widget) => widget is ComposerPane && widget.session.sessionId == left,
  );
  final composer = tester.widget<ComposerPane>(pane).session;
  expect(composer.enabled, isTrue);
  expect(composer.controller.ownership, ComposerOwnership.ready);
  await tester.enterText(
    find.descendant(
      of: pane,
      matching: find.byKey(const Key('composer-editor')),
    ),
    "printf 'keep this draft'",
  );
  await tester.pumpAndSettle();
  expect(composer.editorFocus.hasFocus, isTrue);
  return (left: left, right: right, composer: composer);
}

Finder _menuAction(TerminalActionId action) => find.byWidgetPredicate(
  (widget) =>
      widget is PopupMenuItem<TerminalActionId> && widget.value == action,
);

void main() {
  testWidgets(
    'secondary click in inactive raw pane preserves Composer target and draft',
    (tester) async {
      final backend = _Backend();
      final container = await _mount(tester, backend);
      final split = await _splitWithDraft(tester, container);
      final draft = split.composer.controller.editor.value;
      final writesBefore = backend.writes.length;

      await tester.tapAt(
        tester.getCenter(_viewportFinder(split.right)),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(
        container.read(sessionControllerProvider).activeSessionId,
        split.left,
      );
      expect(split.composer.editorFocus.hasFocus, isTrue);
      expect(split.composer.controller.editor.value, draft);
      expect(backend.writes.length, writesBefore);
      expect(backend.submissions, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets(
      'primary $kind click still activates the clicked pane without losing draft',
      (tester) async {
        final backend = _Backend();
        final container = await _mount(tester, backend);
        final split = await _splitWithDraft(tester, container);
        final draft = split.composer.controller.editor.value;

        await tester.tapAt(
          tester.getCenter(_viewportFinder(split.right)),
          kind: kind,
        );
        await tester.pumpAndSettle();

        expect(
          container.read(sessionControllerProvider).activeSessionId,
          split.right,
        );
        expect(split.composer.editorFocus.hasFocus, isFalse);
        expect(split.composer.controller.editor.value, draft);
        expect(
          tester
              .widget<app_terminal.TerminalViewport>(
                _viewportFinder(split.right),
              )
              .focusNode!
              .hasFocus,
          isTrue,
        );
        expect(backend.submissions, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'cancelling an inactive tab menu restores the original Composer draft focus',
    (tester) async {
      final backend = _Backend();
      final container = await _mount(tester, backend);
      final split = await _splitWithDraft(tester, container);
      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(defaultTerminalProfile());
      final other = container.read(sessionControllerProvider).activeSessionId!;
      controller.activateSession(split.left);
      await tester.pumpAndSettle();
      split.composer.editorFocus.requestFocus();
      await tester.pump();
      final draft = split.composer.controller.editor.value;
      final writesBefore = backend.writes.length;

      await tester.tap(
        find.byKey(Key('shell-tab-$other')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(
        container.read(sessionControllerProvider).activeSessionId,
        split.left,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(
        container.read(sessionControllerProvider).activeSessionId,
        split.left,
      );
      expect(split.composer.editorFocus.hasFocus, isTrue);
      expect(split.composer.controller.editor.value, draft);
      expect(backend.writes.length, writesBefore);
      expect(backend.submissions, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final active in [false, true]) {
    testWidgets(
      '${active ? 'active' : 'inactive'} TUI secondary click respects the current input owner',
      (tester) async {
        final backend = _Backend();
        final container = await _mount(tester, backend);
        final split = await _splitWithDraft(tester, container);
        final runtime = container.read(terminalRuntimeControllerProvider);
        final frame = runtime.viewportFor(split.right).frame;
        backend.setFrame(split.right, {
          'rows': [
            {'index': 0, 'text': 'TUI with mouse reporting'},
          ],
          'cursor': {'row': 0, 'col': 0, 'visible': true},
          'viewport_cols': frame.viewportCols,
          'viewport_rows': frame.viewportRows,
          'modes': {
            'alternate_screen': true,
            'mouse_mode': 'normal',
            'mouse_encoding': 'sgr',
          },
        });
        runtime.refreshSession(split.right);
        await tester.pumpAndSettle();
        final controller = container.read(sessionControllerProvider.notifier);
        if (active) {
          controller.activateSession(split.right);
          await tester.pumpAndSettle();
          tester
              .widget<app_terminal.TerminalViewport>(
                _viewportFinder(split.right),
              )
              .focusNode!
              .requestFocus();
          await tester.pump();
        }
        final viewport = tester.widget<app_terminal.TerminalViewport>(
          _viewportFinder(split.right),
        );
        expect(viewport.controller.frame.modes.mouseMode, 'normal');
        final draft = split.composer.controller.editor.value;
        final writesBefore = backend.writesBySession.length;

        await tester.tapAt(
          tester.getCenter(_viewportFinder(split.right)),
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();

        final reports = backend.writesBySession.skip(writesBefore).toList();
        if (active) {
          expect(reports.map((entry) => entry.key), [split.right, split.right]);
          final press = utf8.decode(reports[0].value);
          expect(press, matches(RegExp(r'^\x1b\[<2;\d+;\d+M$')));
          expect(
            utf8.decode(reports[1].value),
            '${press.substring(0, press.length - 1)}m',
          );
          // The old input sink must lose ownership synchronously, even before
          // the first frame rebuilding the active-pane widgets.
          controller.activateSession(split.left);
          final writesBeforeSwitch = backend.writes.length;
          viewport.inputController.sendMouseReport(
            modes: viewport.controller.frame.modes,
            row: 0,
            col: 0,
            button: 2,
            pressed: true,
          );
          expect(backend.writes.length, writesBeforeSwitch);
          await tester.pumpAndSettle();
        } else {
          expect(
            reports,
            isEmpty,
            reason: 'Inspecting an inactive TUI must not send mouse bytes.',
          );
          expect(
            container.read(sessionControllerProvider).activeSessionId,
            split.left,
          );
          expect(split.composer.editorFocus.hasFocus, isTrue);
        }
        expect(split.composer.controller.editor.value, draft);
        expect(backend.submissions, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'DPR-only resize updates native pixels and replay metrics without changing cells',
    (tester) async {
      final backend = _Backend();
      final container = await _mount(tester, backend);
      final id = container.read(sessionControllerProvider).activeSessionId!;
      final runtime = container.read(terminalRuntimeControllerProvider);
      final before = backend.metrics.last;
      final logicalCell = runtime.viewportFor(id).measuredCellSize!;
      final viewportSize = tester.getSize(_viewportFinder(id));
      final events = <TerminalSessionResizeEvent>[];
      final subscription = runtime.resizeEvents.listen(events.add);
      addTearDown(subscription.cancel);
      backend.metrics.clear();

      _setDpr(tester, 2);
      await _settleMetrics(tester);

      expect(tester.getSize(_viewportFinder(id)), viewportSize);
      expect(backend.metrics, hasLength(1));
      final after = backend.metrics.single;
      expect((after.cols, after.rows), (before.cols, before.rows));
      expect(after.pixelWidth, before.pixelWidth * 2);
      expect(after.pixelHeight, before.pixelHeight * 2);
      expect(after.cellWidth, (logicalCell.width * 2).round());
      expect(after.cellHeight, (logicalCell.height * 2).round());
      expect(events, hasLength(1));
      final event = events.single;
      expect(event.sessionId, id);
      expect(event.devicePixelRatio, 2);
      expect(event.viewportSize.width * 2, after.pixelWidth);
      expect(event.viewportSize.height * 2, after.pixelHeight);
      expect(
        (event.cellWidth, event.cellHeight),
        (after.cellWidth, after.cellHeight),
      );

      backend.setFrame(id, {
        'rows': [
          {'index': 0, 'text': 'ordinary output after the display change'},
        ],
        'cursor': {'row': 0, 'col': 0, 'visible': true},
        'viewport_cols': after.cols,
        'viewport_rows': after.rows,
        'dirty_ranges': [
          {'start': 0, 'end': 1},
        ],
      });
      runtime.refreshSession(id);
      await _settleMetrics(tester);
      expect(
        runtime
            .viewportFor(id)
            .frame
            .rows
            .firstWhere((row) => row.index == 0)
            .text,
        'ordinary output after the display change',
      );
      expect(
        backend.metrics,
        hasLength(1),
        reason: 'Ordinary frames are not resizes.',
      );
      expect(events, hasLength(1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'DPR 1 to 2 to 1 before debounce never commits obsolete metrics',
    (tester) async {
      final backend = _Backend();
      final container = await _mount(tester, backend);
      final runtime = container.read(terminalRuntimeControllerProvider);
      final events = <TerminalSessionResizeEvent>[];
      final subscription = runtime.resizeEvents.listen(events.add);
      addTearDown(subscription.cancel);
      backend.metrics.clear();

      _setDpr(tester, 2);
      await tester.pump();
      _setDpr(tester, 1);
      await _settleMetrics(tester);

      expect(backend.metrics, isEmpty);
      expect(events, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'selection release cannot commit a queued resize from the previous DPR',
    (tester) async {
      final backend = _Backend();
      final container = await _mount(tester, backend);
      final id = container.read(sessionControllerProvider).activeSessionId!;
      final viewport = tester.widget<app_terminal.TerminalViewport>(
        _viewportFinder(id),
      );
      final before = backend.metrics.last;
      final events = <TerminalSessionResizeEvent>[];
      final subscription = container
          .read(terminalRuntimeControllerProvider)
          .resizeEvents
          .listen(events.add);
      addTearDown(subscription.cancel);
      backend.metrics.clear();
      viewport.selectionController.setSelection(
        const TerminalSelection(startRow: 0, startCol: 0, endRow: 0, endCol: 3),
      );

      _setDpr(tester, 2);
      await _settleMetrics(tester);
      expect(backend.metrics, isEmpty, reason: 'Selection holds the resize.');
      viewport.selectionController.clear();
      // The selection guard has queued the old DPR 2 post-frame commit. A new
      // metrics frame now supersedes it before that callback is allowed to run.
      _setDpr(tester, 3);
      await _settleMetrics(tester);

      expect(backend.metrics, hasLength(1));
      expect(backend.metrics.single.pixelWidth, before.pixelWidth * 3);
      expect(backend.metrics.single.pixelHeight, before.pixelHeight * 3);
      expect(events.map((event) => event.devicePixelRatio), [3]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final action in [
    TerminalActionId.closePane,
    TerminalActionId.closeActiveTab,
  ]) {
    testWidgets(
      'tab menu $action keeps its captured target after the original pane exits',
      (tester) async {
        final backend = _Backend();
        final container = await _mount(tester, backend);
        final controller = container.read(sessionControllerProvider.notifier);
        final original = container
            .read(sessionControllerProvider)
            .activeSessionId!;
        controller.splitActiveSession(
          defaultTerminalProfile(),
          TerminalSplitAxis.horizontal,
        );
        final survivor = container
            .read(sessionControllerProvider)
            .activeSessionId!;
        final tabId = container
            .read(sessionControllerProvider)
            .tabs
            .single
            .sessionId;
        controller.createSession(defaultTerminalProfile());
        final otherTab = container
            .read(sessionControllerProvider)
            .activeSessionId!;
        controller.activateSession(original);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(Key('shell-tab-$tabId')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        final menuItem = _menuAction(action);
        expect(menuItem, findsOneWidget);
        await tester.ensureVisible(menuItem);
        await tester.pumpAndSettle();

        backend.enqueueEvent(
          original,
          PtyEvent(
            kind: 'exit',
            sessionId: original,
            payload: const {'code': 0},
          ),
        );
        container
            .read(terminalRuntimeControllerProvider)
            .refreshSession(original);
        await tester.pumpAndSettle();
        final capturedTab = container
            .read(sessionControllerProvider)
            .tabs
            .singleWhere((tab) => tab.sessionId == tabId);
        expect(capturedTab.effectivePanes.map((pane) => pane.sessionId), [
          survivor,
        ]);
        expect(capturedTab.activeSessionId, survivor);
        expect(backend.closedSessionIds, contains(original));
        final writesBefore = backend.writes.length;

        await tester.tap(menuItem);
        await tester.pumpAndSettle();

        final remaining = container.read(sessionControllerProvider).tabs;
        expect(remaining.any((tab) => tab.containsSession(otherTab)), isTrue);
        if (action == TerminalActionId.closePane) {
          expect(
            remaining.any((tab) => tab.containsSession(survivor)),
            isTrue,
            reason: 'The menu did not authorize closing the replacement pane.',
          );
          expect(backend.closedSessionIds, isNot(contains(survivor)));
        } else {
          expect(
            remaining.any((tab) => tab.sessionId == tabId),
            isFalse,
            reason: 'Explicit close tab retains the original tab identity.',
          );
          expect(backend.closedSessionIds, contains(survivor));
        }
        expect(backend.writes.length, writesBefore);
        expect(backend.submissions, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'old tab mode menu cannot follow a pane moved into another tab',
    (tester) async {
      final backend = _Backend();
      final container = await _mount(tester, backend);
      final controller = container.read(sessionControllerProvider.notifier);
      final original = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      controller.splitActiveSession(
        defaultTerminalProfile(),
        TerminalSplitAxis.horizontal,
      );
      final survivor = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      final tabId = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .sessionId;
      controller.createSession(defaultTerminalProfile());
      final other = container.read(sessionControllerProvider).activeSessionId!;
      controller.activateSession(original);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('shell-tab-$tabId')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final oldModeItem = find.byKey(Key('terminal-mode-blocks-$original'));
      expect(oldModeItem, findsOneWidget);

      expect(
        controller.moveSessionToPane(
          sourceSessionId: original,
          targetSessionId: other,
          axis: TerminalSplitAxis.horizontal,
          before: true,
        ),
        isTrue,
      );
      await tester.pumpAndSettle();
      final stateBeforeAction = container.read(sessionControllerProvider);
      expect(
        stateBeforeAction.tabs
            .singleWhere((tab) => tab.containsSession(survivor))
            .effectivePanes
            .map((pane) => pane.sessionId),
        [survivor],
      );
      final movedPane = stateBeforeAction.tabs
          .singleWhere((tab) => tab.containsSession(original))
          .paneFor(original)!;
      expect(movedPane.terminalMode.mode, TerminalViewMode.normal);
      final writesBefore = backend.writes.length;

      await tester.tap(oldModeItem);
      await tester.pumpAndSettle();

      final stateAfterAction = container.read(sessionControllerProvider);
      expect(
        stateAfterAction.activeSessionId,
        stateBeforeAction.activeSessionId,
      );
      expect(
        stateAfterAction.tabs
            .singleWhere((tab) => tab.containsSession(original))
            .paneFor(original)!
            .terminalMode
            .mode,
        TerminalViewMode.normal,
      );
      expect(backend.closedSessionIds, isEmpty);
      expect(backend.writes.length, writesBefore);
      expect(backend.submissions, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final modeAction in [true, false]) {
    testWidgets(
      'old ${modeAction ? 'mode' : 'close tab'} menu cannot follow a detached root pane reusing the tab ID',
      (tester) async {
        final backend = _Backend();
        final container = await _mount(tester, backend);
        final controller = container.read(sessionControllerProvider.notifier);
        final original = container
            .read(sessionControllerProvider)
            .activeSessionId!;
        controller.splitActiveSession(
          defaultTerminalProfile(),
          TerminalSplitAxis.horizontal,
        );
        final survivor = container
            .read(sessionControllerProvider)
            .activeSessionId!;
        final tabId = container
            .read(sessionControllerProvider)
            .tabs
            .single
            .sessionId;
        controller.activateSession(original);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(Key('shell-tab-$tabId')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        final item = modeAction
            ? find.byKey(Key('terminal-mode-blocks-$original'))
            : _menuAction(TerminalActionId.closeActiveTab);
        await tester.ensureVisible(item);
        await tester.pumpAndSettle();

        expect(
          controller.detachPaneToTab(sessionId: original, insertionIndex: 0),
          isTrue,
        );
        await tester.pumpAndSettle();
        final detached = container.read(sessionControllerProvider);
        expect(detached.tabs, hasLength(2));
        expect(
          detached.tabs
              .singleWhere((tab) => tab.sessionId == tabId)
              .effectivePanes
              .map((pane) => pane.sessionId),
          [original],
        );
        expect(
          detached.tabs
              .singleWhere((tab) => tab.containsSession(survivor))
              .sessionId,
          isNot(tabId),
        );
        final writesBefore = backend.writes.length;

        await tester.tap(item);
        await tester.pumpAndSettle();

        final after = container.read(sessionControllerProvider);
        expect(
          after.tabs.map((tab) => tab.sessionId),
          detached.tabs.map((tab) => tab.sessionId),
        );
        expect(
          after.tabs
              .singleWhere((tab) => tab.containsSession(original))
              .paneFor(original)!
              .terminalMode
              .mode,
          TerminalViewMode.normal,
        );
        expect(backend.closedSessionIds, isEmpty);
        expect(backend.writes.length, writesBefore);
        expect(backend.submissions, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
