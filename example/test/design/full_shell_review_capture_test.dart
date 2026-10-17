import 'dart:async';

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_ports.dart';
import 'package:app/features/shell/shell_acceptance.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/ssh/ssh_feature_access.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  _ReviewRecordings(this.scene)
    : super(
        directoryResolver: () => throw StateError('No file I/O in UI fixture'),
      );
  final String scene;
  @override
  Future<List<LocalSessionRecordingEntry>> listRecordings() async {
    if (scene == 'recordings-empty') return [];
    if (scene == 'recordings-error') throw StateError('录屏目录暂时不可用');
    return [
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
}

final GlobalKey _captureBoundary = GlobalKey();

Future<_ReviewBackend> _pumpShell(
  WidgetTester tester, {
  required TargetPlatform platform,
  required Brightness brightness,
  required Size size,
  required String scene,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final backend = _ReviewBackend();
  if (scene == 'home-error') backend.failingOperations.add('createSession');
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
        ptySessionBackendProvider.overrideWithValue(backend),
        sessionClipboardPasteProvider.overrideWithValue(() async => '测试剪贴板内容'),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(
              profiles: scene == 'home-empty'
                  ? <TerminalProfile>[]
                  : <TerminalProfile>[local, ssh],
            ),
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
          MemoryLocalTerminalConfigRepository(
            const LocalTerminalConfigDocument(
              clipboard: LocalTerminalClipboardConfig(
                osc52: LocalTerminalOsc52Policy.ask,
              ),
            ),
          ),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          _ReviewRecordings(scene),
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
  return backend;
}

void main() {
  ConfigurationCaptureBinding();
  setUpAll(loadVisualCaptureFonts);
  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    for (final brightness in Brightness.values) {
      for (final landscape in [false, true]) {
        if (platform == TargetPlatform.macOS && landscape) continue;
        for (final scene in [
          'home',
          'home-empty',
          'home-error',
          'menu',
          'recordings',
          'profiles',
          'recordings-empty',
          'recordings-error',
          'url-confirm',
          'report-confirm',
          'clipboard-confirm',
          'search',
          'paste-confirm',
        ]) {
          testWidgets(
            'shell review ${platform.name} ${brightness.name} $landscape $scene',
            (tester) async {
              final backend = await _pumpShell(
                tester,
                platform: platform,
                scene: scene,
                brightness: brightness,
                size: platform == TargetPlatform.macOS
                    ? const Size(1280, 900)
                    : landscape
                    ? const Size(874, 402)
                    : const Size(402, 874),
              );
              if (scene == 'home-error' && platform == TargetPlatform.iOS) {
                await tester.tap(
                  find.byKey(const Key('ios-ssh-empty-profile-ssh-capture')),
                );
                await tester.pumpAndSettle();
                expect(
                  ProviderScope.containerOf(
                    tester.element(find.byType(ShellScreen)),
                  ).read(sessionControllerProvider).lastError,
                  isNotNull,
                );
              }
              final live = [
                'url-confirm',
                'report-confirm',
                'clipboard-confirm',
                'search',
                'paste-confirm',
              ].contains(scene);
              if (scene != 'home') {
                final mobile = platform == TargetPlatform.iOS;
                if (mobile && (scene == 'menu' || live)) {
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
                if (!live && (!mobile || scene == 'menu')) {
                  final menu = find
                      .byKey(const Key('shell-chrome-menu'))
                      .hitTestable();
                  expect(menu, findsOneWidget);
                  await tester.tap(menu);
                  await tester.pumpAndSettle();
                }
                if (scene.startsWith('recordings') || scene == 'profiles') {
                  final key = scene.startsWith('recordings')
                      ? 'shell-open-recording'
                      : mobile
                      ? 'mobile-manage-connections'
                      : 'shell-command-profiles';
                  final action = find.byKey(Key(key));
                  await tester.ensureVisible(action);
                  await tester.tap(action.hitTestable());
                  await tester.pumpAndSettle();
                  if (scene.startsWith('recordings')) {
                    expect(
                      find.byKey(const Key('saved-recordings-shelf')),
                      findsOneWidget,
                    );
                  }
                }
              }
              if (live) {
                final container = ProviderScope.containerOf(
                  tester.element(find.byType(ShellScreen)),
                );
                final id = container
                    .read(sessionControllerProvider)
                    .activeSessionId!;
                if (scene.endsWith('-confirm') && scene != 'paste-confirm') {
                  final kind = switch (scene) {
                    'url-confirm' => 'open_url_request',
                    'report-confirm' => 'report_variable_request',
                    _ => 'clipboard_paste_request',
                  };
                  backend.enqueueEvent(
                    id,
                    PtyEvent(
                      kind: kind,
                      sessionId: id,
                      payload: {
                        if (scene == 'url-confirm') ...{
                          'source': 'iterm1337',
                          'url': 'https://example.test/review',
                        },
                        if (scene == 'report-confirm') ...{
                          'source': 'iterm1337',
                          'name': 'session.path',
                          'value': '/review',
                        },
                        if (scene == 'clipboard-confirm') 'selection': 'c',
                      },
                    ),
                  );
                  container
                      .read(terminalRuntimeControllerProvider)
                      .refreshSession(id);
                } else if (scene == 'search') {
                  await tester.sendKeyDownEvent(
                    LogicalKeyboardKey.metaLeft,
                    platform: platform == TargetPlatform.iOS ? 'ios' : 'macos',
                  );
                  await tester.sendKeyEvent(
                    LogicalKeyboardKey.keyF,
                    platform: platform == TargetPlatform.iOS ? 'ios' : 'macos',
                  );
                  await tester.sendKeyUpEvent(
                    LogicalKeyboardKey.metaLeft,
                    platform: platform == TargetPlatform.iOS ? 'ios' : 'macos',
                  );
                } else {
                  tester.binding.defaultBinaryMessenger
                      .setMockMethodCallHandler(
                        SystemChannels.platform,
                        (call) async => call.method == 'Clipboard.getData'
                            ? {'text': '第一行\n第二行'}
                            : null,
                      );
                  addTearDown(
                    () => tester.binding.defaultBinaryMessenger
                        .setMockMethodCallHandler(
                          SystemChannels.platform,
                          null,
                        ),
                  );
                  const codec = StandardMethodCodec();
                  unawaited(
                    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
                      'app/window_bridge',
                      codec.encodeMethodCall(const MethodCall('nativePaste')),
                      (_) {},
                    ),
                  );
                }
                for (var tick = 0; tick < 10; tick++) {
                  await tester.pump(const Duration(milliseconds: 100));
                }
                if (scene == 'clipboard-confirm') {
                  expect(find.byType(AlertDialog), findsOneWidget);
                } else {
                  final key = switch (scene) {
                    'url-confirm' => 'osc1337-open-url-dialog',
                    'report-confirm' => 'osc1337-report-variable-dialog',
                    'search' => 'terminal-search-field',
                    _ => 'paste-confirmation-dialog',
                  };
                  expect(find.byKey(Key(key)), findsOneWidget);
                }
              }
              if (scene == 'recordings-empty' || scene == 'recordings-error') {
                expect(
                  find.byKey(
                    Key(
                      scene == 'recordings-empty'
                          ? 'recording-library-empty'
                          : 'recording-library-error',
                    ),
                  ),
                  findsOneWidget,
                );
              }
              await captureUiReview(
                tester,
                _captureBoundary,
                '${platform.name}-${brightness.name}-${landscape ? 'landscape' : 'portrait'}-shell-$scene',
              );
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
            },
            variant: TargetPlatformVariant.only(platform),
          );
        }
      }
    }
  }
}
