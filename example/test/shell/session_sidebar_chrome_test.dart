import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_profile_repository.dart';
import 'shell_screen_phase1a_test.dart' show pumpShellScreen;

const _sidebar = Key('session-sidebar');
const _handle = Key('session-sidebar-resize-handle');
const _divider = Key('session-sidebar-divider');
const _toggle = Key('shell-toggle-sidebar');
const _gear = Key('shell-chrome-menu');

Future<void> _pump(WidgetTester tester, FakePtyBackend backend) async {
  await tester.binding.setSurfaceSize(const Size(1200, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await pumpShellScreen(
    tester,
    fakeBindings: backend,
    repository: MemoryProfileRepository(
      TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
    ),
  );
}

double _width(WidgetTester tester) =>
    tester.getSize(find.byKey(_sidebar)).width;
double _lineOpacity(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byKey(_divider)).opacity;

void _expectCenteredTitle(WidgetTester tester) {
  final toggle = tester.getCenter(find.byKey(_toggle));
  final gear = tester.getCenter(find.byKey(_gear));
  final title = tester.getCenter(
    find.byKey(const Key('shell-chrome-window-title')),
  );
  expect(title.dx, closeTo((toggle.dx + gear.dx) / 2, 0.1));
  expect(toggle.dy, gear.dy);
  expect(title.dy, closeTo(gear.dy, 0.1));
}

void main() {
  testWidgets(
    'sidebar resizing clamps, preserves width and keeps the terminal alive',
    (tester) async {
      final backend = FakePtyBackend();
      final nativeLayouts = <Object?>[];
      const channel = MethodChannel('app/window_bridge');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'setTitleBarLayout') {
          nativeLayouts.add(call.arguments);
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await _pump(tester, backend);
      final terminal = tester.element(
        find.byKey(const Key('shell-terminal-surface')),
      );
      expect(
        tester.widget<AppTabLayoutIcon>(find.byType(AppTabLayoutIcon)).layout,
        AppTabLayout.sidebar,
      );
      expect(find.byTooltip('Switch to sidebar tabs'), findsOneWidget);
      _expectCenteredTitle(tester);
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(_width(tester), 280);
      expect(
        tester.widget<AppTabLayoutIcon>(find.byType(AppTabLayoutIcon)).layout,
        AppTabLayout.top,
      );
      expect(find.byTooltip('Switch to top tabs'), findsOneWidget);
      expect(find.byKey(const Key('shell-toolbar-settings')), findsNothing);
      expect(find.byKey(const Key('shell-toolbar-search')), findsNothing);
      expect(find.byKey(const Key('shell-toolbar-replay')), findsNothing);
      expect(tester.getRect(find.byKey(_gear)).right, lessThan(_width(tester)));
      _expectCenteredTitle(tester);
      await tester.drag(find.byKey(_handle), const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(_width(tester), 380);
      await tester.drag(find.byKey(_handle), const Offset(1000, 0));
      await tester.pumpAndSettle();
      expect(_width(tester), 480);
      await tester.drag(find.byKey(_handle), const Offset(-1000, 0));
      await tester.pumpAndSettle();
      expect(_width(tester), 240);
      await tester.drag(find.byKey(_handle), const Offset(160, 0));
      await tester.pumpAndSettle();
      expect(_width(tester), 400);
      _expectCenteredTitle(tester);
      expect(
        tester
            .getSize(find.byKey(const Key('shell-chrome-title-surface')))
            .width,
        400,
      );
      expect(nativeLayouts.last, {'sidebarWidth': 400.0});
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(find.byKey(_handle), findsNothing);
      expect(nativeLayouts.last, {'sidebarWidth': null});
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(_width(tester), 400);
      await tester.binding.setSurfaceSize(const Size(640, 700));
      await tester.pumpAndSettle();
      expect(_width(tester), 288);
      _expectCenteredTitle(tester);
      await tester.binding.setSurfaceSize(const Size(1200, 700));
      await tester.pumpAndSettle();
      expect(_width(tester), 400);
      expect(
        tester.element(find.byKey(const Key('shell-terminal-surface'))),
        same(terminal),
      );
      expect(backend.closedSessionIds, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'divider appears on hover or drag and supports keyboard resizing',
    (tester) async {
      await _pump(tester, FakePtyBackend());
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(_lineOpacity(tester), 0);
      expect(tester.getSize(find.byKey(_handle)).width, 8);
      expect(tester.getTopLeft(find.byKey(_handle)).dy, 0);
      expect(
        tester.widget<MouseRegion>(find.byKey(_handle)).cursor,
        SystemMouseCursors.resizeLeftRight,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(700, 100));
      await mouse.moveTo(tester.getCenter(find.byKey(_handle)));
      await tester.pumpAndSettle();
      expect(_lineOpacity(tester), 1);
      await mouse.down(tester.getCenter(find.byKey(_handle)));
      await mouse.moveBy(const Offset(40, 0));
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(500, -20));
      await tester.pumpAndSettle();
      expect(
        _lineOpacity(tester),
        1,
        reason: 'The drag stays visible outside its hover target.',
      );
      await mouse.cancel();
      await tester.pumpAndSettle();
      expect(_lineOpacity(tester), 0);
      await mouse.removePointer();
      final focus = tester
          .widget<Focus>(find.byKey(const Key('session-sidebar-resize-focus')))
          .focusNode!;
      focus.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(_width(tester), 240);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_width(tester), 250);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(_width(tester), 480);
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'only the active directory branch uses accent folder and text colors',
    (tester) async {
      final backend = FakePtyBackend();
      await _pump(tester, backend);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final first = container.read(sessionControllerProvider).activeSessionId!;
      container
          .read(sessionControllerProvider.notifier)
          .createSession(defaultTerminalProfile());
      await tester.pumpAndSettle();
      final second = container.read(sessionControllerProvider).activeSessionId!;
      for (final entry in {first: '/work/api', second: '/work/web'}.entries) {
        backend.enqueueEvent(
          entry.key,
          PtyEvent(
            sessionId: entry.key,
            kind: 'shell_context',
            payload: {'source': 'osc7', 'cwd': entry.value},
          ),
        );
        container
            .read(terminalRuntimeControllerProvider)
            .refreshSession(entry.key);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      final context = tester.element(find.byKey(_sidebar));
      final accent = context.appTheme.accent;
      final normal = Theme.of(context).colorScheme.onSurface;
      void expectBranch(String name, Color color) {
        final label = find.byWidgetPredicate(
          (widget) => widget is Text && widget.semanticsLabel == name,
        );
        final tile = find
            .ancestor(of: label, matching: find.byType(ListTile))
            .first;
        expect(tester.widget<Text>(label).style!.color, color);
        final folder = find.descendant(
          of: tile,
          matching: find.byIcon(Icons.folder_outlined),
        );
        expect(tester.widget<Icon>(folder).color, color);
      }

      expectBranch('api', normal);
      expectBranch('web', accent);
      await tester.tap(find.byKey(ValueKey('sidebar-session-$first')));
      await tester.pumpAndSettle();
      expectBranch('api', accent);
      expectBranch('web', normal);
      expect(tester.takeException(), isNull);
    },
  );
}
