import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_profile_repository.dart';
import 'shell_screen_phase1a_test.dart' show pumpShellScreen;

void main() {
  testWidgets(
    'sidebar replaces tabs and preserves the live terminal and grouping',
    (tester) async {
      final backend = FakePtyBackend();
      await pumpShellScreen(
        tester,
        fakeBindings: backend,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final id = container.read(sessionControllerProvider).activeSessionId!;
      final terminal = tester.element(
        find.byKey(const Key('shell-terminal-surface')),
      );
      expect(find.byKey(const Key('session-sidebar')), findsNothing);
      await tester.tap(find.byKey(const Key('shell-toggle-sidebar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shell-tab-strip')), findsNothing);
      expect(find.text('Directory'), findsOneWidget);
      final sidebarBounds = tester.getRect(
        find.byKey(const Key('session-sidebar')),
      );
      final rowBounds = tester.getRect(
        find.byKey(ValueKey('sidebar-session-$id')),
      );
      expect(rowBounds.left - sidebarBounds.left, 12);
      expect(sidebarBounds.right - rowBounds.right, 12);
      expect(rowBounds.height, 32);
      expect(
        tester.getSize(find.byKey(const Key('shell-toggle-sidebar'))).height,
        28,
      );
      expect(
        tester.getSize(find.byKey(const Key('session-sidebar-header'))).height,
        lessThanOrEqualTo(42),
      );

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.semanticsLabel == 'Unknown directory',
        ),
        findsOneWidget,
      );
      expect(
        tester.element(find.byKey(const Key('shell-terminal-surface'))),
        same(terminal),
      );

      backend.enqueueEvent(
        id,
        PtyEvent(
          sessionId: id,
          kind: 'shell_context',
          payload: <String, Object?>{'source': 'osc7', 'cwd': '/work/project'},
        ),
      );
      container.read(terminalRuntimeControllerProvider).refreshSession(id);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.semanticsLabel == '/work/project',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.semanticsLabel == 'Unknown directory',
        ),
        findsNothing,
      );
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.semanticsLabel == '/work/project',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('sidebar-session-$id')), findsNothing);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.semanticsLabel == '/work/project',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('sidebar-session-$id')), findsOneWidget);

      await tester.tap(find.byKey(const Key('shell-toggle-sidebar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shell-tab-strip')), findsOneWidget);
      expect(
        tester.element(find.byKey(const Key('shell-terminal-surface'))),
        same(terminal),
      );
      expect(container.read(sessionControllerProvider).activeSessionId, id);
      expect(backend.closedSessionIds, isEmpty);
      await tester.tap(find.byKey(const Key('shell-toggle-sidebar')));
      await tester.pumpAndSettle();
      expect(find.text('Sessions'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('directory branches select and close the correct session', (
    tester,
  ) async {
    final backend = FakePtyBackend();
    await pumpShellScreen(
      tester,
      fakeBindings: backend,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final controller = container.read(sessionControllerProvider.notifier);
    final first = container.read(sessionControllerProvider).activeSessionId!;
    controller.createSession(defaultTerminalProfile());
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
    await tester.tap(find.byKey(const Key('shell-toggle-sidebar')));
    await tester.pumpAndSettle();
    expect(find.text('/work'), findsOneWidget);
    expect(find.text('api'), findsOneWidget);
    expect(find.text('web'), findsOneWidget);
    final firstRow = find.byKey(ValueKey('sidebar-session-$first'));
    await tester.tap(firstRow);
    await tester.pumpAndSettle();
    expect(container.read(sessionControllerProvider).activeSessionId, first);
    final close = find.byKey(ValueKey('sidebar-close-$first'));
    expect(close.hitTestable(), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(firstRow));
    await tester.pumpAndSettle();
    expect(close.hitTestable(), findsOneWidget);
    expect(tester.getSize(close), const Size.square(24));
    expect(tester.getCenter(close).dy, tester.getCenter(firstRow).dy);
    expect(
      tester.getCenter(find.byKey(ValueKey('sidebar-close-glyph-$first'))),
      tester.getCenter(close),
    );
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(close.hitTestable(), findsNothing);
    await mouse.moveTo(tester.getCenter(firstRow));
    await tester.pumpAndSettle();
    await tester.tap(close);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(backend.closedSessionIds, contains(first));
    expect(find.byKey(ValueKey('sidebar-session-$second')), findsOneWidget);
    expect(container.read(sessionControllerProvider).activeSessionId, second);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar supports dark theme, larger text and narrow windows', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.binding.setSurfaceSize(const Size(640, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );
    await tester.tap(find.byKey(const Key('shell-toggle-sidebar')));
    await tester.pumpAndSettle();
    expect(find.text('Sessions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'same command groups directories and follows execution and buffer state',
    (tester) async {
      var now = DateTime(2026, 9, 15, 12);
      final backend = FakePtyBackend();
      await pumpShellScreen(
        tester,
        fakeBindings: backend,
        commandClock: () => now,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final first = container.read(sessionControllerProvider).activeSessionId!;
      container
          .read(sessionControllerProvider.notifier)
          .createSession(defaultTerminalProfile());
      await tester.pumpAndSettle();
      final second = container.read(sessionControllerProvider).activeSessionId!;
      final runtime = container.read(terminalRuntimeControllerProvider);
      for (final entry in {first: '/work/api', second: '/work/web'}.entries) {
        backend.enqueueEvent(
          entry.key,
          PtyEvent(
            sessionId: entry.key,
            kind: 'shell_context',
            payload: {'source': 'osc7', 'cwd': entry.value},
          ),
        );
        backend.enqueueEvent(
          entry.key,
          PtyEvent(
            sessionId: entry.key,
            kind: 'shell_command',
            payload: {
              'source': 'osc133',
              'eventType': 'command_executed',
              'command': 'npm run dev',
            },
          ),
        );
        runtime.refreshSession(entry.key);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shell-toggle-sidebar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('session-group-running')), findsNothing);
      now = now.add(const Duration(seconds: 11));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('npm run dev'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.semanticsLabel == '/work/api',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.semanticsLabel == '/work/web',
        ),
        findsOneWidget,
      );
      expect(find.text('11s'), findsNWidgets(2));
      for (final entry in {first: 'api', second: 'web'}.entries) {
        final path =
            '/tmp/trail-unified-sidebar/very-long-common-parent/${entry.value}';
        backend.enqueueEvent(
          entry.key,
          PtyEvent(
            sessionId: entry.key,
            kind: 'shell_context',
            payload: {'source': 'osc7', 'cwd': path},
          ),
        );
        runtime.refreshSession(entry.key);
      }
      await tester.pumpAndSettle();
      for (final suffix in ['api', 'web']) {
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data != null &&
                widget.data!.startsWith('/') &&
                widget.data!.contains('…') &&
                widget.data!.endsWith('/$suffix') &&
                widget.semanticsLabel ==
                    '/tmp/trail-unified-sidebar/very-long-common-parent/$suffix',
          ),
          findsOneWidget,
        );
      }

      expect(
        find.byKey(const ValueKey('session-group-directory')),
        findsNothing,
      );
      final viewport = runtime.viewportFor(first);
      backend.setFrame(first, {
        'rows': [],
        'modes': {'alternate_screen': true},
      });
      runtime.refreshSession(first);
      await tester.pumpAndSettle();
      expect(viewport.frame.modes.alternateScreen, isTrue);
      expect(
        find.byKey(const ValueKey('session-group-interactive')),
        findsOneWidget,
      );
      expect(find.text('npm run dev'), findsNWidgets(2));
      expect(find.byKey(ValueKey('sidebar-session-$first')), findsOneWidget);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('session-group-interactive')))
            .dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('session-group-running')))
              .dy,
        ),
      );
      backend.setFrame(first, {
        'rows': [],
        'modes': {'alternate_screen': false},
      });
      backend.enqueueEvent(
        first,
        PtyEvent(
          sessionId: first,
          kind: 'shell_command',
          payload: {
            'source': 'osc133',
            'eventType': 'command_finished',
            'exitCode': 0,
          },
        ),
      );
      runtime.refreshSession(first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('session-group-interactive')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-group-directory')),
        findsOneWidget,
      );
      expect(find.text('npm run dev'), findsOneWidget);
      expect(
        container
            .read(sessionControllerProvider)
            .tabs
            .first
            .activePane
            .shellIntegration
            .commandStartedAt,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
