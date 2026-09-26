import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';
import '../support/no_io_local_terminal_layout_repository.dart';
import 'configuration_capture_binding.dart';
import 'visual_capture_fonts.dart';

const _captureKey = Key('session-chrome-review');
const _enabled = bool.fromEnvironment('TRAIL_CHROME_CAPTURE');

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory = Directory(
      '../output/design/trail-implementation-20260926',
    );
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  if (_enabled) ConfigurationCaptureBinding();
  testWidgets(
    'capture implemented tab chrome in light, hover and narrow dark states',
    (tester) async {
      await tester.runAsync(loadVisualCaptureFonts);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(864, 1084);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final backend = FakePtyBackend();
      final baseProfile = defaultTerminalProfile();
      final profile = baseProfile.copyWith(
        appearance: baseProfile.appearance.copyWith(
          font: baseProfile.appearance.font.copyWith(
            family: visualCaptureMonoFont,
            fallback: visualCaptureFontFallback,
          ),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ptySessionBackendProvider.overrideWithValue(backend),
            profileRepositoryProvider.overrideWithValue(
              MemoryProfileRepository(
                TerminalProfilesDocument(profiles: [profile]),
              ),
            ),
            appPreferencesRepositoryProvider.overrideWithValue(
              MemoryAppPreferencesRepository(null),
            ),
            localTerminalConfigRepositoryProvider.overrideWithValue(
              MemoryLocalTerminalConfigRepository(null),
            ),
            pasteHistoryRepositoryProvider.overrideWithValue(
              MemoryPasteHistoryRepository(),
            ),
            localTerminalLayoutRepositoryProvider.overrideWithValue(
              noIoLocalTerminalLayoutRepository(),
            ),
            localSessionRecordingRepositoryProvider.overrideWithValue(
              noIoLocalSessionRecordingRepository(),
            ),
          ],
          child: RepaintBoundary(
            key: _captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: withVisualCaptureFonts(
                buildIanvsTerminalTheme(Brightness.light),
              ),
              darkTheme: withVisualCaptureFonts(
                buildIanvsTerminalTheme(Brightness.dark),
              ),
              home: const ShellScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      final controller = container.read(sessionControllerProvider.notifier);
      final first = container.read(sessionControllerProvider).activeSessionId!;
      controller.createSession(profile);
      await tester.pumpAndSettle();
      final second = container.read(sessionControllerProvider).activeSessionId!;
      for (final entry in {
        first: '/Users/robinfai',
        second: '/work/records',
      }.entries) {
        backend.setFrame(entry.key, {
          'rows': [
            {
              'index': 0,
              'text': 'robinfai@MacBook  ~  > git status',
              'style_runs': <Object?>[],
            },
            {'index': 1, 'text': 'On branch main', 'style_runs': <Object?>[]},
            {
              'index': 2,
              'text': 'nothing to commit, working tree clean',
              'style_runs': <Object?>[],
            },
          ],
          'cursor': {'row': 4, 'col': 0, 'visible': false},
          'viewport_rows': 24,
          'viewport_cols': 80,
          'window_title': entry.key == first
              ? 'lighthouse@VM-4-2-ubuntu: ~'
              : 'Local Shell',
          'modes': {'bracketed_paste': true, 'mouse_mode': 'normal'},
          'dirty_ranges': [
            {'start': 0, 'end': 3},
          ],
        });
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
      controller.activateSession(first);
      await tester.pumpAndSettle();
      await _capture(tester, 'top-tabs-light');
      await tester.tap(find.byKey(const Key('shell-toggle-sidebar')));
      await tester.pumpAndSettle();
      await _capture(tester, 'sidebar-light');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(700, 100));
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(const Key('session-sidebar-resize-handle')),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, 'sidebar-hover');
      await mouse.removePointer();
      await tester.drag(
        find.byKey(const Key('session-sidebar-resize-handle')),
        const Offset(-1000, 0),
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      tester.view.physicalSize = const Size(640, 600);
      await tester.pumpAndSettle();
      await _capture(tester, 'sidebar-dark-minimum-large-text');
      expect(tester.takeException(), isNull);
    },
    skip: !_enabled,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
