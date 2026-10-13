// Host captures of production widgets; substitute fonts are not native iOS proof.
import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/data/services/portable_master_key.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/ai_settings_dialog.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_editor.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/recording/mobile_replay_player.dart';
import 'package:app/features/security/master_key_management.dart';
import 'package:app/features/sftp/sftp_file_actions.dart';
import 'package:app/features/sftp/sftp_side_panel.dart';
import 'package:app/features/shell/defaults_appearance_dialog.dart';
import 'package:app/features/shell/widgets/mobile_disconnected_session_notice.dart';
import 'package:app/features/ssh/new_session_launcher.dart';
import 'package:app/features/ssh/ssh_auth_prompt.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:app/ui/components/app_notifications.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:app/ui/previews/app_notifications_preview.dart';
import 'package:app/ui/previews/command_blocks_preview.dart';
import 'package:app/ui/previews/ios_terminal_input_bar_preview.dart';
import 'package:app/ui/previews/mobile_prd_component_previews.dart';
import 'package:app/ui/previews/mobile_sessions_preview.dart';
import 'package:app/ui/previews/shell_capabilities_preview.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ai/terminal_ai_test.dart' show MemoryAiStore;
import 'configuration_capture_binding.dart';
import 'ui_review_capture.dart';
import 'visual_capture_fonts.dart';

class _MasterKeyStore implements PortableMasterKeyStorage {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String portableValue) async {}
}

class _ReplayDriver implements terminal.TerminalReplayDriver {
  @override
  Duration position = const Duration(seconds: 30);
  @override
  Duration get duration => const Duration(minutes: 2);
  @override
  void advanceTo(Duration sourceOffset) => position = sourceOffset;
  @override
  void seekTo(Duration sourceOffset) => position = sourceOffset;
}

class _DirectorySource implements SftpDirectoryDataSource {
  @override
  SftpDirectoryLoadOperation startListDirectory(SftpDirectoryRequest request) =>
      SftpDirectoryLoadOperation(
        onCancel: () {},
        future: Future.value(
          const SftpDirectorySnapshot(
            path: '/home/deploy',
            entries: [
              SftpDirectoryEntry(
                name: 'projects',
                kind: SftpDirectoryEntryKind.directory,
              ),
              SftpDirectoryEntry(
                name: 'README.md',
                kind: SftpDirectoryEntryKind.file,
              ),
              SftpDirectoryEntry(
                name: 'build-output-2026-10-13.log',
                kind: SftpDirectoryEntryKind.file,
              ),
            ],
          ),
        ),
      );
}

Widget _settings(TargetPlatform platform) {
  final profile = defaultTerminalProfile();
  return DefaultsAndAppearanceDialog(
    profiles: [profile],
    configuredDefaultProfileId: profile.id,
    effectiveDefaultProfileId: profile.id,
    themeMode: TerminalThemeMode.system,
    languageMode: TerminalLanguageMode.system,
    terminalViewportPadding:
        TerminalAppAppearance.defaultTerminalViewportPadding,
    restoreLayout: true,
    osc52Policy: LocalTerminalOsc52Policy.profile,
    openUrlPolicy: LocalTerminalOpenUrlPolicy.ask,
    requestAttentionPolicy: LocalTerminalRequestAttentionPolicy.disabled,
    reportVariableDecisions: const {},
    dataApiConfiguration: const DataApiConfiguration.disabled(),
    localDataApiAvailable: platform == TargetPlatform.macOS,
    localSessionsEnabled: platform != TargetPlatform.iOS,
  );
}

