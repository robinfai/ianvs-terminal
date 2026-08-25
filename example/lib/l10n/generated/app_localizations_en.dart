// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Ianvs Terminal';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Retry';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get continueAction => 'Continue';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get importAction => 'Import';

  @override
  String get preview => 'Preview';

  @override
  String dialogSemantics(String title) {
    return '$title dialog';
  }

  @override
  String get closeDialog => 'Close dialog';

  @override
  String startingAppAttempt(int attempt) {
    return 'Starting Ianvs Terminal, attempt $attempt';
  }

  @override
  String get preparingTerminalRuntime => 'Preparing terminal runtime…';

  @override
  String startupStage(String stage) {
    return 'Stage: $stage';
  }

  @override
  String get retryStartup => 'Retry startup';

  @override
  String get dataServiceSettings => 'Data service settings';

  @override
  String get connectAndContinue => 'Connect and continue';

  @override
  String get disableDataServiceQuestion => 'Disable the data service?';

  @override
  String get disableDataServiceExplanation =>
      'This explicitly switches to local-terminal-only mode on the next startup attempt. No API process will start; existing remote data is not deleted.';

  @override
  String get useLocalTerminal => 'Use local terminal';

  @override
  String get dataServiceRecovery => 'Data service recovery';

  @override
  String get configurationReadFailed =>
      'The current configuration could not be read. You can still explicitly select Disabled.';

  @override
  String get reconnectConfiguredOrigin =>
      'Reconnect to the configured remote origin before startup retries. The origin cannot be changed here.';

  @override
  String get masterKeyFromAnotherDeviceOptional =>
      'Master key from another device (optional)';

  @override
  String get masterKeyImportHelp =>
      'Paste an exported ianvs-key-v1 key when this device does not already have it.';

  @override
  String get localDataServiceStartFailed =>
      'The local data service could not start. Select local terminal mode to continue without an API. Local API data is retained.';

  @override
  String get alreadyUsingLocalTerminal =>
      'The app is already in local terminal mode. Retry startup or save that mode again to clear its recovery lock.';

  @override
  String get reconnectAndRetry => 'Reconnect and retry';

  @override
  String get appleMasterKeySynchronized =>
      'The master key is stored and synchronized automatically through iCloud Keychain. No key entry is required.';

  @override
  String get masterKeyImportUnavailable => 'Master-key import is unavailable.';

  @override
  String get httpApiUrl => 'HTTP API URL';

  @override
  String get chooseDataMode => 'Choose your data mode';

  @override
  String get dataModeLocalBundledOrRemote =>
      'Use only local terminals, start the bundled offline API, or connect a remote API for cross-device sync.';

  @override
  String get dataModeLocalOrRemote =>
      'Continue without a data service for one-time SSH connections, or connect a remote API to save profiles and sync them.';

  @override
  String get remoteApiRequiredOnIos =>
      'A remote HTTP API connection is required before Ianvs Terminal can be used on iOS.';

  @override
  String get masterKeyOpenExistingHelp =>
      'Paste an exported ianvs-key-v1 key to open existing encrypted data.';

  @override
  String get continueWithoutDataService => 'Continue without data service';

  @override
  String get connectRemoteApi => 'Connect remote API';

  @override
  String get useBundledLocalApi => 'Use bundled local API';

  @override
  String get useLocalTerminalOnly => 'Use local terminal only';

  @override
  String get appCouldNotStart => 'Ianvs Terminal could not start';

  @override
  String startupStageName(String stage) {
    String _temp0 = intl.Intl.selectLogic(stage, {
      'paths': 'File paths',
      'secureRecovery': 'Secure recovery',
      'configuration': 'Configuration',
      'dataBootstrap': 'Data service startup',
      'platform': 'Platform initialization',
      'pty': 'Terminal runtime',
      'configurationValidation': 'Configuration validation',
      'runtimeComposition': 'Runtime composition',
      'runtimeShutdown': 'Runtime shutdown',
      'other': '$stage',
    });
    return '$_temp0';
  }

  @override
  String get openCommandPalette => 'Open command palette';

  @override
  String get commandPalette => 'Command palette';

  @override
  String get closeCommandPalette => 'Close command palette';

  @override
  String get searchActions => 'Search actions';

  @override
  String get typeActionAndPressEnter => 'Type an action and press Enter';

  @override
  String noActionMatches(String query) {
    return 'No action matches \"$query\".';
  }

  @override
  String get quickActions => 'Quick actions';

  @override
  String get appActions => 'App actions';

  @override
  String get sessionActions => 'Session actions';

  @override
  String get replay => 'Replay';

  @override
  String get shellTools => 'Shell tools';

  @override
  String get openTerminalTabFirst => 'Open a terminal tab first.';

  @override
  String get noDefaultProfileConfigured => 'No default profile is configured.';

  @override
  String get noRecentlyClosedTab => 'No recently closed tab is available.';

  @override
  String get searchTerminalOutput => 'Search terminal output';

  @override
  String get searchTerminalOutputDescription =>
      'Top action • Open in-terminal search for the active pane.';

  @override
  String get newTab => 'New tab';

  @override
  String get newTabTitleCase => 'New Tab';

  @override
  String get newTabDescription => 'Top action • Open the default profile.';

  @override
  String get toolbelt => 'Toolbelt';

  @override
  String get toolbeltDescription =>
      'Top action • Open terminal tools for this pane.';

  @override
  String get defaultsAppearance => 'Defaults & appearance';

  @override
  String get defaultsAppearanceDescription =>
      'App action • Pick the default profile and theme.';

  @override
  String get reopenClosedTab => 'Reopen closed tab';

  @override
  String get reopenClosedTabDescription =>
      'App action • Recreate the most recently closed tab.';

  @override
  String get terminalColorPresets => 'Terminal color presets';

  @override
  String get terminalColorPresetsDescription =>
      'App action • Open Defaults & appearance to choose terminal colors.';

  @override
  String commandFinishedNotifications(String enabled) {
    String _temp0 = intl.Intl.selectLogic(enabled, {
      'true': 'Disable command-finished notifications',
      'other': 'Enable command-finished notifications',
    });
    return '$_temp0';
  }

  @override
  String get commandFinishedNotificationsDescription =>
      'App action • Toggle shell hook completion alerts.';

  @override
  String get commandFinishedNotificationsBlockedDescription =>
      'App action • Toggle shell hook completion alerts. macOS notifications are currently blocked in System Settings.';

  @override
  String activityMonitor(String enabled) {
    String _temp0 = intl.Intl.selectLogic(enabled, {
      'true': 'Disable activity monitor',
      'other': 'Enable activity monitor',
    });
    return '$_temp0';
  }

  @override
  String get activityMonitorDescription =>
      'App action • Toggle inactive-session activity alerts.';

  @override
  String get activityMonitorBlockedDescription =>
      'App action • Toggle inactive-session activity alerts. macOS notifications are currently blocked in System Settings.';

  @override
  String get profilesEllipsis => 'Profiles…';

  @override
  String get profilesDescription => 'App action • Open or edit shell profiles.';

  @override
  String get requiresActiveShellSession => 'Requires an active shell session.';

  @override
  String readOnlyMode(String enabled) {
    String _temp0 = intl.Intl.selectLogic(enabled, {
      'true': 'Disable read-only mode',
      'other': 'Enable read-only mode',
    });
    return '$_temp0';
  }

  @override
  String get readOnlyModeDescription =>
      'Session action • Block terminal input for this pane.';

  @override
  String get clearBuffer => 'Clear buffer';

  @override
  String get clearBufferDescription =>
      'Session action • Clear visible output and history; keep the current command line.';

  @override
  String get openSftpPanel => 'Open SFTP panel';

  @override
  String get openSftpPanelDescription =>
      'Session action • Browse files for the active SSH connection in a right-side panel.';

  @override
  String get requiresActiveSshSession => 'Requires an active SSH session.';

  @override
  String get exportTerminalHistory => 'Export terminal history';

  @override
  String get exportTerminalHistoryDescription =>
      'Session action • Save retained text as a .txt file for sharing or later review.';

  @override
  String get exportDiagnostics => 'Export diagnostics';

  @override
  String get exportDiagnosticsDescription =>
      'Session action • Save a local resource evidence bundle.';

  @override
  String get replayRecentActivity => 'Replay recent activity';

  @override
  String get replayRecentActivityDescription =>
      'Replay • Review the current pane’s rolling frame history.';

  @override
  String get stopAndSaveRecording => 'Stop & save recording';

  @override
  String get retrySavingRecording => 'Retry saving recording';

  @override
  String get startRecordingForReplay => 'Start recording for Replay';

  @override
  String get recordingDescription =>
      'Replay • Capture this session as a durable recording. Keystrokes are redacted; shell command metadata is included when available.';

  @override
  String get recordingOperationInProgress =>
      'A recording operation is already in progress.';

  @override
  String get openRecordingInReplay => 'Open recording in Replay…';

  @override
  String get openRecordingInReplayDescription =>
      'Replay • Open one saved terminal recording without importing it.';

  @override
  String get globalSearch => 'Global search';

  @override
  String get globalSearchDescription => 'Shell tool • Search all tabs at once.';

  @override
  String openCommandPaletteWith(String shortcut) {
    return 'Open command palette with $shortcut';
  }

  @override
  String get configurationWarningsSummary =>
      'Some terminal profile values were ignored and reset to safe defaults.';

  @override
  String get dismissConfigurationWarnings => 'Dismiss configuration warnings';

  @override
  String get reviewProfiles => 'Review Profiles';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get terminalRuntimeError => 'Terminal runtime error.';

  @override
  String get dismissRuntimeError => 'Dismiss runtime error';

  @override
  String get terminalCouldNotStart => 'Terminal could not start';

  @override
  String get terminalCouldNotStartHelp =>
      'Review the startup error, then try loading the layout again.';

  @override
  String get useLastRemoteSnapshot => 'Use local snapshot';

  @override
  String get switchingToLocalSnapshot => 'Switching to local…';

  @override
  String get remoteFallbackTitle => 'Use the last remote snapshot?';

  @override
  String remoteFallbackDescription(String capturedAt, int resourceCount) {
    return 'The remote service is unavailable. Ianvs Terminal can switch to the bundled local API using $resourceCount resources last synchronized at $capturedAt. Remote data is not deleted, and the change takes effect after restart.';
  }

  @override
  String get switchToLocalApi => 'Switch to local API';

  @override
  String get remoteFallbackCompleteTitle => 'Local fallback is ready';

  @override
  String remoteFallbackCompleteDescription(String capturedAt) {
    return 'The bundled local API will use the remote data synchronized at $capturedAt. Restart Ianvs Terminal to apply the change.';
  }

  @override
  String remoteFallbackFailed(String error) {
    return 'Could not switch to the local snapshot: $error';
  }

  @override
  String get repairTerminalSettings => 'Repair settings';

  @override
  String get repairTerminalSettingsTitle => 'Repair terminal settings?';

  @override
  String get repairTerminalSettingsDescription =>
      'Ianvs Terminal will preserve the original remote document as a recovery copy, fill in the required current-format fields, and retry startup. Profiles and session data are not changed.';

  @override
  String get repairAndRetry => 'Repair and retry';

  @override
  String terminalSettingsRepairFailed(String error) {
    return 'Could not repair terminal settings: $error';
  }

  @override
  String get shellLayoutIdle => 'Shell layout is idle';

  @override
  String get startShellLayout => 'Start a shell layout';

  @override
  String get lastSessionClosedHelp =>
      'The last session has closed. Open a new tab to keep working in the shell layout.';

  @override
  String get openNewTabToStart =>
      'Open a new tab to start working in the shell layout.';

  @override
  String currentNewTabProfile(String profile) {
    return 'Current new-tab profile • $profile';
  }

  @override
  String configuredDefaultProfile(String profile) {
    return 'Configured default • $profile';
  }

  @override
  String get noProfileAvailable => 'No profile available';

  @override
  String get connectWithSsh => 'Connect with SSH';

  @override
  String get createSshConnectionFirstTab =>
      'Create an SSH connection to open your first tab.';

  @override
  String get chooseSavedProfileForTab =>
      'Choose a saved profile to open a terminal tab.';

  @override
  String get localSessionsUnavailableOnIphone =>
      'Local terminal sessions are unavailable on iPhone.';

  @override
  String get noSshProfilesYet => 'No SSH profiles yet';

  @override
  String get newSshConnection => 'New SSH Connection';

  @override
  String get newTerminalTab => 'New terminal tab';

  @override
  String get newSshTab => 'New SSH tab';

  @override
  String get chooseLocalShellOrSsh =>
      'Choose a local shell or connect to an SSH host.';

  @override
  String get chooseSavedSshOrCreate =>
      'Choose a saved SSH profile or create a new one.';

  @override
  String get localShell => 'Local shell';

  @override
  String get sshSession => 'SSH session';

  @override
  String get newSshConnectionLower => 'New SSH connection';

  @override
  String get newOneTimeSshConnection => 'New one-time SSH connection';

  @override
  String get connectionWillNotBeSaved => 'This connection will not be saved';

  @override
  String get remoteDataRequiredToSaveSsh =>
      'Connect a remote data service to save reusable SSH profiles. You can still connect once without an Ianvs account or data service.';

  @override
  String get searchSshProfiles => 'Search SSH profiles';

  @override
  String get searchByNameHostUser => 'Search by name, host, or user';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get savedSshProfiles => 'Saved SSH profiles';

  @override
  String get fromOpenSshConfig => 'From ~/.ssh/config';

  @override
  String get openSshProfilesUnavailable => 'OpenSSH profiles unavailable';

  @override
  String get noConcreteSshHosts => 'No concrete SSH hosts found';

  @override
  String get noMatchingSshProfiles => 'No matching SSH profiles';

  @override
  String get tryDifferentNameHostUser => 'Try a different name, host, or user.';

  @override
  String moreActionsFor(String name) {
    return 'More actions for $name';
  }

  @override
  String get connect => 'Connect';

  @override
  String get profiles => 'Profiles';

  @override
  String get savedSshProfilesRequireRemote =>
      'Saved SSH profiles require a remote data service on iPhone.';

  @override
  String get openSavedSshOrEdit =>
      'Open a saved SSH profile or edit its terminal settings.';

  @override
  String get openSavedProfileOrEdit =>
      'Open a tab with any saved profile or edit its terminal settings.';

  @override
  String get noMatchingProfiles => 'No matching profiles';

  @override
  String get noSavedProfiles => 'No saved profiles';

  @override
  String get noProfilesYet => 'No profiles yet';

  @override
  String get tryDifferentProfileSearch =>
      'Try a different profile name, shell, or tag.';

  @override
  String get connectRemoteToCreateSyncSsh =>
      'Connect a remote data service to create and sync SSH profiles.';

  @override
  String get createSshProfileToConnect =>
      'Create an SSH profile to connect to a remote host.';

  @override
  String get createProfileToCustomize =>
      'Create a profile to customize a terminal session.';

  @override
  String get createProfile => 'Create profile';

  @override
  String get connectRemoteToCreateSavedSsh =>
      'Connect a remote data service to create saved SSH profiles';

  @override
  String get newAction => 'New';

  @override
  String get closeProfiles => 'Close profiles';

  @override
  String get searchProfilesOrTags => 'Search profiles or tags';

  @override
  String editNamedItem(String name) {
    return 'Edit $name';
  }

  @override
  String deleteNamedItem(String name) {
    return 'Delete $name';
  }

  @override
  String get newProfile => 'New profile';

  @override
  String get runShellOnDevice => 'Run a shell on this device.';

  @override
  String get connectRemoteHost => 'Connect to a remote host.';

  @override
  String scrollbackLineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines',
      one: '1 line',
    );
    return '$_temp0';
  }

  @override
  String get defaultProfile => 'Default profile';

  @override
  String get defaultsAppearanceSubtitle =>
      'Pick the default profile for new tabs and choose how the shell follows the app theme.';

  @override
  String get closeDefaults => 'Close defaults';

  @override
  String get useAutomaticFallback => 'Use automatic fallback';

  @override
  String get noProfileForNewTabs => 'No profile is available for new tabs.';

  @override
  String newTabsUseProfileAutomatically(String profile) {
    return 'New tabs use $profile automatically until you choose a fixed default.';
  }

  @override
  String automaticFallbackProfile(String profile) {
    return 'Automatic fallback • $profile';
  }

  @override
  String get unknownProfile => 'Unknown profile';

  @override
  String get terminalPreset => 'Terminal preset';

  @override
  String get createProfileBeforeColors =>
      'Create a profile before choosing terminal colors.';

  @override
  String applyPaletteToProfile(String profile) {
    return 'Apply a curated terminal color palette to $profile.';
  }

  @override
  String get filterTerminalPresets => 'Filter terminal presets';

  @override
  String get keepCurrent => 'Keep current';

  @override
  String get customColors => 'Custom colors';

  @override
  String currentlyPreset(String preset) {
    return 'Currently $preset';
  }

  @override
  String selectedTerminalPreset(String preset) {
    return '$preset, selected';
  }

  @override
  String noTerminalPresetsMatch(String query) {
    return 'No terminal presets match “$query”.';
  }

  @override
  String get startup => 'Startup';

  @override
  String get startupLayoutDescription =>
      'Choose whether the terminal should rebuild your last tab and pane arrangement.';

  @override
  String get restoreTabsAndPanes => 'Restore tabs and panes on launch';

  @override
  String get restoreTabsAndPanesDescription =>
      'Starts new shell processes and restores their folders. Running processes are not resumed.';

  @override
  String get language => 'Language';

  @override
  String get languageDescription =>
      'Choose the language used by the application interface.';

  @override
  String languageModeName(String mode) {
    String _temp0 = intl.Intl.selectLogic(mode, {
      'system': 'Follow system',
      'english': 'English',
      'simplifiedChinese': '简体中文',
      'other': '$mode',
    });
    return '$_temp0';
  }

  @override
  String languageModeDescription(String mode) {
    String _temp0 = intl.Intl.selectLogic(mode, {
      'system': 'Use the preferred language from this device.',
      'english': 'Always display the app in English.',
      'simplifiedChinese': '始终使用简体中文显示应用。',
      'other': '$mode',
    });
    return '$_temp0';
  }

  @override
  String get generalSettingsDescription =>
      'Choose the default profile for new tabs and the language used by the app.';

  @override
  String get appearanceSettingsDescription =>
      'Customize terminal colors, startup behavior, and the app theme.';

  @override
  String get appearance => 'Appearance';

  @override
  String themeModeName(String mode) {
    String _temp0 = intl.Intl.selectLogic(mode, {
      'system': 'System',
      'light': 'Light',
      'dark': 'Dark',
      'other': '$mode',
    });
    return '$_temp0';
  }

  @override
  String themeModeDescription(String mode) {
    String _temp0 = intl.Intl.selectLogic(mode, {
      'system': 'Follow the current device appearance.',
      'light': 'Keep the shell app in light mode.',
      'dark': 'Keep the shell app in dark mode.',
      'other': '$mode',
    });
    return '$_temp0';
  }

  @override
  String get terminalCanvasInset => 'Terminal canvas inset';

  @override
  String get terminalCanvasInsetDescription =>
      'Adjust the empty space between the shell frame and terminal text.';

  @override
  String get viewportPadding => 'Viewport padding';

  @override
  String pixelCount(int count) {
    return '$count pixels';
  }

  @override
  String get decreaseViewportPadding => 'Decrease viewport padding';

  @override
  String get increaseViewportPadding => 'Increase viewport padding';

  @override
  String viewportPaddingRange(int minimum, int maximum) {
    return 'Range $minimum–$maximum px';
  }

  @override
  String get viewportPaddingDescription =>
      'Lower values keep the prompt close to the edges; higher values create a larger terminal gutter.';

  @override
  String get resetDefault => 'Reset default';

  @override
  String get resetTheme => 'Reset theme';

  @override
  String get migrateToRemoteApi => 'Migrate to remote API';

  @override
  String get migrateToLocalApi => 'Migrate to local API';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get detailedSettingsInProfiles =>
      'Detailed terminal settings live in Profiles.';

  @override
  String get editTerminalDetailsInProfiles =>
      'Edit font, colors, cursor, scrollback, and startup arguments from the Profiles editor.';

  @override
  String editProfileInProfiles(String profile) {
    return 'Edit $profile in Profiles';
  }

  @override
  String get keyboardShortcuts => 'Keyboard shortcuts';

  @override
  String get keyboardShortcutsDescription =>
      'Select a shortcut to record a new key combination. Changes apply immediately after saving.';

  @override
  String get keyboardShortcutsNavigationDescription =>
      'Customize key combinations for terminal actions.';

  @override
  String get manageShortcuts => 'Manage shortcuts';

  @override
  String get backToDefaultsAppearance => 'Back to Defaults & appearance';

  @override
  String get moreShortcutActions => 'More shortcut actions';

  @override
  String get done => 'Done';

  @override
  String get filterShortcutActions => 'Filter shortcut actions';

  @override
  String get filterActions => 'Filter actions';

  @override
  String get category => 'Category';

  @override
  String get allActions => 'All actions';

  @override
  String get restoreAllDefaults => 'Restore all defaults';

  @override
  String get noMatchingActions => 'No matching actions';

  @override
  String get tryAnotherActionOrCategory =>
      'Try another action name or category.';

  @override
  String shortcutConflictSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count shortcut conflicts. Resolve conflicts before saving.',
      one: '1 shortcut conflict. Resolve conflicts before saving.',
    );
    return '$_temp0';
  }

  @override
  String get resolveShortcutConflicts =>
      'Resolve shortcut conflicts before saving';

  @override
  String get addShortcut => 'Add shortcut';

  @override
  String editShortcutFor(String action) {
    return 'Edit shortcut for $action';
  }

  @override
  String disableShortcutFor(String action) {
    return 'Disable shortcut for $action';
  }

  @override
  String restoreShortcutFor(String action) {
    return 'Restore default shortcut for $action';
  }

  @override
  String get recordShortcut => 'Record shortcut';

  @override
  String get activeWhen => 'Active when';

  @override
  String get waitingForShortcut => 'Waiting for shortcut';

  @override
  String recordedShortcut(String shortcut) {
    return 'Recorded $shortcut';
  }

  @override
  String get pressShortcut => 'Press a shortcut';

  @override
  String get shortcutCaptureHelp =>
      'Press Escape to cancel, or Delete to disable this shortcut.';

  @override
  String get disableShortcut => 'Disable shortcut';

  @override
  String get apply => 'Apply';

  @override
  String get copyMasterKeyQuestion => 'Copy the master key?';

  @override
  String get copyMasterKeyWarning =>
      'Anyone with this key can decrypt your Ianvs data. The key will be placed on the system clipboard; paste it into the destination app and then clear the clipboard.';

  @override
  String get copyKey => 'Copy key';

  @override
  String get importMasterKey => 'Import master key';

  @override
  String get ianvsMasterKey => 'Ianvs master key';

  @override
  String get masterKeyPasteHelp =>
      'Paste the complete value beginning with ianvs-key-v1.';

  @override
  String get masterKey => 'Master key';

  @override
  String get appleEncryptionManagedAutomatically =>
      'Encryption is managed automatically on this Apple device.';

  @override
  String get portableMasterKeyDescription =>
      'One portable key unlocks local, remote, and SSH profile encryption across supported platforms.';

  @override
  String get appleMasterKeyStorageDescription =>
      'Ianvs Terminal stores the master key in iCloud Keychain and requests synchronization automatically. No manual key entry is required.';

  @override
  String get copyForAnotherDevice => 'Copy for another device';

  @override
  String get pasteFromAnotherDevice => 'Paste from another device';

  @override
  String get closeSftpPanel => 'Close SFTP panel';

  @override
  String get copyFullPath => 'Copy full path';

  @override
  String get editLocally => 'Edit locally';

  @override
  String get createDirectory => 'Create directory';

  @override
  String copiedPath(String path) {
    return 'Copied $path';
  }

  @override
  String createdNamedItem(String name) {
    return 'Created $name';
  }

  @override
  String couldNotCreateNamedItem(String name) {
    return 'Could not create $name.';
  }

  @override
  String get name => 'Name';

  @override
  String get create => 'Create';

  @override
  String deleteNamedItemQuestion(String name) {
    return 'Delete $name?';
  }

  @override
  String get directoryMustBeEmpty =>
      'The directory must be empty before it can be deleted.';

  @override
  String get remoteFileDeletedPermanently =>
      'This remote file will be deleted permanently.';

  @override
  String deletedNamedItem(String name) {
    return 'Deleted $name';
  }

  @override
  String couldNotDeleteNamedItem(String name) {
    return 'Could not delete $name.';
  }

  @override
  String sftpPanelFor(String address) {
    return 'SFTP panel for $address';
  }

  @override
  String get remoteRoot => 'Remote root';

  @override
  String get parentDirectory => 'Parent directory';

  @override
  String get refreshRemoteDirectory => 'Refresh remote directory';

  @override
  String get loadingRemoteDirectory => 'Loading remote directory';

  @override
  String get unableLoadRemoteDirectory =>
      'Unable to load the remote directory.';

  @override
  String get remoteFilesUnavailable => 'Remote files unavailable';

  @override
  String get remoteDirectoryEmpty => 'This remote directory is empty.';

  @override
  String remoteEntrySemantics(String type, String name) {
    return '$type $name';
  }

  @override
  String get folder => 'Folder';

  @override
  String get file => 'File';

  @override
  String get sshHostKeyChanged => 'SSH host key changed';

  @override
  String get trustThisSshHost => 'Trust this SSH host?';

  @override
  String get sshHostKeyChangedWarning =>
      'The key saved for this server does not match the key it presented now. Only continue if you verified the new fingerprint; accepting replaces the saved key.';

  @override
  String get sshUnknownHostWarning =>
      'Strict verification has no saved key for this server. Verify the fingerprint before trusting it.';

  @override
  String get server => 'Server';

  @override
  String get algorithm => 'Algorithm';

  @override
  String get sha256Fingerprint => 'SHA-256 fingerprint';

  @override
  String get reject => 'Reject';

  @override
  String get replaceKeyAndContinue => 'Replace key and continue';

  @override
  String get trustAndContinue => 'Trust and continue';

  @override
  String get sshAuthentication => 'SSH authentication';

  @override
  String responseNumber(int number) {
    return 'Response $number';
  }

  @override
  String get responseHidden => 'Your response is hidden.';

  @override
  String get editProfile => 'Edit profile';

  @override
  String get discardChangesQuestion => 'Discard changes?';

  @override
  String get discardProfileChangesWarning =>
      'You have unsaved profile changes. Close the editor and lose them?';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get discardChanges => 'Discard changes';

  @override
  String get findProfileSetting => 'Find profile setting';

  @override
  String get findSetting => 'Find setting';

  @override
  String get clearSettingsSearch => 'Clear settings search';

  @override
  String get noSettingsFound => 'No settings found';

  @override
  String sectionsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sections found',
      one: '1 section found',
    );
    return '$_temp0';
  }

  @override
  String modifiedSections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count modified sections',
      one: '1 modified section',
    );
    return '$_temp0';
  }

  @override
  String noProfileSettingsMatch(String query) {
    return 'No profile settings match “$query”.';
  }

  @override
  String get profileEditorSectionNavigation =>
      'Profile editor section navigation';

  @override
  String get profileEditorDialog => 'Profile editor dialog';

  @override
  String get profileChangesNewSessionsOnly =>
      'Changes apply to new sessions only. Existing tabs keep the profile snapshot they started with.';

  @override
  String get closeProfileEditor => 'Close profile editor';

  @override
  String profileSectionName(String section) {
    String _temp0 = intl.Intl.selectLogic(section, {
      'general': 'General',
      'startup': 'Startup',
      'terminal': 'Terminal',
      'appearance': 'Appearance',
      'keys': 'Keys',
      'automation': 'Automation',
      'advanced': 'Advanced',
      'other': '$section',
    });
    return '$_temp0';
  }

  @override
  String resetProfileSection(String section) {
    return 'Reset $section';
  }

  @override
  String profileSectionSemantics(String section, String modified) {
    String _temp0 = intl.Intl.selectLogic(modified, {
      'true': ', modified',
      'other': '',
    });
    return '$section profile section$_temp0';
  }

  @override
  String get sshConnection => 'SSH connection';

  @override
  String get connectOnceOrSaveProfile =>
      'Connect once or save a reusable session profile.';

  @override
  String get connection => 'Connection';

  @override
  String get connectionSectionDescription =>
      'Name the session and enter the destination address.';

  @override
  String get sessionName => 'Session name';

  @override
  String get exampleProduction => 'For example, Production';

  @override
  String get host => 'Host';

  @override
  String get hostnameOrIp => 'hostname or IP address';

  @override
  String get user => 'User';

  @override
  String get remoteUser => 'remote user';

  @override
  String get port => 'Port';

  @override
  String get authentication => 'Authentication';

  @override
  String get authenticationDescription =>
      'Choose how the server should verify your identity.';

  @override
  String get method => 'Method';

  @override
  String get authenticationMethod => 'Authentication method';

  @override
  String get automaticKeysThenPassword => 'Automatic (keys, then password)';

  @override
  String get privateKey => 'Private key';

  @override
  String get keyboardInteractiveOtp => 'Keyboard interactive / OTP';

  @override
  String get passwordFallback => 'Password fallback';

  @override
  String get passwordFallbackHelp =>
      'Used only when key authentication is unavailable.';

  @override
  String get forgetSavedPassword => 'Forget saved password';

  @override
  String get privateKeyDescription =>
      'The selected path is shown here. Only the encrypted key contents are saved.';

  @override
  String get privateKeyFile => 'Private key file';

  @override
  String get select => 'Select';

  @override
  String get replace => 'Replace';

  @override
  String get forgetSavedPrivateKey => 'Forget saved private key';

  @override
  String get privateKeyPassphrase => 'Private key passphrase';

  @override
  String get privateKeyPassphraseHelp =>
      'Leave blank for an unencrypted private key.';

  @override
  String get forgetSavedKeyPassphrase => 'Forget saved key passphrase';

  @override
  String get keyboardInteractiveHelp =>
      'The server will ask for each required response after the connection starts, including multi-step OTP challenges.';

  @override
  String get hostVerificationAdvanced =>
      'Host verification and advanced options';

  @override
  String get hostVerificationAdvancedDescription =>
      'Host keys, jump hosts, tunnels, agent and X11 forwarding';

  @override
  String get hostKeyPolicy => 'Host key policy';

  @override
  String get acceptNewHostsRecommended => 'Accept new hosts (recommended)';

  @override
  String get askBeforeTrusting => 'Ask before trusting';

  @override
  String get doNotVerifyUnsafe => 'Do not verify (unsafe)';

  @override
  String get knownHostsFileOptional => 'Known hosts file (optional)';

  @override
  String get proxyCommandOptional => 'ProxyCommand (optional)';

  @override
  String get proxyJumpOptional => 'ProxyJump (optional)';

  @override
  String get proxyJumpHelp =>
      'Comma-separated [user@]host[:port]; bracket IPv6 hosts. New hops use independent Auto authentication.';

  @override
  String get portForwards => 'Port forwards';

  @override
  String get portForwardsHelp =>
      'One per line: L bind:port target:port, R bind:port target:port, or D bind:port.';

  @override
  String get forwardSshAgent => 'Forward SSH agent';

  @override
  String get agentSocketHelp => 'Blank socket path uses SSH_AUTH_SOCK.';

  @override
  String get agentSocketOptional => 'Agent socket (optional)';

  @override
  String get forwardX11 => 'Forward X11';

  @override
  String get x11ForwardingHelp =>
      'Blank target uses DISPLAY; a 32-character MIT-MAGIC-COOKIE is required.';

  @override
  String get localX11Target => 'Local X11 target host:port';

  @override
  String get x11AuthenticationCookie => 'X11 authentication cookie';

  @override
  String get x11CookieRequired =>
      'Required: exactly 32 hexadecimal characters.';

  @override
  String get forgetSavedX11Cookie => 'Forget saved X11 cookie';

  @override
  String get saveThisSshSession => 'Save this SSH session';

  @override
  String get secretsEncryptedDescription =>
      'Secrets are encrypted; the key stays in platform safe storage.';

  @override
  String get remoteServiceRequiredToSaveProfile =>
      'A remote data service is required to save profiles. This connection is one-time only.';

  @override
  String get requiredField => 'Required';

  @override
  String enterRange(int minimum, int maximum) {
    return 'Enter $minimum–$maximum';
  }

  @override
  String get connectTimeoutSeconds => 'Connect timeout (seconds)';

  @override
  String get keepaliveSeconds => 'Keepalive (seconds)';

  @override
  String get keepaliveRetries => 'Keepalive retries';

  @override
  String get general => 'General';

  @override
  String get generalProfileDescription =>
      'Name and tag the profile before configuring launch behavior.';

  @override
  String get tags => 'Tags';

  @override
  String get tagsCommaHelp => 'Separate tags with commas.';

  @override
  String get profileStartupDescription =>
      'Configure the command, working directory, and process environment.';

  @override
  String get command => 'Command';

  @override
  String get shellProgram => 'Shell / Program';

  @override
  String get workingDirectory => 'Working directory';

  @override
  String get workingDirectoryHelp =>
      'Leave empty to use the default working directory.';

  @override
  String get argumentsAndEnvironment => 'Arguments and environment';

  @override
  String get arguments => 'Arguments';

  @override
  String get terminal => 'Terminal';

  @override
  String get terminalProfileDescription =>
      'Choose terminal emulation and retained scrollback for new sessions.';

  @override
  String get emulation => 'Emulation';

  @override
  String get scrollbackLines => 'Scrollback lines';

  @override
  String get profileAppearanceDescription =>
      'Control typography, colors, and cursor behavior.';

  @override
  String get typography => 'Typography';

  @override
  String get fontFamily => 'Font family';

  @override
  String get fallbackFonts => 'Fallback fonts';

  @override
  String get fontSize => 'Font size';

  @override
  String get lineHeight => 'Line height';

  @override
  String get colors => 'Colors';

  @override
  String get specialColors => 'Special';

  @override
  String get ansiNormal => 'ANSI normal';

  @override
  String get ansiBright => 'ANSI bright';

  @override
  String get cursor => 'Cursor';

  @override
  String get cursorShape => 'Cursor shape';

  @override
  String get blinkCursor => 'Blink cursor';

  @override
  String get keys => 'Keys';

  @override
  String get keysProfileDescription =>
      'Choose selection defaults for newly opened sessions.';

  @override
  String get selection => 'Selection';

  @override
  String get copyOnSelect => 'Copy on select';

  @override
  String get optionDragMode => 'Option-drag mode';

  @override
  String get automation => 'Automation';

  @override
  String get automationProfileDescription =>
      'Match terminal output, then notify you or type a fixed reply.';

  @override
  String get rules => 'Rules';

  @override
  String get triggers => 'Triggers';

  @override
  String get triggerExamples =>
      'Examples: ERROR => notify, Password: => send: secret';

  @override
  String get automaticProfileSwitching => 'Automatic profile switching';

  @override
  String get automaticProfileSwitchingHelp =>
      'Change this profile after host, user, or directory changes.';

  @override
  String get advanced => 'Advanced';

  @override
  String get advancedProfileDescription =>
      'Control shell-aware profile behavior for new sessions.';

  @override
  String get integration => 'Integration';

  @override
  String get shellIntegration => 'Shell Integration';

  @override
  String get shellIntegrationDescription =>
      'Enable prompt marks, badges, command navigation, and shell-aware actions.';

  @override
  String get toolbeltTerminalTools => 'Toolbelt terminal tools';

  @override
  String get closeToolbelt => 'Close toolbelt';

  @override
  String get promptMarks => 'Prompt Marks';

  @override
  String promptMarkCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count marks',
      one: '1 mark',
    );
    return '$_temp0';
  }

  @override
  String get tmuxIntegration => 'tmux integration';

  @override
  String get controlModeActive => 'Control mode active';

  @override
  String get startOrAttach => 'Start or attach';

  @override
  String get coprocess => 'Coprocess';

  @override
  String get automationActive => 'Automation active';

  @override
  String get runAutomation => 'Run automation';

  @override
  String get annotations => 'Annotations';

  @override
  String annotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes',
      one: '1 note',
    );
    return '$_temp0';
  }

  @override
  String get recentFrames => 'Recent frames';

  @override
  String get passwordManager => 'Password manager';

  @override
  String get promptGatedSends => 'Prompt-gated sends';

  @override
  String get commands => 'Commands';

  @override
  String get directoriesShort => 'Dirs';

  @override
  String get output => 'Output';

  @override
  String get paste => 'Paste';

  @override
  String get commandHistory => 'Command History';

  @override
  String commandCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count commands',
      one: '1 command',
    );
    return '$_temp0';
  }

  @override
  String get all => 'All';

  @override
  String get runCommandToFillHistory =>
      'Run a command in this tab to fill command history.';

  @override
  String get insertCommand => 'Insert command';

  @override
  String get recentDirectories => 'Recent Directories';

  @override
  String directoryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count directories',
      one: '1 directory',
    );
    return '$_temp0';
  }

  @override
  String get changeDirectoriesToFillHistory =>
      'Change directories to fill recent directories.';

  @override
  String get insertCdCommand => 'Insert cd command';

  @override
  String get capturedOutput => 'Captured output';

  @override
  String capturedLineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count captured lines',
      one: '1 captured line',
    );
    return '$_temp0';
  }

  @override
  String get open => 'Open';

  @override
  String get profileAutomationCapturesOutput =>
      'Profile triggers and coprocesses can capture output.';

  @override
  String capturedOutputLocation(String pattern, int row) {
    return 'Pattern $pattern · Row $row';
  }

  @override
  String get pasteHistory => 'Paste history';

  @override
  String recentItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recent items',
      one: '1 recent item',
    );
    return '$_temp0';
  }

  @override
  String get copiedAndPastedTextAppearsHere =>
      'Copied and pasted text appears here.';

  @override
  String get copied => 'Copied';

  @override
  String get pasted => 'Pasted';

  @override
  String get advancedPaste => 'Advanced Paste';

  @override
  String get closeAdvancedPaste => 'Close advanced paste';

  @override
  String get pasteText => 'Paste text';

  @override
  String get text => 'Text';

  @override
  String get escapeSpecialCharacters => 'Escape special characters';

  @override
  String get base64Encode => 'Base64 encode';

  @override
  String get appendNewline => 'Append newline';

  @override
  String byteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bytes',
      one: '1 byte',
    );
    return '$_temp0';
  }

  @override
  String get closeCapturedOutput => 'Close captured output';

  @override
  String get clear => 'Clear';

  @override
  String get startCapturingMatchingOutput => 'Start capturing matching output';

  @override
  String get capturedOutputEmptyBody =>
      'Captured rows appear after a profile trigger or coprocess pattern matches terminal output.';

  @override
  String get openProfilesAndAddTrigger =>
      'Open Profiles and add a trigger pattern.';

  @override
  String get runCommandThatPrintsPattern =>
      'Run a command that prints the pattern.';

  @override
  String get reopenCapturedOutput =>
      'Reopen Captured Output to review and copy matches.';

  @override
  String get copyCapturedOutput => 'Copy captured output';

  @override
  String get closeAnnotations => 'Close annotations';

  @override
  String get selectTerminalTextToAnnotate =>
      'Select terminal text to add an annotation.';

  @override
  String get note => 'Note';

  @override
  String get addAnnotation => 'Add Annotation';

  @override
  String get addFirstAnnotation => 'Add the first annotation';

  @override
  String get selectOutputBeforeAnnotating => 'Select output before annotating';

  @override
  String get annotationSelectionReadyBody =>
      'Use the note field above to attach a note to the selected terminal output.';

  @override
  String get annotationSelectionRequiredBody =>
      'Annotations are created from selected terminal text in the active pane.';

  @override
  String get enterNoteForSelectedOutput =>
      'Enter a note for the selected output.';

  @override
  String get saveAnnotation => 'Save the annotation.';

  @override
  String get useAnnotationBadge =>
      'Use the annotation badge to reopen notes later.';

  @override
  String get selectTerminalOutputInPane =>
      'Select terminal output in the pane.';

  @override
  String get openAnnotationsAgain => 'Open Annotations again.';

  @override
  String get enterNoteAndSave => 'Enter a note and save it.';

  @override
  String get removeAnnotation => 'Remove annotation';

  @override
  String get closePasteHistory => 'Close paste history';

  @override
  String get saveHistoryToDisk => 'Save History to Disk';

  @override
  String get keepPasteHistoryAcrossLaunches =>
      'Keep recent copied and pasted text across launches.';

  @override
  String get noPasteHistoryYet => 'No copied or pasted text yet.';

  @override
  String get closePasswordManager => 'Close password manager';

  @override
  String get passwordPromptDetected =>
      'Password prompt detected in the active session.';

  @override
  String get openPasswordPromptFirst =>
      'Open a password prompt before sending a password.';

  @override
  String get passwordManagerSessionSecurity =>
      'Passwords are kept for this app session and can only be sent when the active terminal appears to be asking for one.';

  @override
  String get label => 'Label';

  @override
  String get serverOrAccount => 'Server or account';

  @override
  String get passwordEntered => 'Password entered';

  @override
  String get add => 'Add';

  @override
  String get noSavedSessionPasswords =>
      'No saved passwords in this session. Add one above, then open a password prompt before sending.';

  @override
  String get readyToSend => 'Ready to send';

  @override
  String get waitingForPasswordPrompt => 'Waiting for password prompt';

  @override
  String get removePassword => 'Remove password';

  @override
  String get send => 'Send';

  @override
  String get closeCoprocess => 'Close coprocess';

  @override
  String get runCoprocess => 'Run Coprocess';

  @override
  String get onePerSession => 'one per session';

  @override
  String get commandLabel => 'Command label';

  @override
  String get inputPattern => 'Input pattern';

  @override
  String get coprocessOutput => 'Coprocess output';

  @override
  String get run => 'Run';

  @override
  String lineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines',
      one: '1 line',
    );
    return '$_temp0';
  }

  @override
  String patternValue(String pattern) {
    return 'Pattern $pattern';
  }

  @override
  String get stop => 'Stop';

  @override
  String get closeTmuxIntegration => 'Close tmux integration';

  @override
  String get controlMode => 'Control Mode';

  @override
  String get startTmuxControlMode => 'Start tmux -CC';

  @override
  String get startTmuxControlModeDescription =>
      'Create a new tmux control-mode session.';

  @override
  String get attachTmuxControlMode => 'Attach tmux -CC';

  @override
  String get attachTmuxControlModeDescription =>
      'Attach to an existing tmux session.';

  @override
  String get tmuxActions => 'tmux Actions';

  @override
  String get available => 'available';

  @override
  String get waiting => 'waiting';

  @override
  String get newWindow => 'New window';

  @override
  String get newWindowDescription => 'Send new-window to tmux control mode.';

  @override
  String get splitPaneRight => 'Split pane right';

  @override
  String get splitPaneRightDescription => 'Send split-window -h.';

  @override
  String get splitPaneDown => 'Split pane down';

  @override
  String get splitPaneDownDescription => 'Send split-window -v.';

  @override
  String get detachClient => 'Detach client';

  @override
  String get detachClientDescription => 'Detach while leaving tmux running.';

  @override
  String get sendTmuxCommand => 'Send tmux command';

  @override
  String get tmuxCommand => 'tmux command';

  @override
  String get controlModeDetected => 'Control mode detected';

  @override
  String get noTmuxControlModeDetected => 'No tmux control mode detected';

  @override
  String get closeShellIntegration => 'Close shell integration';

  @override
  String get runCommandAfterOpeningTab =>
      'Run a command after opening this tab to fill command history.';

  @override
  String get insertPreviousCommand => 'Insert previous command';

  @override
  String get changeDirectoriesAfterOpeningTab =>
      'Change directories after opening this tab to fill this list.';

  @override
  String get promptMarksAppearAfterPrompt =>
      'Prompt marks appear after the shell draws new prompts.';

  @override
  String get commandSucceededShort => 'ok';

  @override
  String commandExitCodeShort(int code) {
    return 'exit $code';
  }

  @override
  String globalLine(int line) {
    return 'Global line $line';
  }

  @override
  String scrollbackOffset(int offset) {
    return 'Offset $offset';
  }

  @override
  String get shellPromptMark => 'Shell prompt mark';

  @override
  String get regexError => 'Regex error';

  @override
  String get noMatches => 'No matches';

  @override
  String get smartCaseSubstring => 'Smart Case Substring';

  @override
  String get caseSensitiveSubstring => 'Case-Sensitive Substring';

  @override
  String get caseInsensitiveSubstring => 'Case-Insensitive Substring';

  @override
  String get caseSensitiveRegex => 'Case-Sensitive Regex';

  @override
  String get caseInsensitiveRegex => 'Case-Insensitive Regex';

  @override
  String searchFilterValue(String filter) {
    return 'Search filter: $filter';
  }

  @override
  String get searchFilter => 'Search filter';

  @override
  String get filter => 'Filter';

  @override
  String get currentTab => 'Current tab';

  @override
  String get allTabs => 'All tabs';

  @override
  String get paneShort => 'Pane';

  @override
  String get tabShort => 'Tab';

  @override
  String get scope => 'Scope';

  @override
  String searchScopeValue(String scope) {
    return 'Search scope: $scope';
  }

  @override
  String get clearSearchText => 'Clear search text';

  @override
  String searchResultValue(String result) {
    return 'Search result: $result';
  }

  @override
  String get search => 'Search';

  @override
  String get previousMatch => 'Previous match';

  @override
  String get nextMatch => 'Next match';

  @override
  String get closeSearch => 'Close search';

  @override
  String searchingAcrossSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions',
      one: '1 session',
    );
    return 'Searching across $_temp0';
  }

  @override
  String matchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matches',
      one: '1 match',
    );
    return '$_temp0';
  }

  @override
  String get closeGlobalSearch => 'Close global search';

  @override
  String searchResultLocation(String session, int row) {
    return '$session · row $row';
  }

  @override
  String get noMatchesInReplayHistory => 'No matches in replay history.';

  @override
  String uniqueReplayMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unique matches in replay',
      one: '1 unique match in replay',
    );
    return '$_temp0';
  }

  @override
  String idleGapValue(String duration) {
    return 'Idle gap: $duration';
  }

  @override
  String get noReplayFrames => 'No replay frames';

  @override
  String recordedAtDimensions(int columns, int rows) {
    return 'Recorded at ${columns}x$rows';
  }

  @override
  String get noReplayFramesCapturedYet => 'No replay frames captured yet.';

  @override
  String get replayRecentActivityLayout => 'Replay recent activity layout';

  @override
  String get closeReplay => 'Close replay';

  @override
  String get terminalChanged => 'Terminal changed';

  @override
  String get replayControlsRecentActivity =>
      'Replay controls for recent activity';

  @override
  String get retentionDisabled => 'Retention disabled';

  @override
  String retainsLatestFrames(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count frames',
      one: '1 frame',
    );
    return 'Retains latest $_temp0';
  }

  @override
  String get recentActivity => 'Recent activity';

  @override
  String get stepBackInReplay => 'Step back in replay';

  @override
  String get pauseReplay => 'Pause replay';

  @override
  String get playReplay => 'Play replay';

  @override
  String get stepForwardInReplay => 'Step forward in replay';

  @override
  String playbackSpeedValue(String speed) {
    return 'Playback speed $speed times';
  }

  @override
  String get playbackSpeed => 'Playback speed';

  @override
  String get realTimeShort => 'Real';

  @override
  String get smartTimeShort => 'Smart';

  @override
  String replayTimingValue(String mode) {
    return '$mode replay timing';
  }

  @override
  String get replayTiming => 'Replay timing';

  @override
  String get smartReplayTimingDescription => 'Smart · skip long idle gaps';

  @override
  String get realReplayTimingDescription => 'Real time · preserve all gaps';

  @override
  String get fitRecordedSize => 'Fit recorded size';

  @override
  String get copyVisible => 'Copy visible';

  @override
  String get copySelection => 'Copy selection';

  @override
  String get clearHistory => 'Clear history';

  @override
  String get searchReplay => 'Search replay';

  @override
  String get previousSearchMatch => 'Previous search match';

  @override
  String get nextSearchMatch => 'Next search match';

  @override
  String get savedTerminalRecordings => 'Saved terminal recordings';

  @override
  String get savedRecordings => 'Saved Recordings';

  @override
  String get importEllipsis => 'Import…';

  @override
  String get refreshRecordings => 'Refresh recordings';

  @override
  String get closeSavedRecordings => 'Close Saved Recordings';

  @override
  String get searchRecordings => 'Search recordings';

  @override
  String get filterPlayableOnly => 'Filter: Playable only';

  @override
  String get filterAllRecordings => 'Filter: All recordings';

  @override
  String get filterRecordings => 'Filter recordings';

  @override
  String get allRecordings => 'All recordings';

  @override
  String get playableOnly => 'Playable only';

  @override
  String recordingSortValue(String sort) {
    return 'Sort: $sort';
  }

  @override
  String get recordingSortOrder => 'Recording sort order';

  @override
  String get newest => 'Newest';

  @override
  String get oldest => 'Oldest';

  @override
  String get recordingsMayContainSensitiveOutput =>
      'Recordings may contain sensitive terminal output.';

  @override
  String get recordingMayContainSensitiveOutput =>
      'This recording may contain sensitive output.';

  @override
  String recordingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recordings',
      one: '1 recording',
    );
    return '$_temp0';
  }

  @override
  String get noMatchingRecordings => 'No matching recordings';

  @override
  String get noSavedRecordings => 'No saved recordings';

  @override
  String actionsForNamedItem(String name) {
    return 'Actions for $name';
  }

  @override
  String get recordingActions => 'Recording actions';

  @override
  String get renameEllipsis => 'Rename…';

  @override
  String get revealInFinder => 'Reveal in Finder';

  @override
  String get exportEllipsis => 'Export…';

  @override
  String get moveToTrash => 'Move to Trash';

  @override
  String couldNotStartReplay(String error) {
    return 'Could not start replay: $error';
  }

  @override
  String couldNotSeekRecording(String error) {
    return 'Could not seek recording: $error';
  }

  @override
  String get inputIncluded => 'Input included';

  @override
  String get keystrokesRedactedCommandMetadataIncluded =>
      'Keystrokes redacted · command metadata included';

  @override
  String get keystrokesRedacted => 'Keystrokes redacted';

  @override
  String get recordedSession => 'Recorded session';

  @override
  String recordingDetail(String session, String disclosure) {
    return '$session · $disclosure';
  }

  @override
  String get preparingReplay => 'Preparing replay…';

  @override
  String replayRecordingLayout(String name) {
    return 'Replay recording layout for $name';
  }

  @override
  String get recording => 'Recording';

  @override
  String matchesAcrossReplay(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matches across replay',
      one: '1 match across replay',
    );
    return '$_temp0';
  }

  @override
  String get replayControlsForRecording => 'Replay controls for recording';

  @override
  String get idleInterval => 'Idle interval';

  @override
  String get inputEvent => 'Input event';

  @override
  String get terminalResized => 'Terminal resized';

  @override
  String get sessionExited => 'Session exited';

  @override
  String get outputEvent => 'Output event';

  @override
  String get activity => 'Activity';

  @override
  String get remoteActivity => 'Remote activity';

  @override
  String commandNumber(int number) {
    return 'Command $number';
  }

  @override
  String replayTimelineSemantics(
    String context,
    String position,
    String duration,
  ) {
    return '$context, $position of $duration';
  }

  @override
  String exitCode(int code) {
    return 'Exit code $code';
  }

  @override
  String jumpToReplaySegment(String segment, String time) {
    return 'Jump to $segment at $time';
  }

  @override
  String get remote => 'Remote';

  @override
  String get idle => 'Idle';

  @override
  String get remoteSession => 'Remote session';

  @override
  String get idleGap => 'Idle gap';

  @override
  String get shellSemantics => 'Shell semantics';

  @override
  String get activityFallbackNoShellHook => 'Activity fallback · no shell hook';

  @override
  String terminalActionName(String action) {
    String _temp0 = intl.Intl.selectLogic(action, {
      'new_tab': 'New tab',
      'new_ssh_session': 'New SSH session',
      'new_tab_at_folder': 'New tab at folder',
      'open_recording_for_replay': 'Open recording for replay',
      'duplicate_current_cwd': 'Duplicate current directory',
      'reopen_closed_tab': 'Reopen closed tab',
      'open_launcher': 'Open launcher',
      'open_command_menu': 'Open command menu',
      'toolbelt': 'Toolbelt',
      'open_sftp_panel': 'Open SFTP panel',
      'split_right': 'Split right',
      'split_down': 'Split down',
      'focus_next_pane': 'Focus next pane',
      'focus_previous_pane': 'Focus previous pane',
      'resize_pane': 'Resize pane',
      'swap_pane': 'Swap pane',
      'zoom_pane': 'Zoom pane',
      'close_pane': 'Close pane',
      'reopen_closed_pane': 'Reopen closed pane',
      'close_active_tab': 'Close active tab',
      'open_defaults': 'Open defaults',
      'activate_tab': 'Activate tab',
      'copy': 'Copy',
      'copy_mode': 'Copy mode',
      'copy_command_output': 'Copy command output',
      'paste': 'Paste',
      'advanced_paste': 'Advanced paste',
      'paste_history': 'Paste history',
      'toggle_read_only': 'Toggle read-only',
      'toggle_replay_recording': 'Toggle replay recording',
      'clear_buffer': 'Clear buffer',
      'shell_integration': 'Shell integration',
      'select_command_output': 'Select command output',
      'open_recent_directory': 'Open recent directory',
      'tmux_integration': 'tmux integration',
      'coprocess': 'Coprocess',
      'annotations': 'Annotations',
      'captured_output': 'Captured output',
      'password_manager': 'Password manager',
      'replay_recent_activity': 'Replay recent activity',
      'search_scrollback': 'Search scrollback',
      'next_search_match': 'Next search match',
      'previous_search_match': 'Previous search match',
      'clear_search': 'Clear search',
      'global_search': 'Global search',
      'autocomplete': 'Autocomplete',
      'auto_composer': 'Auto composer',
      'hotkey_window': 'Hotkey window',
      'defaults': 'Defaults',
      'profiles': 'Profiles',
      'dynamic_profiles': 'Dynamic profiles',
      'request_quit_confirmation': 'Request quit confirmation',
      'previous_prompt': 'Previous prompt',
      'next_prompt': 'Next prompt',
      'toggle_command_finished_notify': 'Toggle command-finished notifications',
      'toggle_bell_notify': 'Toggle bell notifications',
      'toggle_activity_monitor': 'Toggle activity monitor',
      'export_scrollback': 'Export scrollback',
      'export_diagnostics': 'Export diagnostics',
      'open_theme_picker': 'Open theme picker',
      'apply_theme': 'Apply theme',
      'apply_layout_template': 'Apply layout template',
      'other': '$action',
    });
    return '$_temp0';
  }

  @override
  String get appCategory => 'App';

  @override
  String get sessionCategory => 'Session';

  @override
  String get replayCategory => 'Replay';

  @override
  String get paneCategory => 'Pane';

  @override
  String get layoutCategory => 'Layout';

  @override
  String get navigationCategory => 'Navigation';

  @override
  String get integrationCategory => 'Integration';

  @override
  String get appFocused => 'App focused';

  @override
  String get terminalFocused => 'Terminal focused';

  @override
  String get appWideFallback => 'App-wide fallback';

  @override
  String get commandMenuOpen => 'Command menu open';

  @override
  String get notAssigned => 'Not assigned';

  @override
  String get noShortcut => 'no shortcut';

  @override
  String get shortcutConflict => 'Conflict';

  @override
  String get shortcutDisabled => 'Disabled';

  @override
  String get shortcutCustom => 'Custom';

  @override
  String get shortcutUnassigned => 'Unassigned';

  @override
  String get shortcutActionColumn => 'Action';

  @override
  String get shortcutValueColumn => 'Shortcut';

  @override
  String get shortcutDefault => 'Default';

  @override
  String shortcutActionSemantics(String action, String state, String shortcut) {
    return '$action, $state, $shortcut';
  }

  @override
  String get listAndSeparator => ' and ';

  @override
  String profileColorName(String color) {
    String _temp0 = intl.Intl.selectLogic(color, {
      'special_foreground': 'Foreground',
      'special_background': 'Background',
      'special_cursor': 'Cursor color',
      'special_selection': 'Selection color',
      'special_tab': 'Tab color',
      'normal_black': 'Black',
      'normal_red': 'Red',
      'normal_green': 'Green',
      'normal_yellow': 'Yellow',
      'normal_blue': 'Blue',
      'normal_magenta': 'Magenta',
      'normal_cyan': 'Cyan',
      'normal_white': 'White',
      'bright_black': 'Bright black',
      'bright_red': 'Bright red',
      'bright_green': 'Bright green',
      'bright_yellow': 'Bright yellow',
      'bright_blue': 'Bright blue',
      'bright_magenta': 'Bright magenta',
      'bright_cyan': 'Bright cyan',
      'bright_white': 'Bright white',
      'other': '$color',
    });
    return '$_temp0';
  }

  @override
  String get moveUp => 'Move up';

  @override
  String get moveDown => 'Move down';

  @override
  String get remove => 'Remove';

  @override
  String get environmentVariables => 'Environment variables';

  @override
  String get addVariable => 'Add variable';

  @override
  String get noEnvironmentVariables => 'No environment variables';

  @override
  String get key => 'Key';

  @override
  String get value => 'Value';

  @override
  String environmentVariableKey(int number) {
    return 'Environment variable key $number';
  }

  @override
  String environmentVariableValue(int number) {
    return 'Environment variable value $number';
  }

  @override
  String get variableName => 'Variable name';

  @override
  String get removeVariable => 'Remove variable';

  @override
  String get themePresets => 'Theme presets';

  @override
  String get themePresetsDescription =>
      'Follow the app theme, apply a curated palette, or fine-tune individual colors.';

  @override
  String get followApplicationThemeColors => 'Follow application theme colors';

  @override
  String get followAppTheme => 'Follow app theme';

  @override
  String get followAppThemeDescription =>
      'Terminal background and text update when the application theme changes.';

  @override
  String get pickColor => 'Pick color';

  @override
  String get inheritingDefaultTerminalColor =>
      'Inheriting default terminal color';

  @override
  String currentColorValue(String color) {
    return 'Current color $color';
  }

  @override
  String get hexColorOrEmpty => '#RRGGBB or empty';

  @override
  String get hex => 'Hex';

  @override
  String get palette => 'Palette';

  @override
  String get hue => 'Hue';

  @override
  String get resetToDefault => 'Reset to default';

  @override
  String get pick => 'Pick';

  @override
  String get reset => 'Reset';

  @override
  String pickNamedColor(String name) {
    return 'Pick $name color';
  }

  @override
  String resetNamedColor(String name) {
    return 'Reset $name color';
  }

  @override
  String get colorPalette => 'Color palette';

  @override
  String get hueSlider => 'Hue slider';

  @override
  String get hexColorValidation => 'Use #RRGGBB or leave empty.';

  @override
  String get dynamicProfilesTopLevelObject =>
      'Top-level JSON must be an object.';

  @override
  String get dynamicProfilesNoneFound => 'No profiles found in JSON.';

  @override
  String dynamicProfilesInvalid(String error) {
    return 'Could not read profiles: $error';
  }

  @override
  String dynamicProfilesPreviewSummary(
    int profiles,
    int added,
    int replacements,
    int warnings,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      profiles,
      locale: localeName,
      other: '$profiles profiles ready',
      one: '1 profile ready',
    );
    String _temp1 = intl.Intl.pluralLogic(
      replacements,
      locale: localeName,
      other: '$replacements replacements',
      one: '1 replacement',
    );
    String _temp2 = intl.Intl.pluralLogic(
      warnings,
      locale: localeName,
      other: ' • $warnings warnings',
      one: ' • 1 warning',
      zero: '',
    );
    return '$_temp0 • $added new • $_temp1$_temp2';
  }

  @override
  String get replacesExisting => 'Replaces existing';

  @override
  String get dynamicProfiles => 'Dynamic Profiles';

  @override
  String get closeDynamicProfiles => 'Close dynamic profiles';

  @override
  String get dynamicProfilesPasteHelp =>
      'Paste an iTerm2 dynamic profile JSON document. This local build only launches local commands.';

  @override
  String get import => 'Import';

  @override
  String get osc52Clipboard => 'OSC 52 clipboard';

  @override
  String get osc52ClipboardDescription =>
      'Choose how terminal escape sequences may access the system clipboard.';

  @override
  String get securityPermissions => 'Security & permissions';

  @override
  String get securityPermissionsDescription =>
      'Control how terminal sessions interact with the app and remote system while balancing safety and convenience.';

  @override
  String get sessionInteractionsPermissions =>
      'Session interactions & permissions';

  @override
  String get sessionInteractionsPermissionsDescription =>
      'Manage requests initiated by terminal applications or remote systems and understand their security impact.';

  @override
  String get securityImpact => 'Security impact';

  @override
  String get currentPolicy => 'Current policy';

  @override
  String get riskLevel => 'Risk level';

  @override
  String riskLevelName(String level) {
    String _temp0 = intl.Intl.selectLogic(level, {
      'low': 'Low',
      'medium': 'Medium',
      'high': 'High',
      'other': '$level',
    });
    return '$_temp0';
  }

  @override
  String get behaviorBoundary => 'Behavior boundary';

  @override
  String get recommendation => 'Why this is recommended';

  @override
  String get recommendedSetting => 'Recommended';

  @override
  String permissionRecommendation(String permission) {
    String _temp0 = intl.Intl.selectLogic(permission, {
      'osc52':
          'Per-profile control balances clipboard convenience with protection for sensitive content.',
      'openUrl':
          'Per-request confirmation prevents remote content from opening external links without explicit consent.',
      'attention':
          'Deny nonessential alerts to avoid interruption; allow bounded attention only when needed.',
      'other':
          'Keeping an explicit user confirmation helps control interactions initiated by terminal content.',
    });
    return '$_temp0';
  }

  @override
  String get manageDecisions => 'Manage decisions';

  @override
  String get terminalUrlRequests => 'Terminal URL requests';

  @override
  String get terminalUrlRequestsDescription =>
      'Choose whether OSC 1337 OpenURL requests may ask for permission. URLs are never opened automatically.';

  @override
  String get terminalAttentionRequests => 'Terminal attention requests';

  @override
  String get terminalAttentionRequestsDescription =>
      'Choose whether OSC 1337 RequestAttention may use a bounded Dock alert or a cursor-local visual effect. Requests never activate or focus the app.';

  @override
  String get terminalVariableReports => 'Terminal variable reports';

  @override
  String get terminalVariableReportsDescription =>
      'OSC 1337 ReportVariable requests are denied the first time. Remembered decisions apply only to the named session.* or user.* variable.';

  @override
  String get noRememberedDecisions => 'No remembered decisions';

  @override
  String rememberedDecisionSummary(int count, int allowed, int denied) {
    return '$count remembered · $allowed allowed · $denied denied';
  }

  @override
  String get forgettingDecisionsHelp =>
      'Forgetting decisions restores the safe first-request denial and lets the app ask again later.';

  @override
  String get allow => 'Allow';

  @override
  String get deny => 'Deny';

  @override
  String forgetDecisionFor(String name) {
    return 'Forget decision for $name';
  }

  @override
  String get forgetAllDecisions => 'Forget all decisions';

  @override
  String get dataService => 'Data service';

  @override
  String get dataServiceDescriptionLocalAvailable =>
      'Choose whether the app starts a local data service or connects to a remote one.';

  @override
  String get dataServiceDescriptionRemoteOnly =>
      'Use one-time SSH connections without a data service, or connect a remote service to save profiles and sync them.';

  @override
  String activeDataService(String service) {
    return 'Active data service: $service';
  }

  @override
  String activeNow(String service) {
    return 'Active now: $service';
  }

  @override
  String currentlyRunning(String service) {
    return 'Currently running: $service';
  }

  @override
  String get running => 'Running';

  @override
  String get selected => 'Selected';

  @override
  String get dataServiceMode => 'Mode';

  @override
  String get apiService => 'API service';

  @override
  String get configurationAndStorage => 'Configuration & storage';

  @override
  String get crossDeviceSync => 'Cross-device sync';

  @override
  String dataModeApiSummary(String deployment) {
    String _temp0 = intl.Intl.selectLogic(deployment, {
      'disabled': 'No API process',
      'local': 'Start the local API service',
      'remote': 'Connect to a remote API',
      'other': '$deployment',
    });
    return '$_temp0';
  }

  @override
  String dataModeStorageSummary(String deployment) {
    String _temp0 = intl.Intl.selectLogic(deployment, {
      'disabled': 'Use local shell configuration',
      'local': 'Persist offline on this Mac',
      'remote': 'Store with the remote service',
      'other': '$deployment',
    });
    return '$_temp0';
  }

  @override
  String dataModeSyncSummary(String deployment) {
    String _temp0 = intl.Intl.selectLogic(deployment, {
      'disabled': 'No sync',
      'local': 'No sync',
      'remote': 'Sync devices after sign-in',
      'other': '$deployment',
    });
    return '$_temp0';
  }

  @override
  String get localTerminal => 'Local terminal';

  @override
  String get noDataService => 'No data service';

  @override
  String get bundledLocalService => 'Bundled local service';

  @override
  String get remoteService => 'Remote service';

  @override
  String get localTerminalNoApiDescription =>
      'No API process. Use local shells and hosts from ~/.ssh/config only.';

  @override
  String get noDataServiceDescription =>
      'No API process. Create one-time SSH connections without saving them.';

  @override
  String get bundledLocalServiceDescription =>
      'Offline API persistence and custom SSH profiles on this Mac.';

  @override
  String get migrateRemoteApiData => 'Migrate remote API data';

  @override
  String get migrateRemoteApiDataDescription =>
      'The app starts a temporary bundled API and merges remote resources before switching. Remote data is retained if startup, export, or merge fails.';

  @override
  String get remoteServiceDescription =>
      'Custom SSH profiles, persistent settings, and cross-device sync over HTTPS.';

  @override
  String get migrateLocalApiData => 'Migrate local API data';

  @override
  String get migrateLocalApiDataDescription =>
      'The app exports and merges local resources before switching. Local data is retained if authentication, export, or merge fails.';

  @override
  String get reconnectRequested => 'Reconnect requested';

  @override
  String get reconnectSignIn => 'Reconnect / sign in';

  @override
  String get remoteApiBaseUrl => 'Remote API base URL';

  @override
  String get loginPasswordHelp => 'Used only for this login request.';

  @override
  String get appleMasterKeyEncryptionDescription =>
      'Encryption uses the one Ianvs master key managed automatically by iCloud Keychain.';

  @override
  String get deviceMasterKeyEncryptionDescription =>
      'Encryption uses the one Ianvs master key stored on this device. Export or import it in Master key management when moving to another platform.';

  @override
  String get dataServiceRestartNotice =>
      'The selection is stored in the app configuration and takes effect after restart.';

  @override
  String get enterRemoteApiBaseUrl => 'Enter the remote API base URL.';

  @override
  String get invalidRemoteApiBaseUrl => 'Enter a valid remote API base URL.';

  @override
  String get usernameValidation =>
      'Use 3–64 lowercase letters, numbers, . _ or -.';

  @override
  String get passwordValidation => 'Use 12–72 UTF-8 bytes.';

  @override
  String osc52PolicyName(String policy) {
    String _temp0 = intl.Intl.selectLogic(policy, {
      'disabled': 'Deny',
      'profile': 'Profile',
      'allow': 'Allow',
      'ask': 'Ask',
      'other': '$policy',
    });
    return '$_temp0';
  }

  @override
  String osc52PolicyDescription(String policy) {
    String _temp0 = intl.Intl.selectLogic(policy, {
      'disabled': 'Block OSC 52 clipboard copy and paste-read requests.',
      'profile':
          'Allow clipboard writes and prompt before paste-read requests.',
      'allow':
          'Allow trusted terminal sessions to use OSC 52 without prompting.',
      'ask': 'Prompt before each OSC 52 clipboard write or paste-read request.',
      'other': '$policy',
    });
    return '$_temp0';
  }

  @override
  String openUrlPolicyName(String policy) {
    String _temp0 = intl.Intl.selectLogic(policy, {
      'disabled': 'Deny',
      'ask': 'Ask every time',
      'other': '$policy',
    });
    return '$_temp0';
  }

  @override
  String openUrlPolicyDescription(String policy) {
    String _temp0 = intl.Intl.selectLogic(policy, {
      'disabled':
          'Block every OSC 1337 OpenURL request without showing a dialog.',
      'ask':
          'Require confirmation for each accepted request from the active terminal.',
      'other': '$policy',
    });
    return '$_temp0';
  }

  @override
  String requestAttentionPolicyName(String policy) {
    String _temp0 = intl.Intl.selectLogic(policy, {
      'disabled': 'Deny',
      'allow': 'Allow with limits',
      'other': '$policy',
    });
    return '$_temp0';
  }

  @override
  String requestAttentionPolicyDescription(String policy) {
    String _temp0 = intl.Intl.selectLogic(policy, {
      'disabled':
          'Block OSC 1337 RequestAttention. Cancellation requests are still honored.',
      'allow':
          'Allow rate-limited Dock attention and a short cursor-local visual effect.',
      'other': '$policy',
    });
    return '$_temp0';
  }

  @override
  String get osc5522PasteDeliveryFailed =>
      'OSC 5522 paste event could not be delivered.';

  @override
  String get confirmPaste => 'Confirm paste';

  @override
  String pasteCharacterLineCount(int characters, int lines) {
    String _temp0 = intl.Intl.pluralLogic(
      characters,
      locale: localeName,
      other: '$characters characters',
      one: '1 character',
    );
    String _temp1 = intl.Intl.pluralLogic(
      lines,
      locale: localeName,
      other: '$lines lines',
      one: '1 line',
    );
    return 'Paste $_temp0 across $_temp1?';
  }

  @override
  String get clearRecentReplayHistoryQuestion => 'Clear recent replay history?';

  @override
  String get clearRecentReplayHistoryWarning =>
      'Recent activity frames for this pane will be removed from Replay. This action cannot be undone.';

  @override
  String get recordingReplayStarted =>
      'Recording for Replay started. Keystrokes are redacted; shell command metadata is included when available.';

  @override
  String recordingSavedNamed(String name) {
    return 'Recording saved · $name';
  }

  @override
  String get reveal => 'Reveal';

  @override
  String couldNotOpenRecording(String error) {
    return 'Could not open recording: $error';
  }

  @override
  String couldNotLoadRecordings(String error) {
    return 'Could not load recordings: $error';
  }

  @override
  String get recordingImported => 'Recording imported';

  @override
  String couldNotImportRecording(String error) {
    return 'Could not import recording: $error';
  }

  @override
  String get renameRecording => 'Rename recording';

  @override
  String get recordingName => 'Recording name';

  @override
  String get rename => 'Rename';

  @override
  String couldNotRenameRecording(String error) {
    return 'Could not rename recording: $error';
  }

  @override
  String couldNotRevealRecording(String error) {
    return 'Could not reveal recording: $error';
  }

  @override
  String get recordingExported => 'Recording exported';

  @override
  String couldNotExportRecording(String error) {
    return 'Could not export recording: $error';
  }

  @override
  String get moveRecordingToTrashQuestion => 'Move recording to Trash?';

  @override
  String recordingRemovedFromSaved(String name) {
    return '“$name” will be removed from Saved Recordings.';
  }

  @override
  String get recordingMovedToTrash => 'Recording moved to Trash';

  @override
  String couldNotRemoveRecording(String error) {
    return 'Could not remove recording: $error';
  }

  @override
  String get noTerminalSessionOptionAvailable =>
      'No terminal session option is available.';

  @override
  String get closeTabRequiresActiveSession =>
      'Close tab requires an active session.';

  @override
  String get closeTabRequiresActiveTab => 'Close tab requires an active tab.';

  @override
  String get duplicateCwdRequiresProfileSession =>
      'Duplicate current directory requires a default profile and active session.';

  @override
  String get noCurrentDirectoryAvailable =>
      'No current directory is available.';

  @override
  String get remoteDirectoryCannotDuplicate =>
      'Remote-reported current directories cannot be duplicated as local sessions.';

  @override
  String get noDuplicatedSessionCreated => 'No duplicated session was created.';

  @override
  String get noRecentlyClosedTabAvailable =>
      'No recently closed tab is available.';

  @override
  String get noRecentlyClosedPaneForTab =>
      'No recently closed pane is available for this tab.';

  @override
  String get noRecentlyClosedPaneReopened =>
      'No recently closed pane could be reopened.';

  @override
  String get closePaneRequiresActiveSession =>
      'Close pane requires an active session.';

  @override
  String get splitRightRequiresProfileSession =>
      'Split right requires a default profile and active session.';

  @override
  String get splitRightUnavailable => 'Split right is unavailable.';

  @override
  String get splitDownRequiresProfileSession =>
      'Split down requires a default profile and active session.';

  @override
  String get splitDownUnavailable => 'Split down is unavailable.';

  @override
  String get focusNextPaneRequiresSession =>
      'Focus next pane requires an active session.';

  @override
  String get noNextPaneAvailable => 'No next pane is available.';

  @override
  String get focusPreviousPaneRequiresSession =>
      'Focus previous pane requires an active session.';

  @override
  String get noPreviousPaneAvailable => 'No previous pane is available.';

  @override
  String get resizePaneRequiresSession =>
      'Resize pane requires an active session.';

  @override
  String get resizePaneRequiresTwoPanes =>
      'Resize pane requires at least two panes.';

  @override
  String get swapPaneRequiresSession => 'Swap pane requires an active session.';

  @override
  String get swapPaneRequiresTwoPanes =>
      'Swap pane requires at least two panes.';

  @override
  String get zoomPaneRequiresSession => 'Zoom pane requires an active session.';

  @override
  String get zoomPaneRequiresTwoPanes =>
      'Zoom pane requires at least two panes.';

  @override
  String get copyRequiresSession => 'Copy requires an active session.';

  @override
  String get copyRequiresSelectionController =>
      'Copy requires an active selection controller.';

  @override
  String get copyCommandOutputRequiresSession =>
      'Copy command output requires an active session.';

  @override
  String get noCommandOutputAvailable =>
      'No command output is available to copy.';

  @override
  String get copyModeRequiresSession => 'Copy mode requires an active session.';

  @override
  String get pasteRequiresSession => 'Paste requires an active session.';

  @override
  String get advancedPasteRequiresSession =>
      'Advanced paste requires an active session.';

  @override
  String get pasteHistoryRequiresSession =>
      'Paste history requires an active session.';

  @override
  String get replayRequiresSession =>
      'Replay recent activity requires an active session.';

  @override
  String get readOnlyRequiresSession =>
      'Read-only mode requires an active session.';

  @override
  String get readOnlyEnabledNotice =>
      'Read-only mode enabled. Input is blocked for this pane.';

  @override
  String get readOnlyDisabledNotice =>
      'Read-only mode disabled. Input is active for this pane.';

  @override
  String get clearBufferRequiresSession =>
      'Clear buffer requires an active session.';

  @override
  String get bufferClearedCommandKept =>
      'Buffer cleared. The current command line was kept.';

  @override
  String get clearBufferRequiresNative =>
      'Clear buffer requires native runtime support.';

  @override
  String get bufferCleared => 'Cleared buffer.';

  @override
  String get clearBufferUnsupported =>
      'Clear buffer is not supported by this runtime.';

  @override
  String get globalSearchRequiresTab =>
      'Global search requires at least one tab.';

  @override
  String get autocompleteRequiresSession =>
      'Autocomplete requires an active session.';

  @override
  String get autoComposerRequiresSession =>
      'Auto composer requires an active session.';

  @override
  String get searchRequiresSession => 'Search requires an active session.';

  @override
  String get previousPromptRequiresSession =>
      'Previous prompt requires an active session.';

  @override
  String get nextPromptRequiresSession =>
      'Next prompt requires an active session.';

  @override
  String get selectCommandOutputRequiresSession =>
      'Select command output requires an active session.';

  @override
  String get shellIntegrationRequiresSession =>
      'Shell integration utilities require an active session.';

  @override
  String get openRecentDirectoryRequiresSession =>
      'Open recent directory requires an active session.';

  @override
  String get noRecentDirectoryAvailable => 'No recent directory is available.';

  @override
  String get tmuxIntegrationRequiresSession =>
      'tmux integration requires an active session.';

  @override
  String get coprocessRequiresSession =>
      'Coprocess requires an active session.';

  @override
  String get annotationsRequireSession =>
      'Annotations require an active session.';

  @override
  String get capturedOutputRequiresSession =>
      'Captured output requires an active session.';

  @override
  String get passwordManagerRequiresSession =>
      'Password manager requires an active session.';

  @override
  String get hotkeyWindowUnavailable => 'Hotkey window is unavailable.';

  @override
  String get layoutTemplateRequiresProfileSession =>
      'Apply layout template requires a default profile and active session.';

  @override
  String get noActiveTabForLayoutTemplates =>
      'No active tab is available for layout templates.';

  @override
  String get twoPaneLayoutAlreadySatisfied =>
      'Two-pane layout template is already satisfied.';

  @override
  String get layoutTemplateUnavailable =>
      'Apply layout template is unavailable.';

  @override
  String get exportScrollbackRequiresSession =>
      'Export scrollback requires an active session.';

  @override
  String get noVisibleContentToExport =>
      'No visible terminal content is available to export.';

  @override
  String get scrollbackExported => 'Scrollback exported';

  @override
  String get exportedTerminalScrollback => 'Exported terminal scrollback.';

  @override
  String get exportDiagnosticsRequiresSession =>
      'Export diagnostics requires an active session.';

  @override
  String get diagnosticsExportUnavailable =>
      'Diagnostics export is unavailable for the active sessions.';

  @override
  String get diagnosticsExported => 'Diagnostics exported';

  @override
  String get exportedTerminalDiagnostics => 'Exported terminal diagnostics.';

  @override
  String commandFinishedNotificationsSaved(String enabled) {
    String _temp0 = intl.Intl.selectLogic(enabled, {
      'true': 'enabled',
      'other': 'disabled',
    });
    return 'Command-finished notifications $_temp0 and saved.';
  }

  @override
  String bellNotificationsSaved(String enabled) {
    String _temp0 = intl.Intl.selectLogic(enabled, {
      'true': 'enabled',
      'other': 'disabled',
    });
    return 'Bell notifications $_temp0 and saved.';
  }

  @override
  String activityMonitorSaved(String enabled) {
    String _temp0 = intl.Intl.selectLogic(enabled, {
      'true': 'enabled',
      'other': 'disabled',
    });
    return 'Activity monitor $_temp0 and saved.';
  }

  @override
  String unableSaveNotifications(String error) {
    return 'Unable to save notifications: $error';
  }

  @override
  String get unableSaveCommandFinishedNotifications =>
      'Unable to save command-finished notifications.';

  @override
  String get unableSaveBellNotifications =>
      'Unable to save bell notifications.';

  @override
  String get unableSaveActivityMonitor =>
      'Unable to save activity monitor notifications.';

  @override
  String get noDefaultProfileAvailable => 'No default profile is available.';

  @override
  String get addAnotherPaneForAction => 'Add another pane to use this action.';

  @override
  String unavailableReason(String reason) {
    return 'Unavailable: $reason';
  }

  @override
  String get duplicateCurrentDirectory => 'Duplicate current directory';

  @override
  String get applyTwoPaneLayout => 'Apply two-pane layout';

  @override
  String get tabAlreadyMultiplePanes => 'This tab already has multiple panes.';

  @override
  String get growActivePane => 'Grow active pane';

  @override
  String get swapActivePane => 'Swap active pane';

  @override
  String get closeActivePane => 'Close active pane';

  @override
  String get movedToNewTab => 'Moved to a new tab';

  @override
  String panePosition(int index, int count) {
    return 'Pane $index/$count';
  }

  @override
  String get splitRight => 'Split right';

  @override
  String get splitDown => 'Split down';

  @override
  String splitRightUnavailableReason(String reason) {
    return 'Split right unavailable: $reason';
  }

  @override
  String splitDownUnavailableReason(String reason) {
    return 'Split down unavailable: $reason';
  }

  @override
  String get activePane => 'Active pane';

  @override
  String get inactivePane => 'Inactive pane';

  @override
  String paneContextUntitled(String id, String state) {
    return 'Pane: $id · $state';
  }

  @override
  String paneContextTitled(String title, String id, String state) {
    return 'Pane: $title ($id) · $state';
  }

  @override
  String get openLink => 'Open link';

  @override
  String get copyLink => 'Copy link';

  @override
  String get copyLinkText => 'Copy link text';

  @override
  String get showTarget => 'Show target';

  @override
  String get copiedLinkTarget => 'Copied link target';

  @override
  String get copiedLinkText => 'Copied link text';

  @override
  String get unknown => 'unknown';

  @override
  String blockedLinkScheme(String scheme) {
    return 'Blocked link scheme: $scheme';
  }

  @override
  String get blockedFileLink => 'Blocked file link';

  @override
  String get couldNotOpenLink => 'Could not open link';

  @override
  String couldNotOpenLinkDetails(String error) {
    return 'Could not open link: $error';
  }

  @override
  String get openLocalFileLinkQuestion => 'Open local file link?';

  @override
  String get terminalRequestsLocalFile =>
      'The terminal is asking to open a local file URL.';

  @override
  String sourceValue(String source) {
    return 'Source: $source';
  }

  @override
  String linkTextOpensTarget(String text, String target) {
    return 'Link text “$text” opens $target';
  }

  @override
  String linkTargetValue(String target) {
    return 'Link target: $target';
  }

  @override
  String get clickToFocusPane => 'Click to focus this pane.';

  @override
  String get remoteContextReported =>
      'Remote context reported by shell integration.';

  @override
  String hostValue(String host) {
    return 'Host: $host';
  }

  @override
  String userValue(String user) {
    return 'User: $user';
  }

  @override
  String get localFileActionsDisabledRemote =>
      'Local file actions stay disabled for remote paths.';

  @override
  String get terminalProgressInPane => 'Terminal progress in this pane.';

  @override
  String osc1337BadgeValue(String badge) {
    return 'OSC 1337 badge: $badge';
  }

  @override
  String get alternateScreenActive => 'Alternate screen buffer is active.';

  @override
  String mouseReportingActive(String mode, String encoding) {
    return 'Mouse reporting is active: $mode, $encoding.';
  }

  @override
  String get mimePasteActive =>
      'OSC 5522 paste events are active and take precedence over bracketed paste.';

  @override
  String get bracketedPasteActive => 'Bracketed paste mode is active.';

  @override
  String get focusReportingActive =>
      'Focus reporting is active. The application receives focus-in and focus-out events.';

  @override
  String get synchronizedOutputActive =>
      'Synchronized output mode is active. Intermediate updates are held until the application flushes.';

  @override
  String get readOnlyPaneActive =>
      'Read-only mode is enabled for this pane. Input and paste sends are blocked.';

  @override
  String get terminalRequestedAttention => 'Terminal requested attention';

  @override
  String dragPaneToSplit(String title) {
    return 'Drag $title to split or move it to the tab bar';
  }

  @override
  String dropToTarget(String target) {
    return 'Drop to $target';
  }

  @override
  String get unzoomPane => 'Unzoom pane';

  @override
  String get zoomPane => 'Zoom pane';

  @override
  String get localFile => 'Local file';

  @override
  String protocolHost(String protocol, String host) {
    return '$protocol host: $host';
  }

  @override
  String get openTerminalRequestedUrlQuestion => 'Open terminal-requested URL?';

  @override
  String get terminalRequestedUrlWarning =>
      'The active terminal requested permission to open this URL. Terminal output can be untrusted.';

  @override
  String destinationValue(String destination) {
    return 'Destination: $destination';
  }

  @override
  String get osc1337OpenUrlBlocked => 'OSC 1337 Open URL blocked';

  @override
  String get osc1337OpenUrlSourceInactive =>
      'OSC 1337 Open URL blocked: source is no longer active';

  @override
  String get allowFutureVariableReportsQuestion =>
      'Allow future variable reports?';

  @override
  String get variableReportDeniedHelp =>
      'The current request was denied and received an empty response. Choose whether future terminal programs may read this variable.';

  @override
  String get variable => 'Variable';

  @override
  String get variableReportPrivacyHelp =>
      'Ianvs only reports session-owned title, dimensions, shell context, and user.* values. It never reads host environment variables or files for this request.';

  @override
  String get notNow => 'Not Now';

  @override
  String get alwaysAllow => 'Always Allow';

  @override
  String get alwaysDeny => 'Always Deny';

  @override
  String get variableDecisionSourceInactive =>
      'Variable-reporting decision not saved: source is no longer active';

  @override
  String futureVariableReportsAllowed(String name) {
    return 'Future reports of $name are allowed';
  }

  @override
  String futureVariableReportsDenied(String name) {
    return 'Future reports of $name are denied';
  }

  @override
  String receivedFile(String name, String size) {
    return 'Received $name ($size)';
  }

  @override
  String allowClipboardCopyQuestion(String protocol) {
    return 'Allow $protocol clipboard copy?';
  }

  @override
  String allowPasteReadQuestion(String protocol) {
    return 'Allow $protocol paste read?';
  }

  @override
  String allowClipboardWriteQuestion(String protocol) {
    return 'Allow $protocol clipboard write?';
  }

  @override
  String allowClipboardReadQuestion(String protocol) {
    return 'Allow $protocol clipboard read?';
  }

  @override
  String get alwaysAllowLower => 'Always allow';

  @override
  String get session => 'Session';

  @override
  String get mimeTypes => 'MIME types';

  @override
  String get application => 'Application';

  @override
  String get size => 'Size';

  @override
  String characterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count characters',
      one: '1 character',
    );
    return '$_temp0';
  }

  @override
  String get previewUnavailable => 'Preview unavailable';

  @override
  String get clipboardEmpty => 'Clipboard is empty';

  @override
  String get previewTruncated => 'preview truncated';

  @override
  String get terminalRequestsClipboardRead =>
      'The terminal is requesting clipboard contents and will send them back to the session if allowed.';

  @override
  String get terminalRequestsClipboardWrite =>
      'The terminal wants to write the following text to your clipboard.';

  @override
  String get alwaysAllowClipboardHelp =>
      '“Always allow” permits future OSC 5522 clipboard reads and writes that use this exact application name and password, only for the current terminal session.';

  @override
  String get trustedSessionsOnly => 'Only allow this for trusted sessions.';

  @override
  String get sessionEnded => 'Session ended';

  @override
  String sessionExitedBody(String session, String code) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'none': '',
      'other': ' with code $code',
    });
    return '$session exited$_temp0.';
  }

  @override
  String sessionNamed(String id) {
    return 'Session $id';
  }

  @override
  String paneNamed(int number) {
    return 'pane $number';
  }

  @override
  String get newTerminalOutputAvailable => 'New terminal output is available.';

  @override
  String get osc1337OpenUrlBlockedByPolicy =>
      'OSC 1337 Open URL blocked by policy';

  @override
  String get couldNotOpenSaveDialog => 'Could not open the save dialog';

  @override
  String get receivedFileDiscarded => 'Received file discarded';

  @override
  String get receivedFileUnavailable => 'Received file is no longer available';

  @override
  String couldNotSaveFile(String name) {
    return 'Could not save $name';
  }

  @override
  String savedFile(String name) {
    return 'Saved $name';
  }

  @override
  String fileDownloadRejected(String reason) {
    return 'File download rejected: $reason';
  }

  @override
  String get fileUploadRequestBlocked => 'File upload request blocked';

  @override
  String zmodemTransportFailed(String session, int bytes, int chunks) {
    return 'ZMODEM transport failed in session $session: $bytes bytes in $chunks queued writes were not confirmed. The terminal connection was closed.';
  }

  @override
  String notificationInSession(String title, String session) {
    return '$title in $session';
  }

  @override
  String get zmodemFilePreserved => 'ZMODEM file preserved';

  @override
  String get zmodemFilePreservedBody =>
      'ZMODEM publish failed. A complete file was preserved; focus the pane to reveal or dismiss it.';

  @override
  String get zmodemReceiveCompleted => 'ZMODEM receive completed';

  @override
  String get zmodemSendCompleted => 'ZMODEM send completed';

  @override
  String get zmodemTransferCancelled => 'ZMODEM transfer cancelled';

  @override
  String get zmodemPreservedUnavailable =>
      'ZMODEM publish failed; preserved file is unavailable to reveal';

  @override
  String zmodemTransferFailed(String reason) {
    return 'ZMODEM transfer failed: $reason';
  }

  @override
  String get protocolError => 'protocol error';

  @override
  String get zmodemTransferUpdate => 'ZMODEM transfer update';

  @override
  String get zmodemTransferNeedsAttention => 'ZMODEM transfer needs attention';

  @override
  String get zmodemStateLost =>
      'Transfer state was lost after an event gap. Focus the pane to retry cancellation.';

  @override
  String get remoteSkippedZmodemFile =>
      'Remote skipped a ZMODEM file; continuing the batch';

  @override
  String remoteSkippedNamedFile(String name) {
    return 'Remote skipped $name; continuing the batch';
  }

  @override
  String get zmodemDirectionUnsupported =>
      'This terminal runtime does not support this ZMODEM direction.';

  @override
  String get zmodemFileSelectionUnavailable =>
      'ZMODEM file selection is unavailable on this platform.';

  @override
  String get retryCancellation => 'Retry cancellation.';

  @override
  String get transferWasCancelled => 'The transfer was cancelled.';

  @override
  String get inactiveTransferWasCancelled =>
      'The inactive transfer was cancelled.';

  @override
  String get focusPaneRetryCancellation =>
      'Focus the pane to retry cancellation.';

  @override
  String get zmodemRequestCancelled => 'ZMODEM request cancelled';

  @override
  String get zmodemRequestNeedsAttention => 'ZMODEM request needs attention';

  @override
  String get couldNotCancelAfterSessionChanged =>
      'Could not cancel after the session changed. Retry or cancel again.';

  @override
  String remoteZmodemRequestCancelled(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'send': 'send',
      'other': 'receive',
    });
    return 'A remote $_temp0 request was cancelled because its pane is inactive.';
  }

  @override
  String remoteZmodemRequestCancelFailed(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'send': 'send',
      'other': 'receive',
    });
    return 'A remote $_temp0 request could not be cancelled. Focus the pane to retry.';
  }

  @override
  String get zmodemPickerAlreadyOpen =>
      'A previous ZMODEM file picker is still open. Close it, then retry this transfer.';

  @override
  String get zmodemDestinationSelectionUnavailable =>
      'ZMODEM destination selection is unavailable on this platform.';

  @override
  String get couldNotOpenDestinationPicker =>
      'Could not open the destination picker. Retry or cancel the transfer.';

  @override
  String get sessionChangedCancellationFailed =>
      'The session changed and cancellation failed. Retry cancellation.';

  @override
  String get destinationSelectionCancelled =>
      'Destination selection cancelled. Retry or cancel the transfer.';

  @override
  String get couldNotAuthorizeDestination =>
      'Could not authorize this destination. Retry or cancel the transfer.';

  @override
  String get couldNotOpenFilePicker =>
      'Could not open the file picker. Retry or cancel the transfer.';

  @override
  String get fileSelectionCancelled =>
      'File selection cancelled. Retry or cancel the transfer.';

  @override
  String get zmodemFileLimit =>
      'You can send at most 256 files. Select fewer files and retry.';

  @override
  String get couldNotAuthorizeFiles =>
      'Could not authorize these files. Retry or cancel the transfer.';

  @override
  String get zmodemPickerResultIgnored =>
      'ZMODEM transfer already ended; the picker result was not used.';

  @override
  String get couldNotCancelZmodem =>
      'Could not cancel the ZMODEM transfer. Retry cancellation.';

  @override
  String get couldNotRevealExport => 'Could not reveal export on this platform';

  @override
  String couldNotRevealExportDetails(String error) {
    return 'Could not reveal export: $error';
  }

  @override
  String get zmodemRecoveryUnavailable =>
      'Preserved ZMODEM file is no longer available';

  @override
  String get zmodemRecoveryResolveFailed =>
      'Could not resolve the preserved ZMODEM file; try again';

  @override
  String get couldNotRevealPreservedZmodem =>
      'Could not reveal preserved ZMODEM file';

  @override
  String get couldNotReleaseZmodemRecovery =>
      'Could not release the ZMODEM recovery token';

  @override
  String get couldNotDismissZmodemRecovery =>
      'Could not dismiss the ZMODEM recovery notice';

  @override
  String get preservedZmodemFile => 'the preserved ZMODEM file';

  @override
  String get permanentlyDiscardFileQuestion => 'Permanently discard file?';

  @override
  String zmodemDiscardWarning(String filename) {
    return '$filename is the only recovery copy retained by Ianvs Terminal. Discarding it permanently deletes the file and cannot be undone.';
  }

  @override
  String get discardFile => 'Discard file';

  @override
  String zmodemPreservedSemantics(String filename, String source) {
    return 'ZMODEM file preserved. $filename from $source.';
  }

  @override
  String zmodemPublishFailedPreserved(String filename, String source) {
    return 'ZMODEM publish failed. Complete file preserved as $filename from $source.';
  }

  @override
  String get permanentlyDeletePreservedZmodem =>
      'Permanently delete preserved ZMODEM file';

  @override
  String get discardFileEllipsis => 'Discard file…';

  @override
  String get zmodemProgress => 'ZMODEM progress';

  @override
  String get indeterminate => 'indeterminate';

  @override
  String percentValue(int percent) {
    return '$percent percent';
  }

  @override
  String get cancelling => 'Cancelling…';

  @override
  String notificationButton(int number) {
    return 'Button $number';
  }

  @override
  String notificationAction(int number) {
    return 'Notification action $number';
  }

  @override
  String get closeAndReportToTerminal =>
      'Close and report to the terminal process';

  @override
  String get removeNotification => 'Remove this notification';

  @override
  String get profileTabColor => 'Profile tab color';

  @override
  String get osc21337StatusIndicator => 'OSC 21337 session status indicator';

  @override
  String get dataServiceWarning => 'Data service warning.';

  @override
  String get dismissDataServiceWarning => 'Dismiss data service warning';

  @override
  String replaySource(String source) {
    return 'Replay source: $source';
  }

  @override
  String get dragResizePanesHorizontally => 'Drag to resize panes horizontally';

  @override
  String get dragResizePanesVertically => 'Drag to resize panes vertically';

  @override
  String get completions => 'Completions';

  @override
  String completePrefix(String prefix) {
    return 'Complete \"$prefix\"';
  }

  @override
  String get previousCompletion => 'Previous completion';

  @override
  String get nextCompletion => 'Next completion';

  @override
  String get closeCompletions => 'Close completions';

  @override
  String get composeCommand => 'Compose command';

  @override
  String get sendCommand => 'Send command';

  @override
  String get closeComposer => 'Close composer';

  @override
  String get terminalKeyboardShortcuts => 'Terminal keyboard shortcuts';

  @override
  String get decreaseTerminalTextSize => 'Decrease terminal text size';

  @override
  String get resetTerminalTextSize => 'Reset terminal text size';

  @override
  String get increaseTerminalTextSize => 'Increase terminal text size';

  @override
  String insertTerminalKey(String key) {
    return 'Insert $key';
  }

  @override
  String get dismissKeyboard => 'Dismiss keyboard';

  @override
  String get sshHostKeyPromptInactive =>
      'The SSH host-key confirmation is no longer active.';

  @override
  String get sshAuthenticationPromptInactive =>
      'The SSH authentication challenge is no longer active.';

  @override
  String get dataServiceConfigurationUnavailable =>
      'Data service configuration is unavailable in this build.';

  @override
  String get remoteAuthenticationUnavailable =>
      'Remote authentication is unavailable in this build.';

  @override
  String get localApiMigrationUnavailable =>
      'The active bundled local API is unavailable for migration.';

  @override
  String get remoteToLocalMigrationUnavailable =>
      'Remote-to-local migration is unavailable in this build.';

  @override
  String migrationToRemoteSummary(
    int resources,
    int created,
    int updated,
    int skipped,
  ) {
    return 'Migrated $resources local resources: $created created, $updated updated, $skipped already current. Restart the app to use the remote API.';
  }

  @override
  String migrationToLocalSummary(
    int resources,
    int created,
    int updated,
    int skipped,
  ) {
    return 'Migrated $resources remote resources: $created created, $updated updated, $skipped already current. Restart the app to use the bundled local API.';
  }

  @override
  String get dataServiceConfigurationSaved =>
      'Data service configuration saved. Restart the app to apply it.';

  @override
  String unableToSaveDataServiceConfiguration(String error) {
    return 'Unable to save the data service configuration: $error';
  }

  @override
  String get deleteProfileQuestion => 'Delete profile?';

  @override
  String deleteProfileWarning(String name) {
    return 'Delete “$name”? Open terminal tabs will keep their current session settings.';
  }

  @override
  String deletedProfile(String name) {
    return 'Deleted profile “$name”.';
  }

  @override
  String get profileWasNotDeleted => 'Profile was not deleted';

  @override
  String profileStillStored(String name, String destination) {
    return '“$name” is still stored in $destination.';
  }

  @override
  String get newSshProfile => 'New SSH Profile';

  @override
  String savedProfileTo(String name, String destination) {
    return 'Saved profile “$name” to $destination.';
  }

  @override
  String profileStorageDestination(String deployment) {
    String _temp0 = intl.Intl.selectLogic(deployment, {
      'remote': 'Remote service',
      'local': 'Bundled local service',
      'other': 'profile storage',
    });
    return '$_temp0';
  }

  @override
  String get profileWasNotSaved => 'Profile was not saved';

  @override
  String profileNotWritten(String name, String destination) {
    return '“$name” was not written to $destination. It will not appear on your other devices.';
  }

  @override
  String get profileSaveFailureConnectOnceHelp =>
      'You can cancel and try saving again, or explicitly continue with a one-time connection.';

  @override
  String get cancelConnection => 'Cancel connection';

  @override
  String get ok => 'OK';

  @override
  String get connectOnceWithoutSaving => 'Connect once without saving';

  @override
  String get profilesChangedElsewhere =>
      'Profiles changed on another device while this save was in progress. Reload the profiles and try again.';

  @override
  String get remoteServiceAuthenticationExpired =>
      'The Remote service session is no longer authenticated. Open Data service settings, sign in again, and retry the save.';

  @override
  String get remoteServiceTimeout =>
      'The Remote service did not respond in time. Check the network connection and try again.';

  @override
  String remoteServiceRejectedSave(int status, String code, String message) {
    return 'Remote service rejected the save ($status/$code): $message';
  }

  @override
  String remoteServiceInvalidResponse(String message) {
    return 'The Remote service returned an invalid response: $message';
  }

  @override
  String get persistentSshProfilesRequireService =>
      'Persistent SSH profiles require a connected bundled local or Remote service. Open Data service settings and connect one first.';

  @override
  String saveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String dynamicProfilesImported(
    int total,
    int added,
    int replaced,
    int warnings,
  ) {
    return 'Imported $total dynamic profiles ($added new, $replaced replaced, $warnings warnings).';
  }

  @override
  String get passwordSendBlockedNoPrompt =>
      'Password send blocked: no password prompt is active.';

  @override
  String sshProfileStored(String action, String name, String destination) {
    String _temp0 = intl.Intl.selectLogic(action, {
      'saved': 'Saved',
      'other': 'Imported',
    });
    return '$_temp0 SSH profile “$name” to $destination.';
  }

  @override
  String get dragReplayControls =>
      'Drag replay controls. Double tap to reset position.';

  @override
  String get localTerminalObjectiveComplete =>
      'Local terminal objective is complete';

  @override
  String get localTerminalObjectiveBlocked =>
      'Local terminal objective is blocked';

  @override
  String get milestones => 'Milestones';

  @override
  String get backlog => 'Backlog';

  @override
  String get verification => 'Verification';

  @override
  String get blockedMilestones => 'Blocked milestones';

  @override
  String get missingProductionMilestones => 'Missing production milestones';

  @override
  String get blockedRealWiringBacklog => 'Blocked real-wiring backlog';

  @override
  String get missingRealWiringBacklog => 'Missing real-wiring backlog';

  @override
  String get blockedVerificationGates => 'Blocked verification gates';

  @override
  String get missingVerificationGates => 'Missing verification gates';

  @override
  String get completion => 'Completion';

  @override
  String get unavailableInCurrentContext =>
      'Unavailable in the current context.';

  @override
  String get terminalModeAlt => 'ALT';

  @override
  String get terminalModeMouse => 'MOUSE';

  @override
  String get terminalModeMimePaste => 'MIME PASTE';

  @override
  String get terminalModePaste => 'PASTE';

  @override
  String get terminalModeFocus => 'FOCUS';

  @override
  String get terminalModeKeys => 'KEYS';

  @override
  String get terminalModeSync => 'SYNC';

  @override
  String get terminalModeReadOnly => 'READ ONLY';

  @override
  String get saveImageAs => 'Save Image As…';

  @override
  String get copyImage => 'Copy Image';

  @override
  String get openImage => 'Open Image';

  @override
  String get inspect => 'Inspect';

  @override
  String get imageInformation => 'Image Information';

  @override
  String get protocol => 'Protocol';

  @override
  String get sourceSize => 'Source size';

  @override
  String get displaySize => 'Display size';

  @override
  String get visibleArea => 'Visible area';

  @override
  String get cellPosition => 'Cell position';

  @override
  String get renderId => 'Render ID';

  @override
  String get placementId => 'Placement ID';

  @override
  String get asset => 'Asset';

  @override
  String get couldNotOpenImageSaveDialog =>
      'Could not open the image save dialog';

  @override
  String get couldNotSaveImage => 'Could not save image';

  @override
  String get savedImage => 'Saved image';

  @override
  String get couldNotCopyImage => 'Could not copy image';

  @override
  String get copiedImage => 'Copied image';

  @override
  String get unfoldTerminalBlock => 'Unfold terminal block';

  @override
  String get foldTerminalBlock => 'Fold terminal block';

  @override
  String get unfoldBlock => 'Unfold block';

  @override
  String get foldBlock => 'Fold block';

  @override
  String get renderedTerminalDocument => 'Rendered terminal document';

  @override
  String get closeRenderedDocument => 'Close rendered document';

  @override
  String get closeTerminalTextDocument => 'Close terminal text document';

  @override
  String get openTerminalImagePreview => 'Open terminal image preview';

  @override
  String get terminalImagePreview => 'Terminal image preview';

  @override
  String get closeImagePreview => 'Close image preview';

  @override
  String get current => 'current';

  @override
  String oscClipboardCopied(String protocol, int count) {
    return '$protocol copied $count characters to the clipboard';
  }

  @override
  String oscClipboardCopyBlocked(String protocol) {
    return '$protocol clipboard copy blocked by policy';
  }

  @override
  String oscClipboardCopyInvalid(String protocol) {
    return '$protocol clipboard copy ignored: invalid payload';
  }

  @override
  String oscPasteReadReplied(String protocol, int count) {
    return '$protocol paste read replied with $count characters';
  }

  @override
  String oscPasteReadBlocked(String protocol) {
    return '$protocol paste read blocked by policy';
  }

  @override
  String oscPasteReadInvalid(String protocol) {
    return '$protocol paste read ignored: invalid payload';
  }

  @override
  String oscMimeWriteSucceeded(int types, int bytes) {
    return 'OSC 5522 wrote $types MIME types ($bytes bytes)';
  }

  @override
  String get oscMimeWriteBlocked =>
      'OSC 5522 MIME clipboard write blocked by policy';

  @override
  String get oscMimeWriteFailed => 'OSC 5522 MIME clipboard write failed';

  @override
  String oscMimeReadSucceeded(int types, int bytes) {
    return 'OSC 5522 replied with $types MIME types ($bytes bytes)';
  }

  @override
  String get oscMimeReadBlocked =>
      'OSC 5522 MIME clipboard read blocked by policy';

  @override
  String get oscMimeReadFailed => 'OSC 5522 MIME clipboard read failed';

  @override
  String get terminalNotification => 'Terminal notification';

  @override
  String notificationOnRemoteInSession(
    String title,
    String remote,
    String session,
  ) {
    return '$title on $remote in $session';
  }

  @override
  String get bell => 'Bell';

  @override
  String get terminalRequestedAttentionBody =>
      'The terminal requested attention.';

  @override
  String get commandFinished => 'Command finished';

  @override
  String commandFinishedInSession(String session) {
    return 'Command finished in $session';
  }

  @override
  String commandFinishedOnRemoteInSession(String remote, String session) {
    return 'Command finished on $remote in $session';
  }

  @override
  String terminalSettingsCouldNotLoad(String error) {
    return 'Terminal settings could not be loaded: $error';
  }

  @override
  String shortcutValue(String shortcut) {
    return 'shortcut: $shortcut';
  }

  @override
  String errorValue(String error) {
    return 'error: $error';
  }

  @override
  String get backInShell => 'Back in shell';

  @override
  String get newOutput => 'New output';

  @override
  String get clickFocusFirstPaneWithNewOutput =>
      'Click to focus the first pane with new output.';

  @override
  String get newOutputInSplitPane => 'New output in a split pane.';

  @override
  String newOutputInSplitPanes(int count) {
    return 'New output in $count split panes.';
  }

  @override
  String get hiddenTabsHaveNewOutput => 'Hidden tabs have new output';

  @override
  String get newOutputInHiddenTab => 'New output in a hidden tab.';

  @override
  String tabSessionDetails(String title, String id) {
    return 'Tab: $title ($id)';
  }

  @override
  String get paneAlreadyFocused => 'Pane already focused.';

  @override
  String newOutputInHiddenPanes(int count) {
    return 'New output in $count hidden panes.';
  }

  @override
  String get noActivePaneAvailable => 'No active pane is available.';

  @override
  String paneTooNarrow(int columns) {
    return 'Another pane would become narrower than $columns columns.';
  }

  @override
  String paneTooShort(int rows) {
    return 'Another pane would become shorter than $rows rows.';
  }

  @override
  String get unzoomActivePaneToManage =>
      'Unzoom the active pane to manage other panes.';

  @override
  String closeNamedTab(String title) {
    return 'Close $title tab';
  }

  @override
  String closeNamed(String title) {
    return 'Close $title';
  }

  @override
  String osc21337Status(String status) {
    return 'OSC 21337 status: $status';
  }

  @override
  String get remoteApiBaseUrlWithoutCredentials =>
      'The remote data API URL must be an http(s) base URL without credentials, query, or fragment.';

  @override
  String get remoteApiRequiresHttps =>
      'Remote data API authentication requires HTTPS. HTTP is allowed only for a loopback development endpoint.';

  @override
  String get shell => 'Shell';

  @override
  String fieldIsRequired(String field) {
    return '$field is required';
  }

  @override
  String fieldMustBePositiveInteger(String field) {
    return '$field must be a positive integer';
  }

  @override
  String fieldMustBeAtMost(String field, int maximum) {
    return '$field must be $maximum or less';
  }

  @override
  String fieldMustBeGreaterThanZero(String field) {
    return '$field must be greater than 0';
  }

  @override
  String get environmentKeyRequired => 'Key is required';

  @override
  String get environmentKeyUnique => 'Key must be unique';

  @override
  String get newProfileDefaultName => 'New Profile';

  @override
  String terminalTabSemantics(String title) {
    return '$title tab';
  }

  @override
  String terminalStatus(String status) {
    return 'status $status';
  }

  @override
  String terminalStatusFromActivePane(String status) {
    return 'status $status from active pane';
  }

  @override
  String get statusIndicatorActive => 'status indicator active';

  @override
  String get statusIndicatorActiveOnActivePane =>
      'status indicator active on active pane';

  @override
  String terminalBadgeFromPane(String badge, String state) {
    return 'badge $badge from $state';
  }

  @override
  String badgeSemanticsValue(String badge) {
    return 'badge $badge';
  }

  @override
  String plusOtherPaneBadges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'plus $count other pane badges',
      one: 'plus 1 other pane badge',
    );
    return '$_temp0';
  }

  @override
  String signalFromPane(String state) {
    return ' from $state';
  }

  @override
  String terminalSignalSummary(String title, String summary, String scope) {
    return '$title: $summary$scope';
  }

  @override
  String plusOtherPaneSignals(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'plus $count other pane signals',
      one: 'plus 1 other pane signal',
    );
    return '$_temp0';
  }

  @override
  String get newOutputLower => 'new output';

  @override
  String get newOutputInSplitPaneLower => 'new output in split pane';

  @override
  String commandShortcut(int index) {
    return 'Command $index';
  }

  @override
  String get otherPaneBadges => 'Other pane badges:';

  @override
  String terminalBadgeValue(String badge) {
    return 'Terminal badge: $badge';
  }

  @override
  String otherPaneBadgeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count other pane badges',
      one: '1 other pane badge',
    );
    return '$_temp0';
  }

  @override
  String additionalOsc1337Badge(String badge) {
    return 'Additional OSC 1337 badge: $badge';
  }

  @override
  String get additionalOsc1337BadgesSplitTab =>
      'Additional OSC 1337 badges in this split tab.';

  @override
  String get clickFocusFirstRemainingBadgePane =>
      'Click to focus the first remaining badge pane.';

  @override
  String get firstRemainingBadgePaneFocused =>
      'First remaining badge pane is already focused.';

  @override
  String terminalBadgesAdditional(int count, String title, String action) {
    return 'Terminal badges: $count additional pane badges in $title; $action';
  }

  @override
  String get clickFocusPaneSemantics => 'click to focus this pane';

  @override
  String get paneAlreadyFocusedSemantics => 'pane already focused';

  @override
  String get clickFocusFirstRemainingBadgePaneSemantics =>
      'click to focus the first remaining badge pane';

  @override
  String get firstRemainingBadgePaneFocusedSemantics =>
      'first remaining badge pane is already focused';

  @override
  String get terminalProgressAbbreviation => 'PROG';

  @override
  String get terminalProgress => 'Terminal progress';

  @override
  String get terminalNotificationAbbreviation => 'NOTE';

  @override
  String get paneSignalAbbreviation => 'PANE';

  @override
  String get otherPaneSignals => 'Other pane signals:';

  @override
  String signalInSplitPane(String signal) {
    return '$signal in a split pane.';
  }

  @override
  String get clickInspectRecentNotifications =>
      'Click to inspect recent notifications.';

  @override
  String get clickFocusFirstPaneWithSignal =>
      'Click to focus the first pane with a signal.';

  @override
  String get clickInspectNotificationActionsSemantics =>
      'click to inspect notification actions';

  @override
  String otherPaneSignalCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count other pane signals',
      one: '1 other pane signal',
    );
    return '$_temp0';
  }

  @override
  String terminalProgressReportedBy(String source) {
    return 'Terminal progress reported by $source.';
  }

  @override
  String labelValue(String value) {
    return 'Label: $value';
  }

  @override
  String progressPercentValue(int value) {
    return 'Percent: $value%';
  }

  @override
  String stateValue(String value) {
    return 'State: $value';
  }

  @override
  String idValue(String value) {
    return 'ID: $value';
  }

  @override
  String terminalNotificationReportedBy(String source) {
    return 'Terminal notification reported by $source.';
  }

  @override
  String titleValue(String value) {
    return 'Title: $value';
  }

  @override
  String messageValue(String value) {
    return 'Message: $value';
  }

  @override
  String remoteHostValue(String value) {
    return 'Remote host: $value';
  }

  @override
  String remoteUserValue(String value) {
    return 'Remote user: $value';
  }

  @override
  String countValue(int value) {
    return 'Count: $value';
  }

  @override
  String get osc1337BadgeInHiddenTab => 'OSC 1337 badge in a hidden tab.';

  @override
  String osc1337BadgesInHiddenPanes(int count) {
    return 'OSC 1337 badges in $count hidden panes.';
  }

  @override
  String get clickFocusFirstBadgePane => 'Click to focus the first badge pane.';

  @override
  String signalInHiddenTab(String signal) {
    return '$signal in a hidden tab.';
  }

  @override
  String paneSignalsInHiddenPanes(int count) {
    return 'Pane signals in $count hidden panes.';
  }

  @override
  String showHiddenTabs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Show $count hidden tabs',
      one: 'Show 1 hidden tab',
    );
    return '$_temp0';
  }

  @override
  String hiddenOsc1337BadgePanesTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hidden OSC 1337 badges: $count panes',
      one: 'Hidden OSC 1337 badge: 1 pane',
    );
    return '$_temp0';
  }

  @override
  String hiddenPaneSignalsTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hidden pane signals: $count panes',
      one: 'Hidden pane signal: 1 pane',
    );
    return '$_temp0';
  }

  @override
  String hiddenNewOutputTabsTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hidden new output: $count tabs',
      one: 'Hidden new output: 1 tab',
    );
    return '$_temp0';
  }

  @override
  String get signalMarkersFocusSources =>
      'Signal markers can focus their source panes.';

  @override
  String hiddenOsc1337BadgePanesSemantics(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hidden OSC 1337 badge panes',
      one: '1 hidden OSC 1337 badge pane',
    );
    return '$_temp0';
  }

  @override
  String hiddenPaneSignalsSemantics(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hidden pane signals',
      one: '1 hidden pane signal',
    );
    return '$_temp0';
  }

  @override
  String hiddenNewOutputTabsSemantics(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hidden tabs with new output',
      one: '1 hidden tab with new output',
    );
    return '$_temp0';
  }
}
