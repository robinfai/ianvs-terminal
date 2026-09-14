import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_ports.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';
import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';
import '../support/no_io_local_terminal_layout_repository.dart';

void main() {
  group('$ShellScreen live titles', () {
    testWidgets(
      'updates tab, pane and window titles without rebuilding the desktop body',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final backend = FakePtyBackend();
        final titles = <String>[];
        final profile = defaultTerminalProfile();
        await tester.pumpApp(
          ProviderScope(
            overrides: [
              ptySessionBackendProvider.overrideWithValue(backend),
              sessionPollingEnabledProvider.overrideWithValue(false),
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
              sessionWindowTitleWriterProvider.overrideWithValue((title) async {
                titles.add(title);
              }),
              shellAnimationsEnabledProvider.overrideWithValue(false),
            ],
            child: const ShellScreen(),
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ShellScreen)),
        );
        final controller = container.read(sessionControllerProvider.notifier);
        final root = container.read(sessionControllerProvider).activeSessionId!;
        controller.splitSession(root, profile, TerminalSplitAxis.horizontal);
        await tester.pumpAndSettle();
        final active = container
            .read(sessionControllerProvider)
            .activeSessionId!;

        Future<void> updateTitle(String id, String title) async {
          backend.setFrame(id, {
            'rows': [
              {
                'index': 0,
                'text': 'sparkles remain visible',
                'style_runs': const <Object?>[],
              },
            ],
            'cursor': {'row': 0, 'col': 0, 'visible': false},
            'viewport_rows': 24,
            'viewport_cols': 80,
            'dirty_ranges': [
              {'start': 0, 'end': 1},
            ],
            'window_title': title,
          });
          container.read(terminalRuntimeControllerProvider).refreshSession(id);
          await tester.pump();
          await tester.pump();
        }

        // Warm up content/layout before isolating subsequent title changes.
        await updateTitle(active, 'Title warmup');
        await tester.pumpAndSettle();
        final paneFinder = find.byKey(Key('shell-pane-$active'));
        final body = tester.widget(paneFinder);
        final viewport = controller.viewportFor(active);
        for (final title in ['Codex star 1', 'Codex star 2']) {
          await updateTitle(active, title);
          expect(find.text(title), findsWidgets);
          expect(titles.last, title);
          expect(tester.widget(paneFinder), same(body));
          expect(controller.viewportFor(active), same(viewport));
        }
        await updateTitle(root, 'Background title');
        expect(find.text('Background title'), findsWidgets);
        expect(titles.last, 'Codex star 2');
        await updateTitle(active, '');
        expect(
          container
              .read(sessionControllerProvider)
              .tabs
              .single
              .paneFor(active)!
              .title,
          profile.name,
        );
        expect(titles.last, profile.name);
        controller.activateSession(root);
        await tester.pumpAndSettle();
        expect(titles.last, 'Background title');
        expect(tester.widget(paneFinder), isNot(same(body)));
        controller.createSession(profile);
        await tester.pumpAndSettle();
        expect(container.read(sessionControllerProvider).tabs, hasLength(2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
}
