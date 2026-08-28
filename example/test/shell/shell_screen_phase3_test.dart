import 'dart:convert';

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_acceptance.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/ssh/ssh_feature_access.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';
import '../support/no_io_local_terminal_layout_repository.dart';

Future<void> _pumpShellScreen(
  WidgetTester tester, {
  required FakePtyBackend fakeBindings,
  required MemoryProfileRepository profileRepository,
  required MemoryAppPreferencesRepository preferencesRepository,
  LocalTerminalConfigDocument? localConfig,
  MemoryLocalTerminalConfigRepository? localConfigRepository,
  LocalTerminalLayoutRepository? workspaceRepository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shellAcceptanceProbeProvider.overrideWithValue(shellAcceptanceProbe),
        customSshProfileConfigurationEnabledProvider.overrideWithValue(true),
        ptySessionBackendProvider.overrideWithValue(fakeBindings),
        profileRepositoryProvider.overrideWithValue(profileRepository),
        pasteHistoryRepositoryProvider.overrideWithValue(
          MemoryPasteHistoryRepository(),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          preferencesRepository,
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          localConfigRepository ??
              MemoryLocalTerminalConfigRepository(localConfig),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          noIoLocalSessionRecordingRepository(),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          workspaceRepository ?? noIoLocalTerminalLayoutRepository(),
        ),
      ],
      child: MaterialApp(
        theme: buildIanvsTerminalTheme(Brightness.light),
        darkTheme: buildIanvsTerminalTheme(Brightness.dark),
        home: const ShellScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ShellScreen)),
  );
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (container.read(sessionControllerProvider).isReady) {
      break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(container.read(sessionControllerProvider).isReady, isTrue);
  await tester.pumpAndSettle();
}

class _MemoryLayoutRepository extends LocalTerminalLayoutRepository {
  _MemoryLayoutRepository(this.layout);

  TerminalLayout? layout;

  @override
  Future<TerminalLayout?> load() async => layout;

  @override
  Future<void> save(TerminalLayout layout) async {
    this.layout = layout;
  }
}

