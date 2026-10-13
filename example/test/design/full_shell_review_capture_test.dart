import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_acceptance.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/ssh/ssh_feature_access.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
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
import 'ui_review_capture.dart';
import 'visual_capture_fonts.dart';

class _ReviewBackend extends FakePtyBackend {
  @override
  PtyRuntimeCapabilities get runtimeCapabilities =>
      PtyRuntimeCapabilities.fromJson({
        'schema_version': 1,
        'runtime_contract': 'ianvs-runtime-contract-v1',
        'frame_schema_versions': <String>[],
        'recording_schema_versions': <int>[],
        'features': ['session-config.json.v1', 'ssh-session.v1'],
      });
}

class _ReviewRecordings extends LocalSessionRecordingRepository
    with NoIoLocalSessionRecordingRecovery {
  _ReviewRecordings()
    : super(
        directoryResolver: () => throw StateError('No file I/O in UI fixture'),
      );
  @override
  Future<List<LocalSessionRecordingEntry>> listRecordings() async => [
    LocalSessionRecordingEntry(
      path: '/review/deploy.trail',
      displayName: '生产部署 · production',
      createdAtUtc: DateTime.utc(2026, 10, 13, 8),
      duration: const Duration(minutes: 2),
      fileSizeBytes: 32768,
    ),
    LocalSessionRecordingEntry(
      path: '/review/diagnostics.trail',
      displayName: '连接诊断',
      createdAtUtc: DateTime.utc(2026, 10, 12, 8),
      duration: const Duration(seconds: 48),
      fileSizeBytes: 8192,
    ),
  ];
}

final GlobalKey _captureBoundary = GlobalKey();

Future<void> _pumpShell(
  WidgetTester tester, {
  required TargetPlatform platform,
  required Brightness brightness,
  required Size size,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final defaultProfile = defaultTerminalProfile();
  final local = defaultProfile.copyWith(
    appearance: defaultProfile.appearance.copyWith(
      font: defaultProfile.appearance.font.copyWith(
        family: visualCaptureMonoFont,
        fallback: visualCaptureFontFallback,
      ),
    ),
    tags: const <String>['local', 'login'],
  );
  final ssh = TerminalProfile(
    id: 'ssh-capture',
    name: 'Production SSH',
    shell: '/usr/bin/ssh',
    connection: const terminal.TerminalConnectionConfig.ssh(
      host: 'prod.example.com',
      user: 'deploy',
      port: 22,
      auth: terminal.TerminalSshAuthMethod.password,
    ),
    tags: const <String>['remote', 'ops'],
  );
  final baseTheme = buildIanvsTerminalTheme(brightness, platform: platform);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shellAcceptanceProbeProvider.overrideWithValue(shellAcceptanceProbe),
        customSshProfileConfigurationEnabledProvider.overrideWithValue(true),
        ptySessionBackendProvider.overrideWithValue(_ReviewBackend()),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(profiles: <TerminalProfile>[local, ssh]),
          ),
        ),
        pasteHistoryRepositoryProvider.overrideWithValue(
          MemoryPasteHistoryRepository(),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(
            const TerminalAppPreferencesDocument(
              appearance: TerminalAppAppearance(
                themeMode: TerminalThemeMode.dark,
              ),
            ),
          ),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          MemoryLocalTerminalConfigRepository(null),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          _ReviewRecordings(),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          noIoLocalTerminalLayoutRepository(),
        ),
      ],
      child: RepaintBoundary(
        key: _captureBoundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: withVisualCaptureFonts(baseTheme),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ShellScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  ConfigurationCaptureBinding();
  setUpAll(loadVisualCaptureFonts);
  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    for (final brightness in Brightness.values) {
      for (final landscape in [false, true]) {
        if (platform == TargetPlatform.macOS && landscape) continue;
        for (final scene in ['home', 'menu', 'recordings', 'profiles']) {
          testWidgets(
            'shell review ${platform.name} ${brightness.name} $landscape $scene',
            (tester) async {
              await _pumpShell(
                tester,
                platform: platform,
                brightness: brightness,
                size: platform == TargetPlatform.macOS
                    ? const Size(1280, 900)
                    : landscape
                    ? const Size(874, 402)
                    : const Size(402, 874),
              );
              if (scene != 'home') {
                final mobile = platform == TargetPlatform.iOS;
                if (mobile && scene == 'menu') {
                  // Seed a connected fake runtime; no credential prompt or real
                  // SSH connection is part of this presentation fixture.
                  final container = ProviderScope.containerOf(
                    tester.element(find.byType(ShellScreen)),
                  );
                  final sessionId = container
                      .read(sessionControllerProvider.notifier)
                      .createSession(
                        defaultTerminalProfile().copyWith(
                          id: 'review-live',
                          name: 'Production SSH',
                          connection:
                              const terminal.TerminalConnectionConfig.ssh(
                                host: 'prod.example.com',
                                user: 'deploy',
                              ),
                        ),
                      );
                  for (var frame = 0; frame < 8; frame++) {
                    await tester.pump(const Duration(milliseconds: 100));
                  }
                  expect(
                    sessionId,
                    isNotNull,
                    reason: container.read(sessionControllerProvider).lastError,
                  );
                  final row = find.byKey(Key('mobile-session-$sessionId'));
                  if (row.evaluate().isNotEmpty) {
                    await tester.tap(row);
                    await tester.pumpAndSettle();
                  }
                }
                if (!mobile || scene == 'menu') {
                  final menu = find
                      .byKey(const Key('shell-chrome-menu'))
                      .hitTestable();
                  expect(menu, findsOneWidget);
                  await tester.tap(menu);
                  await tester.pumpAndSettle();
                }
                if (scene == 'recordings' || scene == 'profiles') {
                  final key = scene == 'recordings'
                      ? 'shell-open-recording'
                      : mobile
                      ? 'mobile-manage-connections'
                      : 'shell-command-profiles';
                  final action = find.byKey(Key(key));
                  await tester.ensureVisible(action);
                  await tester.tap(action.hitTestable());
                  await tester.pumpAndSettle();
                  if (scene == 'recordings') {
                    expect(
                      find.byKey(const Key('saved-recordings-shelf')),
                      findsOneWidget,
                    );
                  }
                }
              }
              expect(tester.takeException(), isNull);
              await captureUiReview(
                tester,
                _captureBoundary,
                '${platform.name}-${brightness.name}-${landscape ? 'landscape' : 'portrait'}-shell-$scene',
              );
              await tester.pumpWidget(const SizedBox.shrink());
            },
            variant: TargetPlatformVariant.only(platform),
          );
        }
      }
    }
  }
}
