import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design/visual_capture_fonts.dart';
import '../support/fake_pty_backend.dart';
import '../support/memory_profile_repository.dart';
import 'shell_screen_phase1b_test.dart' as fixture;

const _evidence = String.fromEnvironment('HEADER_TABS_EVIDENCE_DIR');

Future<void> capture(WidgetTester tester, String name) async {
  if (_evidence.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find
        .ancestor(
          of: find.byKey(const Key('shell-chrome-bar')),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(_evidence).create(recursive: true);
    await File(
      '$_evidence/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [871.0, 640.0]) {
      testWidgets(
        'header tabs ${brightness.name} $width share Cmd and close slot',
        (tester) async {
          await tester.runAsync(
            () => loadVisualCaptureFonts(productionIcons: true),
          );
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 300);
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.platformDispatcher.clearAllTestValues);
          await fixture.pumpShellScreen(
            tester,
            fakeBindings: FakePtyBackend(),
            repository: MemoryProfileRepository(
              TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
            ),
            captureFonts: true,
          );
          await fixture.openNewShellTab(tester);
          await fixture.openNewShellTab(tester);
          final container = ProviderScope.containerOf(
            tester.element(find.byType(ShellScreen)),
          );
          final sessions = container.read(sessionControllerProvider.notifier);
          sessions.activateSession('2');
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('shell-tab-2')));
          await tester.pumpAndSettle();
          final active = find.byKey(const Key('shell-tab-close-2'));
          final inactive = find.byKey(const Key('shell-tab-close-1'));
          expect(active.hitTestable(), findsOneWidget);
          expect(inactive.hitTestable(), findsNothing);
          expect(find.byKey(const Key('shell-tab-shortcut-2')), findsNothing);
          final slot = find.byKey(const Key('shell-tab-action-slot-2'));
          final before = tester.getRect(slot);
          final titleBefore = tester.getRect(
            find.byKey(const Key('shell-tab-title-2')),
          );
          await capture(tester, '${brightness.name}-$width-default');
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: const Offset(0, 250));
          await mouse.moveTo(
            tester.getCenter(find.byKey(const Key('shell-tab-1'))),
          );
          await tester.pumpAndSettle();
          expect(inactive.hitTestable(), findsOneWidget);
          await capture(tester, '${brightness.name}-$width-hover');
          await tester.sendKeyDownEvent(
            LogicalKeyboardKey.metaLeft,
            platform: 'macos',
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('shell-tab-shortcut-2')), findsOneWidget);
          expect(active, findsNothing);
          expect(inactive, findsNothing);
          expect(tester.getRect(slot), before);
          expect(
            tester.getRect(find.byKey(const Key('shell-tab-title-2'))),
            titleBefore,
          );
          await capture(tester, '${brightness.name}-$width-cmd');
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('shell-tab-shortcut-2')), findsNothing);
          expect(active.hitTestable(), findsOneWidget);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pump();
          expect(find.byKey(const Key('shell-tab-shortcut-2')), findsOneWidget);
          // The visual observer must not consume the actual session shortcut.
          await tester.sendKeyEvent(
            LogicalKeyboardKey.digit1,
            platform: 'macos',
          );
          await tester.pumpAndSettle();
          expect(
            container.read(sessionControllerProvider).activeSessionId,
            '1',
          );
          await tester.sendKeyUpEvent(
            LogicalKeyboardKey.metaLeft,
            platform: 'macos',
          );
          await tester.pumpAndSettle();
          await mouse.moveTo(const Offset(0, 250));
          await tester.pumpAndSettle();
          expect(inactive.hitTestable(), findsOneWidget); // now active
          expect(active.hitTestable(), findsNothing);
          await tester.sendKeyDownEvent(
            LogicalKeyboardKey.metaRight,
            platform: 'macos',
          );
          await tester.pump();
          expect(find.byKey(const Key('shell-tab-shortcut-1')), findsOneWidget);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          expect(find.byKey(const Key('shell-tab-shortcut-1')), findsNothing);
          await tester.sendKeyUpEvent(
            LogicalKeyboardKey.metaRight,
            platform: 'macos',
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          await tester.tap(inactive);
          await tester.pumpAndSettle();
          expect(container.read(sessionControllerProvider).tabs.length, 2);
          expect(
            container
                .read(sessionControllerProvider)
                .tabs
                .any((tab) => tab.sessionId == '1'),
            isFalse,
          );
          await mouse.removePointer();
          // Overflow keeps hidden tabs reachable in a narrow window.
          for (var i = 0; i < 5; i++) {
            await fixture.openNewShellTab(tester);
          }
          await capture(tester, '${brightness.name}-$width-overflow');
          expect(
            find.byKey(const Key('shell-tab-overflow-button')),
            findsOneWidget,
          );
          if (width == 640) {
            tester.view.physicalSize = const Size(520, 300);
            tester.platformDispatcher.textScaleFactorTestValue = 2;
            await tester.pumpAndSettle();
            await tester.sendKeyDownEvent(
              LogicalKeyboardKey.metaLeft,
              platform: 'macos',
            );
            await tester.pumpAndSettle();
            final shortcut = find.byKey(const Key('shell-tab-shortcut-2'));
            final slot = find.byKey(const Key('shell-tab-action-slot-2'));
            expect(shortcut, findsOneWidget);
            expect(
              tester.getSize(shortcut).width,
              lessThanOrEqualTo(tester.getSize(slot).width),
            );
            await capture(tester, '${brightness.name}-520-scaled-cmd');
            await tester.sendKeyUpEvent(
              LogicalKeyboardKey.metaLeft,
              platform: 'macos',
            );
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }
  }
}