void main() {
  ConfigurationCaptureBinding();
  setUpAll(loadVisualCaptureFonts);
  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    for (final brightness in Brightness.values) {
      for (final landscape in [false, true]) {
        if (platform == TargetPlatform.macOS && landscape) continue;
        for (final page in [
          'blocks',
          'ssh',
          'ssh-advanced',
          'hostkey',
          'hostkey-changed',
          'authentication',
          'aisettings',
          'masterkey',
          'notifications',
          'settings',
          for (final tab in [
            'general',
            'appearance',
            'security',
            'data',
            'shortcuts',
          ])
            'settings-$tab',
          for (final tab in [
            'general',
            'startup',
            'terminal',
            'appearance',
            'keys',
            'automation',
            'advanced',
          ])
            'profile-$tab',
          'sftp',
          'sftp-menu',
          'disconnected',
          'sessions',
          'sessions-disconnected',
          'capabilities',
          'keyboard',
          'replay',
          'replay-options',
          for (final component in MobilePrdPreviewComponent.values)
            for (final state in [
              MobilePrdPreviewState.defaultState,
              MobilePrdPreviewState.error,
              MobilePrdPreviewState.unknown,
            ])
              'ai-${component.name}-${state.name}',
        ]) {
          final name =
              '${platform.name}-${brightness.name}-${landscape ? 'landscape' : 'portrait'}-$page';
          testWidgets(name, (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = platform == TargetPlatform.macOS
                ? const Size(1280, 900)
                : landscape
                ? const Size(874, 402)
                : const Size(402, 874);
            addTearDown(tester.view.reset);
            final theme = withVisualCaptureFonts(
              buildIanvsTerminalTheme(brightness, platform: platform),
            );
            final boundary = GlobalKey();
            final profile = defaultTerminalProfile();
            final files = SftpFileActions();
            addTearDown(files.dispose);
            final replay = terminal.TerminalReplayController(
              driver: _ReplayDriver(),
            );
            addTearDown(replay.dispose);
            final aiSettings = AiSettingsController(MemoryAiStore(null));
            addTearDown(aiSettings.dispose);
            await aiSettings.loaded;
            final family = page.split('-').first;
            final content = switch (family) {
              'ssh' => SshProfileEditorDialog(
                initialValue: profile.copyWith(
                  name: '生产环境',
                  connection: const terminal.TerminalConnectionConfig.ssh(
                    host: 'prod.example.com',
                    user: 'deploy',
                    port: 22,
                    auth: terminal.TerminalSshAuthMethod.auto,
                    privateKeys: ['~/.ssh/id_ed25519'],
                  ),
                ),
                allowSaveChoice: true,
              ),
              'sessions' => (mobileSessionsLightPreview() as MaterialApp).home!,
              'capabilities' =>
                (shellCapabilitiesLightPreview() as MaterialApp).home!,
              'keyboard' =>
                (iosTerminalKeyboardLightPreview() as MaterialApp).home!,
              'replay' => MobileReplayPlayer(
                controller: replay,
                title: '部署记录 · production',
                details: '输入已隐藏',
                recordedViewportSize: const Size(800, 480),
                viewport: ColoredBox(
                  color: theme.colorScheme.surface,
                  child: Text(
                    r'$ flutter build ios',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                onClose: () {},
                onSearchChanged: (_) {},
              ),
              'ai' => TerminalAiComponentFixture(
                component: MobilePrdPreviewComponent.values.byName(
                  page.split('-')[1],
                ),
                state: MobilePrdPreviewState.values.byName(page.split('-')[2]),
              ),
              'sftp' => SftpSidePanel(
                target: const SftpSessionTarget(
                  sessionId: 'review',
                  profileName: '生产环境',
                  host: 'prod.example.com',
                  user: 'deploy',
                  port: 22,
                ),
                dataSource: _DirectorySource(),
                fileActions: files,
                onClose: () {},
              ),
              'disconnected' => Align(
                alignment: Alignment.bottomCenter,
                child: MobileDisconnectedSessionNotice(
                  sessionId: 'review',
                  reconnected: false,
                  compact: landscape,
                  exitCode: 255,
                  onReconnect: () {},
                ),
              ),
              'aisettings' => AiSettingsDialog(settings: aiSettings),
              'masterkey' => Padding(
                padding: const EdgeInsets.all(16),
                child: MasterKeyManagementPanel(
                  repository: PortableMasterKeyRepository(
                    storage: _MasterKeyStore(),
                  ),
                ),
              ),
              'notifications' =>
                (notificationsLightPreview() as MaterialApp).home!,
              'hostkey' => SshHostKeyPromptDialog(
                event: terminal.TerminalSessionSshHostKeyPromptEvent(
                  'review',
                  rawPayload: {
                    'challenge_id': 7,
                    'host': 'prod.example.com',
                    'port': 22,
                    'reason': page.endsWith('changed') ? 'changed' : 'unknown',
                    'algorithm': 'ssh-ed25519',
                    'fingerprint': 'SHA256:review-fingerprint',
                  },
                ),
              ),
              'authentication' => SshAuthenticationPromptDialog(
                event: terminal.TerminalSessionSshAuthPromptEvent(
                  'review',
                  rawPayload: {
                    'challenge_id': 7,
                    'host': 'prod.example.com',
                    'user': 'deploy',
                    'name': '身份验证',
                    'instructions': '请输入 SSH 服务器要求的验证码。',
                    'prompts': [
                      {'prompt': '验证码', 'echo': false},
                    ],
                  },
                ),
              ),
              'settings' => _settings(platform),
              'profile' => ProfileEditorDialog(initialValue: profile),
              _ => const SizedBox.shrink(),
            };
            await tester.pumpWidget(
              RepaintBoundary(
                key: boundary,
                child: page == 'blocks'
                    ? CommandBlocksPreview(brightness: brightness, theme: theme)
                    : MaterialApp(
                        debugShowCheckedModeBanner: false,
                        locale: const Locale('zh'),
                        localizationsDelegates:
                            AppLocalizations.localizationsDelegates,
                        supportedLocales: AppLocalizations.supportedLocales,
                        theme: theme,
                        builder: family == 'notifications'
                            ? (context, child) => AppNotificationHost(
                                topInset: 44,
                                child: child!,
                              )
                            : null,
                        home: Scaffold(body: content),
                      ),
              ),
            );
            if (family == 'ai') {
              for (var frame = 0; frame < 12; frame++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
            } else {
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull, reason: name);
            if (page.startsWith('settings-') || page.startsWith('profile-')) {
              final section = page.split('-').last;
              final key = family == 'settings'
                  ? 'defaults-section-$section'
                  : 'profile-editor-nav-$section';
              await tester.ensureVisible(find.byKey(Key(key)));
              await tester.tap(find.byKey(Key(key)));
              await tester.pumpAndSettle();
            }
            if (page == 'ssh-advanced') {
              final toggle = platform == TargetPlatform.iOS
                  ? find.byKey(const Key('ssh-more-settings-toggle'))
                  : find.byType(ExpansionTile);
              await tester.ensureVisible(toggle);
              await tester.tap(toggle);
              await tester.pumpAndSettle();
            }
            final extra = switch (page) {
              'sftp-menu' => 'sftp-entry-actions-README.md',
              'sessions-disconnected' => 'mobile-sessions-disconnected-toggle',
              'replay-options' => 'mobile-replay-more',
              _ => null,
            };
            if (extra != null) {
              if (page == 'sftp-menu' && platform == TargetPlatform.macOS) {
                await tester.tap(
                  find.text('README.md'),
                  buttons: kSecondaryMouseButton,
                );
              } else {
                await tester.tap(find.byKey(Key(extra)));
              }
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull, reason: '$name selected');
            await captureUiReview(tester, boundary, name);
            // Record the middle and end of long sections, not only the first
            // viewport. No settings values or submit actions are changed.
            final vertical =
                tester
                    .stateList<ScrollableState>(find.byType(Scrollable))
                    .where(
                      (state) =>
                          state.position.axis == Axis.vertical &&
                          state.position.maxScrollExtent > 0,
                    )
                    .toList()
                  ..sort(
                    (a, b) => b.position.maxScrollExtent.compareTo(
                      a.position.maxScrollExtent,
                    ),
                  );
            if (vertical.isNotEmpty && family != 'blocks' && family != 'ai') {
              final position = vertical.first.position;
              for (final fraction in [.5, 1.0]) {
                position.jumpTo(position.maxScrollExtent * fraction);
                await tester.pumpAndSettle();
                expect(
                  tester.takeException(),
                  isNull,
                  reason: '$name scroll $fraction',
                );
                await captureUiReview(
                  tester,
                  boundary,
                  '$name-${fraction == .5 ? 'middle' : 'bottom'}',
                );
              }
            }
            await tester.pumpWidget(const SizedBox.shrink());
          }, variant: TargetPlatformVariant.only(platform));
        }
      }
    }
  }
}