void main() {
  testWidgets(
    'defaults remain hidden from the shell layout until the user opens tools',
    (tester) async {
      final profileRepository = MemoryProfileRepository(
        TerminalProfilesDocument(
          profiles: [
            defaultTerminalProfile(),
            TerminalProfile(id: 'ssh', name: 'SSH', shell: '/usr/bin/ssh'),
          ],
        ),
      );

      await _pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        profileRepository: profileRepository,
        preferencesRepository: MemoryAppPreferencesRepository(null),
      );

      expect(find.byKey(const Key('shell-empty-state')), findsNothing);
      expect(find.text('Current new-tab profile • SSH'), findsNothing);
      expect(find.text('Theme • System'), findsNothing);
    },
  );

  testWidgets('configuration warnings are shown and can open Profiles', (
    tester,
  ) async {
    const warning = TerminalProfileLoadWarning(
      profileId: 'default',
      profileName: 'Local Shell',
      path: 'terminal.scrollbackLines',
      rawValueSummary: '-1',
      fallbackSummary: 'used default value 8000',
    );

    await _pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      profileRepository: MemoryProfileRepository(
        TerminalProfilesDocument(
          profiles: [defaultTerminalProfile()],
          loadWarnings: [warning],
        ),
      ),
      preferencesRepository: MemoryAppPreferencesRepository(null),
    );

    expect(
      find.byKey(const Key('shell-configuration-warnings')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Some terminal profile values were ignored and reset to safe defaults.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(terminalProfileLoadWarningMessage(warning)),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('shell-configuration-warnings-review')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profiles-sheet')), findsOneWidget);
    expect(shellAcceptanceProbe.current.profilesOpen, isTrue);
  });

  testWidgets(
    'configuration warnings can be dismissed without affecting tabs',
    (tester) async {
      await _pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        profileRepository: MemoryProfileRepository(
          TerminalProfilesDocument(
            profiles: [defaultTerminalProfile()],
            loadWarnings: const [
              TerminalProfileLoadWarning(
                profileId: 'default',
                profileName: 'Local Shell',
                path: 'appearance.colors.foreground',
                rawValueSummary: '"red"',
                fallbackSummary: 'used inherited default color',
              ),
            ],
          ),
        ),
        preferencesRepository: MemoryAppPreferencesRepository(null),
      );

      expect(shellAcceptanceProbe.current.activeTabCount, 1);
      expect(
        find.byKey(const Key('shell-configuration-warnings')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('shell-configuration-warnings-dismiss')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('shell-configuration-warnings')),
        findsNothing,
      );
      expect(shellAcceptanceProbe.current.activeTabCount, 1);
    },
  );

  testWidgets(
    'terminal layout relaunch failures stay visible and can be dismissed',
    (tester) async {
      await _pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        profileRepository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
        preferencesRepository: MemoryAppPreferencesRepository(null),
        localConfig: const LocalTerminalConfigDocument(
          layout: LocalTerminalLayoutConfig(restoreLayout: true),
        ),
        workspaceRepository: _MemoryLayoutRepository(
          TerminalLayout(
            activeTabId: 'old-tab',
            tabs: [
              TerminalLayoutTab(
                id: 'old-tab',
                activePaneId: 'old-pane',
                root: TerminalPaneNode.leaf(
                  id: 'old-pane',
                  sessionIntent: const TerminalRelaunchSpec(
                    profileId: 'removed-profile',
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      expect(find.byKey(const Key('shell-runtime-error')), findsOneWidget);
      expect(
        find.textContaining('Terminal layout restore skipped 1 pane'),
        findsOneWidget,
      );
      expect(find.textContaining('removed-profile'), findsOneWidget);
      expect(find.byKey(const Key('shell-empty-state')), findsNothing);

      await tester.tap(find.byKey(const Key('shell-runtime-error-dismiss')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shell-runtime-error')), findsNothing);
    },
  );

  testWidgets(
    'defaults dialog shows the current new-tab profile when no default is configured',
    (tester) async {
      final profileRepository = MemoryProfileRepository(
        TerminalProfilesDocument(
          profiles: [
            defaultTerminalProfile(),
            TerminalProfile(id: 'ssh', name: 'SSH', shell: '/usr/bin/ssh'),
          ],
        ),
      );

      await _pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        profileRepository: profileRepository,
        preferencesRepository: MemoryAppPreferencesRepository(null),
      );

      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Defaults & appearance'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('defaults-dialog')), findsOneWidget);
      expect(find.byKey(const Key('shell-command-defaults')), findsNothing);
      expect(shellAcceptanceProbe.current.defaultsOpen, isTrue);
      expect(shellAcceptanceProbe.current.commandMenuOpen, isFalse);
      expect(shellAcceptanceProbe.current.visibleOverlay, 'defaults');
      expect(shellAcceptanceProbe.current.themeMode, 'system');
      expect(shellAcceptanceProbe.current.terminalHasVisibleContent, isTrue);
      expect(shellAcceptanceProbe.current.terminalPreview, isNotNull);
      expect(
        find.text(
          'New tabs use Local Shell automatically until you choose a fixed default.',
        ),
        findsOneWidget,
      );
      expect(find.text('Automatic fallback • Local Shell'), findsNothing);
      expect(
        find.text('Detailed terminal settings live in Profiles.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Edit font, colors, cursor, scrollback, and startup arguments from the Profiles editor.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('defaults-open-profiles')), findsOneWidget);
      expect(find.byKey(const Key('defaults-profiles-notice')), findsOneWidget);
      expect(
        find.byKey(const Key('defaults-current-profile-summary')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('defaults-section-appearance')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('defaults-terminal-preset-grid')),
        findsOneWidget,
      );
      final currentPresetRect = tester.getRect(
        find.byKey(const Key('defaults-terminal-preset-current')),
      );
      final graphitePresetRect = tester.getRect(
        find.byKey(const Key('defaults-terminal-preset-graphite-night')),
      );
      final emberPresetRect = tester.getRect(
        find.byKey(const Key('defaults-terminal-preset-ember-dusk')),
      );
      final presetSpacing = Theme.of(
        tester.element(find.byKey(const Key('defaults-terminal-preset-grid'))),
      ).extension<AppThemeTokens>()!.spacing.lg;
      expect(
        graphitePresetRect.left - currentPresetRect.right,
        closeTo(presetSpacing, 0.01),
      );
      expect(
        emberPresetRect.top - currentPresetRect.bottom,
        closeTo(presetSpacing, 0.01),
      );
      for (final panelKey in <Key>[
        const Key('defaults-appearance-options'),
        const Key('defaults-canvas-inset-panel'),
      ]) {
        expect(find.byKey(panelKey), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('defaults-section-security')));
      await tester.pumpAndSettle();
      for (final panelKey in <Key>[
        const Key('defaults-osc52-options'),
        const Key('defaults-open-url-options'),
        const Key('defaults-request-attention-options'),
        const Key('defaults-report-variable-panel'),
      ]) {
        expect(find.byKey(panelKey), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('defaults-section-appearance')));
      await tester.pumpAndSettle();

      final dialogSize = tester.getSize(
        find.byKey(const Key('defaults-dialog')),
      );
      expect(dialogSize.width, greaterThanOrEqualTo(680));
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('defaults-terminal-preset-filter')),
            )
            .autofocus,
        isFalse,
      );
      expect(
        tester.getCenter(find.text('Reset default')).dx,
        lessThan(tester.getCenter(find.text('Cancel')).dx),
      );
    },
  );

  testWidgets(
    'defaults and appearance modal is the only place that mutates default profile and theme',
    (tester) async {
      final preferencesRepository = MemoryAppPreferencesRepository(null);
      final localConfigRepository = MemoryLocalTerminalConfigRepository(null);
      final profileRepository = MemoryProfileRepository(
        TerminalProfilesDocument(
          profiles: [
            defaultTerminalProfile(),
            TerminalProfile(
              id: 'ssh',
              name: 'SSH',
              shell: '/bin/zsh',
              connection: const terminal.TerminalConnectionConfig.ssh(
                host: 'ssh.example.test',
                user: 'operator',
                port: 2222,
              ),
            ),
          ],
        ),
      );

      await _pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        profileRepository: profileRepository,
        preferencesRepository: preferencesRepository,
        localConfigRepository: localConfigRepository,
      );

      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Defaults & appearance'));
      await tester.pumpAndSettle();

      final defaultsVersion = shellAcceptanceProbe.current.snapshotVersion;
      expect(find.byKey(const Key('defaults-dialog')), findsOneWidget);
      expect(find.text('Use automatic fallback'), findsOneWidget);
      final fallbackProfileOption = tester.widget<RadioListTile<String?>>(
        find.byKey(const Key('default-profile-option-fallback')),
      );
      expect(fallbackProfileOption.contentPadding, EdgeInsets.zero);
      expect(find.byKey(const Key('defaults-save')), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('defaults-save'))).height, 40);
      expect(
        tester.getSize(find.byKey(const Key('defaults-cancel'))).height,
        tester.getSize(find.byKey(const Key('defaults-save'))).height,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('defaults-save')))
            .onPressed,
        isNull,
      );

      final sshProfileOption = find.byKey(
        const Key('default-profile-option-ssh'),
      );
      await tester.ensureVisible(sshProfileOption);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: sshProfileOption,
          matching: find.text('SSH • operator@ssh.example.test:2222'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sshProfileOption, matching: find.text('/bin/zsh')),
        findsNothing,
      );
      await tester.tap(sshProfileOption);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('defaults-section-appearance')));
      await tester.pumpAndSettle();
      final darkThemeOption = tester.widget<RadioListTile<TerminalThemeMode>>(
        find.byKey(const Key('default-theme-option-dark')),
      );
      expect(darkThemeOption.contentPadding, EdgeInsets.zero);
      expect(
        find.byKey(const Key('default-terminal-viewport-padding')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('default-theme-option-dark')),
      );
      await tester.tap(find.byKey(const Key('default-theme-option-dark')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('defaults-save')))
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(
        find.byKey(const Key('default-terminal-viewport-padding')),
      );
      final paddingSlider = tester.widget<Slider>(
        find.byKey(const Key('default-terminal-viewport-padding')),
      );
      expect(paddingSlider.divisions, 48);
      paddingSlider.onChanged!(18);
      await tester.pump();
      expect(
        tester
            .widget<Slider>(
              find.byKey(const Key('default-terminal-viewport-padding')),
            )
            .value,
        18,
      );
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      final savedConfig = await localConfigRepository.load();
      expect(savedConfig, isNotNull);
      expect(savedConfig!.defaultProfileId, 'ssh');
      expect(savedConfig.appearance.themeMode, TerminalThemeMode.dark);
      expect(savedConfig.appearance.terminalViewportPadding, 18);

      expect(find.byKey(const Key('shell-chrome-menu')), findsOneWidget);
      expect(shellAcceptanceProbe.current.visibleOverlay, 'none');
      expect(
        shellAcceptanceProbe.current.snapshotVersion,
        greaterThan(defaultsVersion),
      );
    },
  );

  testWidgets(
    'closing defaults and appearance restores terminal viewport focus',
    (tester) async {
      final fakeBindings = FakePtyBackend();

      await _pumpShellScreen(
        tester,
        fakeBindings: fakeBindings,
        profileRepository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
        preferencesRepository: MemoryAppPreferencesRepository(null),
      );

      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Defaults & appearance'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('defaults-dialog')), findsOneWidget);

      await tester.tap(find.byTooltip('Close defaults'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('defaults-dialog')), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
      await tester.pump();

      expect(fakeBindings.writes, isNotEmpty);
      expect(fakeBindings.writes.last, 'v'.codeUnits);
    },
  );

  testWidgets('defaults dialog can hand off to the profiles editor', (
    tester,
  ) async {
    await _pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      profileRepository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
      preferencesRepository: MemoryAppPreferencesRepository(null),
    );

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Defaults & appearance'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defaults-dialog')), findsOneWidget);

    final openProfilesButton = find.byKey(const Key('defaults-open-profiles'));
    await tester.ensureVisible(openProfilesButton);
    await tester.pumpAndSettle();
    await tester.tap(openProfilesButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defaults-dialog')), findsNothing);
    expect(find.byKey(const Key('profiles-sheet')), findsOneWidget);
    expect(shellAcceptanceProbe.current.defaultsOpen, isFalse);
    expect(shellAcceptanceProbe.current.profilesOpen, isTrue);
    expect(shellAcceptanceProbe.current.visibleOverlay, 'profiles');
  });

  testWidgets('profiles sheet opens from the command menu and lists profiles', (
    tester,
  ) async {
    final localProfile = defaultTerminalProfile().copyWith(
      tags: const ['local', 'login'],
    );
    final sshProfile = TerminalProfile(
      id: 'ssh',
      name: 'SSH',
      shell: '/usr/bin/ssh',
      terminalEmulation: TerminalEmulation.vt220,
      scrollbackLines: 4096,
      tags: const ['remote', 'ops'],
    );
    final profileRepository = MemoryProfileRepository(
      TerminalProfilesDocument(profiles: [localProfile, sshProfile]),
    );

    await _pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      profileRepository: profileRepository,
      preferencesRepository: MemoryAppPreferencesRepository(null),
    );

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Profiles…'));
    await tester.tap(find.text('Profiles…'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profiles-sheet')), findsOneWidget);
    expect(shellAcceptanceProbe.current.profilesOpen, isTrue);
    expect(shellAcceptanceProbe.current.commandMenuOpen, isFalse);
    expect(shellAcceptanceProbe.current.visibleOverlay, 'profiles');
    expect(find.text('Profiles'), findsOneWidget);
    expect(find.byKey(const Key('profile-entry-default')), findsOneWidget);
    expect(find.byKey(const Key('profile-entry-ssh')), findsOneWidget);
    expect(find.byKey(const Key('profiles-search-field')), findsOneWidget);
    expect(find.text('Local Shell'), findsWidgets);
    expect(find.text('SSH'), findsOneWidget);
    expect(find.byKey(const Key('profile-tag-local')), findsOneWidget);
    expect(find.byKey(const Key('profile-tag-remote')), findsOneWidget);
    expect(
      find.text(
        '${localProfile.shell} • xterm-256color • ${localProfile.scrollbackLines} lines • Default profile',
      ),
      findsOneWidget,
    );
    expect(find.text('/usr/bin/ssh • VT220 • 4096 lines'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('profiles-search-field')),
      'remote',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-entry-default')), findsNothing);
    expect(find.byKey(const Key('profile-entry-ssh')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('profiles-search-field')),
      'missing',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-entry-ssh')), findsNothing);
    expect(find.text('No matching profiles'), findsOneWidget);
  });

  testWidgets('profiles sheet can create a new profile', (tester) async {
    final profileRepository = MemoryProfileRepository(
      TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
    );

    await _pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      profileRepository: profileRepository,
      preferencesRepository: MemoryAppPreferencesRepository(null),
    );

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Profiles…'));
    await tester.tap(find.text('Profiles…'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profiles-create')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profiles-create-local')), findsOneWidget);
    expect(find.byKey(const Key('profiles-create-ssh')), findsOneWidget);
    await tester.tap(find.byKey(const Key('profiles-create-local')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-editor-dialog')), findsOneWidget);
    expect(find.text('New profile'), findsOneWidget);
    expect(find.text('Edit profile'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('profile-editor-name')),
      'Work Shell',
    );
    await tester.ensureVisible(find.byKey(const Key('profile-editor-save')));
    await tester.tap(find.byKey(const Key('profile-editor-save')));
    await tester.pumpAndSettle();

    final savedDocument = await profileRepository.load();
    expect(savedDocument.profiles, hasLength(2));
    final created = savedDocument.profiles.singleWhere(
      (profile) => profile.name == 'Work Shell',
    );
    expect(created.id, isNot('default'));
    expect(created.shell, defaultTerminalProfile().shell);
    expect(find.byKey(const Key('profiles-sheet')), findsNothing);
  });

  testWidgets('editing a profile in the GUI only affects new sessions', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    final profileRepository = MemoryProfileRepository(
      TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
    );

    await _pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      profileRepository: profileRepository,
      preferencesRepository: MemoryAppPreferencesRepository(null),
    );

    final initialCreatedProfileJson = jsonEncode(
      fakeBindings.lastCreatedSessionPayload,
    );

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Profiles…'));
    await tester.tap(find.text('Profiles…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit Local Shell'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-editor-dialog')), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-editor-nav-startup')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile-editor-shell')),
      '/bin/fish',
    );
    await tester.tap(find.byKey(const Key('profile-editor-nav-terminal')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('profile-editor-scrollback')),
    );
    await tester.enterText(
      find.byKey(const Key('profile-editor-scrollback')),
      '4096',
    );
    await tester.tap(find.byKey(const Key('profile-editor-nav-appearance')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('profile-editor-color-foreground')),
    );
    await tester.enterText(
      find.byKey(const Key('profile-editor-color-foreground')),
      '#112233',
    );
    await tester.tap(find.byKey(const Key('profile-editor-nav-keys')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('profile-editor-copy-on-select')),
    );
    await tester.tap(find.byKey(const Key('profile-editor-copy-on-select')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('profile-editor-save')));
    await tester.tap(find.byKey(const Key('profile-editor-save')));
    await tester.pumpAndSettle();

    expect(
      jsonEncode(fakeBindings.lastCreatedSessionPayload),
      initialCreatedProfileJson,
    );
    expect(shellAcceptanceProbe.current.activeTabCount, 1);

    final savedDocument = await profileRepository.load();
    final savedProfile = savedDocument.profiles.single;
    expect(savedProfile.shell, '/bin/fish');
    expect(savedProfile.terminalEmulation, TerminalEmulation.xterm256);
    expect(savedProfile.scrollbackLines, 4096);
    expect(savedProfile.appearance.colors.foreground, '#112233');
    expect(savedProfile.interaction.copyOnSelect, isTrue);

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Profiles…'));
    await tester.tap(find.text('Profiles…'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile-entry-default')));
    await tester.tap(find.byKey(const Key('profile-entry-default')));
    await tester.pumpAndSettle();

    expect(shellAcceptanceProbe.current.activeTabCount, 2);
    expect(fakeBindings.lastCreatedSessionPayload, isNotNull);
    expect(fakeBindings.lastCreatedSessionPayload!['launch'], {
      'program': '/bin/fish',
      'args': <String>['-l'],
      'env': <String, String>{
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      },
      'cwd': null,
    });
    expect(fakeBindings.lastCreatedSessionPayload!['terminal'], {
      'emulation': 'xterm256',
      'scrollbackLines': 4096,
      'graphics': {
        'enabled': true,
        'advertise': 'kitty',
        'maxImageBytes': terminal.defaultTerminalGraphicMaxImageBytes,
        'maxTotalBytes': terminal.defaultTerminalGraphicMaxTotalBytes,
      },
      'dragDropEnabled': true,
    });
    expect(fakeBindings.lastCreatedSessionPayload!['appearance'], {
      'font': {
        'family': savedProfile.appearance.font.family,
        'fallback': savedProfile.appearance.font.fallback,
        'size': savedProfile.appearance.font.size,
        'lineHeight': savedProfile.appearance.font.lineHeight,
      },
      'colors': savedProfile.appearance.colors.resolveWith().toJson(),
      'cursor': {
        'shape': savedProfile.appearance.cursor.shape.name,
        'blink': savedProfile.appearance.cursor.blink,
      },
    });
    expect(fakeBindings.lastCreatedSessionPayload!['interaction'], {
      'copyOnSelect': true,
      'optionDragMode': 'block_selection',
    });
  });

  testWidgets('saving defaults still only changes default profile and theme', (
    tester,
  ) async {
    final preferencesRepository = MemoryAppPreferencesRepository(null);
    final localConfigRepository = MemoryLocalTerminalConfigRepository(null);
    final profileRepository = MemoryProfileRepository(
      TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
    );

    await _pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      profileRepository: profileRepository,
      preferencesRepository: preferencesRepository,
      localConfigRepository: localConfigRepository,
    );

    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Defaults & appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('defaults-section-appearance')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('defaults-save')));
    await tester.ensureVisible(
      find.byKey(const Key('default-theme-option-dark')),
    );
    await tester.tap(find.byKey(const Key('default-theme-option-dark')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('defaults-save')));
    await tester.tap(find.byKey(const Key('defaults-save')));
    await tester.pumpAndSettle();

    final savedConfig = await localConfigRepository.load();
    expect(savedConfig, isNotNull);
    expect(savedConfig!.defaultProfileId, isNull);
    expect(savedConfig.appearance.themeMode, TerminalThemeMode.dark);

    final savedProfiles = await profileRepository.load();
    expect(savedProfiles.profiles.single.appearance.colors.foreground, isNull);
    expect(savedProfiles.profiles.single.scrollbackLines, 8000);
  });

  testWidgets(
    'defaults dialog can apply a terminal preset to the new-tab profile',
    (tester) async {
      final preferencesRepository = MemoryAppPreferencesRepository(null);
      final profileRepository = MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      );
      final preset = terminalThemePresets.first;

      await _pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        profileRepository: profileRepository,
        preferencesRepository: preferencesRepository,
      );

      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Defaults & appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('defaults-section-appearance')));
      await tester.pumpAndSettle();

      final filterFinder = find.byKey(
        const Key('defaults-terminal-preset-filter'),
      );
      expect(filterFinder, findsOneWidget);
      await tester.enterText(filterFinder, 'sage');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('defaults-terminal-preset-sage-mist')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('defaults-terminal-preset-${preset.id}')),
        findsNothing,
      );
      await tester.enterText(filterFinder, '');
      await tester.pumpAndSettle();

      final presetFinder = find.byKey(
        Key('defaults-terminal-preset-${preset.id}'),
      );
      await tester.ensureVisible(presetFinder);
      await tester.tap(presetFinder);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('defaults-save')));
      await tester.tap(find.byKey(const Key('defaults-save')));
      await tester.pumpAndSettle();

      final savedProfiles = await profileRepository.load();
      final savedColors = savedProfiles.profiles.single.appearance.colors;
      expect(savedColors.special.foreground, preset.palette.special.foreground);
      expect(savedColors.special.background, preset.palette.special.background);
      expect(savedColors.special.cursor, preset.palette.special.cursor);
      expect(savedColors.normal.blue, preset.palette.normal.blue);
    },
  );

  test(
    'driver acceptance probe returns the latest shell snapshot as json',
    () async {
      shellAcceptanceProbe.update(
        const ShellAcceptanceSnapshot(
          commandMenuOpen: true,
          defaultsOpen: false,
          profilesOpen: true,
          visibleOverlay: 'profiles',
          terminalHasVisibleContent: true,
          terminalPreview: 'driver ready',
          activeTabCount: 2,
          activeSessionId: '2',
          themeMode: 'dark',
          snapshotVersion: 4,
        ),
      );

      final response = await shellAcceptanceProbe.handleDriverRequest(
        'shell.acceptance',
      );

      expect(response, contains('"commandMenuOpen":true'));
      expect(response, contains('"profilesOpen":true'));
      expect(response, contains('"visibleOverlay":"profiles"'));
      expect(response, contains('"terminalHasVisibleContent":true'));
      expect(response, contains('"terminalPreview":"driver ready"'));
      expect(response, contains('"activeTabCount":2'));
      expect(response, contains('"activeSessionId":"2"'));
      expect(response, contains('"themeMode":"dark"'));
      expect(response, contains('"snapshotVersion":'));
    },
  );
}
