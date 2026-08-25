import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'Ianvs Terminal'**
  String get appTitle;

  /// Generic cancel action
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Generic close action
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Generic retry action
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Generic save action
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Generic delete action
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Generic continue action
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// Username field label
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// Password field label
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// Generic import action
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importAction;

  /// Generic preview label
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// Accessibility label for a dialog
  ///
  /// In en, this message translates to:
  /// **'{title} dialog'**
  String dialogSemantics(String title);

  /// Tooltip for closing a dialog
  ///
  /// In en, this message translates to:
  /// **'Close dialog'**
  String get closeDialog;

  /// Accessibility label shown while the application starts
  ///
  /// In en, this message translates to:
  /// **'Starting Ianvs Terminal, attempt {attempt}'**
  String startingAppAttempt(int attempt);

  /// Status shown while the terminal runtime is initialized
  ///
  /// In en, this message translates to:
  /// **'Preparing terminal runtime…'**
  String get preparingTerminalRuntime;

  /// Status shown in a new terminal tab while its first renderable frame loads
  ///
  /// In en, this message translates to:
  /// **'Loading {profile}…'**
  String loadingTerminalSession(String profile);

  /// Startup failure stage label
  ///
  /// In en, this message translates to:
  /// **'Stage: {stage}'**
  String startupStage(String stage);

  /// Action that retries application startup
  ///
  /// In en, this message translates to:
  /// **'Retry startup'**
  String get retryStartup;

  /// Title or action for data service settings
  ///
  /// In en, this message translates to:
  /// **'Data service settings'**
  String get dataServiceSettings;

  /// Action that connects to the configured data service
  ///
  /// In en, this message translates to:
  /// **'Connect and continue'**
  String get connectAndContinue;

  /// Confirmation title for disabling the data service
  ///
  /// In en, this message translates to:
  /// **'Disable the data service?'**
  String get disableDataServiceQuestion;

  /// Explanation shown before disabling the data service
  ///
  /// In en, this message translates to:
  /// **'This explicitly switches to local-terminal-only mode on the next startup attempt. No API process will start; existing remote data is not deleted.'**
  String get disableDataServiceExplanation;

  /// Action that switches to local-terminal-only mode
  ///
  /// In en, this message translates to:
  /// **'Use local terminal'**
  String get useLocalTerminal;

  /// Data service recovery dialog title
  ///
  /// In en, this message translates to:
  /// **'Data service recovery'**
  String get dataServiceRecovery;

  /// Message shown when the data service configuration cannot be read
  ///
  /// In en, this message translates to:
  /// **'The current configuration could not be read. You can still explicitly select Disabled.'**
  String get configurationReadFailed;

  /// Recovery instructions for reconnecting to the data service
  ///
  /// In en, this message translates to:
  /// **'Reconnect to the configured remote origin before startup retries. The origin cannot be changed here.'**
  String get reconnectConfiguredOrigin;

  /// Optional imported master-key field label
  ///
  /// In en, this message translates to:
  /// **'Master key from another device (optional)'**
  String get masterKeyFromAnotherDeviceOptional;

  /// Help text for importing a master key
  ///
  /// In en, this message translates to:
  /// **'Paste an exported ianvs-key-v1 key when this device does not already have it.'**
  String get masterKeyImportHelp;

  /// Recovery message when the local data service failed to start
  ///
  /// In en, this message translates to:
  /// **'The local data service could not start. Select local terminal mode to continue without an API. Local API data is retained.'**
  String get localDataServiceStartFailed;

  /// Recovery message when the app already uses local terminal mode
  ///
  /// In en, this message translates to:
  /// **'The app is already in local terminal mode. Retry startup or save that mode again to clear its recovery lock.'**
  String get alreadyUsingLocalTerminal;

  /// Action that reconnects the data service and retries startup
  ///
  /// In en, this message translates to:
  /// **'Reconnect and retry'**
  String get reconnectAndRetry;

  /// Explanation of automatic Apple master-key synchronization
  ///
  /// In en, this message translates to:
  /// **'The master key is stored and synchronized automatically through iCloud Keychain. No key entry is required.'**
  String get appleMasterKeySynchronized;

  /// Error shown when master-key import is unavailable
  ///
  /// In en, this message translates to:
  /// **'Master-key import is unavailable.'**
  String get masterKeyImportUnavailable;

  /// HTTP data API URL field label
  ///
  /// In en, this message translates to:
  /// **'HTTP API URL'**
  String get httpApiUrl;

  /// Initial data-mode setup heading
  ///
  /// In en, this message translates to:
  /// **'Choose your data mode'**
  String get chooseDataMode;

  /// Data-mode choices when the bundled API is available
  ///
  /// In en, this message translates to:
  /// **'Use only local terminals, start the bundled offline API, or connect a remote API for cross-device sync.'**
  String get dataModeLocalBundledOrRemote;

  /// Data-mode choices when the bundled API is unavailable
  ///
  /// In en, this message translates to:
  /// **'Continue without a data service for one-time SSH connections, or connect a remote API to save profiles and sync them.'**
  String get dataModeLocalOrRemote;

  /// Explanation that iOS requires a remote HTTP API
  ///
  /// In en, this message translates to:
  /// **'A remote HTTP API connection is required before Ianvs Terminal can be used on iOS.'**
  String get remoteApiRequiredOnIos;

  /// Help text for opening existing encrypted data with a master key
  ///
  /// In en, this message translates to:
  /// **'Paste an exported ianvs-key-v1 key to open existing encrypted data.'**
  String get masterKeyOpenExistingHelp;

  /// Action that continues without a data service
  ///
  /// In en, this message translates to:
  /// **'Continue without data service'**
  String get continueWithoutDataService;

  /// Action that connects a remote data API
  ///
  /// In en, this message translates to:
  /// **'Connect remote API'**
  String get connectRemoteApi;

  /// Action that starts the bundled local data API
  ///
  /// In en, this message translates to:
  /// **'Use bundled local API'**
  String get useBundledLocalApi;

  /// Action that uses only local terminal features
  ///
  /// In en, this message translates to:
  /// **'Use local terminal only'**
  String get useLocalTerminalOnly;

  /// Startup failure heading
  ///
  /// In en, this message translates to:
  /// **'Ianvs Terminal could not start'**
  String get appCouldNotStart;

  /// Localized name of an application startup stage
  ///
  /// In en, this message translates to:
  /// **'{stage, select, paths{File paths} secureRecovery{Secure recovery} configuration{Configuration} dataBootstrap{Data service startup} platform{Platform initialization} pty{Terminal runtime} configurationValidation{Configuration validation} runtimeComposition{Runtime composition} runtimeShutdown{Runtime shutdown} other{{stage}}}'**
  String startupStageName(String stage);

  /// Tooltip for opening the command palette
  ///
  /// In en, this message translates to:
  /// **'Open command palette'**
  String get openCommandPalette;

  /// Command palette title
  ///
  /// In en, this message translates to:
  /// **'Command palette'**
  String get commandPalette;

  /// Tooltip for closing the command palette
  ///
  /// In en, this message translates to:
  /// **'Close command palette'**
  String get closeCommandPalette;

  /// Command palette search field label
  ///
  /// In en, this message translates to:
  /// **'Search actions'**
  String get searchActions;

  /// Command palette search field hint
  ///
  /// In en, this message translates to:
  /// **'Type an action and press Enter'**
  String get typeActionAndPressEnter;

  /// Message shown when command search has no match
  ///
  /// In en, this message translates to:
  /// **'No action matches \"{query}\".'**
  String noActionMatches(String query);

  /// Command palette quick-actions section
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get quickActions;

  /// Command palette application-actions section
  ///
  /// In en, this message translates to:
  /// **'App actions'**
  String get appActions;

  /// Command palette session-actions section
  ///
  /// In en, this message translates to:
  /// **'Session actions'**
  String get sessionActions;

  /// Replay feature label
  ///
  /// In en, this message translates to:
  /// **'Replay'**
  String get replay;

  /// Command palette shell-tools section
  ///
  /// In en, this message translates to:
  /// **'Shell tools'**
  String get shellTools;

  /// Disabled reason when an action needs an active terminal
  ///
  /// In en, this message translates to:
  /// **'Open a terminal tab first.'**
  String get openTerminalTabFirst;

  /// Disabled reason when no default profile exists
  ///
  /// In en, this message translates to:
  /// **'No default profile is configured.'**
  String get noDefaultProfileConfigured;

  /// Disabled reason when there is no tab to reopen
  ///
  /// In en, this message translates to:
  /// **'No recently closed tab is available.'**
  String get noRecentlyClosedTab;

  /// Command palette action title
  ///
  /// In en, this message translates to:
  /// **'Search terminal output'**
  String get searchTerminalOutput;

  /// Command palette action description
  ///
  /// In en, this message translates to:
  /// **'Top action • Open in-terminal search for the active pane.'**
  String get searchTerminalOutputDescription;

  /// Action that opens a new terminal tab
  ///
  /// In en, this message translates to:
  /// **'New tab'**
  String get newTab;

  /// No description provided for @newTabTitleCase.
  ///
  /// In en, this message translates to:
  /// **'New Tab'**
  String get newTabTitleCase;

  /// Command palette new-tab description
  ///
  /// In en, this message translates to:
  /// **'Top action • Open the default profile.'**
  String get newTabDescription;

  /// Terminal toolbelt title
  ///
  /// In en, this message translates to:
  /// **'Toolbelt'**
  String get toolbelt;

  /// Command palette toolbelt description
  ///
  /// In en, this message translates to:
  /// **'Top action • Open terminal tools for this pane.'**
  String get toolbeltDescription;

  /// Defaults and appearance settings title
  ///
  /// In en, this message translates to:
  /// **'Defaults & appearance'**
  String get defaultsAppearance;

  /// Command palette defaults description
  ///
  /// In en, this message translates to:
  /// **'App action • Pick the default profile and theme.'**
  String get defaultsAppearanceDescription;

  /// Action that reopens the latest closed terminal tab
  ///
  /// In en, this message translates to:
  /// **'Reopen closed tab'**
  String get reopenClosedTab;

  /// Command palette reopen-tab description
  ///
  /// In en, this message translates to:
  /// **'App action • Recreate the most recently closed tab.'**
  String get reopenClosedTabDescription;

  /// Terminal color preset picker title
  ///
  /// In en, this message translates to:
  /// **'Terminal color presets'**
  String get terminalColorPresets;

  /// Command palette terminal color presets description
  ///
  /// In en, this message translates to:
  /// **'App action • Open Defaults & appearance to choose terminal colors.'**
  String get terminalColorPresetsDescription;

  /// Toggle title for command-finished notifications
  ///
  /// In en, this message translates to:
  /// **'{enabled, select, true{Disable command-finished notifications} other{Enable command-finished notifications}}'**
  String commandFinishedNotifications(String enabled);

  /// Command-finished notification toggle description
  ///
  /// In en, this message translates to:
  /// **'App action • Toggle shell hook completion alerts.'**
  String get commandFinishedNotificationsDescription;

  /// Command-finished notification toggle description when system access is blocked
  ///
  /// In en, this message translates to:
  /// **'App action • Toggle shell hook completion alerts. macOS notifications are currently blocked in System Settings.'**
  String get commandFinishedNotificationsBlockedDescription;

  /// Toggle title for the activity monitor
  ///
  /// In en, this message translates to:
  /// **'{enabled, select, true{Disable activity monitor} other{Enable activity monitor}}'**
  String activityMonitor(String enabled);

  /// Activity monitor toggle description
  ///
  /// In en, this message translates to:
  /// **'App action • Toggle inactive-session activity alerts.'**
  String get activityMonitorDescription;

  /// Activity monitor toggle description when system access is blocked
  ///
  /// In en, this message translates to:
  /// **'App action • Toggle inactive-session activity alerts. macOS notifications are currently blocked in System Settings.'**
  String get activityMonitorBlockedDescription;

  /// Action that opens profile management
  ///
  /// In en, this message translates to:
  /// **'Profiles…'**
  String get profilesEllipsis;

  /// Command palette profiles description
  ///
  /// In en, this message translates to:
  /// **'App action • Open or edit shell profiles.'**
  String get profilesDescription;

  /// Message shown when no active shell session exists
  ///
  /// In en, this message translates to:
  /// **'Requires an active shell session.'**
  String get requiresActiveShellSession;

  /// Toggle title for terminal read-only mode
  ///
  /// In en, this message translates to:
  /// **'{enabled, select, true{Disable read-only mode} other{Enable read-only mode}}'**
  String readOnlyMode(String enabled);

  /// Read-only mode action description
  ///
  /// In en, this message translates to:
  /// **'Session action • Block terminal input for this pane.'**
  String get readOnlyModeDescription;

  /// Action that clears terminal output and history
  ///
  /// In en, this message translates to:
  /// **'Clear buffer'**
  String get clearBuffer;

  /// Clear-buffer action description
  ///
  /// In en, this message translates to:
  /// **'Session action • Clear visible output and history; keep the current command line.'**
  String get clearBufferDescription;

  /// Action that opens the SFTP file panel
  ///
  /// In en, this message translates to:
  /// **'Open SFTP panel'**
  String get openSftpPanel;

  /// Open-SFTP-panel action description
  ///
  /// In en, this message translates to:
  /// **'Session action • Browse files for the active SSH connection in a right-side panel.'**
  String get openSftpPanelDescription;

  /// Disabled reason when an action needs an SSH session
  ///
  /// In en, this message translates to:
  /// **'Requires an active SSH session.'**
  String get requiresActiveSshSession;

  /// Action that exports terminal scrollback
  ///
  /// In en, this message translates to:
  /// **'Export terminal history'**
  String get exportTerminalHistory;

  /// Export-terminal-history action description
  ///
  /// In en, this message translates to:
  /// **'Session action • Save retained text as a .txt file for sharing or later review.'**
  String get exportTerminalHistoryDescription;

  /// Action that exports diagnostics
  ///
  /// In en, this message translates to:
  /// **'Export diagnostics'**
  String get exportDiagnostics;

  /// Export-diagnostics action description
  ///
  /// In en, this message translates to:
  /// **'Session action • Save a local resource evidence bundle.'**
  String get exportDiagnosticsDescription;

  /// Action that opens recent terminal activity replay
  ///
  /// In en, this message translates to:
  /// **'Replay recent activity'**
  String get replayRecentActivity;

  /// Recent-activity replay action description
  ///
  /// In en, this message translates to:
  /// **'Replay • Review the current pane’s rolling frame history.'**
  String get replayRecentActivityDescription;

  /// Action that stops and saves an active recording
  ///
  /// In en, this message translates to:
  /// **'Stop & save recording'**
  String get stopAndSaveRecording;

  /// Action that retries saving a recording
  ///
  /// In en, this message translates to:
  /// **'Retry saving recording'**
  String get retrySavingRecording;

  /// Action that starts terminal recording
  ///
  /// In en, this message translates to:
  /// **'Start recording for Replay'**
  String get startRecordingForReplay;

  /// Terminal recording action description
  ///
  /// In en, this message translates to:
  /// **'Replay • Capture this session as a durable recording. Keystrokes are redacted; shell command metadata is included when available.'**
  String get recordingDescription;

  /// Disabled reason while recording work is in progress
  ///
  /// In en, this message translates to:
  /// **'A recording operation is already in progress.'**
  String get recordingOperationInProgress;

  /// Action that opens a saved recording
  ///
  /// In en, this message translates to:
  /// **'Open recording in Replay…'**
  String get openRecordingInReplay;

  /// Open-recording action description
  ///
  /// In en, this message translates to:
  /// **'Replay • Open one saved terminal recording without importing it.'**
  String get openRecordingInReplayDescription;

  /// Action that searches all terminal tabs
  ///
  /// In en, this message translates to:
  /// **'Global search'**
  String get globalSearch;

  /// Global-search action description
  ///
  /// In en, this message translates to:
  /// **'Shell tool • Search all tabs at once.'**
  String get globalSearchDescription;

  /// Command palette keyboard shortcut hint
  ///
  /// In en, this message translates to:
  /// **'Open command palette with {shortcut}'**
  String openCommandPaletteWith(String shortcut);

  /// Summary shown when terminal profile values were repaired
  ///
  /// In en, this message translates to:
  /// **'Some terminal profile values were ignored and reset to safe defaults.'**
  String get configurationWarningsSummary;

  /// Tooltip that dismisses profile configuration warnings
  ///
  /// In en, this message translates to:
  /// **'Dismiss configuration warnings'**
  String get dismissConfigurationWarnings;

  /// Action that opens profiles after a configuration warning
  ///
  /// In en, this message translates to:
  /// **'Review Profiles'**
  String get reviewProfiles;

  /// Generic dismiss action
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// Accessibility label for a terminal runtime error
  ///
  /// In en, this message translates to:
  /// **'Terminal runtime error.'**
  String get terminalRuntimeError;

  /// Tooltip that dismisses a runtime error
  ///
  /// In en, this message translates to:
  /// **'Dismiss runtime error'**
  String get dismissRuntimeError;

  /// Terminal startup error title inside the main shell
  ///
  /// In en, this message translates to:
  /// **'Terminal could not start'**
  String get terminalCouldNotStart;

  /// Terminal startup error recovery guidance
  ///
  /// In en, this message translates to:
  /// **'Review the startup error, then try loading the layout again.'**
  String get terminalCouldNotStartHelp;

  /// Action that manually falls back to the bundled local API using the last successfully mirrored remote data
  ///
  /// In en, this message translates to:
  /// **'Use local snapshot'**
  String get useLastRemoteSnapshot;

  /// Progress label while committing a manual remote-to-local fallback
  ///
  /// In en, this message translates to:
  /// **'Switching to local…'**
  String get switchingToLocalSnapshot;

  /// Confirmation title for offline remote-to-local fallback
  ///
  /// In en, this message translates to:
  /// **'Use the last remote snapshot?'**
  String get remoteFallbackTitle;

  /// Confirmation details for offline remote-to-local fallback
  ///
  /// In en, this message translates to:
  /// **'The remote service is unavailable. Ianvs Terminal can switch to the bundled local API using {resourceCount} resources last synchronized at {capturedAt}. Remote data is not deleted, and the change takes effect after restart.'**
  String remoteFallbackDescription(String capturedAt, int resourceCount);

  /// Confirmation action for offline remote-to-local fallback
  ///
  /// In en, this message translates to:
  /// **'Switch to local API'**
  String get switchToLocalApi;

  /// Title shown after the local fallback configuration is committed
  ///
  /// In en, this message translates to:
  /// **'Local fallback is ready'**
  String get remoteFallbackCompleteTitle;

  /// Completion details for offline remote-to-local fallback
  ///
  /// In en, this message translates to:
  /// **'The bundled local API will use the remote data synchronized at {capturedAt}. Restart Ianvs Terminal to apply the change.'**
  String remoteFallbackCompleteDescription(String capturedAt);

  /// Error shown when offline remote-to-local fallback fails
  ///
  /// In en, this message translates to:
  /// **'Could not switch to the local snapshot: {error}'**
  String remoteFallbackFailed(String error);

  /// Action that offers to repair a noncanonical terminal settings document
  ///
  /// In en, this message translates to:
  /// **'Repair settings'**
  String get repairTerminalSettings;

  /// Confirmation title for repairing a noncanonical terminal settings document
  ///
  /// In en, this message translates to:
  /// **'Repair terminal settings?'**
  String get repairTerminalSettingsTitle;

  /// Explanation shown before repairing a noncanonical terminal settings document
  ///
  /// In en, this message translates to:
  /// **'Ianvs Terminal will preserve the original remote document as a recovery copy, fill in the required current-format fields, and retry startup. Profiles and session data are not changed.'**
  String get repairTerminalSettingsDescription;

  /// Confirmation action that repairs terminal settings and retries startup
  ///
  /// In en, this message translates to:
  /// **'Repair and retry'**
  String get repairAndRetry;

  /// Message shown when terminal settings recovery fails
  ///
  /// In en, this message translates to:
  /// **'Could not repair terminal settings: {error}'**
  String terminalSettingsRepairFailed(String error);

  /// Empty-state title after the final shell session closes
  ///
  /// In en, this message translates to:
  /// **'Shell layout is idle'**
  String get shellLayoutIdle;

  /// Empty-state title before opening a shell session
  ///
  /// In en, this message translates to:
  /// **'Start a shell layout'**
  String get startShellLayout;

  /// Empty-state guidance after the final shell session closes
  ///
  /// In en, this message translates to:
  /// **'The last session has closed. Open a new tab to keep working in the shell layout.'**
  String get lastSessionClosedHelp;

  /// Empty-state guidance before opening a shell session
  ///
  /// In en, this message translates to:
  /// **'Open a new tab to start working in the shell layout.'**
  String get openNewTabToStart;

  /// Summary of the effective profile used for new tabs
  ///
  /// In en, this message translates to:
  /// **'Current new-tab profile • {profile}'**
  String currentNewTabProfile(String profile);

  /// Summary of the configured default profile
  ///
  /// In en, this message translates to:
  /// **'Configured default • {profile}'**
  String configuredDefaultProfile(String profile);

  /// Fallback when no terminal profile exists
  ///
  /// In en, this message translates to:
  /// **'No profile available'**
  String get noProfileAvailable;

  /// SSH-only empty-state title
  ///
  /// In en, this message translates to:
  /// **'Connect with SSH'**
  String get connectWithSsh;

  /// SSH-only empty-state guidance without saved profiles
  ///
  /// In en, this message translates to:
  /// **'Create an SSH connection to open your first tab.'**
  String get createSshConnectionFirstTab;

  /// SSH-only empty-state guidance with saved profiles
  ///
  /// In en, this message translates to:
  /// **'Choose a saved profile to open a terminal tab.'**
  String get chooseSavedProfileForTab;

  /// Explanation of the iPhone SSH-only limitation
  ///
  /// In en, this message translates to:
  /// **'Local terminal sessions are unavailable on iPhone.'**
  String get localSessionsUnavailableOnIphone;

  /// Empty state for the SSH profile list
  ///
  /// In en, this message translates to:
  /// **'No SSH profiles yet'**
  String get noSshProfilesYet;

  /// Action that creates a new SSH connection
  ///
  /// In en, this message translates to:
  /// **'New SSH Connection'**
  String get newSshConnection;

  /// New-session launcher title when local sessions are available
  ///
  /// In en, this message translates to:
  /// **'New terminal tab'**
  String get newTerminalTab;

  /// New-session launcher title in SSH-only mode
  ///
  /// In en, this message translates to:
  /// **'New SSH tab'**
  String get newSshTab;

  /// New-session launcher guidance with local sessions
  ///
  /// In en, this message translates to:
  /// **'Choose a local shell or connect to an SSH host.'**
  String get chooseLocalShellOrSsh;

  /// New-session launcher guidance in SSH-only mode
  ///
  /// In en, this message translates to:
  /// **'Choose a saved SSH profile or create a new one.'**
  String get chooseSavedSshOrCreate;

  /// Local shell connection type
  ///
  /// In en, this message translates to:
  /// **'Local shell'**
  String get localShell;

  /// SSH session connection type
  ///
  /// In en, this message translates to:
  /// **'SSH session'**
  String get sshSession;

  /// Action that creates a saved SSH connection
  ///
  /// In en, this message translates to:
  /// **'New SSH connection'**
  String get newSshConnectionLower;

  /// Action that creates a one-time SSH connection
  ///
  /// In en, this message translates to:
  /// **'New one-time SSH connection'**
  String get newOneTimeSshConnection;

  /// Warning title for a one-time SSH connection
  ///
  /// In en, this message translates to:
  /// **'This connection will not be saved'**
  String get connectionWillNotBeSaved;

  /// Explanation of why an SSH connection cannot be saved
  ///
  /// In en, this message translates to:
  /// **'Connect a remote data service to save reusable SSH profiles. You can still connect once without an Ianvs account or data service.'**
  String get remoteDataRequiredToSaveSsh;

  /// Accessibility label for SSH profile search
  ///
  /// In en, this message translates to:
  /// **'Search SSH profiles'**
  String get searchSshProfiles;

  /// SSH profile search hint
  ///
  /// In en, this message translates to:
  /// **'Search by name, host, or user'**
  String get searchByNameHostUser;

  /// Action that clears a search query
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// Saved SSH profile section title
  ///
  /// In en, this message translates to:
  /// **'Saved SSH profiles'**
  String get savedSshProfiles;

  /// Imported OpenSSH configuration section title
  ///
  /// In en, this message translates to:
  /// **'From ~/.ssh/config'**
  String get fromOpenSshConfig;

  /// Error title when OpenSSH profiles cannot be imported
  ///
  /// In en, this message translates to:
  /// **'OpenSSH profiles unavailable'**
  String get openSshProfilesUnavailable;

  /// Empty state for imported OpenSSH hosts
  ///
  /// In en, this message translates to:
  /// **'No concrete SSH hosts found'**
  String get noConcreteSshHosts;

  /// Empty state for filtered SSH profiles
  ///
  /// In en, this message translates to:
  /// **'No matching SSH profiles'**
  String get noMatchingSshProfiles;

  /// Guidance after SSH profile search has no matches
  ///
  /// In en, this message translates to:
  /// **'Try a different name, host, or user.'**
  String get tryDifferentNameHostUser;

  /// Tooltip for opening item actions
  ///
  /// In en, this message translates to:
  /// **'More actions for {name}'**
  String moreActionsFor(String name);

  /// Generic connect action
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// Terminal profile management title
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get profiles;

  /// Profile sheet description when saved SSH profiles are unavailable
  ///
  /// In en, this message translates to:
  /// **'Saved SSH profiles require a remote data service on iPhone.'**
  String get savedSshProfilesRequireRemote;

  /// Profile sheet description in SSH-only mode
  ///
  /// In en, this message translates to:
  /// **'Open a saved SSH profile or edit its terminal settings.'**
  String get openSavedSshOrEdit;

  /// Profile sheet description
  ///
  /// In en, this message translates to:
  /// **'Open a tab with any saved profile or edit its terminal settings.'**
  String get openSavedProfileOrEdit;

  /// Empty state for filtered profiles
  ///
  /// In en, this message translates to:
  /// **'No matching profiles'**
  String get noMatchingProfiles;

  /// Empty state when saved profiles are unavailable
  ///
  /// In en, this message translates to:
  /// **'No saved profiles'**
  String get noSavedProfiles;

  /// Empty state when no terminal profiles exist
  ///
  /// In en, this message translates to:
  /// **'No profiles yet'**
  String get noProfilesYet;

  /// Guidance after profile search has no matches
  ///
  /// In en, this message translates to:
  /// **'Try a different profile name, shell, or tag.'**
  String get tryDifferentProfileSearch;

  /// Guidance when SSH profiles require a remote data service
  ///
  /// In en, this message translates to:
  /// **'Connect a remote data service to create and sync SSH profiles.'**
  String get connectRemoteToCreateSyncSsh;

  /// Guidance when no SSH profiles exist
  ///
  /// In en, this message translates to:
  /// **'Create an SSH profile to connect to a remote host.'**
  String get createSshProfileToConnect;

  /// Guidance when no terminal profiles exist
  ///
  /// In en, this message translates to:
  /// **'Create a profile to customize a terminal session.'**
  String get createProfileToCustomize;

  /// Action that creates a terminal profile
  ///
  /// In en, this message translates to:
  /// **'Create profile'**
  String get createProfile;

  /// Disabled reason for creating saved SSH profiles
  ///
  /// In en, this message translates to:
  /// **'Connect a remote data service to create saved SSH profiles'**
  String get connectRemoteToCreateSavedSsh;

  /// Generic new-item action
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newAction;

  /// Tooltip for closing profile management
  ///
  /// In en, this message translates to:
  /// **'Close profiles'**
  String get closeProfiles;

  /// Profile search field label
  ///
  /// In en, this message translates to:
  /// **'Search profiles or tags'**
  String get searchProfilesOrTags;

  /// Tooltip for editing a named item
  ///
  /// In en, this message translates to:
  /// **'Edit {name}'**
  String editNamedItem(String name);

  /// Tooltip for deleting a named item
  ///
  /// In en, this message translates to:
  /// **'Delete {name}'**
  String deleteNamedItem(String name);

  /// New profile dialog title
  ///
  /// In en, this message translates to:
  /// **'New profile'**
  String get newProfile;

  /// Local shell profile description
  ///
  /// In en, this message translates to:
  /// **'Run a shell on this device.'**
  String get runShellOnDevice;

  /// SSH profile description
  ///
  /// In en, this message translates to:
  /// **'Connect to a remote host.'**
  String get connectRemoteHost;

  /// Terminal scrollback line count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 line} other{{count} lines}}'**
  String scrollbackLineCount(int count);

  /// Label for the default terminal profile
  ///
  /// In en, this message translates to:
  /// **'Default profile'**
  String get defaultProfile;

  /// Defaults and appearance dialog subtitle
  ///
  /// In en, this message translates to:
  /// **'Pick the default profile for new tabs and choose how the shell follows the app theme.'**
  String get defaultsAppearanceSubtitle;

  /// Tooltip for closing defaults and appearance
  ///
  /// In en, this message translates to:
  /// **'Close defaults'**
  String get closeDefaults;

  /// Option to automatically choose a default profile
  ///
  /// In en, this message translates to:
  /// **'Use automatic fallback'**
  String get useAutomaticFallback;

  /// Message when no profile can be used for new tabs
  ///
  /// In en, this message translates to:
  /// **'No profile is available for new tabs.'**
  String get noProfileForNewTabs;

  /// Automatic default profile explanation
  ///
  /// In en, this message translates to:
  /// **'New tabs use {profile} automatically until you choose a fixed default.'**
  String newTabsUseProfileAutomatically(String profile);

  /// Automatic profile fallback summary
  ///
  /// In en, this message translates to:
  /// **'Automatic fallback • {profile}'**
  String automaticFallbackProfile(String profile);

  /// Fallback for a missing configured profile
  ///
  /// In en, this message translates to:
  /// **'Unknown profile'**
  String get unknownProfile;

  /// Terminal color preset section title
  ///
  /// In en, this message translates to:
  /// **'Terminal preset'**
  String get terminalPreset;

  /// Guidance when terminal colors cannot be selected
  ///
  /// In en, this message translates to:
  /// **'Create a profile before choosing terminal colors.'**
  String get createProfileBeforeColors;

  /// Terminal color preset section guidance
  ///
  /// In en, this message translates to:
  /// **'Apply a curated terminal color palette to {profile}.'**
  String applyPaletteToProfile(String profile);

  /// Terminal preset filter field label
  ///
  /// In en, this message translates to:
  /// **'Filter terminal presets'**
  String get filterTerminalPresets;

  /// Option that keeps current terminal colors
  ///
  /// In en, this message translates to:
  /// **'Keep current'**
  String get keepCurrent;

  /// Label for custom terminal colors
  ///
  /// In en, this message translates to:
  /// **'Custom colors'**
  String get customColors;

  /// Current terminal preset summary
  ///
  /// In en, this message translates to:
  /// **'Currently {preset}'**
  String currentlyPreset(String preset);

  /// No description provided for @selectedTerminalPreset.
  ///
  /// In en, this message translates to:
  /// **'{preset}, selected'**
  String selectedTerminalPreset(String preset);

  /// Empty state for terminal preset search
  ///
  /// In en, this message translates to:
  /// **'No terminal presets match “{query}”.'**
  String noTerminalPresetsMatch(String query);

  /// Startup settings section title
  ///
  /// In en, this message translates to:
  /// **'Startup'**
  String get startup;

  /// Startup layout settings description
  ///
  /// In en, this message translates to:
  /// **'Choose whether the terminal should rebuild your last tab and pane arrangement.'**
  String get startupLayoutDescription;

  /// Startup layout restoration toggle title
  ///
  /// In en, this message translates to:
  /// **'Restore tabs and panes on launch'**
  String get restoreTabsAndPanes;

  /// Startup layout restoration explanation
  ///
  /// In en, this message translates to:
  /// **'Starts new shell processes and restores their folders. Running processes are not resumed.'**
  String get restoreTabsAndPanesDescription;

  /// Application language settings section title
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Application language settings description
  ///
  /// In en, this message translates to:
  /// **'Choose the language used by the application interface.'**
  String get languageDescription;

  /// Application language mode name
  ///
  /// In en, this message translates to:
  /// **'{mode, select, system{Follow system} english{English} simplifiedChinese{简体中文} other{{mode}}}'**
  String languageModeName(String mode);

  /// Application language mode description
  ///
  /// In en, this message translates to:
  /// **'{mode, select, system{Use the preferred language from this device.} english{Always display the app in English.} simplifiedChinese{始终使用简体中文显示应用。} other{{mode}}}'**
  String languageModeDescription(String mode);

  /// No description provided for @generalSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose the default profile for new tabs and the language used by the app.'**
  String get generalSettingsDescription;

  /// No description provided for @appearanceSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Customize terminal colors, startup behavior, and the app theme.'**
  String get appearanceSettingsDescription;

  /// Appearance settings section title
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// Application theme mode name
  ///
  /// In en, this message translates to:
  /// **'{mode, select, system{System} light{Light} dark{Dark} other{{mode}}}'**
  String themeModeName(String mode);

  /// Application theme mode description
  ///
  /// In en, this message translates to:
  /// **'{mode, select, system{Follow the current device appearance.} light{Keep the shell app in light mode.} dark{Keep the shell app in dark mode.} other{{mode}}}'**
  String themeModeDescription(String mode);

  /// Terminal canvas inset section title
  ///
  /// In en, this message translates to:
  /// **'Terminal canvas inset'**
  String get terminalCanvasInset;

  /// Terminal canvas inset explanation
  ///
  /// In en, this message translates to:
  /// **'Adjust the empty space between the shell frame and terminal text.'**
  String get terminalCanvasInsetDescription;

  /// Terminal viewport padding setting label
  ///
  /// In en, this message translates to:
  /// **'Viewport padding'**
  String get viewportPadding;

  /// Accessibility value for a pixel measurement
  ///
  /// In en, this message translates to:
  /// **'{count} pixels'**
  String pixelCount(int count);

  /// Action that decreases terminal viewport padding
  ///
  /// In en, this message translates to:
  /// **'Decrease viewport padding'**
  String get decreaseViewportPadding;

  /// Action that increases terminal viewport padding
  ///
  /// In en, this message translates to:
  /// **'Increase viewport padding'**
  String get increaseViewportPadding;

  /// Terminal viewport padding range
  ///
  /// In en, this message translates to:
  /// **'Range {minimum}–{maximum} px'**
  String viewportPaddingRange(int minimum, int maximum);

  /// Terminal viewport padding explanation
  ///
  /// In en, this message translates to:
  /// **'Lower values keep the prompt close to the edges; higher values create a larger terminal gutter.'**
  String get viewportPaddingDescription;

  /// Action that resets the default profile
  ///
  /// In en, this message translates to:
  /// **'Reset default'**
  String get resetDefault;

  /// Action that resets appearance settings
  ///
  /// In en, this message translates to:
  /// **'Reset theme'**
  String get resetTheme;

  /// Action that migrates local data to a remote API
  ///
  /// In en, this message translates to:
  /// **'Migrate to remote API'**
  String get migrateToRemoteApi;

  /// Action that migrates remote data to a local API
  ///
  /// In en, this message translates to:
  /// **'Migrate to local API'**
  String get migrateToLocalApi;

  /// Action that saves settings changes
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// Profile settings notice title
  ///
  /// In en, this message translates to:
  /// **'Detailed terminal settings live in Profiles.'**
  String get detailedSettingsInProfiles;

  /// Profile settings notice explanation
  ///
  /// In en, this message translates to:
  /// **'Edit font, colors, cursor, scrollback, and startup arguments from the Profiles editor.'**
  String get editTerminalDetailsInProfiles;

  /// Action that opens a profile in profile management
  ///
  /// In en, this message translates to:
  /// **'Edit {profile} in Profiles'**
  String editProfileInProfiles(String profile);

  /// Keyboard shortcut settings title
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get keyboardShortcuts;

  /// Keyboard shortcut settings explanation
  ///
  /// In en, this message translates to:
  /// **'Select a shortcut to record a new key combination. Changes apply immediately after saving.'**
  String get keyboardShortcutsDescription;

  /// Description for the navigation entry that opens keyboard shortcut settings
  ///
  /// In en, this message translates to:
  /// **'Customize key combinations for terminal actions.'**
  String get keyboardShortcutsNavigationDescription;

  /// Action that opens keyboard shortcut management
  ///
  /// In en, this message translates to:
  /// **'Manage shortcuts'**
  String get manageShortcuts;

  /// Tooltip for returning from shortcut management to Defaults and appearance
  ///
  /// In en, this message translates to:
  /// **'Back to Defaults & appearance'**
  String get backToDefaultsAppearance;

  /// Tooltip for the compact shortcut management overflow menu
  ///
  /// In en, this message translates to:
  /// **'More shortcut actions'**
  String get moreShortcutActions;

  /// Action that finishes a nested settings task
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Accessibility label for shortcut action filtering
  ///
  /// In en, this message translates to:
  /// **'Filter shortcut actions'**
  String get filterShortcutActions;

  /// Shortcut action filter field label
  ///
  /// In en, this message translates to:
  /// **'Filter actions'**
  String get filterActions;

  /// Shortcut category field label
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// Option showing all shortcut actions
  ///
  /// In en, this message translates to:
  /// **'All actions'**
  String get allActions;

  /// Action that restores all default shortcuts
  ///
  /// In en, this message translates to:
  /// **'Restore all defaults'**
  String get restoreAllDefaults;

  /// Empty state for shortcut action search
  ///
  /// In en, this message translates to:
  /// **'No matching actions'**
  String get noMatchingActions;

  /// Guidance after shortcut action search has no matches
  ///
  /// In en, this message translates to:
  /// **'Try another action name or category.'**
  String get tryAnotherActionOrCategory;

  /// Accessibility summary of shortcut conflicts
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 shortcut conflict. Resolve conflicts before saving.} other{{count} shortcut conflicts. Resolve conflicts before saving.}}'**
  String shortcutConflictSummary(int count);

  /// Shortcut conflict error title
  ///
  /// In en, this message translates to:
  /// **'Resolve shortcut conflicts before saving'**
  String get resolveShortcutConflicts;

  /// Action that adds a shortcut
  ///
  /// In en, this message translates to:
  /// **'Add shortcut'**
  String get addShortcut;

  /// Tooltip for editing an action shortcut
  ///
  /// In en, this message translates to:
  /// **'Edit shortcut for {action}'**
  String editShortcutFor(String action);

  /// Tooltip for disabling an action shortcut
  ///
  /// In en, this message translates to:
  /// **'Disable shortcut for {action}'**
  String disableShortcutFor(String action);

  /// Tooltip for restoring an action shortcut
  ///
  /// In en, this message translates to:
  /// **'Restore default shortcut for {action}'**
  String restoreShortcutFor(String action);

  /// Shortcut capture dialog title
  ///
  /// In en, this message translates to:
  /// **'Record shortcut'**
  String get recordShortcut;

  /// Shortcut scope field label
  ///
  /// In en, this message translates to:
  /// **'Active when'**
  String get activeWhen;

  /// Accessibility status while waiting for shortcut input
  ///
  /// In en, this message translates to:
  /// **'Waiting for shortcut'**
  String get waitingForShortcut;

  /// Accessibility status after recording a shortcut
  ///
  /// In en, this message translates to:
  /// **'Recorded {shortcut}'**
  String recordedShortcut(String shortcut);

  /// Shortcut capture prompt
  ///
  /// In en, this message translates to:
  /// **'Press a shortcut'**
  String get pressShortcut;

  /// Shortcut capture keyboard guidance
  ///
  /// In en, this message translates to:
  /// **'Press Escape to cancel, or Delete to disable this shortcut.'**
  String get shortcutCaptureHelp;

  /// Action that disables a shortcut
  ///
  /// In en, this message translates to:
  /// **'Disable shortcut'**
  String get disableShortcut;

  /// Generic apply action
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// Master key copy confirmation title
  ///
  /// In en, this message translates to:
  /// **'Copy the master key?'**
  String get copyMasterKeyQuestion;

  /// Security warning before copying the master key
  ///
  /// In en, this message translates to:
  /// **'Anyone with this key can decrypt your Ianvs data. The key will be placed on the system clipboard; paste it into the destination app and then clear the clipboard.'**
  String get copyMasterKeyWarning;

  /// Action that copies a master key
  ///
  /// In en, this message translates to:
  /// **'Copy key'**
  String get copyKey;

  /// Master key import dialog title
  ///
  /// In en, this message translates to:
  /// **'Import master key'**
  String get importMasterKey;

  /// Master key input field label
  ///
  /// In en, this message translates to:
  /// **'Ianvs master key'**
  String get ianvsMasterKey;

  /// Master key input help text
  ///
  /// In en, this message translates to:
  /// **'Paste the complete value beginning with ianvs-key-v1.'**
  String get masterKeyPasteHelp;

  /// Master key management title
  ///
  /// In en, this message translates to:
  /// **'Master key'**
  String get masterKey;

  /// Apple master key management summary
  ///
  /// In en, this message translates to:
  /// **'Encryption is managed automatically on this Apple device.'**
  String get appleEncryptionManagedAutomatically;

  /// Portable master key summary
  ///
  /// In en, this message translates to:
  /// **'One portable key unlocks local, remote, and SSH profile encryption across supported platforms.'**
  String get portableMasterKeyDescription;

  /// Apple master key storage explanation
  ///
  /// In en, this message translates to:
  /// **'Ianvs Terminal stores the master key in iCloud Keychain and requests synchronization automatically. No manual key entry is required.'**
  String get appleMasterKeyStorageDescription;

  /// Action that copies the master key for transfer
  ///
  /// In en, this message translates to:
  /// **'Copy for another device'**
  String get copyForAnotherDevice;

  /// Action that imports a master key from another device
  ///
  /// In en, this message translates to:
  /// **'Paste from another device'**
  String get pasteFromAnotherDevice;

  /// Tooltip for closing the SFTP panel
  ///
  /// In en, this message translates to:
  /// **'Close SFTP panel'**
  String get closeSftpPanel;

  /// SFTP action that copies a remote path
  ///
  /// In en, this message translates to:
  /// **'Copy full path'**
  String get copyFullPath;

  /// SFTP action that edits a remote file locally
  ///
  /// In en, this message translates to:
  /// **'Edit locally'**
  String get editLocally;

  /// SFTP action that creates a directory
  ///
  /// In en, this message translates to:
  /// **'Create directory'**
  String get createDirectory;

  /// Confirmation after copying a remote path
  ///
  /// In en, this message translates to:
  /// **'Copied {path}'**
  String copiedPath(String path);

  /// Confirmation after creating a named item
  ///
  /// In en, this message translates to:
  /// **'Created {name}'**
  String createdNamedItem(String name);

  /// Error after failing to create a named item
  ///
  /// In en, this message translates to:
  /// **'Could not create {name}.'**
  String couldNotCreateNamedItem(String name);

  /// Generic name field label
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// Generic create action
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// Confirmation title for deleting a named item
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String deleteNamedItemQuestion(String name);

  /// SFTP directory deletion explanation
  ///
  /// In en, this message translates to:
  /// **'The directory must be empty before it can be deleted.'**
  String get directoryMustBeEmpty;

  /// SFTP file deletion warning
  ///
  /// In en, this message translates to:
  /// **'This remote file will be deleted permanently.'**
  String get remoteFileDeletedPermanently;

  /// Confirmation after deleting a named item
  ///
  /// In en, this message translates to:
  /// **'Deleted {name}'**
  String deletedNamedItem(String name);

  /// Error after failing to delete a named item
  ///
  /// In en, this message translates to:
  /// **'Could not delete {name}.'**
  String couldNotDeleteNamedItem(String name);

  /// Accessibility label for an SFTP panel
  ///
  /// In en, this message translates to:
  /// **'SFTP panel for {address}'**
  String sftpPanelFor(String address);

  /// SFTP action that navigates to the remote root
  ///
  /// In en, this message translates to:
  /// **'Remote root'**
  String get remoteRoot;

  /// SFTP action that navigates to the parent directory
  ///
  /// In en, this message translates to:
  /// **'Parent directory'**
  String get parentDirectory;

  /// SFTP action that reloads a remote directory
  ///
  /// In en, this message translates to:
  /// **'Refresh remote directory'**
  String get refreshRemoteDirectory;

  /// Accessibility status while loading SFTP content
  ///
  /// In en, this message translates to:
  /// **'Loading remote directory'**
  String get loadingRemoteDirectory;

  /// Generic SFTP directory load error
  ///
  /// In en, this message translates to:
  /// **'Unable to load the remote directory.'**
  String get unableLoadRemoteDirectory;

  /// SFTP directory error title
  ///
  /// In en, this message translates to:
  /// **'Remote files unavailable'**
  String get remoteFilesUnavailable;

  /// SFTP directory empty state
  ///
  /// In en, this message translates to:
  /// **'This remote directory is empty.'**
  String get remoteDirectoryEmpty;

  /// Accessibility label for a remote file or folder
  ///
  /// In en, this message translates to:
  /// **'{type} {name}'**
  String remoteEntrySemantics(String type, String name);

  /// Folder item type
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get folder;

  /// File item type
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get file;

  /// SSH changed-host-key warning title
  ///
  /// In en, this message translates to:
  /// **'SSH host key changed'**
  String get sshHostKeyChanged;

  /// SSH unknown-host confirmation title
  ///
  /// In en, this message translates to:
  /// **'Trust this SSH host?'**
  String get trustThisSshHost;

  /// SSH changed-host-key security warning
  ///
  /// In en, this message translates to:
  /// **'The key saved for this server does not match the key it presented now. Only continue if you verified the new fingerprint; accepting replaces the saved key.'**
  String get sshHostKeyChangedWarning;

  /// SSH unknown-host security warning
  ///
  /// In en, this message translates to:
  /// **'Strict verification has no saved key for this server. Verify the fingerprint before trusting it.'**
  String get sshUnknownHostWarning;

  /// Server detail label
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get server;

  /// Cryptographic algorithm detail label
  ///
  /// In en, this message translates to:
  /// **'Algorithm'**
  String get algorithm;

  /// SSH host-key fingerprint label
  ///
  /// In en, this message translates to:
  /// **'SHA-256 fingerprint'**
  String get sha256Fingerprint;

  /// Action that rejects an SSH host key
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// Action that replaces a changed SSH host key
  ///
  /// In en, this message translates to:
  /// **'Replace key and continue'**
  String get replaceKeyAndContinue;

  /// Action that trusts an SSH host key
  ///
  /// In en, this message translates to:
  /// **'Trust and continue'**
  String get trustAndContinue;

  /// Fallback SSH authentication prompt title
  ///
  /// In en, this message translates to:
  /// **'SSH authentication'**
  String get sshAuthentication;

  /// Fallback label for an SSH authentication response
  ///
  /// In en, this message translates to:
  /// **'Response {number}'**
  String responseNumber(int number);

  /// Explanation for an obscured SSH authentication response
  ///
  /// In en, this message translates to:
  /// **'Your response is hidden.'**
  String get responseHidden;

  /// Profile editor title
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfile;

  /// Unsaved profile changes confirmation title
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardChangesQuestion;

  /// Unsaved profile changes confirmation message
  ///
  /// In en, this message translates to:
  /// **'You have unsaved profile changes. Close the editor and lose them?'**
  String get discardProfileChangesWarning;

  /// Action that returns to profile editing
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// Action that discards unsaved changes
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get discardChanges;

  /// Accessibility label for profile setting search
  ///
  /// In en, this message translates to:
  /// **'Find profile setting'**
  String get findProfileSetting;

  /// Profile setting search hint
  ///
  /// In en, this message translates to:
  /// **'Find setting'**
  String get findSetting;

  /// Action that clears profile setting search
  ///
  /// In en, this message translates to:
  /// **'Clear settings search'**
  String get clearSettingsSearch;

  /// Empty profile setting search result
  ///
  /// In en, this message translates to:
  /// **'No settings found'**
  String get noSettingsFound;

  /// Profile setting search result count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 section found} other{{count} sections found}}'**
  String sectionsFound(int count);

  /// Modified profile section count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 modified section} other{{count} modified sections}}'**
  String modifiedSections(int count);

  /// Empty state for profile setting search
  ///
  /// In en, this message translates to:
  /// **'No profile settings match “{query}”.'**
  String noProfileSettingsMatch(String query);

  /// Accessibility label for profile editor navigation
  ///
  /// In en, this message translates to:
  /// **'Profile editor section navigation'**
  String get profileEditorSectionNavigation;

  /// Accessibility label for the profile editor dialog
  ///
  /// In en, this message translates to:
  /// **'Profile editor dialog'**
  String get profileEditorDialog;

  /// Profile editor change scope explanation
  ///
  /// In en, this message translates to:
  /// **'Changes apply to new sessions only. Existing tabs keep the profile snapshot they started with.'**
  String get profileChangesNewSessionsOnly;

  /// Tooltip for closing the profile editor
  ///
  /// In en, this message translates to:
  /// **'Close profile editor'**
  String get closeProfileEditor;

  /// Profile editor section name
  ///
  /// In en, this message translates to:
  /// **'{section, select, general{General} startup{Startup} terminal{Terminal} appearance{Appearance} keys{Keys} automation{Automation} advanced{Advanced} other{{section}}}'**
  String profileSectionName(String section);

  /// Action that resets one profile section
  ///
  /// In en, this message translates to:
  /// **'Reset {section}'**
  String resetProfileSection(String section);

  /// Accessibility label for a profile editor section
  ///
  /// In en, this message translates to:
  /// **'{section} profile section{modified, select, true{, modified} other{}}'**
  String profileSectionSemantics(String section, String modified);

  /// No description provided for @sshConnection.
  ///
  /// In en, this message translates to:
  /// **'SSH connection'**
  String get sshConnection;

  /// No description provided for @connectOnceOrSaveProfile.
  ///
  /// In en, this message translates to:
  /// **'Connect once or save a reusable session profile.'**
  String get connectOnceOrSaveProfile;

  /// No description provided for @connection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connection;

  /// No description provided for @connectionSectionDescription.
  ///
  /// In en, this message translates to:
  /// **'Name the session and enter the destination address.'**
  String get connectionSectionDescription;

  /// No description provided for @sessionName.
  ///
  /// In en, this message translates to:
  /// **'Session name'**
  String get sessionName;

  /// No description provided for @exampleProduction.
  ///
  /// In en, this message translates to:
  /// **'For example, Production'**
  String get exampleProduction;

  /// No description provided for @host.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get host;

  /// No description provided for @hostnameOrIp.
  ///
  /// In en, this message translates to:
  /// **'hostname or IP address'**
  String get hostnameOrIp;

  /// No description provided for @user.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// No description provided for @remoteUser.
  ///
  /// In en, this message translates to:
  /// **'remote user'**
  String get remoteUser;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @authentication.
  ///
  /// In en, this message translates to:
  /// **'Authentication'**
  String get authentication;

  /// No description provided for @authenticationDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose how the server should verify your identity.'**
  String get authenticationDescription;

  /// No description provided for @method.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get method;

  /// No description provided for @authenticationMethod.
  ///
  /// In en, this message translates to:
  /// **'Authentication method'**
  String get authenticationMethod;

  /// No description provided for @automaticKeysThenPassword.
  ///
  /// In en, this message translates to:
  /// **'Automatic (keys, then password)'**
  String get automaticKeysThenPassword;

  /// No description provided for @privateKey.
  ///
  /// In en, this message translates to:
  /// **'Private key'**
  String get privateKey;

  /// No description provided for @keyboardInteractiveOtp.
  ///
  /// In en, this message translates to:
  /// **'Keyboard interactive / OTP'**
  String get keyboardInteractiveOtp;

  /// No description provided for @passwordFallback.
  ///
  /// In en, this message translates to:
  /// **'Password fallback'**
  String get passwordFallback;

  /// No description provided for @passwordFallbackHelp.
  ///
  /// In en, this message translates to:
  /// **'Used only when key authentication is unavailable.'**
  String get passwordFallbackHelp;

  /// No description provided for @forgetSavedPassword.
  ///
  /// In en, this message translates to:
  /// **'Forget saved password'**
  String get forgetSavedPassword;

  /// No description provided for @privateKeyDescription.
  ///
  /// In en, this message translates to:
  /// **'The selected path is shown here. Only the encrypted key contents are saved.'**
  String get privateKeyDescription;

  /// No description provided for @privateKeyFile.
  ///
  /// In en, this message translates to:
  /// **'Private key file'**
  String get privateKeyFile;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @replace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replace;

  /// No description provided for @forgetSavedPrivateKey.
  ///
  /// In en, this message translates to:
  /// **'Forget saved private key'**
  String get forgetSavedPrivateKey;

  /// No description provided for @privateKeyPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Private key passphrase'**
  String get privateKeyPassphrase;

  /// No description provided for @privateKeyPassphraseHelp.
  ///
  /// In en, this message translates to:
  /// **'Leave blank for an unencrypted private key.'**
  String get privateKeyPassphraseHelp;

  /// No description provided for @forgetSavedKeyPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Forget saved key passphrase'**
  String get forgetSavedKeyPassphrase;

  /// No description provided for @keyboardInteractiveHelp.
  ///
  /// In en, this message translates to:
  /// **'The server will ask for each required response after the connection starts, including multi-step OTP challenges.'**
  String get keyboardInteractiveHelp;

  /// No description provided for @hostVerificationAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Host verification and advanced options'**
  String get hostVerificationAdvanced;

  /// No description provided for @hostVerificationAdvancedDescription.
  ///
  /// In en, this message translates to:
  /// **'Host keys, jump hosts, tunnels, agent and X11 forwarding'**
  String get hostVerificationAdvancedDescription;

  /// No description provided for @hostKeyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Host key policy'**
  String get hostKeyPolicy;

  /// No description provided for @acceptNewHostsRecommended.
  ///
  /// In en, this message translates to:
  /// **'Accept new hosts (recommended)'**
  String get acceptNewHostsRecommended;

  /// No description provided for @askBeforeTrusting.
  ///
  /// In en, this message translates to:
  /// **'Ask before trusting'**
  String get askBeforeTrusting;

  /// No description provided for @doNotVerifyUnsafe.
  ///
  /// In en, this message translates to:
  /// **'Do not verify (unsafe)'**
  String get doNotVerifyUnsafe;

  /// No description provided for @knownHostsFileOptional.
  ///
  /// In en, this message translates to:
  /// **'Known hosts file (optional)'**
  String get knownHostsFileOptional;

  /// No description provided for @proxyCommandOptional.
  ///
  /// In en, this message translates to:
  /// **'ProxyCommand (optional)'**
  String get proxyCommandOptional;

  /// No description provided for @proxyJumpOptional.
  ///
  /// In en, this message translates to:
  /// **'ProxyJump (optional)'**
  String get proxyJumpOptional;

  /// No description provided for @proxyJumpHelp.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated [user@]host[:port]; bracket IPv6 hosts. New hops use independent Auto authentication.'**
  String get proxyJumpHelp;

  /// No description provided for @portForwards.
  ///
  /// In en, this message translates to:
  /// **'Port forwards'**
  String get portForwards;

  /// No description provided for @portForwardsHelp.
  ///
  /// In en, this message translates to:
  /// **'One per line: L bind:port target:port, R bind:port target:port, or D bind:port.'**
  String get portForwardsHelp;

  /// No description provided for @forwardSshAgent.
  ///
  /// In en, this message translates to:
  /// **'Forward SSH agent'**
  String get forwardSshAgent;

  /// No description provided for @agentSocketHelp.
  ///
  /// In en, this message translates to:
  /// **'Blank socket path uses SSH_AUTH_SOCK.'**
  String get agentSocketHelp;

  /// No description provided for @agentSocketOptional.
  ///
  /// In en, this message translates to:
  /// **'Agent socket (optional)'**
  String get agentSocketOptional;

  /// No description provided for @forwardX11.
  ///
  /// In en, this message translates to:
  /// **'Forward X11'**
  String get forwardX11;

  /// No description provided for @x11ForwardingHelp.
  ///
  /// In en, this message translates to:
  /// **'Blank target uses DISPLAY; a 32-character MIT-MAGIC-COOKIE is required.'**
  String get x11ForwardingHelp;

  /// No description provided for @localX11Target.
  ///
  /// In en, this message translates to:
  /// **'Local X11 target host:port'**
  String get localX11Target;

  /// No description provided for @x11AuthenticationCookie.
  ///
  /// In en, this message translates to:
  /// **'X11 authentication cookie'**
  String get x11AuthenticationCookie;

  /// No description provided for @x11CookieRequired.
  ///
  /// In en, this message translates to:
  /// **'Required: exactly 32 hexadecimal characters.'**
  String get x11CookieRequired;

  /// No description provided for @forgetSavedX11Cookie.
  ///
  /// In en, this message translates to:
  /// **'Forget saved X11 cookie'**
  String get forgetSavedX11Cookie;

  /// No description provided for @saveThisSshSession.
  ///
  /// In en, this message translates to:
  /// **'Save this SSH session'**
  String get saveThisSshSession;

  /// No description provided for @secretsEncryptedDescription.
  ///
  /// In en, this message translates to:
  /// **'Secrets are encrypted; the key stays in platform safe storage.'**
  String get secretsEncryptedDescription;

  /// No description provided for @remoteServiceRequiredToSaveProfile.
  ///
  /// In en, this message translates to:
  /// **'A remote data service is required to save profiles. This connection is one-time only.'**
  String get remoteServiceRequiredToSaveProfile;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredField;

  /// Numeric field range validation message
  ///
  /// In en, this message translates to:
  /// **'Enter {minimum}–{maximum}'**
  String enterRange(int minimum, int maximum);

  /// No description provided for @connectTimeoutSeconds.
  ///
  /// In en, this message translates to:
  /// **'Connect timeout (seconds)'**
  String get connectTimeoutSeconds;

  /// No description provided for @keepaliveSeconds.
  ///
  /// In en, this message translates to:
  /// **'Keepalive (seconds)'**
  String get keepaliveSeconds;

  /// No description provided for @keepaliveRetries.
  ///
  /// In en, this message translates to:
  /// **'Keepalive retries'**
  String get keepaliveRetries;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @generalProfileDescription.
  ///
  /// In en, this message translates to:
  /// **'Name and tag the profile before configuring launch behavior.'**
  String get generalProfileDescription;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @tagsCommaHelp.
  ///
  /// In en, this message translates to:
  /// **'Separate tags with commas.'**
  String get tagsCommaHelp;

  /// No description provided for @profileStartupDescription.
  ///
  /// In en, this message translates to:
  /// **'Configure the command, working directory, and process environment.'**
  String get profileStartupDescription;

  /// No description provided for @command.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get command;

  /// No description provided for @shellProgram.
  ///
  /// In en, this message translates to:
  /// **'Shell / Program'**
  String get shellProgram;

  /// No description provided for @workingDirectory.
  ///
  /// In en, this message translates to:
  /// **'Working directory'**
  String get workingDirectory;

  /// No description provided for @workingDirectoryHelp.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use the default working directory.'**
  String get workingDirectoryHelp;

  /// No description provided for @argumentsAndEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Arguments and environment'**
  String get argumentsAndEnvironment;

  /// No description provided for @arguments.
  ///
  /// In en, this message translates to:
  /// **'Arguments'**
  String get arguments;

  /// No description provided for @terminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get terminal;

  /// No description provided for @terminalProfileDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose terminal emulation and retained scrollback for new sessions.'**
  String get terminalProfileDescription;

  /// No description provided for @emulation.
  ///
  /// In en, this message translates to:
  /// **'Emulation'**
  String get emulation;

  /// No description provided for @scrollbackLines.
  ///
  /// In en, this message translates to:
  /// **'Scrollback lines'**
  String get scrollbackLines;

  /// No description provided for @profileAppearanceDescription.
  ///
  /// In en, this message translates to:
  /// **'Control typography, colors, and cursor behavior.'**
  String get profileAppearanceDescription;

  /// No description provided for @typography.
  ///
  /// In en, this message translates to:
  /// **'Typography'**
  String get typography;

  /// No description provided for @fontFamily.
  ///
  /// In en, this message translates to:
  /// **'Font family'**
  String get fontFamily;

  /// No description provided for @fallbackFonts.
  ///
  /// In en, this message translates to:
  /// **'Fallback fonts'**
  String get fallbackFonts;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get fontSize;

  /// No description provided for @lineHeight.
  ///
  /// In en, this message translates to:
  /// **'Line height'**
  String get lineHeight;

  /// No description provided for @colors.
  ///
  /// In en, this message translates to:
  /// **'Colors'**
  String get colors;

  /// No description provided for @specialColors.
  ///
  /// In en, this message translates to:
  /// **'Special'**
  String get specialColors;

  /// No description provided for @ansiNormal.
  ///
  /// In en, this message translates to:
  /// **'ANSI normal'**
  String get ansiNormal;

  /// No description provided for @ansiBright.
  ///
  /// In en, this message translates to:
  /// **'ANSI bright'**
  String get ansiBright;

  /// No description provided for @cursor.
  ///
  /// In en, this message translates to:
  /// **'Cursor'**
  String get cursor;

  /// No description provided for @cursorShape.
  ///
  /// In en, this message translates to:
  /// **'Cursor shape'**
  String get cursorShape;

  /// No description provided for @blinkCursor.
  ///
  /// In en, this message translates to:
  /// **'Blink cursor'**
  String get blinkCursor;

  /// No description provided for @keys.
  ///
  /// In en, this message translates to:
  /// **'Keys'**
  String get keys;

  /// No description provided for @keysProfileDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose selection defaults for newly opened sessions.'**
  String get keysProfileDescription;

  /// No description provided for @selection.
  ///
  /// In en, this message translates to:
  /// **'Selection'**
  String get selection;

  /// No description provided for @copyOnSelect.
  ///
  /// In en, this message translates to:
  /// **'Copy on select'**
  String get copyOnSelect;

  /// No description provided for @optionDragMode.
  ///
  /// In en, this message translates to:
  /// **'Option-drag mode'**
  String get optionDragMode;

  /// No description provided for @automation.
  ///
  /// In en, this message translates to:
  /// **'Automation'**
  String get automation;

  /// No description provided for @automationProfileDescription.
  ///
  /// In en, this message translates to:
  /// **'Match terminal output, then notify you or type a fixed reply.'**
  String get automationProfileDescription;

  /// No description provided for @rules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get rules;

  /// No description provided for @triggers.
  ///
  /// In en, this message translates to:
  /// **'Triggers'**
  String get triggers;

  /// No description provided for @triggerExamples.
  ///
  /// In en, this message translates to:
  /// **'Examples: ERROR => notify, Password: => send: secret'**
  String get triggerExamples;

  /// No description provided for @automaticProfileSwitching.
  ///
  /// In en, this message translates to:
  /// **'Automatic profile switching'**
  String get automaticProfileSwitching;

  /// No description provided for @automaticProfileSwitchingHelp.
  ///
  /// In en, this message translates to:
  /// **'Change this profile after host, user, or directory changes.'**
  String get automaticProfileSwitchingHelp;

  /// No description provided for @advanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advanced;

  /// No description provided for @advancedProfileDescription.
  ///
  /// In en, this message translates to:
  /// **'Control shell-aware profile behavior for new sessions.'**
  String get advancedProfileDescription;

  /// No description provided for @integration.
  ///
  /// In en, this message translates to:
  /// **'Integration'**
  String get integration;

  /// No description provided for @shellIntegration.
  ///
  /// In en, this message translates to:
  /// **'Shell Integration'**
  String get shellIntegration;

  /// No description provided for @shellIntegrationDescription.
  ///
  /// In en, this message translates to:
  /// **'Enable prompt marks, badges, command navigation, and shell-aware actions.'**
  String get shellIntegrationDescription;

  /// No description provided for @toolbeltTerminalTools.
  ///
  /// In en, this message translates to:
  /// **'Toolbelt terminal tools'**
  String get toolbeltTerminalTools;

  /// No description provided for @closeToolbelt.
  ///
  /// In en, this message translates to:
  /// **'Close toolbelt'**
  String get closeToolbelt;

  /// No description provided for @promptMarks.
  ///
  /// In en, this message translates to:
  /// **'Prompt Marks'**
  String get promptMarks;

  /// No description provided for @promptMarkCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 mark} other{{count} marks}}'**
  String promptMarkCount(int count);

  /// No description provided for @tmuxIntegration.
  ///
  /// In en, this message translates to:
  /// **'tmux integration'**
  String get tmuxIntegration;

  /// No description provided for @controlModeActive.
  ///
  /// In en, this message translates to:
  /// **'Control mode active'**
  String get controlModeActive;

  /// No description provided for @startOrAttach.
  ///
  /// In en, this message translates to:
  /// **'Start or attach'**
  String get startOrAttach;

  /// No description provided for @coprocess.
  ///
  /// In en, this message translates to:
  /// **'Coprocess'**
  String get coprocess;

  /// No description provided for @automationActive.
  ///
  /// In en, this message translates to:
  /// **'Automation active'**
  String get automationActive;

  /// No description provided for @runAutomation.
  ///
  /// In en, this message translates to:
  /// **'Run automation'**
  String get runAutomation;

  /// No description provided for @annotations.
  ///
  /// In en, this message translates to:
  /// **'Annotations'**
  String get annotations;

  /// No description provided for @annotationCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note} other{{count} notes}}'**
  String annotationCount(int count);

  /// No description provided for @recentFrames.
  ///
  /// In en, this message translates to:
  /// **'Recent frames'**
  String get recentFrames;

  /// No description provided for @passwordManager.
  ///
  /// In en, this message translates to:
  /// **'Password manager'**
  String get passwordManager;

  /// No description provided for @promptGatedSends.
  ///
  /// In en, this message translates to:
  /// **'Prompt-gated sends'**
  String get promptGatedSends;

  /// No description provided for @commands.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get commands;

  /// No description provided for @directoriesShort.
  ///
  /// In en, this message translates to:
  /// **'Dirs'**
  String get directoriesShort;

  /// No description provided for @output.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get output;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @commandHistory.
  ///
  /// In en, this message translates to:
  /// **'Command History'**
  String get commandHistory;

  /// No description provided for @commandCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 command} other{{count} commands}}'**
  String commandCount(int count);

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @runCommandToFillHistory.
  ///
  /// In en, this message translates to:
  /// **'Run a command in this tab to fill command history.'**
  String get runCommandToFillHistory;

  /// No description provided for @insertCommand.
  ///
  /// In en, this message translates to:
  /// **'Insert command'**
  String get insertCommand;

  /// No description provided for @recentDirectories.
  ///
  /// In en, this message translates to:
  /// **'Recent Directories'**
  String get recentDirectories;

  /// No description provided for @directoryCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 directory} other{{count} directories}}'**
  String directoryCount(int count);

  /// No description provided for @changeDirectoriesToFillHistory.
  ///
  /// In en, this message translates to:
  /// **'Change directories to fill recent directories.'**
  String get changeDirectoriesToFillHistory;

  /// No description provided for @insertCdCommand.
  ///
  /// In en, this message translates to:
  /// **'Insert cd command'**
  String get insertCdCommand;

  /// No description provided for @capturedOutput.
  ///
  /// In en, this message translates to:
  /// **'Captured output'**
  String get capturedOutput;

  /// No description provided for @capturedLineCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 captured line} other{{count} captured lines}}'**
  String capturedLineCount(int count);

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @profileAutomationCapturesOutput.
  ///
  /// In en, this message translates to:
  /// **'Profile triggers and coprocesses can capture output.'**
  String get profileAutomationCapturesOutput;

  /// No description provided for @capturedOutputLocation.
  ///
  /// In en, this message translates to:
  /// **'Pattern {pattern} · Row {row}'**
  String capturedOutputLocation(String pattern, int row);

  /// No description provided for @pasteHistory.
  ///
  /// In en, this message translates to:
  /// **'Paste history'**
  String get pasteHistory;

  /// No description provided for @recentItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 recent item} other{{count} recent items}}'**
  String recentItemCount(int count);

  /// No description provided for @copiedAndPastedTextAppearsHere.
  ///
  /// In en, this message translates to:
  /// **'Copied and pasted text appears here.'**
  String get copiedAndPastedTextAppearsHere;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @pasted.
  ///
  /// In en, this message translates to:
  /// **'Pasted'**
  String get pasted;

  /// No description provided for @advancedPaste.
  ///
  /// In en, this message translates to:
  /// **'Advanced Paste'**
  String get advancedPaste;

  /// No description provided for @closeAdvancedPaste.
  ///
  /// In en, this message translates to:
  /// **'Close advanced paste'**
  String get closeAdvancedPaste;

  /// No description provided for @pasteText.
  ///
  /// In en, this message translates to:
  /// **'Paste text'**
  String get pasteText;

  /// No description provided for @text.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get text;

  /// No description provided for @escapeSpecialCharacters.
  ///
  /// In en, this message translates to:
  /// **'Escape special characters'**
  String get escapeSpecialCharacters;

  /// No description provided for @base64Encode.
  ///
  /// In en, this message translates to:
  /// **'Base64 encode'**
  String get base64Encode;

  /// No description provided for @appendNewline.
  ///
  /// In en, this message translates to:
  /// **'Append newline'**
  String get appendNewline;

  /// No description provided for @byteCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 byte} other{{count} bytes}}'**
  String byteCount(int count);

  /// No description provided for @closeCapturedOutput.
  ///
  /// In en, this message translates to:
  /// **'Close captured output'**
  String get closeCapturedOutput;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @startCapturingMatchingOutput.
  ///
  /// In en, this message translates to:
  /// **'Start capturing matching output'**
  String get startCapturingMatchingOutput;

  /// No description provided for @capturedOutputEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Captured rows appear after a profile trigger or coprocess pattern matches terminal output.'**
  String get capturedOutputEmptyBody;

  /// No description provided for @openProfilesAndAddTrigger.
  ///
  /// In en, this message translates to:
  /// **'Open Profiles and add a trigger pattern.'**
  String get openProfilesAndAddTrigger;

  /// No description provided for @runCommandThatPrintsPattern.
  ///
  /// In en, this message translates to:
  /// **'Run a command that prints the pattern.'**
  String get runCommandThatPrintsPattern;

  /// No description provided for @reopenCapturedOutput.
  ///
  /// In en, this message translates to:
  /// **'Reopen Captured Output to review and copy matches.'**
  String get reopenCapturedOutput;

  /// No description provided for @copyCapturedOutput.
  ///
  /// In en, this message translates to:
  /// **'Copy captured output'**
  String get copyCapturedOutput;

  /// No description provided for @closeAnnotations.
  ///
  /// In en, this message translates to:
  /// **'Close annotations'**
  String get closeAnnotations;

  /// No description provided for @selectTerminalTextToAnnotate.
  ///
  /// In en, this message translates to:
  /// **'Select terminal text to add an annotation.'**
  String get selectTerminalTextToAnnotate;

  /// No description provided for @note.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get note;

  /// No description provided for @addAnnotation.
  ///
  /// In en, this message translates to:
  /// **'Add Annotation'**
  String get addAnnotation;

  /// No description provided for @addFirstAnnotation.
  ///
  /// In en, this message translates to:
  /// **'Add the first annotation'**
  String get addFirstAnnotation;

  /// No description provided for @selectOutputBeforeAnnotating.
  ///
  /// In en, this message translates to:
  /// **'Select output before annotating'**
  String get selectOutputBeforeAnnotating;

  /// No description provided for @annotationSelectionReadyBody.
  ///
  /// In en, this message translates to:
  /// **'Use the note field above to attach a note to the selected terminal output.'**
  String get annotationSelectionReadyBody;

  /// No description provided for @annotationSelectionRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'Annotations are created from selected terminal text in the active pane.'**
  String get annotationSelectionRequiredBody;

  /// No description provided for @enterNoteForSelectedOutput.
  ///
  /// In en, this message translates to:
  /// **'Enter a note for the selected output.'**
  String get enterNoteForSelectedOutput;

  /// No description provided for @saveAnnotation.
  ///
  /// In en, this message translates to:
  /// **'Save the annotation.'**
  String get saveAnnotation;

  /// No description provided for @useAnnotationBadge.
  ///
  /// In en, this message translates to:
  /// **'Use the annotation badge to reopen notes later.'**
  String get useAnnotationBadge;

  /// No description provided for @selectTerminalOutputInPane.
  ///
  /// In en, this message translates to:
  /// **'Select terminal output in the pane.'**
  String get selectTerminalOutputInPane;

  /// No description provided for @openAnnotationsAgain.
  ///
  /// In en, this message translates to:
  /// **'Open Annotations again.'**
  String get openAnnotationsAgain;

  /// No description provided for @enterNoteAndSave.
  ///
  /// In en, this message translates to:
  /// **'Enter a note and save it.'**
  String get enterNoteAndSave;

  /// No description provided for @removeAnnotation.
  ///
  /// In en, this message translates to:
  /// **'Remove annotation'**
  String get removeAnnotation;

  /// No description provided for @closePasteHistory.
  ///
  /// In en, this message translates to:
  /// **'Close paste history'**
  String get closePasteHistory;

  /// No description provided for @saveHistoryToDisk.
  ///
  /// In en, this message translates to:
  /// **'Save History to Disk'**
  String get saveHistoryToDisk;

  /// No description provided for @keepPasteHistoryAcrossLaunches.
  ///
  /// In en, this message translates to:
  /// **'Keep recent copied and pasted text across launches.'**
  String get keepPasteHistoryAcrossLaunches;

  /// No description provided for @noPasteHistoryYet.
  ///
  /// In en, this message translates to:
  /// **'No copied or pasted text yet.'**
  String get noPasteHistoryYet;

  /// No description provided for @closePasswordManager.
  ///
  /// In en, this message translates to:
  /// **'Close password manager'**
  String get closePasswordManager;

  /// No description provided for @passwordPromptDetected.
  ///
  /// In en, this message translates to:
  /// **'Password prompt detected in the active session.'**
  String get passwordPromptDetected;

  /// No description provided for @openPasswordPromptFirst.
  ///
  /// In en, this message translates to:
  /// **'Open a password prompt before sending a password.'**
  String get openPasswordPromptFirst;

  /// No description provided for @passwordManagerSessionSecurity.
  ///
  /// In en, this message translates to:
  /// **'Passwords are kept for this app session and can only be sent when the active terminal appears to be asking for one.'**
  String get passwordManagerSessionSecurity;

  /// No description provided for @label.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get label;

  /// No description provided for @serverOrAccount.
  ///
  /// In en, this message translates to:
  /// **'Server or account'**
  String get serverOrAccount;

  /// No description provided for @passwordEntered.
  ///
  /// In en, this message translates to:
  /// **'Password entered'**
  String get passwordEntered;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @noSavedSessionPasswords.
  ///
  /// In en, this message translates to:
  /// **'No saved passwords in this session. Add one above, then open a password prompt before sending.'**
  String get noSavedSessionPasswords;

  /// No description provided for @readyToSend.
  ///
  /// In en, this message translates to:
  /// **'Ready to send'**
  String get readyToSend;

  /// No description provided for @waitingForPasswordPrompt.
  ///
  /// In en, this message translates to:
  /// **'Waiting for password prompt'**
  String get waitingForPasswordPrompt;

  /// No description provided for @removePassword.
  ///
  /// In en, this message translates to:
  /// **'Remove password'**
  String get removePassword;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @closeCoprocess.
  ///
  /// In en, this message translates to:
  /// **'Close coprocess'**
  String get closeCoprocess;

  /// No description provided for @runCoprocess.
  ///
  /// In en, this message translates to:
  /// **'Run Coprocess'**
  String get runCoprocess;

  /// No description provided for @onePerSession.
  ///
  /// In en, this message translates to:
  /// **'one per session'**
  String get onePerSession;

  /// No description provided for @commandLabel.
  ///
  /// In en, this message translates to:
  /// **'Command label'**
  String get commandLabel;

  /// No description provided for @inputPattern.
  ///
  /// In en, this message translates to:
  /// **'Input pattern'**
  String get inputPattern;

  /// No description provided for @coprocessOutput.
  ///
  /// In en, this message translates to:
  /// **'Coprocess output'**
  String get coprocessOutput;

  /// No description provided for @run.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get run;

  /// No description provided for @lineCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 line} other{{count} lines}}'**
  String lineCount(int count);

  /// No description provided for @patternValue.
  ///
  /// In en, this message translates to:
  /// **'Pattern {pattern}'**
  String patternValue(String pattern);

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @closeTmuxIntegration.
  ///
  /// In en, this message translates to:
  /// **'Close tmux integration'**
  String get closeTmuxIntegration;

  /// No description provided for @controlMode.
  ///
  /// In en, this message translates to:
  /// **'Control Mode'**
  String get controlMode;

  /// No description provided for @startTmuxControlMode.
  ///
  /// In en, this message translates to:
  /// **'Start tmux -CC'**
  String get startTmuxControlMode;

  /// No description provided for @startTmuxControlModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Create a new tmux control-mode session.'**
  String get startTmuxControlModeDescription;

  /// No description provided for @attachTmuxControlMode.
  ///
  /// In en, this message translates to:
  /// **'Attach tmux -CC'**
  String get attachTmuxControlMode;

  /// No description provided for @attachTmuxControlModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Attach to an existing tmux session.'**
  String get attachTmuxControlModeDescription;

  /// No description provided for @tmuxActions.
  ///
  /// In en, this message translates to:
  /// **'tmux Actions'**
  String get tmuxActions;

  /// No description provided for @available.
  ///
  /// In en, this message translates to:
  /// **'available'**
  String get available;

  /// No description provided for @waiting.
  ///
  /// In en, this message translates to:
  /// **'waiting'**
  String get waiting;

  /// No description provided for @newWindow.
  ///
  /// In en, this message translates to:
  /// **'New window'**
  String get newWindow;

  /// No description provided for @newWindowDescription.
  ///
  /// In en, this message translates to:
  /// **'Send new-window to tmux control mode.'**
  String get newWindowDescription;

  /// No description provided for @splitPaneRight.
  ///
  /// In en, this message translates to:
  /// **'Split pane right'**
  String get splitPaneRight;

  /// No description provided for @splitPaneRightDescription.
  ///
  /// In en, this message translates to:
  /// **'Send split-window -h.'**
  String get splitPaneRightDescription;

  /// No description provided for @splitPaneDown.
  ///
  /// In en, this message translates to:
  /// **'Split pane down'**
  String get splitPaneDown;

  /// No description provided for @splitPaneDownDescription.
  ///
  /// In en, this message translates to:
  /// **'Send split-window -v.'**
  String get splitPaneDownDescription;

  /// No description provided for @detachClient.
  ///
  /// In en, this message translates to:
  /// **'Detach client'**
  String get detachClient;

  /// No description provided for @detachClientDescription.
  ///
  /// In en, this message translates to:
  /// **'Detach while leaving tmux running.'**
  String get detachClientDescription;

  /// No description provided for @sendTmuxCommand.
  ///
  /// In en, this message translates to:
  /// **'Send tmux command'**
  String get sendTmuxCommand;

  /// No description provided for @tmuxCommand.
  ///
  /// In en, this message translates to:
  /// **'tmux command'**
  String get tmuxCommand;

  /// No description provided for @controlModeDetected.
  ///
  /// In en, this message translates to:
  /// **'Control mode detected'**
  String get controlModeDetected;

  /// No description provided for @noTmuxControlModeDetected.
  ///
  /// In en, this message translates to:
  /// **'No tmux control mode detected'**
  String get noTmuxControlModeDetected;

  /// No description provided for @closeShellIntegration.
  ///
  /// In en, this message translates to:
  /// **'Close shell integration'**
  String get closeShellIntegration;

  /// No description provided for @runCommandAfterOpeningTab.
  ///
  /// In en, this message translates to:
  /// **'Run a command after opening this tab to fill command history.'**
  String get runCommandAfterOpeningTab;

  /// No description provided for @insertPreviousCommand.
  ///
  /// In en, this message translates to:
  /// **'Insert previous command'**
  String get insertPreviousCommand;

  /// No description provided for @changeDirectoriesAfterOpeningTab.
  ///
  /// In en, this message translates to:
  /// **'Change directories after opening this tab to fill this list.'**
  String get changeDirectoriesAfterOpeningTab;

  /// No description provided for @promptMarksAppearAfterPrompt.
  ///
  /// In en, this message translates to:
  /// **'Prompt marks appear after the shell draws new prompts.'**
  String get promptMarksAppearAfterPrompt;

  /// No description provided for @commandSucceededShort.
  ///
  /// In en, this message translates to:
  /// **'ok'**
  String get commandSucceededShort;

  /// No description provided for @commandExitCodeShort.
  ///
  /// In en, this message translates to:
  /// **'exit {code}'**
  String commandExitCodeShort(int code);

  /// No description provided for @globalLine.
  ///
  /// In en, this message translates to:
  /// **'Global line {line}'**
  String globalLine(int line);

  /// No description provided for @scrollbackOffset.
  ///
  /// In en, this message translates to:
  /// **'Offset {offset}'**
  String scrollbackOffset(int offset);

  /// No description provided for @shellPromptMark.
  ///
  /// In en, this message translates to:
  /// **'Shell prompt mark'**
  String get shellPromptMark;

  /// No description provided for @regexError.
  ///
  /// In en, this message translates to:
  /// **'Regex error'**
  String get regexError;

  /// No description provided for @noMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get noMatches;

  /// No description provided for @smartCaseSubstring.
  ///
  /// In en, this message translates to:
  /// **'Smart Case Substring'**
  String get smartCaseSubstring;

  /// No description provided for @caseSensitiveSubstring.
  ///
  /// In en, this message translates to:
  /// **'Case-Sensitive Substring'**
  String get caseSensitiveSubstring;

  /// No description provided for @caseInsensitiveSubstring.
  ///
  /// In en, this message translates to:
  /// **'Case-Insensitive Substring'**
  String get caseInsensitiveSubstring;

  /// No description provided for @caseSensitiveRegex.
  ///
  /// In en, this message translates to:
  /// **'Case-Sensitive Regex'**
  String get caseSensitiveRegex;

  /// No description provided for @caseInsensitiveRegex.
  ///
  /// In en, this message translates to:
  /// **'Case-Insensitive Regex'**
  String get caseInsensitiveRegex;

  /// No description provided for @searchFilterValue.
  ///
  /// In en, this message translates to:
  /// **'Search filter: {filter}'**
  String searchFilterValue(String filter);

  /// No description provided for @searchFilter.
  ///
  /// In en, this message translates to:
  /// **'Search filter'**
  String get searchFilter;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @currentTab.
  ///
  /// In en, this message translates to:
  /// **'Current tab'**
  String get currentTab;

  /// No description provided for @allTabs.
  ///
  /// In en, this message translates to:
  /// **'All tabs'**
  String get allTabs;

  /// No description provided for @paneShort.
  ///
  /// In en, this message translates to:
  /// **'Pane'**
  String get paneShort;

  /// No description provided for @tabShort.
  ///
  /// In en, this message translates to:
  /// **'Tab'**
  String get tabShort;

  /// No description provided for @scope.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get scope;

  /// No description provided for @searchScopeValue.
  ///
  /// In en, this message translates to:
  /// **'Search scope: {scope}'**
  String searchScopeValue(String scope);

  /// No description provided for @clearSearchText.
  ///
  /// In en, this message translates to:
  /// **'Clear search text'**
  String get clearSearchText;

  /// No description provided for @searchResultValue.
  ///
  /// In en, this message translates to:
  /// **'Search result: {result}'**
  String searchResultValue(String result);

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @previousMatch.
  ///
  /// In en, this message translates to:
  /// **'Previous match'**
  String get previousMatch;

  /// No description provided for @nextMatch.
  ///
  /// In en, this message translates to:
  /// **'Next match'**
  String get nextMatch;

  /// No description provided for @closeSearch.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get closeSearch;

  /// No description provided for @searchingAcrossSessions.
  ///
  /// In en, this message translates to:
  /// **'Searching across {count, plural, =1{1 session} other{{count} sessions}}'**
  String searchingAcrossSessions(int count);

  /// No description provided for @matchCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 match} other{{count} matches}}'**
  String matchCount(int count);

  /// No description provided for @closeGlobalSearch.
  ///
  /// In en, this message translates to:
  /// **'Close global search'**
  String get closeGlobalSearch;

  /// No description provided for @searchResultLocation.
  ///
  /// In en, this message translates to:
  /// **'{session} · row {row}'**
  String searchResultLocation(String session, int row);

  /// No description provided for @noMatchesInReplayHistory.
  ///
  /// In en, this message translates to:
  /// **'No matches in replay history.'**
  String get noMatchesInReplayHistory;

  /// No description provided for @uniqueReplayMatchCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unique match in replay} other{{count} unique matches in replay}}'**
  String uniqueReplayMatchCount(int count);

  /// No description provided for @idleGapValue.
  ///
  /// In en, this message translates to:
  /// **'Idle gap: {duration}'**
  String idleGapValue(String duration);

  /// No description provided for @noReplayFrames.
  ///
  /// In en, this message translates to:
  /// **'No replay frames'**
  String get noReplayFrames;

  /// No description provided for @recordedAtDimensions.
  ///
  /// In en, this message translates to:
  /// **'Recorded at {columns}x{rows}'**
  String recordedAtDimensions(int columns, int rows);

  /// No description provided for @noReplayFramesCapturedYet.
  ///
  /// In en, this message translates to:
  /// **'No replay frames captured yet.'**
  String get noReplayFramesCapturedYet;

  /// No description provided for @replayRecentActivityLayout.
  ///
  /// In en, this message translates to:
  /// **'Replay recent activity layout'**
  String get replayRecentActivityLayout;

  /// No description provided for @closeReplay.
  ///
  /// In en, this message translates to:
  /// **'Close replay'**
  String get closeReplay;

  /// No description provided for @terminalChanged.
  ///
  /// In en, this message translates to:
  /// **'Terminal changed'**
  String get terminalChanged;

  /// No description provided for @replayControlsRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Replay controls for recent activity'**
  String get replayControlsRecentActivity;

  /// No description provided for @retentionDisabled.
  ///
  /// In en, this message translates to:
  /// **'Retention disabled'**
  String get retentionDisabled;

  /// No description provided for @retainsLatestFrames.
  ///
  /// In en, this message translates to:
  /// **'Retains latest {count, plural, =1{1 frame} other{{count} frames}}'**
  String retainsLatestFrames(int count);

  /// No description provided for @recentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get recentActivity;

  /// No description provided for @stepBackInReplay.
  ///
  /// In en, this message translates to:
  /// **'Step back in replay'**
  String get stepBackInReplay;

  /// No description provided for @pauseReplay.
  ///
  /// In en, this message translates to:
  /// **'Pause replay'**
  String get pauseReplay;

  /// No description provided for @playReplay.
  ///
  /// In en, this message translates to:
  /// **'Play replay'**
  String get playReplay;

  /// No description provided for @stepForwardInReplay.
  ///
  /// In en, this message translates to:
  /// **'Step forward in replay'**
  String get stepForwardInReplay;

  /// No description provided for @playbackSpeedValue.
  ///
  /// In en, this message translates to:
  /// **'Playback speed {speed} times'**
  String playbackSpeedValue(String speed);

  /// No description provided for @playbackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback speed'**
  String get playbackSpeed;

  /// No description provided for @realTimeShort.
  ///
  /// In en, this message translates to:
  /// **'Real'**
  String get realTimeShort;

  /// No description provided for @smartTimeShort.
  ///
  /// In en, this message translates to:
  /// **'Smart'**
  String get smartTimeShort;

  /// No description provided for @replayTimingValue.
  ///
  /// In en, this message translates to:
  /// **'{mode} replay timing'**
  String replayTimingValue(String mode);

  /// No description provided for @replayTiming.
  ///
  /// In en, this message translates to:
  /// **'Replay timing'**
  String get replayTiming;

  /// No description provided for @smartReplayTimingDescription.
  ///
  /// In en, this message translates to:
  /// **'Smart · skip long idle gaps'**
  String get smartReplayTimingDescription;

  /// No description provided for @realReplayTimingDescription.
  ///
  /// In en, this message translates to:
  /// **'Real time · preserve all gaps'**
  String get realReplayTimingDescription;

  /// No description provided for @fitRecordedSize.
  ///
  /// In en, this message translates to:
  /// **'Fit recorded size'**
  String get fitRecordedSize;

  /// No description provided for @copyVisible.
  ///
  /// In en, this message translates to:
  /// **'Copy visible'**
  String get copyVisible;

  /// No description provided for @copySelection.
  ///
  /// In en, this message translates to:
  /// **'Copy selection'**
  String get copySelection;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get clearHistory;

  /// No description provided for @searchReplay.
  ///
  /// In en, this message translates to:
  /// **'Search replay'**
  String get searchReplay;

  /// No description provided for @previousSearchMatch.
  ///
  /// In en, this message translates to:
  /// **'Previous search match'**
  String get previousSearchMatch;

  /// No description provided for @nextSearchMatch.
  ///
  /// In en, this message translates to:
  /// **'Next search match'**
  String get nextSearchMatch;

  /// No description provided for @savedTerminalRecordings.
  ///
  /// In en, this message translates to:
  /// **'Saved terminal recordings'**
  String get savedTerminalRecordings;

  /// No description provided for @savedRecordings.
  ///
  /// In en, this message translates to:
  /// **'Saved Recordings'**
  String get savedRecordings;

  /// No description provided for @importEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Import…'**
  String get importEllipsis;

  /// No description provided for @refreshRecordings.
  ///
  /// In en, this message translates to:
  /// **'Refresh recordings'**
  String get refreshRecordings;

  /// No description provided for @closeSavedRecordings.
  ///
  /// In en, this message translates to:
  /// **'Close Saved Recordings'**
  String get closeSavedRecordings;

  /// No description provided for @searchRecordings.
  ///
  /// In en, this message translates to:
  /// **'Search recordings'**
  String get searchRecordings;

  /// No description provided for @filterPlayableOnly.
  ///
  /// In en, this message translates to:
  /// **'Filter: Playable only'**
  String get filterPlayableOnly;

  /// No description provided for @filterAllRecordings.
  ///
  /// In en, this message translates to:
  /// **'Filter: All recordings'**
  String get filterAllRecordings;

  /// No description provided for @filterRecordings.
  ///
  /// In en, this message translates to:
  /// **'Filter recordings'**
  String get filterRecordings;

  /// No description provided for @allRecordings.
  ///
  /// In en, this message translates to:
  /// **'All recordings'**
  String get allRecordings;

  /// No description provided for @playableOnly.
  ///
  /// In en, this message translates to:
  /// **'Playable only'**
  String get playableOnly;

  /// No description provided for @recordingSortValue.
  ///
  /// In en, this message translates to:
  /// **'Sort: {sort}'**
  String recordingSortValue(String sort);

  /// No description provided for @recordingSortOrder.
  ///
  /// In en, this message translates to:
  /// **'Recording sort order'**
  String get recordingSortOrder;

  /// No description provided for @newest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get newest;

  /// No description provided for @oldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get oldest;

  /// No description provided for @recordingsMayContainSensitiveOutput.
  ///
  /// In en, this message translates to:
  /// **'Recordings may contain sensitive terminal output.'**
  String get recordingsMayContainSensitiveOutput;

  /// No description provided for @recordingMayContainSensitiveOutput.
  ///
  /// In en, this message translates to:
  /// **'This recording may contain sensitive output.'**
  String get recordingMayContainSensitiveOutput;

  /// No description provided for @recordingCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 recording} other{{count} recordings}}'**
  String recordingCount(int count);

  /// No description provided for @noMatchingRecordings.
  ///
  /// In en, this message translates to:
  /// **'No matching recordings'**
  String get noMatchingRecordings;

  /// No description provided for @noSavedRecordings.
  ///
  /// In en, this message translates to:
  /// **'No saved recordings'**
  String get noSavedRecordings;

  /// No description provided for @actionsForNamedItem.
  ///
  /// In en, this message translates to:
  /// **'Actions for {name}'**
  String actionsForNamedItem(String name);

  /// No description provided for @recordingActions.
  ///
  /// In en, this message translates to:
  /// **'Recording actions'**
  String get recordingActions;

  /// No description provided for @renameEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Rename…'**
  String get renameEllipsis;

  /// No description provided for @revealInFinder.
  ///
  /// In en, this message translates to:
  /// **'Reveal in Finder'**
  String get revealInFinder;

  /// No description provided for @exportEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Export…'**
  String get exportEllipsis;

  /// No description provided for @moveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get moveToTrash;

  /// No description provided for @couldNotStartReplay.
  ///
  /// In en, this message translates to:
  /// **'Could not start replay: {error}'**
  String couldNotStartReplay(String error);

  /// No description provided for @couldNotSeekRecording.
  ///
  /// In en, this message translates to:
  /// **'Could not seek recording: {error}'**
  String couldNotSeekRecording(String error);

  /// No description provided for @inputIncluded.
  ///
  /// In en, this message translates to:
  /// **'Input included'**
  String get inputIncluded;

  /// No description provided for @keystrokesRedactedCommandMetadataIncluded.
  ///
  /// In en, this message translates to:
  /// **'Keystrokes redacted · command metadata included'**
  String get keystrokesRedactedCommandMetadataIncluded;

  /// No description provided for @keystrokesRedacted.
  ///
  /// In en, this message translates to:
  /// **'Keystrokes redacted'**
  String get keystrokesRedacted;

  /// No description provided for @recordedSession.
  ///
  /// In en, this message translates to:
  /// **'Recorded session'**
  String get recordedSession;

  /// No description provided for @recordingDetail.
  ///
  /// In en, this message translates to:
  /// **'{session} · {disclosure}'**
  String recordingDetail(String session, String disclosure);

  /// No description provided for @preparingReplay.
  ///
  /// In en, this message translates to:
  /// **'Preparing replay…'**
  String get preparingReplay;

  /// No description provided for @replayRecordingLayout.
  ///
  /// In en, this message translates to:
  /// **'Replay recording layout for {name}'**
  String replayRecordingLayout(String name);

  /// No description provided for @recording.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get recording;

  /// No description provided for @matchesAcrossReplay.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 match across replay} other{{count} matches across replay}}'**
  String matchesAcrossReplay(int count);

  /// No description provided for @replayControlsForRecording.
  ///
  /// In en, this message translates to:
  /// **'Replay controls for recording'**
  String get replayControlsForRecording;

  /// No description provided for @idleInterval.
  ///
  /// In en, this message translates to:
  /// **'Idle interval'**
  String get idleInterval;

  /// No description provided for @inputEvent.
  ///
  /// In en, this message translates to:
  /// **'Input event'**
  String get inputEvent;

  /// No description provided for @terminalResized.
  ///
  /// In en, this message translates to:
  /// **'Terminal resized'**
  String get terminalResized;

  /// No description provided for @sessionExited.
  ///
  /// In en, this message translates to:
  /// **'Session exited'**
  String get sessionExited;

  /// No description provided for @outputEvent.
  ///
  /// In en, this message translates to:
  /// **'Output event'**
  String get outputEvent;

  /// No description provided for @activity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activity;

  /// No description provided for @remoteActivity.
  ///
  /// In en, this message translates to:
  /// **'Remote activity'**
  String get remoteActivity;

  /// No description provided for @commandNumber.
  ///
  /// In en, this message translates to:
  /// **'Command {number}'**
  String commandNumber(int number);

  /// No description provided for @replayTimelineSemantics.
  ///
  /// In en, this message translates to:
  /// **'{context}, {position} of {duration}'**
  String replayTimelineSemantics(
    String context,
    String position,
    String duration,
  );

  /// No description provided for @exitCode.
  ///
  /// In en, this message translates to:
  /// **'Exit code {code}'**
  String exitCode(int code);

  /// No description provided for @jumpToReplaySegment.
  ///
  /// In en, this message translates to:
  /// **'Jump to {segment} at {time}'**
  String jumpToReplaySegment(String segment, String time);

  /// No description provided for @remote.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get remote;

  /// No description provided for @idle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get idle;

  /// No description provided for @remoteSession.
  ///
  /// In en, this message translates to:
  /// **'Remote session'**
  String get remoteSession;

  /// No description provided for @idleGap.
  ///
  /// In en, this message translates to:
  /// **'Idle gap'**
  String get idleGap;

  /// No description provided for @shellSemantics.
  ///
  /// In en, this message translates to:
  /// **'Shell semantics'**
  String get shellSemantics;

  /// No description provided for @activityFallbackNoShellHook.
  ///
  /// In en, this message translates to:
  /// **'Activity fallback · no shell hook'**
  String get activityFallbackNoShellHook;

  /// No description provided for @terminalActionName.
  ///
  /// In en, this message translates to:
  /// **'{action, select, new_tab{New tab} new_ssh_session{New SSH session} new_tab_at_folder{New tab at folder} open_recording_for_replay{Open recording for replay} duplicate_current_cwd{Duplicate current directory} reopen_closed_tab{Reopen closed tab} open_launcher{Open launcher} open_command_menu{Open command menu} toolbelt{Toolbelt} open_sftp_panel{Open SFTP panel} split_right{Split right} split_down{Split down} focus_next_pane{Focus next pane} focus_previous_pane{Focus previous pane} resize_pane{Resize pane} swap_pane{Swap pane} zoom_pane{Zoom pane} close_pane{Close pane} reopen_closed_pane{Reopen closed pane} close_active_tab{Close active tab} open_defaults{Open defaults} activate_tab{Activate tab} copy{Copy} copy_mode{Copy mode} copy_command_output{Copy command output} paste{Paste} advanced_paste{Advanced paste} paste_history{Paste history} toggle_read_only{Toggle read-only} toggle_replay_recording{Toggle replay recording} clear_buffer{Clear buffer} shell_integration{Shell integration} select_command_output{Select command output} open_recent_directory{Open recent directory} tmux_integration{tmux integration} coprocess{Coprocess} annotations{Annotations} captured_output{Captured output} password_manager{Password manager} replay_recent_activity{Replay recent activity} search_scrollback{Search scrollback} next_search_match{Next search match} previous_search_match{Previous search match} clear_search{Clear search} global_search{Global search} autocomplete{Autocomplete} auto_composer{Auto composer} hotkey_window{Hotkey window} defaults{Defaults} profiles{Profiles} dynamic_profiles{Dynamic profiles} request_quit_confirmation{Request quit confirmation} previous_prompt{Previous prompt} next_prompt{Next prompt} toggle_command_finished_notify{Toggle command-finished notifications} toggle_bell_notify{Toggle bell notifications} toggle_activity_monitor{Toggle activity monitor} export_scrollback{Export scrollback} export_diagnostics{Export diagnostics} open_theme_picker{Open theme picker} apply_theme{Apply theme} apply_layout_template{Apply layout template} other{{action}}}'**
  String terminalActionName(String action);

  /// No description provided for @appCategory.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get appCategory;

  /// No description provided for @sessionCategory.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get sessionCategory;

  /// No description provided for @replayCategory.
  ///
  /// In en, this message translates to:
  /// **'Replay'**
  String get replayCategory;

  /// No description provided for @paneCategory.
  ///
  /// In en, this message translates to:
  /// **'Pane'**
  String get paneCategory;

  /// No description provided for @layoutCategory.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get layoutCategory;

  /// No description provided for @navigationCategory.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get navigationCategory;

  /// No description provided for @integrationCategory.
  ///
  /// In en, this message translates to:
  /// **'Integration'**
  String get integrationCategory;

  /// No description provided for @appFocused.
  ///
  /// In en, this message translates to:
  /// **'App focused'**
  String get appFocused;

  /// No description provided for @terminalFocused.
  ///
  /// In en, this message translates to:
  /// **'Terminal focused'**
  String get terminalFocused;

  /// No description provided for @appWideFallback.
  ///
  /// In en, this message translates to:
  /// **'App-wide fallback'**
  String get appWideFallback;

  /// No description provided for @commandMenuOpen.
  ///
  /// In en, this message translates to:
  /// **'Command menu open'**
  String get commandMenuOpen;

  /// No description provided for @notAssigned.
  ///
  /// In en, this message translates to:
  /// **'Not assigned'**
  String get notAssigned;

  /// No description provided for @noShortcut.
  ///
  /// In en, this message translates to:
  /// **'no shortcut'**
  String get noShortcut;

  /// No description provided for @shortcutConflict.
  ///
  /// In en, this message translates to:
  /// **'Conflict'**
  String get shortcutConflict;

  /// No description provided for @shortcutDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get shortcutDisabled;

  /// No description provided for @shortcutCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get shortcutCustom;

  /// No description provided for @shortcutUnassigned.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get shortcutUnassigned;

  /// No description provided for @shortcutActionColumn.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get shortcutActionColumn;

  /// No description provided for @shortcutValueColumn.
  ///
  /// In en, this message translates to:
  /// **'Shortcut'**
  String get shortcutValueColumn;

  /// No description provided for @shortcutDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get shortcutDefault;

  /// No description provided for @shortcutActionSemantics.
  ///
  /// In en, this message translates to:
  /// **'{action}, {state}, {shortcut}'**
  String shortcutActionSemantics(String action, String state, String shortcut);

  /// No description provided for @listAndSeparator.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get listAndSeparator;

  /// No description provided for @profileColorName.
  ///
  /// In en, this message translates to:
  /// **'{color, select, special_foreground{Foreground} special_background{Background} special_cursor{Cursor color} special_selection{Selection color} special_tab{Tab color} normal_black{Black} normal_red{Red} normal_green{Green} normal_yellow{Yellow} normal_blue{Blue} normal_magenta{Magenta} normal_cyan{Cyan} normal_white{White} bright_black{Bright black} bright_red{Bright red} bright_green{Bright green} bright_yellow{Bright yellow} bright_blue{Bright blue} bright_magenta{Bright magenta} bright_cyan{Bright cyan} bright_white{Bright white} other{{color}}}'**
  String profileColorName(String color);

  /// No description provided for @moveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get moveDown;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @environmentVariables.
  ///
  /// In en, this message translates to:
  /// **'Environment variables'**
  String get environmentVariables;

  /// No description provided for @addVariable.
  ///
  /// In en, this message translates to:
  /// **'Add variable'**
  String get addVariable;

  /// No description provided for @noEnvironmentVariables.
  ///
  /// In en, this message translates to:
  /// **'No environment variables'**
  String get noEnvironmentVariables;

  /// No description provided for @key.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get key;

  /// No description provided for @value.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get value;

  /// No description provided for @environmentVariableKey.
  ///
  /// In en, this message translates to:
  /// **'Environment variable key {number}'**
  String environmentVariableKey(int number);

  /// No description provided for @environmentVariableValue.
  ///
  /// In en, this message translates to:
  /// **'Environment variable value {number}'**
  String environmentVariableValue(int number);

  /// No description provided for @variableName.
  ///
  /// In en, this message translates to:
  /// **'Variable name'**
  String get variableName;

  /// No description provided for @removeVariable.
  ///
  /// In en, this message translates to:
  /// **'Remove variable'**
  String get removeVariable;

  /// No description provided for @themePresets.
  ///
  /// In en, this message translates to:
  /// **'Theme presets'**
  String get themePresets;

  /// No description provided for @themePresetsDescription.
  ///
  /// In en, this message translates to:
  /// **'Follow the app theme, apply a curated palette, or fine-tune individual colors.'**
  String get themePresetsDescription;

  /// No description provided for @followApplicationThemeColors.
  ///
  /// In en, this message translates to:
  /// **'Follow application theme colors'**
  String get followApplicationThemeColors;

  /// No description provided for @followAppTheme.
  ///
  /// In en, this message translates to:
  /// **'Follow app theme'**
  String get followAppTheme;

  /// No description provided for @followAppThemeDescription.
  ///
  /// In en, this message translates to:
  /// **'Terminal background and text update when the application theme changes.'**
  String get followAppThemeDescription;

  /// No description provided for @pickColor.
  ///
  /// In en, this message translates to:
  /// **'Pick color'**
  String get pickColor;

  /// No description provided for @inheritingDefaultTerminalColor.
  ///
  /// In en, this message translates to:
  /// **'Inheriting default terminal color'**
  String get inheritingDefaultTerminalColor;

  /// No description provided for @currentColorValue.
  ///
  /// In en, this message translates to:
  /// **'Current color {color}'**
  String currentColorValue(String color);

  /// No description provided for @hexColorOrEmpty.
  ///
  /// In en, this message translates to:
  /// **'#RRGGBB or empty'**
  String get hexColorOrEmpty;

  /// No description provided for @hex.
  ///
  /// In en, this message translates to:
  /// **'Hex'**
  String get hex;

  /// No description provided for @palette.
  ///
  /// In en, this message translates to:
  /// **'Palette'**
  String get palette;

  /// No description provided for @hue.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get hue;

  /// No description provided for @resetToDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get resetToDefault;

  /// No description provided for @pick.
  ///
  /// In en, this message translates to:
  /// **'Pick'**
  String get pick;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @pickNamedColor.
  ///
  /// In en, this message translates to:
  /// **'Pick {name} color'**
  String pickNamedColor(String name);

  /// No description provided for @resetNamedColor.
  ///
  /// In en, this message translates to:
  /// **'Reset {name} color'**
  String resetNamedColor(String name);

  /// No description provided for @colorPalette.
  ///
  /// In en, this message translates to:
  /// **'Color palette'**
  String get colorPalette;

  /// No description provided for @hueSlider.
  ///
  /// In en, this message translates to:
  /// **'Hue slider'**
  String get hueSlider;

  /// No description provided for @hexColorValidation.
  ///
  /// In en, this message translates to:
  /// **'Use #RRGGBB or leave empty.'**
  String get hexColorValidation;

  /// No description provided for @dynamicProfilesTopLevelObject.
  ///
  /// In en, this message translates to:
  /// **'Top-level JSON must be an object.'**
  String get dynamicProfilesTopLevelObject;

  /// No description provided for @dynamicProfilesNoneFound.
  ///
  /// In en, this message translates to:
  /// **'No profiles found in JSON.'**
  String get dynamicProfilesNoneFound;

  /// No description provided for @dynamicProfilesInvalid.
  ///
  /// In en, this message translates to:
  /// **'Could not read profiles: {error}'**
  String dynamicProfilesInvalid(String error);

  /// No description provided for @dynamicProfilesPreviewSummary.
  ///
  /// In en, this message translates to:
  /// **'{profiles, plural, =1{1 profile ready} other{{profiles} profiles ready}} • {added} new • {replacements, plural, =1{1 replacement} other{{replacements} replacements}}{warnings, plural, =0{} =1{ • 1 warning} other{ • {warnings} warnings}}'**
  String dynamicProfilesPreviewSummary(
    int profiles,
    int added,
    int replacements,
    int warnings,
  );

  /// No description provided for @replacesExisting.
  ///
  /// In en, this message translates to:
  /// **'Replaces existing'**
  String get replacesExisting;

  /// No description provided for @dynamicProfiles.
  ///
  /// In en, this message translates to:
  /// **'Dynamic Profiles'**
  String get dynamicProfiles;

  /// No description provided for @closeDynamicProfiles.
  ///
  /// In en, this message translates to:
  /// **'Close dynamic profiles'**
  String get closeDynamicProfiles;

  /// No description provided for @dynamicProfilesPasteHelp.
  ///
  /// In en, this message translates to:
  /// **'Paste an iTerm2 dynamic profile JSON document. This local build only launches local commands.'**
  String get dynamicProfilesPasteHelp;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @osc52Clipboard.
  ///
  /// In en, this message translates to:
  /// **'OSC 52 clipboard'**
  String get osc52Clipboard;

  /// No description provided for @osc52ClipboardDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose how terminal escape sequences may access the system clipboard.'**
  String get osc52ClipboardDescription;

  /// No description provided for @securityPermissions.
  ///
  /// In en, this message translates to:
  /// **'Security & permissions'**
  String get securityPermissions;

  /// No description provided for @securityPermissionsDescription.
  ///
  /// In en, this message translates to:
  /// **'Control how terminal sessions interact with the app and remote system while balancing safety and convenience.'**
  String get securityPermissionsDescription;

  /// No description provided for @sessionInteractionsPermissions.
  ///
  /// In en, this message translates to:
  /// **'Session interactions & permissions'**
  String get sessionInteractionsPermissions;

  /// No description provided for @sessionInteractionsPermissionsDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage requests initiated by terminal applications or remote systems and understand their security impact.'**
  String get sessionInteractionsPermissionsDescription;

  /// No description provided for @securityImpact.
  ///
  /// In en, this message translates to:
  /// **'Security impact'**
  String get securityImpact;

  /// No description provided for @currentPolicy.
  ///
  /// In en, this message translates to:
  /// **'Current policy'**
  String get currentPolicy;

  /// No description provided for @riskLevel.
  ///
  /// In en, this message translates to:
  /// **'Risk level'**
  String get riskLevel;

  /// No description provided for @riskLevelName.
  ///
  /// In en, this message translates to:
  /// **'{level, select, low{Low} medium{Medium} high{High} other{{level}}}'**
  String riskLevelName(String level);

  /// No description provided for @behaviorBoundary.
  ///
  /// In en, this message translates to:
  /// **'Behavior boundary'**
  String get behaviorBoundary;

  /// No description provided for @recommendation.
  ///
  /// In en, this message translates to:
  /// **'Why this is recommended'**
  String get recommendation;

  /// No description provided for @recommendedSetting.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get recommendedSetting;

  /// No description provided for @permissionRecommendation.
  ///
  /// In en, this message translates to:
  /// **'{permission, select, osc52{Per-profile control balances clipboard convenience with protection for sensitive content.} openUrl{Per-request confirmation prevents remote content from opening external links without explicit consent.} attention{Deny nonessential alerts to avoid interruption; allow bounded attention only when needed.} other{Keeping an explicit user confirmation helps control interactions initiated by terminal content.}}'**
  String permissionRecommendation(String permission);

  /// No description provided for @manageDecisions.
  ///
  /// In en, this message translates to:
  /// **'Manage decisions'**
  String get manageDecisions;

  /// No description provided for @terminalUrlRequests.
  ///
  /// In en, this message translates to:
  /// **'Terminal URL requests'**
  String get terminalUrlRequests;

  /// No description provided for @terminalUrlRequestsDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose whether OSC 1337 OpenURL requests may ask for permission. URLs are never opened automatically.'**
  String get terminalUrlRequestsDescription;

  /// No description provided for @terminalAttentionRequests.
  ///
  /// In en, this message translates to:
  /// **'Terminal attention requests'**
  String get terminalAttentionRequests;

  /// No description provided for @terminalAttentionRequestsDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose whether OSC 1337 RequestAttention may use a bounded Dock alert or a cursor-local visual effect. Requests never activate or focus the app.'**
  String get terminalAttentionRequestsDescription;

  /// No description provided for @terminalVariableReports.
  ///
  /// In en, this message translates to:
  /// **'Terminal variable reports'**
  String get terminalVariableReports;

  /// No description provided for @terminalVariableReportsDescription.
  ///
  /// In en, this message translates to:
  /// **'OSC 1337 ReportVariable requests are denied the first time. Remembered decisions apply only to the named session.* or user.* variable.'**
  String get terminalVariableReportsDescription;

  /// No description provided for @noRememberedDecisions.
  ///
  /// In en, this message translates to:
  /// **'No remembered decisions'**
  String get noRememberedDecisions;

  /// No description provided for @rememberedDecisionSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} remembered · {allowed} allowed · {denied} denied'**
  String rememberedDecisionSummary(int count, int allowed, int denied);

  /// No description provided for @forgettingDecisionsHelp.
  ///
  /// In en, this message translates to:
  /// **'Forgetting decisions restores the safe first-request denial and lets the app ask again later.'**
  String get forgettingDecisionsHelp;

  /// No description provided for @allow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allow;

  /// No description provided for @deny.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get deny;

  /// No description provided for @forgetDecisionFor.
  ///
  /// In en, this message translates to:
  /// **'Forget decision for {name}'**
  String forgetDecisionFor(String name);

  /// No description provided for @forgetAllDecisions.
  ///
  /// In en, this message translates to:
  /// **'Forget all decisions'**
  String get forgetAllDecisions;

  /// No description provided for @dataService.
  ///
  /// In en, this message translates to:
  /// **'Data service'**
  String get dataService;

  /// No description provided for @dataServiceDescriptionLocalAvailable.
  ///
  /// In en, this message translates to:
  /// **'Choose whether the app starts a local data service or connects to a remote one.'**
  String get dataServiceDescriptionLocalAvailable;

  /// No description provided for @dataServiceDescriptionRemoteOnly.
  ///
  /// In en, this message translates to:
  /// **'Use one-time SSH connections without a data service, or connect a remote service to save profiles and sync them.'**
  String get dataServiceDescriptionRemoteOnly;

  /// No description provided for @activeDataService.
  ///
  /// In en, this message translates to:
  /// **'Active data service: {service}'**
  String activeDataService(String service);

  /// No description provided for @activeNow.
  ///
  /// In en, this message translates to:
  /// **'Active now: {service}'**
  String activeNow(String service);

  /// No description provided for @currentlyRunning.
  ///
  /// In en, this message translates to:
  /// **'Currently running: {service}'**
  String currentlyRunning(String service);

  /// No description provided for @running.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get running;

  /// No description provided for @selected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get selected;

  /// No description provided for @dataServiceMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get dataServiceMode;

  /// No description provided for @apiService.
  ///
  /// In en, this message translates to:
  /// **'API service'**
  String get apiService;

  /// No description provided for @configurationAndStorage.
  ///
  /// In en, this message translates to:
  /// **'Configuration & storage'**
  String get configurationAndStorage;

  /// No description provided for @crossDeviceSync.
  ///
  /// In en, this message translates to:
  /// **'Cross-device sync'**
  String get crossDeviceSync;

  /// No description provided for @dataModeApiSummary.
  ///
  /// In en, this message translates to:
  /// **'{deployment, select, disabled{No API process} local{Start the local API service} remote{Connect to a remote API} other{{deployment}}}'**
  String dataModeApiSummary(String deployment);

  /// No description provided for @dataModeStorageSummary.
  ///
  /// In en, this message translates to:
  /// **'{deployment, select, disabled{Use local shell configuration} local{Persist offline on this Mac} remote{Store with the remote service} other{{deployment}}}'**
  String dataModeStorageSummary(String deployment);

  /// No description provided for @dataModeSyncSummary.
  ///
  /// In en, this message translates to:
  /// **'{deployment, select, disabled{No sync} local{No sync} remote{Sync devices after sign-in} other{{deployment}}}'**
  String dataModeSyncSummary(String deployment);

  /// No description provided for @localTerminal.
  ///
  /// In en, this message translates to:
  /// **'Local terminal'**
  String get localTerminal;

  /// No description provided for @noDataService.
  ///
  /// In en, this message translates to:
  /// **'No data service'**
  String get noDataService;

  /// No description provided for @bundledLocalService.
  ///
  /// In en, this message translates to:
  /// **'Bundled local service'**
  String get bundledLocalService;

  /// No description provided for @remoteService.
  ///
  /// In en, this message translates to:
  /// **'Remote service'**
  String get remoteService;

  /// No description provided for @localTerminalNoApiDescription.
  ///
  /// In en, this message translates to:
  /// **'No API process. Use local shells and hosts from ~/.ssh/config only.'**
  String get localTerminalNoApiDescription;

  /// No description provided for @noDataServiceDescription.
  ///
  /// In en, this message translates to:
  /// **'No API process. Create one-time SSH connections without saving them.'**
  String get noDataServiceDescription;

  /// No description provided for @bundledLocalServiceDescription.
  ///
  /// In en, this message translates to:
  /// **'Offline API persistence and custom SSH profiles on this Mac.'**
  String get bundledLocalServiceDescription;

  /// No description provided for @migrateRemoteApiData.
  ///
  /// In en, this message translates to:
  /// **'Migrate remote API data'**
  String get migrateRemoteApiData;

  /// No description provided for @migrateRemoteApiDataDescription.
  ///
  /// In en, this message translates to:
  /// **'The app starts a temporary bundled API and merges remote resources before switching. Remote data is retained if startup, export, or merge fails.'**
  String get migrateRemoteApiDataDescription;

  /// No description provided for @remoteServiceDescription.
  ///
  /// In en, this message translates to:
  /// **'Custom SSH profiles, persistent settings, and cross-device sync over HTTPS.'**
  String get remoteServiceDescription;

  /// No description provided for @migrateLocalApiData.
  ///
  /// In en, this message translates to:
  /// **'Migrate local API data'**
  String get migrateLocalApiData;

  /// No description provided for @migrateLocalApiDataDescription.
  ///
  /// In en, this message translates to:
  /// **'The app exports and merges local resources before switching. Local data is retained if authentication, export, or merge fails.'**
  String get migrateLocalApiDataDescription;

  /// No description provided for @reconnectRequested.
  ///
  /// In en, this message translates to:
  /// **'Reconnect requested'**
  String get reconnectRequested;

  /// No description provided for @reconnectSignIn.
  ///
  /// In en, this message translates to:
  /// **'Reconnect / sign in'**
  String get reconnectSignIn;

  /// No description provided for @remoteApiBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Remote API base URL'**
  String get remoteApiBaseUrl;

  /// No description provided for @loginPasswordHelp.
  ///
  /// In en, this message translates to:
  /// **'Used only for this login request.'**
  String get loginPasswordHelp;

  /// No description provided for @appleMasterKeyEncryptionDescription.
  ///
  /// In en, this message translates to:
  /// **'Encryption uses the one Ianvs master key managed automatically by iCloud Keychain.'**
  String get appleMasterKeyEncryptionDescription;

  /// No description provided for @deviceMasterKeyEncryptionDescription.
  ///
  /// In en, this message translates to:
  /// **'Encryption uses the one Ianvs master key stored on this device. Export or import it in Master key management when moving to another platform.'**
  String get deviceMasterKeyEncryptionDescription;

  /// No description provided for @dataServiceRestartNotice.
  ///
  /// In en, this message translates to:
  /// **'The selection is stored in the app configuration and takes effect after restart.'**
  String get dataServiceRestartNotice;

  /// No description provided for @enterRemoteApiBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter the remote API base URL.'**
  String get enterRemoteApiBaseUrl;

  /// No description provided for @invalidRemoteApiBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid remote API base URL.'**
  String get invalidRemoteApiBaseUrl;

  /// No description provided for @usernameValidation.
  ///
  /// In en, this message translates to:
  /// **'Use 3–64 lowercase letters, numbers, . _ or -.'**
  String get usernameValidation;

  /// No description provided for @passwordValidation.
  ///
  /// In en, this message translates to:
  /// **'Use 12–72 UTF-8 bytes.'**
  String get passwordValidation;

  /// No description provided for @osc52PolicyName.
  ///
  /// In en, this message translates to:
  /// **'{policy, select, disabled{Deny} profile{Profile} allow{Allow} ask{Ask} other{{policy}}}'**
  String osc52PolicyName(String policy);

  /// No description provided for @osc52PolicyDescription.
  ///
  /// In en, this message translates to:
  /// **'{policy, select, disabled{Block OSC 52 clipboard copy and paste-read requests.} profile{Allow clipboard writes and prompt before paste-read requests.} allow{Allow trusted terminal sessions to use OSC 52 without prompting.} ask{Prompt before each OSC 52 clipboard write or paste-read request.} other{{policy}}}'**
  String osc52PolicyDescription(String policy);

  /// No description provided for @openUrlPolicyName.
  ///
  /// In en, this message translates to:
  /// **'{policy, select, disabled{Deny} ask{Ask every time} other{{policy}}}'**
  String openUrlPolicyName(String policy);

  /// No description provided for @openUrlPolicyDescription.
  ///
  /// In en, this message translates to:
  /// **'{policy, select, disabled{Block every OSC 1337 OpenURL request without showing a dialog.} ask{Require confirmation for each accepted request from the active terminal.} other{{policy}}}'**
  String openUrlPolicyDescription(String policy);

  /// No description provided for @requestAttentionPolicyName.
  ///
  /// In en, this message translates to:
  /// **'{policy, select, disabled{Deny} allow{Allow with limits} other{{policy}}}'**
  String requestAttentionPolicyName(String policy);

  /// No description provided for @requestAttentionPolicyDescription.
  ///
  /// In en, this message translates to:
  /// **'{policy, select, disabled{Block OSC 1337 RequestAttention. Cancellation requests are still honored.} allow{Allow rate-limited Dock attention and a short cursor-local visual effect.} other{{policy}}}'**
  String requestAttentionPolicyDescription(String policy);

  /// No description provided for @osc5522PasteDeliveryFailed.
  ///
  /// In en, this message translates to:
  /// **'OSC 5522 paste event could not be delivered.'**
  String get osc5522PasteDeliveryFailed;

  /// No description provided for @confirmPaste.
  ///
  /// In en, this message translates to:
  /// **'Confirm paste'**
  String get confirmPaste;

  /// No description provided for @pasteCharacterLineCount.
  ///
  /// In en, this message translates to:
  /// **'Paste {characters, plural, =1{1 character} other{{characters} characters}} across {lines, plural, =1{1 line} other{{lines} lines}}?'**
  String pasteCharacterLineCount(int characters, int lines);

  /// No description provided for @clearRecentReplayHistoryQuestion.
  ///
  /// In en, this message translates to:
  /// **'Clear recent replay history?'**
  String get clearRecentReplayHistoryQuestion;

  /// No description provided for @clearRecentReplayHistoryWarning.
  ///
  /// In en, this message translates to:
  /// **'Recent activity frames for this pane will be removed from Replay. This action cannot be undone.'**
  String get clearRecentReplayHistoryWarning;

  /// No description provided for @recordingReplayStarted.
  ///
  /// In en, this message translates to:
  /// **'Recording for Replay started. Keystrokes are redacted; shell command metadata is included when available.'**
  String get recordingReplayStarted;

  /// No description provided for @recordingSavedNamed.
  ///
  /// In en, this message translates to:
  /// **'Recording saved · {name}'**
  String recordingSavedNamed(String name);

  /// No description provided for @reveal.
  ///
  /// In en, this message translates to:
  /// **'Reveal'**
  String get reveal;

  /// No description provided for @couldNotOpenRecording.
  ///
  /// In en, this message translates to:
  /// **'Could not open recording: {error}'**
  String couldNotOpenRecording(String error);

  /// No description provided for @couldNotLoadRecordings.
  ///
  /// In en, this message translates to:
  /// **'Could not load recordings: {error}'**
  String couldNotLoadRecordings(String error);

  /// No description provided for @recordingImported.
  ///
  /// In en, this message translates to:
  /// **'Recording imported'**
  String get recordingImported;

  /// No description provided for @couldNotImportRecording.
  ///
  /// In en, this message translates to:
  /// **'Could not import recording: {error}'**
  String couldNotImportRecording(String error);

  /// No description provided for @renameRecording.
  ///
  /// In en, this message translates to:
  /// **'Rename recording'**
  String get renameRecording;

  /// No description provided for @recordingName.
  ///
  /// In en, this message translates to:
  /// **'Recording name'**
  String get recordingName;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @couldNotRenameRecording.
  ///
  /// In en, this message translates to:
  /// **'Could not rename recording: {error}'**
  String couldNotRenameRecording(String error);

  /// No description provided for @couldNotRevealRecording.
  ///
  /// In en, this message translates to:
  /// **'Could not reveal recording: {error}'**
  String couldNotRevealRecording(String error);

  /// No description provided for @recordingExported.
  ///
  /// In en, this message translates to:
  /// **'Recording exported'**
  String get recordingExported;

  /// No description provided for @couldNotExportRecording.
  ///
  /// In en, this message translates to:
  /// **'Could not export recording: {error}'**
  String couldNotExportRecording(String error);

  /// No description provided for @moveRecordingToTrashQuestion.
  ///
  /// In en, this message translates to:
  /// **'Move recording to Trash?'**
  String get moveRecordingToTrashQuestion;

  /// No description provided for @recordingRemovedFromSaved.
  ///
  /// In en, this message translates to:
  /// **'“{name}” will be removed from Saved Recordings.'**
  String recordingRemovedFromSaved(String name);

  /// No description provided for @recordingMovedToTrash.
  ///
  /// In en, this message translates to:
  /// **'Recording moved to Trash'**
  String get recordingMovedToTrash;

  /// No description provided for @couldNotRemoveRecording.
  ///
  /// In en, this message translates to:
  /// **'Could not remove recording: {error}'**
  String couldNotRemoveRecording(String error);

  /// No description provided for @noTerminalSessionOptionAvailable.
  ///
  /// In en, this message translates to:
  /// **'No terminal session option is available.'**
  String get noTerminalSessionOptionAvailable;

  /// No description provided for @closeTabRequiresActiveSession.
  ///
  /// In en, this message translates to:
  /// **'Close tab requires an active session.'**
  String get closeTabRequiresActiveSession;

  /// No description provided for @closeTabRequiresActiveTab.
  ///
  /// In en, this message translates to:
  /// **'Close tab requires an active tab.'**
  String get closeTabRequiresActiveTab;

  /// No description provided for @duplicateCwdRequiresProfileSession.
  ///
  /// In en, this message translates to:
  /// **'Duplicate current directory requires a default profile and active session.'**
  String get duplicateCwdRequiresProfileSession;

  /// No description provided for @noCurrentDirectoryAvailable.
  ///
  /// In en, this message translates to:
  /// **'No current directory is available.'**
  String get noCurrentDirectoryAvailable;

  /// No description provided for @remoteDirectoryCannotDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Remote-reported current directories cannot be duplicated as local sessions.'**
  String get remoteDirectoryCannotDuplicate;

  /// No description provided for @noDuplicatedSessionCreated.
  ///
  /// In en, this message translates to:
  /// **'No duplicated session was created.'**
  String get noDuplicatedSessionCreated;

  /// No description provided for @noRecentlyClosedTabAvailable.
  ///
  /// In en, this message translates to:
  /// **'No recently closed tab is available.'**
  String get noRecentlyClosedTabAvailable;

  /// No description provided for @noRecentlyClosedPaneForTab.
  ///
  /// In en, this message translates to:
  /// **'No recently closed pane is available for this tab.'**
  String get noRecentlyClosedPaneForTab;

  /// No description provided for @noRecentlyClosedPaneReopened.
  ///
  /// In en, this message translates to:
  /// **'No recently closed pane could be reopened.'**
  String get noRecentlyClosedPaneReopened;

  /// No description provided for @closePaneRequiresActiveSession.
  ///
  /// In en, this message translates to:
  /// **'Close pane requires an active session.'**
  String get closePaneRequiresActiveSession;

  /// No description provided for @splitRightRequiresProfileSession.
  ///
  /// In en, this message translates to:
  /// **'Split right requires a default profile and active session.'**
  String get splitRightRequiresProfileSession;

  /// No description provided for @splitRightUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Split right is unavailable.'**
  String get splitRightUnavailable;

  /// No description provided for @splitDownRequiresProfileSession.
  ///
  /// In en, this message translates to:
  /// **'Split down requires a default profile and active session.'**
  String get splitDownRequiresProfileSession;

  /// No description provided for @splitDownUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Split down is unavailable.'**
  String get splitDownUnavailable;

  /// No description provided for @focusNextPaneRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Focus next pane requires an active session.'**
  String get focusNextPaneRequiresSession;

  /// No description provided for @noNextPaneAvailable.
  ///
  /// In en, this message translates to:
  /// **'No next pane is available.'**
  String get noNextPaneAvailable;

  /// No description provided for @focusPreviousPaneRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Focus previous pane requires an active session.'**
  String get focusPreviousPaneRequiresSession;

  /// No description provided for @noPreviousPaneAvailable.
  ///
  /// In en, this message translates to:
  /// **'No previous pane is available.'**
  String get noPreviousPaneAvailable;

  /// No description provided for @resizePaneRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Resize pane requires an active session.'**
  String get resizePaneRequiresSession;

  /// No description provided for @resizePaneRequiresTwoPanes.
  ///
  /// In en, this message translates to:
  /// **'Resize pane requires at least two panes.'**
  String get resizePaneRequiresTwoPanes;

  /// No description provided for @swapPaneRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Swap pane requires an active session.'**
  String get swapPaneRequiresSession;

  /// No description provided for @swapPaneRequiresTwoPanes.
  ///
  /// In en, this message translates to:
  /// **'Swap pane requires at least two panes.'**
  String get swapPaneRequiresTwoPanes;

  /// No description provided for @zoomPaneRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Zoom pane requires an active session.'**
  String get zoomPaneRequiresSession;

  /// No description provided for @zoomPaneRequiresTwoPanes.
  ///
  /// In en, this message translates to:
  /// **'Zoom pane requires at least two panes.'**
  String get zoomPaneRequiresTwoPanes;

  /// No description provided for @copyRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Copy requires an active session.'**
  String get copyRequiresSession;

  /// No description provided for @copyRequiresSelectionController.
  ///
  /// In en, this message translates to:
  /// **'Copy requires an active selection controller.'**
  String get copyRequiresSelectionController;

  /// No description provided for @copyCommandOutputRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Copy command output requires an active session.'**
  String get copyCommandOutputRequiresSession;

  /// No description provided for @noCommandOutputAvailable.
  ///
  /// In en, this message translates to:
  /// **'No command output is available to copy.'**
  String get noCommandOutputAvailable;

  /// No description provided for @copyModeRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Copy mode requires an active session.'**
  String get copyModeRequiresSession;

  /// No description provided for @pasteRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Paste requires an active session.'**
  String get pasteRequiresSession;

  /// No description provided for @advancedPasteRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Advanced paste requires an active session.'**
  String get advancedPasteRequiresSession;

  /// No description provided for @pasteHistoryRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Paste history requires an active session.'**
  String get pasteHistoryRequiresSession;

  /// No description provided for @replayRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Replay recent activity requires an active session.'**
  String get replayRequiresSession;

  /// No description provided for @readOnlyRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Read-only mode requires an active session.'**
  String get readOnlyRequiresSession;

  /// No description provided for @readOnlyEnabledNotice.
  ///
  /// In en, this message translates to:
  /// **'Read-only mode enabled. Input is blocked for this pane.'**
  String get readOnlyEnabledNotice;

  /// No description provided for @readOnlyDisabledNotice.
  ///
  /// In en, this message translates to:
  /// **'Read-only mode disabled. Input is active for this pane.'**
  String get readOnlyDisabledNotice;

  /// No description provided for @clearBufferRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Clear buffer requires an active session.'**
  String get clearBufferRequiresSession;

  /// No description provided for @bufferClearedCommandKept.
  ///
  /// In en, this message translates to:
  /// **'Buffer cleared. The current command line was kept.'**
  String get bufferClearedCommandKept;

  /// No description provided for @clearBufferRequiresNative.
  ///
  /// In en, this message translates to:
  /// **'Clear buffer requires native runtime support.'**
  String get clearBufferRequiresNative;

  /// No description provided for @bufferCleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared buffer.'**
  String get bufferCleared;

  /// No description provided for @clearBufferUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Clear buffer is not supported by this runtime.'**
  String get clearBufferUnsupported;

  /// No description provided for @globalSearchRequiresTab.
  ///
  /// In en, this message translates to:
  /// **'Global search requires at least one tab.'**
  String get globalSearchRequiresTab;

  /// No description provided for @autocompleteRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Autocomplete requires an active session.'**
  String get autocompleteRequiresSession;

  /// No description provided for @autoComposerRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Auto composer requires an active session.'**
  String get autoComposerRequiresSession;

  /// No description provided for @searchRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Search requires an active session.'**
  String get searchRequiresSession;

  /// No description provided for @previousPromptRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Previous prompt requires an active session.'**
  String get previousPromptRequiresSession;

  /// No description provided for @nextPromptRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Next prompt requires an active session.'**
  String get nextPromptRequiresSession;

  /// No description provided for @selectCommandOutputRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Select command output requires an active session.'**
  String get selectCommandOutputRequiresSession;

  /// No description provided for @shellIntegrationRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Shell integration utilities require an active session.'**
  String get shellIntegrationRequiresSession;

  /// No description provided for @openRecentDirectoryRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Open recent directory requires an active session.'**
  String get openRecentDirectoryRequiresSession;

  /// No description provided for @noRecentDirectoryAvailable.
  ///
  /// In en, this message translates to:
  /// **'No recent directory is available.'**
  String get noRecentDirectoryAvailable;

  /// No description provided for @tmuxIntegrationRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'tmux integration requires an active session.'**
  String get tmuxIntegrationRequiresSession;

  /// No description provided for @coprocessRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Coprocess requires an active session.'**
  String get coprocessRequiresSession;

  /// No description provided for @annotationsRequireSession.
  ///
  /// In en, this message translates to:
  /// **'Annotations require an active session.'**
  String get annotationsRequireSession;

  /// No description provided for @capturedOutputRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Captured output requires an active session.'**
  String get capturedOutputRequiresSession;

  /// No description provided for @passwordManagerRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Password manager requires an active session.'**
  String get passwordManagerRequiresSession;

  /// No description provided for @hotkeyWindowUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Hotkey window is unavailable.'**
  String get hotkeyWindowUnavailable;

  /// No description provided for @layoutTemplateRequiresProfileSession.
  ///
  /// In en, this message translates to:
  /// **'Apply layout template requires a default profile and active session.'**
  String get layoutTemplateRequiresProfileSession;

  /// No description provided for @noActiveTabForLayoutTemplates.
  ///
  /// In en, this message translates to:
  /// **'No active tab is available for layout templates.'**
  String get noActiveTabForLayoutTemplates;

  /// No description provided for @twoPaneLayoutAlreadySatisfied.
  ///
  /// In en, this message translates to:
  /// **'Two-pane layout template is already satisfied.'**
  String get twoPaneLayoutAlreadySatisfied;

  /// No description provided for @layoutTemplateUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Apply layout template is unavailable.'**
  String get layoutTemplateUnavailable;

  /// No description provided for @exportScrollbackRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Export scrollback requires an active session.'**
  String get exportScrollbackRequiresSession;

  /// No description provided for @noVisibleContentToExport.
  ///
  /// In en, this message translates to:
  /// **'No visible terminal content is available to export.'**
  String get noVisibleContentToExport;

  /// No description provided for @scrollbackExported.
  ///
  /// In en, this message translates to:
  /// **'Scrollback exported'**
  String get scrollbackExported;

  /// No description provided for @exportedTerminalScrollback.
  ///
  /// In en, this message translates to:
  /// **'Exported terminal scrollback.'**
  String get exportedTerminalScrollback;

  /// No description provided for @exportDiagnosticsRequiresSession.
  ///
  /// In en, this message translates to:
  /// **'Export diagnostics requires an active session.'**
  String get exportDiagnosticsRequiresSession;

  /// No description provided for @diagnosticsExportUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics export is unavailable for the active sessions.'**
  String get diagnosticsExportUnavailable;

  /// No description provided for @diagnosticsExported.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics exported'**
  String get diagnosticsExported;

  /// No description provided for @exportedTerminalDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Exported terminal diagnostics.'**
  String get exportedTerminalDiagnostics;

  /// No description provided for @commandFinishedNotificationsSaved.
  ///
  /// In en, this message translates to:
  /// **'Command-finished notifications {enabled, select, true{enabled} other{disabled}} and saved.'**
  String commandFinishedNotificationsSaved(String enabled);

  /// No description provided for @bellNotificationsSaved.
  ///
  /// In en, this message translates to:
  /// **'Bell notifications {enabled, select, true{enabled} other{disabled}} and saved.'**
  String bellNotificationsSaved(String enabled);

  /// No description provided for @activityMonitorSaved.
  ///
  /// In en, this message translates to:
  /// **'Activity monitor {enabled, select, true{enabled} other{disabled}} and saved.'**
  String activityMonitorSaved(String enabled);

  /// No description provided for @unableSaveNotifications.
  ///
  /// In en, this message translates to:
  /// **'Unable to save notifications: {error}'**
  String unableSaveNotifications(String error);

  /// No description provided for @unableSaveCommandFinishedNotifications.
  ///
  /// In en, this message translates to:
  /// **'Unable to save command-finished notifications.'**
  String get unableSaveCommandFinishedNotifications;

  /// No description provided for @unableSaveBellNotifications.
  ///
  /// In en, this message translates to:
  /// **'Unable to save bell notifications.'**
  String get unableSaveBellNotifications;

  /// No description provided for @unableSaveActivityMonitor.
  ///
  /// In en, this message translates to:
  /// **'Unable to save activity monitor notifications.'**
  String get unableSaveActivityMonitor;

  /// No description provided for @noDefaultProfileAvailable.
  ///
  /// In en, this message translates to:
  /// **'No default profile is available.'**
  String get noDefaultProfileAvailable;

  /// No description provided for @addAnotherPaneForAction.
  ///
  /// In en, this message translates to:
  /// **'Add another pane to use this action.'**
  String get addAnotherPaneForAction;

  /// No description provided for @unavailableReason.
  ///
  /// In en, this message translates to:
  /// **'Unavailable: {reason}'**
  String unavailableReason(String reason);

  /// No description provided for @duplicateCurrentDirectory.
  ///
  /// In en, this message translates to:
  /// **'Duplicate current directory'**
  String get duplicateCurrentDirectory;

  /// No description provided for @applyTwoPaneLayout.
  ///
  /// In en, this message translates to:
  /// **'Apply two-pane layout'**
  String get applyTwoPaneLayout;

  /// No description provided for @tabAlreadyMultiplePanes.
  ///
  /// In en, this message translates to:
  /// **'This tab already has multiple panes.'**
  String get tabAlreadyMultiplePanes;

  /// No description provided for @growActivePane.
  ///
  /// In en, this message translates to:
  /// **'Grow active pane'**
  String get growActivePane;

  /// No description provided for @swapActivePane.
  ///
  /// In en, this message translates to:
  /// **'Swap active pane'**
  String get swapActivePane;

  /// No description provided for @closeActivePane.
  ///
  /// In en, this message translates to:
  /// **'Close active pane'**
  String get closeActivePane;

  /// No description provided for @movedToNewTab.
  ///
  /// In en, this message translates to:
  /// **'Moved to a new tab'**
  String get movedToNewTab;

  /// No description provided for @panePosition.
  ///
  /// In en, this message translates to:
  /// **'Pane {index}/{count}'**
  String panePosition(int index, int count);

  /// No description provided for @splitRight.
  ///
  /// In en, this message translates to:
  /// **'Split right'**
  String get splitRight;

  /// No description provided for @splitDown.
  ///
  /// In en, this message translates to:
  /// **'Split down'**
  String get splitDown;

  /// No description provided for @splitRightUnavailableReason.
  ///
  /// In en, this message translates to:
  /// **'Split right unavailable: {reason}'**
  String splitRightUnavailableReason(String reason);

  /// No description provided for @splitDownUnavailableReason.
  ///
  /// In en, this message translates to:
  /// **'Split down unavailable: {reason}'**
  String splitDownUnavailableReason(String reason);

  /// No description provided for @activePane.
  ///
  /// In en, this message translates to:
  /// **'Active pane'**
  String get activePane;

  /// No description provided for @inactivePane.
  ///
  /// In en, this message translates to:
  /// **'Inactive pane'**
  String get inactivePane;

  /// No description provided for @paneContextUntitled.
  ///
  /// In en, this message translates to:
  /// **'Pane: {id} · {state}'**
  String paneContextUntitled(String id, String state);

  /// No description provided for @paneContextTitled.
  ///
  /// In en, this message translates to:
  /// **'Pane: {title} ({id}) · {state}'**
  String paneContextTitled(String title, String id, String state);

  /// No description provided for @openLink.
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get openLink;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @copyLinkText.
  ///
  /// In en, this message translates to:
  /// **'Copy link text'**
  String get copyLinkText;

  /// No description provided for @showTarget.
  ///
  /// In en, this message translates to:
  /// **'Show target'**
  String get showTarget;

  /// No description provided for @copiedLinkTarget.
  ///
  /// In en, this message translates to:
  /// **'Copied link target'**
  String get copiedLinkTarget;

  /// No description provided for @copiedLinkText.
  ///
  /// In en, this message translates to:
  /// **'Copied link text'**
  String get copiedLinkText;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get unknown;

  /// No description provided for @blockedLinkScheme.
  ///
  /// In en, this message translates to:
  /// **'Blocked link scheme: {scheme}'**
  String blockedLinkScheme(String scheme);

  /// No description provided for @blockedFileLink.
  ///
  /// In en, this message translates to:
  /// **'Blocked file link'**
  String get blockedFileLink;

  /// No description provided for @couldNotOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Could not open link'**
  String get couldNotOpenLink;

  /// No description provided for @couldNotOpenLinkDetails.
  ///
  /// In en, this message translates to:
  /// **'Could not open link: {error}'**
  String couldNotOpenLinkDetails(String error);

  /// No description provided for @openLocalFileLinkQuestion.
  ///
  /// In en, this message translates to:
  /// **'Open local file link?'**
  String get openLocalFileLinkQuestion;

  /// No description provided for @terminalRequestsLocalFile.
  ///
  /// In en, this message translates to:
  /// **'The terminal is asking to open a local file URL.'**
  String get terminalRequestsLocalFile;

  /// No description provided for @sourceValue.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String sourceValue(String source);

  /// No description provided for @linkTextOpensTarget.
  ///
  /// In en, this message translates to:
  /// **'Link text “{text}” opens {target}'**
  String linkTextOpensTarget(String text, String target);

  /// No description provided for @linkTargetValue.
  ///
  /// In en, this message translates to:
  /// **'Link target: {target}'**
  String linkTargetValue(String target);

  /// No description provided for @clickToFocusPane.
  ///
  /// In en, this message translates to:
  /// **'Click to focus this pane.'**
  String get clickToFocusPane;

  /// No description provided for @remoteContextReported.
  ///
  /// In en, this message translates to:
  /// **'Remote context reported by shell integration.'**
  String get remoteContextReported;

  /// No description provided for @hostValue.
  ///
  /// In en, this message translates to:
  /// **'Host: {host}'**
  String hostValue(String host);

  /// No description provided for @userValue.
  ///
  /// In en, this message translates to:
  /// **'User: {user}'**
  String userValue(String user);

  /// No description provided for @localFileActionsDisabledRemote.
  ///
  /// In en, this message translates to:
  /// **'Local file actions stay disabled for remote paths.'**
  String get localFileActionsDisabledRemote;

  /// No description provided for @terminalProgressInPane.
  ///
  /// In en, this message translates to:
  /// **'Terminal progress in this pane.'**
  String get terminalProgressInPane;

  /// No description provided for @osc1337BadgeValue.
  ///
  /// In en, this message translates to:
  /// **'OSC 1337 badge: {badge}'**
  String osc1337BadgeValue(String badge);

  /// No description provided for @alternateScreenActive.
  ///
  /// In en, this message translates to:
  /// **'Alternate screen buffer is active.'**
  String get alternateScreenActive;

  /// No description provided for @mouseReportingActive.
  ///
  /// In en, this message translates to:
  /// **'Mouse reporting is active: {mode}, {encoding}.'**
  String mouseReportingActive(String mode, String encoding);

  /// No description provided for @mimePasteActive.
  ///
  /// In en, this message translates to:
  /// **'OSC 5522 paste events are active and take precedence over bracketed paste.'**
  String get mimePasteActive;

  /// No description provided for @bracketedPasteActive.
  ///
  /// In en, this message translates to:
  /// **'Bracketed paste mode is active.'**
  String get bracketedPasteActive;

  /// No description provided for @focusReportingActive.
  ///
  /// In en, this message translates to:
  /// **'Focus reporting is active. The application receives focus-in and focus-out events.'**
  String get focusReportingActive;

  /// No description provided for @synchronizedOutputActive.
  ///
  /// In en, this message translates to:
  /// **'Synchronized output mode is active. Intermediate updates are held until the application flushes.'**
  String get synchronizedOutputActive;

  /// No description provided for @readOnlyPaneActive.
  ///
  /// In en, this message translates to:
  /// **'Read-only mode is enabled for this pane. Input and paste sends are blocked.'**
  String get readOnlyPaneActive;

  /// No description provided for @terminalRequestedAttention.
  ///
  /// In en, this message translates to:
  /// **'Terminal requested attention'**
  String get terminalRequestedAttention;

  /// No description provided for @dragPaneToSplit.
  ///
  /// In en, this message translates to:
  /// **'Drag {title} to split or move it to the tab bar'**
  String dragPaneToSplit(String title);

  /// No description provided for @dropToTarget.
  ///
  /// In en, this message translates to:
  /// **'Drop to {target}'**
  String dropToTarget(String target);

  /// No description provided for @unzoomPane.
  ///
  /// In en, this message translates to:
  /// **'Unzoom pane'**
  String get unzoomPane;

  /// No description provided for @zoomPane.
  ///
  /// In en, this message translates to:
  /// **'Zoom pane'**
  String get zoomPane;

  /// No description provided for @localFile.
  ///
  /// In en, this message translates to:
  /// **'Local file'**
  String get localFile;

  /// No description provided for @protocolHost.
  ///
  /// In en, this message translates to:
  /// **'{protocol} host: {host}'**
  String protocolHost(String protocol, String host);

  /// No description provided for @openTerminalRequestedUrlQuestion.
  ///
  /// In en, this message translates to:
  /// **'Open terminal-requested URL?'**
  String get openTerminalRequestedUrlQuestion;

  /// No description provided for @terminalRequestedUrlWarning.
  ///
  /// In en, this message translates to:
  /// **'The active terminal requested permission to open this URL. Terminal output can be untrusted.'**
  String get terminalRequestedUrlWarning;

  /// No description provided for @destinationValue.
  ///
  /// In en, this message translates to:
  /// **'Destination: {destination}'**
  String destinationValue(String destination);

  /// No description provided for @osc1337OpenUrlBlocked.
  ///
  /// In en, this message translates to:
  /// **'OSC 1337 Open URL blocked'**
  String get osc1337OpenUrlBlocked;

  /// No description provided for @osc1337OpenUrlSourceInactive.
  ///
  /// In en, this message translates to:
  /// **'OSC 1337 Open URL blocked: source is no longer active'**
  String get osc1337OpenUrlSourceInactive;

  /// No description provided for @allowFutureVariableReportsQuestion.
  ///
  /// In en, this message translates to:
  /// **'Allow future variable reports?'**
  String get allowFutureVariableReportsQuestion;

  /// No description provided for @variableReportDeniedHelp.
  ///
  /// In en, this message translates to:
  /// **'The current request was denied and received an empty response. Choose whether future terminal programs may read this variable.'**
  String get variableReportDeniedHelp;

  /// No description provided for @variable.
  ///
  /// In en, this message translates to:
  /// **'Variable'**
  String get variable;

  /// No description provided for @variableReportPrivacyHelp.
  ///
  /// In en, this message translates to:
  /// **'Ianvs only reports session-owned title, dimensions, shell context, and user.* values. It never reads host environment variables or files for this request.'**
  String get variableReportPrivacyHelp;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not Now'**
  String get notNow;

  /// No description provided for @alwaysAllow.
  ///
  /// In en, this message translates to:
  /// **'Always Allow'**
  String get alwaysAllow;

  /// No description provided for @alwaysDeny.
  ///
  /// In en, this message translates to:
  /// **'Always Deny'**
  String get alwaysDeny;

  /// No description provided for @variableDecisionSourceInactive.
  ///
  /// In en, this message translates to:
  /// **'Variable-reporting decision not saved: source is no longer active'**
  String get variableDecisionSourceInactive;

  /// No description provided for @futureVariableReportsAllowed.
  ///
  /// In en, this message translates to:
  /// **'Future reports of {name} are allowed'**
  String futureVariableReportsAllowed(String name);

  /// No description provided for @futureVariableReportsDenied.
  ///
  /// In en, this message translates to:
  /// **'Future reports of {name} are denied'**
  String futureVariableReportsDenied(String name);

  /// No description provided for @receivedFile.
  ///
  /// In en, this message translates to:
  /// **'Received {name} ({size})'**
  String receivedFile(String name, String size);

  /// No description provided for @allowClipboardCopyQuestion.
  ///
  /// In en, this message translates to:
  /// **'Allow {protocol} clipboard copy?'**
  String allowClipboardCopyQuestion(String protocol);

  /// No description provided for @allowPasteReadQuestion.
  ///
  /// In en, this message translates to:
  /// **'Allow {protocol} paste read?'**
  String allowPasteReadQuestion(String protocol);

  /// No description provided for @allowClipboardWriteQuestion.
  ///
  /// In en, this message translates to:
  /// **'Allow {protocol} clipboard write?'**
  String allowClipboardWriteQuestion(String protocol);

  /// No description provided for @allowClipboardReadQuestion.
  ///
  /// In en, this message translates to:
  /// **'Allow {protocol} clipboard read?'**
  String allowClipboardReadQuestion(String protocol);

  /// No description provided for @alwaysAllowLower.
  ///
  /// In en, this message translates to:
  /// **'Always allow'**
  String get alwaysAllowLower;

  /// No description provided for @session.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get session;

  /// No description provided for @mimeTypes.
  ///
  /// In en, this message translates to:
  /// **'MIME types'**
  String get mimeTypes;

  /// No description provided for @application.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get application;

  /// No description provided for @size.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get size;

  /// No description provided for @characterCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 character} other{{count} characters}}'**
  String characterCount(int count);

  /// No description provided for @previewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Preview unavailable'**
  String get previewUnavailable;

  /// No description provided for @clipboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'Clipboard is empty'**
  String get clipboardEmpty;

  /// No description provided for @previewTruncated.
  ///
  /// In en, this message translates to:
  /// **'preview truncated'**
  String get previewTruncated;

  /// No description provided for @terminalRequestsClipboardRead.
  ///
  /// In en, this message translates to:
  /// **'The terminal is requesting clipboard contents and will send them back to the session if allowed.'**
  String get terminalRequestsClipboardRead;

  /// No description provided for @terminalRequestsClipboardWrite.
  ///
  /// In en, this message translates to:
  /// **'The terminal wants to write the following text to your clipboard.'**
  String get terminalRequestsClipboardWrite;

  /// No description provided for @alwaysAllowClipboardHelp.
  ///
  /// In en, this message translates to:
  /// **'“Always allow” permits future OSC 5522 clipboard reads and writes that use this exact application name and password, only for the current terminal session.'**
  String get alwaysAllowClipboardHelp;

  /// No description provided for @trustedSessionsOnly.
  ///
  /// In en, this message translates to:
  /// **'Only allow this for trusted sessions.'**
  String get trustedSessionsOnly;

  /// No description provided for @sessionEnded.
  ///
  /// In en, this message translates to:
  /// **'Session ended'**
  String get sessionEnded;

  /// No description provided for @sessionExitedBody.
  ///
  /// In en, this message translates to:
  /// **'{session} exited{code, select, none{} other{ with code {code}}}.'**
  String sessionExitedBody(String session, String code);

  /// No description provided for @sessionNamed.
  ///
  /// In en, this message translates to:
  /// **'Session {id}'**
  String sessionNamed(String id);

  /// No description provided for @paneNamed.
  ///
  /// In en, this message translates to:
  /// **'pane {number}'**
  String paneNamed(int number);

  /// No description provided for @newTerminalOutputAvailable.
  ///
  /// In en, this message translates to:
  /// **'New terminal output is available.'**
  String get newTerminalOutputAvailable;

  /// No description provided for @osc1337OpenUrlBlockedByPolicy.
  ///
  /// In en, this message translates to:
  /// **'OSC 1337 Open URL blocked by policy'**
  String get osc1337OpenUrlBlockedByPolicy;

  /// No description provided for @couldNotOpenSaveDialog.
  ///
  /// In en, this message translates to:
  /// **'Could not open the save dialog'**
  String get couldNotOpenSaveDialog;

  /// No description provided for @receivedFileDiscarded.
  ///
  /// In en, this message translates to:
  /// **'Received file discarded'**
  String get receivedFileDiscarded;

  /// No description provided for @receivedFileUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Received file is no longer available'**
  String get receivedFileUnavailable;

  /// No description provided for @couldNotSaveFile.
  ///
  /// In en, this message translates to:
  /// **'Could not save {name}'**
  String couldNotSaveFile(String name);

  /// No description provided for @savedFile.
  ///
  /// In en, this message translates to:
  /// **'Saved {name}'**
  String savedFile(String name);

  /// No description provided for @fileDownloadRejected.
  ///
  /// In en, this message translates to:
  /// **'File download rejected: {reason}'**
  String fileDownloadRejected(String reason);

  /// No description provided for @fileUploadRequestBlocked.
  ///
  /// In en, this message translates to:
  /// **'File upload request blocked'**
  String get fileUploadRequestBlocked;

  /// No description provided for @zmodemTransportFailed.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM transport failed in session {session}: {bytes} bytes in {chunks} queued writes were not confirmed. The terminal connection was closed.'**
  String zmodemTransportFailed(String session, int bytes, int chunks);

  /// No description provided for @notificationInSession.
  ///
  /// In en, this message translates to:
  /// **'{title} in {session}'**
  String notificationInSession(String title, String session);

  /// No description provided for @zmodemFilePreserved.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM file preserved'**
  String get zmodemFilePreserved;

  /// No description provided for @zmodemFilePreservedBody.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM publish failed. A complete file was preserved; focus the pane to reveal or dismiss it.'**
  String get zmodemFilePreservedBody;

  /// No description provided for @zmodemReceiveCompleted.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM receive completed'**
  String get zmodemReceiveCompleted;

  /// No description provided for @zmodemSendCompleted.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM send completed'**
  String get zmodemSendCompleted;

  /// No description provided for @zmodemTransferCancelled.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM transfer cancelled'**
  String get zmodemTransferCancelled;

  /// No description provided for @zmodemPreservedUnavailable.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM publish failed; preserved file is unavailable to reveal'**
  String get zmodemPreservedUnavailable;

  /// No description provided for @zmodemTransferFailed.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM transfer failed: {reason}'**
  String zmodemTransferFailed(String reason);

  /// No description provided for @protocolError.
  ///
  /// In en, this message translates to:
  /// **'protocol error'**
  String get protocolError;

  /// No description provided for @zmodemTransferUpdate.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM transfer update'**
  String get zmodemTransferUpdate;

  /// No description provided for @zmodemTransferNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM transfer needs attention'**
  String get zmodemTransferNeedsAttention;

  /// No description provided for @zmodemStateLost.
  ///
  /// In en, this message translates to:
  /// **'Transfer state was lost after an event gap. Focus the pane to retry cancellation.'**
  String get zmodemStateLost;

  /// No description provided for @remoteSkippedZmodemFile.
  ///
  /// In en, this message translates to:
  /// **'Remote skipped a ZMODEM file; continuing the batch'**
  String get remoteSkippedZmodemFile;

  /// No description provided for @remoteSkippedNamedFile.
  ///
  /// In en, this message translates to:
  /// **'Remote skipped {name}; continuing the batch'**
  String remoteSkippedNamedFile(String name);

  /// No description provided for @zmodemDirectionUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This terminal runtime does not support this ZMODEM direction.'**
  String get zmodemDirectionUnsupported;

  /// No description provided for @zmodemFileSelectionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM file selection is unavailable on this platform.'**
  String get zmodemFileSelectionUnavailable;

  /// No description provided for @retryCancellation.
  ///
  /// In en, this message translates to:
  /// **'Retry cancellation.'**
  String get retryCancellation;

  /// No description provided for @transferWasCancelled.
  ///
  /// In en, this message translates to:
  /// **'The transfer was cancelled.'**
  String get transferWasCancelled;

  /// No description provided for @inactiveTransferWasCancelled.
  ///
  /// In en, this message translates to:
  /// **'The inactive transfer was cancelled.'**
  String get inactiveTransferWasCancelled;

  /// No description provided for @focusPaneRetryCancellation.
  ///
  /// In en, this message translates to:
  /// **'Focus the pane to retry cancellation.'**
  String get focusPaneRetryCancellation;

  /// No description provided for @zmodemRequestCancelled.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM request cancelled'**
  String get zmodemRequestCancelled;

  /// No description provided for @zmodemRequestNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM request needs attention'**
  String get zmodemRequestNeedsAttention;

  /// No description provided for @couldNotCancelAfterSessionChanged.
  ///
  /// In en, this message translates to:
  /// **'Could not cancel after the session changed. Retry or cancel again.'**
  String get couldNotCancelAfterSessionChanged;

  /// No description provided for @remoteZmodemRequestCancelled.
  ///
  /// In en, this message translates to:
  /// **'A remote {direction, select, send{send} other{receive}} request was cancelled because its pane is inactive.'**
  String remoteZmodemRequestCancelled(String direction);

  /// No description provided for @remoteZmodemRequestCancelFailed.
  ///
  /// In en, this message translates to:
  /// **'A remote {direction, select, send{send} other{receive}} request could not be cancelled. Focus the pane to retry.'**
  String remoteZmodemRequestCancelFailed(String direction);

  /// No description provided for @zmodemPickerAlreadyOpen.
  ///
  /// In en, this message translates to:
  /// **'A previous ZMODEM file picker is still open. Close it, then retry this transfer.'**
  String get zmodemPickerAlreadyOpen;

  /// No description provided for @zmodemDestinationSelectionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM destination selection is unavailable on this platform.'**
  String get zmodemDestinationSelectionUnavailable;

  /// No description provided for @couldNotOpenDestinationPicker.
  ///
  /// In en, this message translates to:
  /// **'Could not open the destination picker. Retry or cancel the transfer.'**
  String get couldNotOpenDestinationPicker;

  /// No description provided for @sessionChangedCancellationFailed.
  ///
  /// In en, this message translates to:
  /// **'The session changed and cancellation failed. Retry cancellation.'**
  String get sessionChangedCancellationFailed;

  /// No description provided for @destinationSelectionCancelled.
  ///
  /// In en, this message translates to:
  /// **'Destination selection cancelled. Retry or cancel the transfer.'**
  String get destinationSelectionCancelled;

  /// No description provided for @couldNotAuthorizeDestination.
  ///
  /// In en, this message translates to:
  /// **'Could not authorize this destination. Retry or cancel the transfer.'**
  String get couldNotAuthorizeDestination;

  /// No description provided for @couldNotOpenFilePicker.
  ///
  /// In en, this message translates to:
  /// **'Could not open the file picker. Retry or cancel the transfer.'**
  String get couldNotOpenFilePicker;

  /// No description provided for @fileSelectionCancelled.
  ///
  /// In en, this message translates to:
  /// **'File selection cancelled. Retry or cancel the transfer.'**
  String get fileSelectionCancelled;

  /// No description provided for @zmodemFileLimit.
  ///
  /// In en, this message translates to:
  /// **'You can send at most 256 files. Select fewer files and retry.'**
  String get zmodemFileLimit;

  /// No description provided for @couldNotAuthorizeFiles.
  ///
  /// In en, this message translates to:
  /// **'Could not authorize these files. Retry or cancel the transfer.'**
  String get couldNotAuthorizeFiles;

  /// No description provided for @zmodemPickerResultIgnored.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM transfer already ended; the picker result was not used.'**
  String get zmodemPickerResultIgnored;

  /// No description provided for @couldNotCancelZmodem.
  ///
  /// In en, this message translates to:
  /// **'Could not cancel the ZMODEM transfer. Retry cancellation.'**
  String get couldNotCancelZmodem;

  /// No description provided for @couldNotRevealExport.
  ///
  /// In en, this message translates to:
  /// **'Could not reveal export on this platform'**
  String get couldNotRevealExport;

  /// No description provided for @couldNotRevealExportDetails.
  ///
  /// In en, this message translates to:
  /// **'Could not reveal export: {error}'**
  String couldNotRevealExportDetails(String error);

  /// No description provided for @zmodemRecoveryUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Preserved ZMODEM file is no longer available'**
  String get zmodemRecoveryUnavailable;

  /// No description provided for @zmodemRecoveryResolveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not resolve the preserved ZMODEM file; try again'**
  String get zmodemRecoveryResolveFailed;

  /// No description provided for @couldNotRevealPreservedZmodem.
  ///
  /// In en, this message translates to:
  /// **'Could not reveal preserved ZMODEM file'**
  String get couldNotRevealPreservedZmodem;

  /// No description provided for @couldNotReleaseZmodemRecovery.
  ///
  /// In en, this message translates to:
  /// **'Could not release the ZMODEM recovery token'**
  String get couldNotReleaseZmodemRecovery;

  /// No description provided for @couldNotDismissZmodemRecovery.
  ///
  /// In en, this message translates to:
  /// **'Could not dismiss the ZMODEM recovery notice'**
  String get couldNotDismissZmodemRecovery;

  /// No description provided for @preservedZmodemFile.
  ///
  /// In en, this message translates to:
  /// **'the preserved ZMODEM file'**
  String get preservedZmodemFile;

  /// No description provided for @permanentlyDiscardFileQuestion.
  ///
  /// In en, this message translates to:
  /// **'Permanently discard file?'**
  String get permanentlyDiscardFileQuestion;

  /// No description provided for @zmodemDiscardWarning.
  ///
  /// In en, this message translates to:
  /// **'{filename} is the only recovery copy retained by Ianvs Terminal. Discarding it permanently deletes the file and cannot be undone.'**
  String zmodemDiscardWarning(String filename);

  /// No description provided for @discardFile.
  ///
  /// In en, this message translates to:
  /// **'Discard file'**
  String get discardFile;

  /// No description provided for @zmodemPreservedSemantics.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM file preserved. {filename} from {source}.'**
  String zmodemPreservedSemantics(String filename, String source);

  /// No description provided for @zmodemPublishFailedPreserved.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM publish failed. Complete file preserved as {filename} from {source}.'**
  String zmodemPublishFailedPreserved(String filename, String source);

  /// No description provided for @permanentlyDeletePreservedZmodem.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete preserved ZMODEM file'**
  String get permanentlyDeletePreservedZmodem;

  /// No description provided for @discardFileEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Discard file…'**
  String get discardFileEllipsis;

  /// No description provided for @zmodemProgress.
  ///
  /// In en, this message translates to:
  /// **'ZMODEM progress'**
  String get zmodemProgress;

  /// No description provided for @indeterminate.
  ///
  /// In en, this message translates to:
  /// **'indeterminate'**
  String get indeterminate;

  /// No description provided for @percentValue.
  ///
  /// In en, this message translates to:
  /// **'{percent} percent'**
  String percentValue(int percent);

  /// No description provided for @cancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling…'**
  String get cancelling;

  /// No description provided for @notificationButton.
  ///
  /// In en, this message translates to:
  /// **'Button {number}'**
  String notificationButton(int number);

  /// No description provided for @notificationAction.
  ///
  /// In en, this message translates to:
  /// **'Notification action {number}'**
  String notificationAction(int number);

  /// No description provided for @closeAndReportToTerminal.
  ///
  /// In en, this message translates to:
  /// **'Close and report to the terminal process'**
  String get closeAndReportToTerminal;

  /// No description provided for @removeNotification.
  ///
  /// In en, this message translates to:
  /// **'Remove this notification'**
  String get removeNotification;

  /// No description provided for @profileTabColor.
  ///
  /// In en, this message translates to:
  /// **'Profile tab color'**
  String get profileTabColor;

  /// No description provided for @osc21337StatusIndicator.
  ///
  /// In en, this message translates to:
  /// **'OSC 21337 session status indicator'**
  String get osc21337StatusIndicator;

  /// No description provided for @dataServiceWarning.
  ///
  /// In en, this message translates to:
  /// **'Data service warning.'**
  String get dataServiceWarning;

  /// No description provided for @dismissDataServiceWarning.
  ///
  /// In en, this message translates to:
  /// **'Dismiss data service warning'**
  String get dismissDataServiceWarning;

  /// No description provided for @replaySource.
  ///
  /// In en, this message translates to:
  /// **'Replay source: {source}'**
  String replaySource(String source);

  /// No description provided for @dragResizePanesHorizontally.
  ///
  /// In en, this message translates to:
  /// **'Drag to resize panes horizontally'**
  String get dragResizePanesHorizontally;

  /// No description provided for @dragResizePanesVertically.
  ///
  /// In en, this message translates to:
  /// **'Drag to resize panes vertically'**
  String get dragResizePanesVertically;

  /// No description provided for @completions.
  ///
  /// In en, this message translates to:
  /// **'Completions'**
  String get completions;

  /// No description provided for @completePrefix.
  ///
  /// In en, this message translates to:
  /// **'Complete \"{prefix}\"'**
  String completePrefix(String prefix);

  /// No description provided for @previousCompletion.
  ///
  /// In en, this message translates to:
  /// **'Previous completion'**
  String get previousCompletion;

  /// No description provided for @nextCompletion.
  ///
  /// In en, this message translates to:
  /// **'Next completion'**
  String get nextCompletion;

  /// No description provided for @closeCompletions.
  ///
  /// In en, this message translates to:
  /// **'Close completions'**
  String get closeCompletions;

  /// No description provided for @composeCommand.
  ///
  /// In en, this message translates to:
  /// **'Compose command'**
  String get composeCommand;

  /// No description provided for @sendCommand.
  ///
  /// In en, this message translates to:
  /// **'Send command'**
  String get sendCommand;

  /// No description provided for @closeComposer.
  ///
  /// In en, this message translates to:
  /// **'Close composer'**
  String get closeComposer;

  /// No description provided for @terminalKeyboardShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Terminal keyboard shortcuts'**
  String get terminalKeyboardShortcuts;

  /// No description provided for @decreaseTerminalTextSize.
  ///
  /// In en, this message translates to:
  /// **'Decrease terminal text size'**
  String get decreaseTerminalTextSize;

  /// No description provided for @resetTerminalTextSize.
  ///
  /// In en, this message translates to:
  /// **'Reset terminal text size'**
  String get resetTerminalTextSize;

  /// No description provided for @increaseTerminalTextSize.
  ///
  /// In en, this message translates to:
  /// **'Increase terminal text size'**
  String get increaseTerminalTextSize;

  /// No description provided for @insertTerminalKey.
  ///
  /// In en, this message translates to:
  /// **'Insert {key}'**
  String insertTerminalKey(String key);

  /// No description provided for @dismissKeyboard.
  ///
  /// In en, this message translates to:
  /// **'Dismiss keyboard'**
  String get dismissKeyboard;

  /// No description provided for @sshHostKeyPromptInactive.
  ///
  /// In en, this message translates to:
  /// **'The SSH host-key confirmation is no longer active.'**
  String get sshHostKeyPromptInactive;

  /// No description provided for @sshAuthenticationPromptInactive.
  ///
  /// In en, this message translates to:
  /// **'The SSH authentication challenge is no longer active.'**
  String get sshAuthenticationPromptInactive;

  /// No description provided for @dataServiceConfigurationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Data service configuration is unavailable in this build.'**
  String get dataServiceConfigurationUnavailable;

  /// No description provided for @remoteAuthenticationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Remote authentication is unavailable in this build.'**
  String get remoteAuthenticationUnavailable;

  /// No description provided for @localApiMigrationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The active bundled local API is unavailable for migration.'**
  String get localApiMigrationUnavailable;

  /// No description provided for @remoteToLocalMigrationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Remote-to-local migration is unavailable in this build.'**
  String get remoteToLocalMigrationUnavailable;

  /// No description provided for @migrationToRemoteSummary.
  ///
  /// In en, this message translates to:
  /// **'Migrated {resources} local resources: {created} created, {updated} updated, {skipped} already current. Restart the app to use the remote API.'**
  String migrationToRemoteSummary(
    int resources,
    int created,
    int updated,
    int skipped,
  );

  /// No description provided for @migrationToLocalSummary.
  ///
  /// In en, this message translates to:
  /// **'Migrated {resources} remote resources: {created} created, {updated} updated, {skipped} already current. Restart the app to use the bundled local API.'**
  String migrationToLocalSummary(
    int resources,
    int created,
    int updated,
    int skipped,
  );

  /// No description provided for @dataServiceConfigurationSaved.
  ///
  /// In en, this message translates to:
  /// **'Data service configuration saved. Restart the app to apply it.'**
  String get dataServiceConfigurationSaved;

  /// No description provided for @unableToSaveDataServiceConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Unable to save the data service configuration: {error}'**
  String unableToSaveDataServiceConfiguration(String error);

  /// No description provided for @deleteProfileQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete profile?'**
  String get deleteProfileQuestion;

  /// No description provided for @deleteProfileWarning.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”? Open terminal tabs will keep their current session settings.'**
  String deleteProfileWarning(String name);

  /// No description provided for @deletedProfile.
  ///
  /// In en, this message translates to:
  /// **'Deleted profile “{name}”.'**
  String deletedProfile(String name);

  /// No description provided for @profileWasNotDeleted.
  ///
  /// In en, this message translates to:
  /// **'Profile was not deleted'**
  String get profileWasNotDeleted;

  /// No description provided for @profileStillStored.
  ///
  /// In en, this message translates to:
  /// **'“{name}” is still stored in {destination}.'**
  String profileStillStored(String name, String destination);

  /// No description provided for @newSshProfile.
  ///
  /// In en, this message translates to:
  /// **'New SSH Profile'**
  String get newSshProfile;

  /// No description provided for @savedProfileTo.
  ///
  /// In en, this message translates to:
  /// **'Saved profile “{name}” to {destination}.'**
  String savedProfileTo(String name, String destination);

  /// No description provided for @profileStorageDestination.
  ///
  /// In en, this message translates to:
  /// **'{deployment, select, remote{Remote service} local{Bundled local service} other{profile storage}}'**
  String profileStorageDestination(String deployment);

  /// No description provided for @profileWasNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile was not saved'**
  String get profileWasNotSaved;

  /// No description provided for @profileNotWritten.
  ///
  /// In en, this message translates to:
  /// **'“{name}” was not written to {destination}. It will not appear on your other devices.'**
  String profileNotWritten(String name, String destination);

  /// No description provided for @profileSaveFailureConnectOnceHelp.
  ///
  /// In en, this message translates to:
  /// **'You can cancel and try saving again, or explicitly continue with a one-time connection.'**
  String get profileSaveFailureConnectOnceHelp;

  /// No description provided for @cancelConnection.
  ///
  /// In en, this message translates to:
  /// **'Cancel connection'**
  String get cancelConnection;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @connectOnceWithoutSaving.
  ///
  /// In en, this message translates to:
  /// **'Connect once without saving'**
  String get connectOnceWithoutSaving;

  /// No description provided for @profilesChangedElsewhere.
  ///
  /// In en, this message translates to:
  /// **'Profiles changed on another device while this save was in progress. Reload the profiles and try again.'**
  String get profilesChangedElsewhere;

  /// No description provided for @remoteServiceAuthenticationExpired.
  ///
  /// In en, this message translates to:
  /// **'The Remote service session is no longer authenticated. Open Data service settings, sign in again, and retry the save.'**
  String get remoteServiceAuthenticationExpired;

  /// No description provided for @remoteServiceTimeout.
  ///
  /// In en, this message translates to:
  /// **'The Remote service did not respond in time. Check the network connection and try again.'**
  String get remoteServiceTimeout;

  /// No description provided for @remoteServiceRejectedSave.
  ///
  /// In en, this message translates to:
  /// **'Remote service rejected the save ({status}/{code}): {message}'**
  String remoteServiceRejectedSave(int status, String code, String message);

  /// No description provided for @remoteServiceInvalidResponse.
  ///
  /// In en, this message translates to:
  /// **'The Remote service returned an invalid response: {message}'**
  String remoteServiceInvalidResponse(String message);

  /// No description provided for @persistentSshProfilesRequireService.
  ///
  /// In en, this message translates to:
  /// **'Persistent SSH profiles require a connected bundled local or Remote service. Open Data service settings and connect one first.'**
  String get persistentSshProfilesRequireService;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailed(String error);

  /// No description provided for @dynamicProfilesImported.
  ///
  /// In en, this message translates to:
  /// **'Imported {total} dynamic profiles ({added} new, {replaced} replaced, {warnings} warnings).'**
  String dynamicProfilesImported(
    int total,
    int added,
    int replaced,
    int warnings,
  );

  /// No description provided for @passwordSendBlockedNoPrompt.
  ///
  /// In en, this message translates to:
  /// **'Password send blocked: no password prompt is active.'**
  String get passwordSendBlockedNoPrompt;

  /// No description provided for @sshProfileStored.
  ///
  /// In en, this message translates to:
  /// **'{action, select, saved{Saved} other{Imported}} SSH profile “{name}” to {destination}.'**
  String sshProfileStored(String action, String name, String destination);

  /// No description provided for @dragReplayControls.
  ///
  /// In en, this message translates to:
  /// **'Drag replay controls. Double tap to reset position.'**
  String get dragReplayControls;

  /// No description provided for @localTerminalObjectiveComplete.
  ///
  /// In en, this message translates to:
  /// **'Local terminal objective is complete'**
  String get localTerminalObjectiveComplete;

  /// No description provided for @localTerminalObjectiveBlocked.
  ///
  /// In en, this message translates to:
  /// **'Local terminal objective is blocked'**
  String get localTerminalObjectiveBlocked;

  /// No description provided for @milestones.
  ///
  /// In en, this message translates to:
  /// **'Milestones'**
  String get milestones;

  /// No description provided for @backlog.
  ///
  /// In en, this message translates to:
  /// **'Backlog'**
  String get backlog;

  /// No description provided for @verification.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get verification;

  /// No description provided for @blockedMilestones.
  ///
  /// In en, this message translates to:
  /// **'Blocked milestones'**
  String get blockedMilestones;

  /// No description provided for @missingProductionMilestones.
  ///
  /// In en, this message translates to:
  /// **'Missing production milestones'**
  String get missingProductionMilestones;

  /// No description provided for @blockedRealWiringBacklog.
  ///
  /// In en, this message translates to:
  /// **'Blocked real-wiring backlog'**
  String get blockedRealWiringBacklog;

  /// No description provided for @missingRealWiringBacklog.
  ///
  /// In en, this message translates to:
  /// **'Missing real-wiring backlog'**
  String get missingRealWiringBacklog;

  /// No description provided for @blockedVerificationGates.
  ///
  /// In en, this message translates to:
  /// **'Blocked verification gates'**
  String get blockedVerificationGates;

  /// No description provided for @missingVerificationGates.
  ///
  /// In en, this message translates to:
  /// **'Missing verification gates'**
  String get missingVerificationGates;

  /// No description provided for @completion.
  ///
  /// In en, this message translates to:
  /// **'Completion'**
  String get completion;

  /// No description provided for @unavailableInCurrentContext.
  ///
  /// In en, this message translates to:
  /// **'Unavailable in the current context.'**
  String get unavailableInCurrentContext;

  /// No description provided for @terminalModeAlt.
  ///
  /// In en, this message translates to:
  /// **'ALT'**
  String get terminalModeAlt;

  /// No description provided for @terminalModeMouse.
  ///
  /// In en, this message translates to:
  /// **'MOUSE'**
  String get terminalModeMouse;

  /// No description provided for @terminalModeMimePaste.
  ///
  /// In en, this message translates to:
  /// **'MIME PASTE'**
  String get terminalModeMimePaste;

  /// No description provided for @terminalModePaste.
  ///
  /// In en, this message translates to:
  /// **'PASTE'**
  String get terminalModePaste;

  /// No description provided for @terminalModeFocus.
  ///
  /// In en, this message translates to:
  /// **'FOCUS'**
  String get terminalModeFocus;

  /// No description provided for @terminalModeKeys.
  ///
  /// In en, this message translates to:
  /// **'KEYS'**
  String get terminalModeKeys;

  /// No description provided for @terminalModeSync.
  ///
  /// In en, this message translates to:
  /// **'SYNC'**
  String get terminalModeSync;

  /// No description provided for @terminalModeReadOnly.
  ///
  /// In en, this message translates to:
  /// **'READ ONLY'**
  String get terminalModeReadOnly;

  /// No description provided for @saveImageAs.
  ///
  /// In en, this message translates to:
  /// **'Save Image As…'**
  String get saveImageAs;

  /// No description provided for @copyImage.
  ///
  /// In en, this message translates to:
  /// **'Copy Image'**
  String get copyImage;

  /// No description provided for @openImage.
  ///
  /// In en, this message translates to:
  /// **'Open Image'**
  String get openImage;

  /// No description provided for @inspect.
  ///
  /// In en, this message translates to:
  /// **'Inspect'**
  String get inspect;

  /// No description provided for @imageInformation.
  ///
  /// In en, this message translates to:
  /// **'Image Information'**
  String get imageInformation;

  /// No description provided for @protocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get protocol;

  /// No description provided for @sourceSize.
  ///
  /// In en, this message translates to:
  /// **'Source size'**
  String get sourceSize;

  /// No description provided for @displaySize.
  ///
  /// In en, this message translates to:
  /// **'Display size'**
  String get displaySize;

  /// No description provided for @visibleArea.
  ///
  /// In en, this message translates to:
  /// **'Visible area'**
  String get visibleArea;

  /// No description provided for @cellPosition.
  ///
  /// In en, this message translates to:
  /// **'Cell position'**
  String get cellPosition;

  /// No description provided for @renderId.
  ///
  /// In en, this message translates to:
  /// **'Render ID'**
  String get renderId;

  /// No description provided for @placementId.
  ///
  /// In en, this message translates to:
  /// **'Placement ID'**
  String get placementId;

  /// No description provided for @asset.
  ///
  /// In en, this message translates to:
  /// **'Asset'**
  String get asset;

  /// No description provided for @couldNotOpenImageSaveDialog.
  ///
  /// In en, this message translates to:
  /// **'Could not open the image save dialog'**
  String get couldNotOpenImageSaveDialog;

  /// No description provided for @couldNotSaveImage.
  ///
  /// In en, this message translates to:
  /// **'Could not save image'**
  String get couldNotSaveImage;

  /// No description provided for @savedImage.
  ///
  /// In en, this message translates to:
  /// **'Saved image'**
  String get savedImage;

  /// No description provided for @couldNotCopyImage.
  ///
  /// In en, this message translates to:
  /// **'Could not copy image'**
  String get couldNotCopyImage;

  /// No description provided for @copiedImage.
  ///
  /// In en, this message translates to:
  /// **'Copied image'**
  String get copiedImage;

  /// No description provided for @unfoldTerminalBlock.
  ///
  /// In en, this message translates to:
  /// **'Unfold terminal block'**
  String get unfoldTerminalBlock;

  /// No description provided for @foldTerminalBlock.
  ///
  /// In en, this message translates to:
  /// **'Fold terminal block'**
  String get foldTerminalBlock;

  /// No description provided for @unfoldBlock.
  ///
  /// In en, this message translates to:
  /// **'Unfold block'**
  String get unfoldBlock;

  /// No description provided for @foldBlock.
  ///
  /// In en, this message translates to:
  /// **'Fold block'**
  String get foldBlock;

  /// No description provided for @renderedTerminalDocument.
  ///
  /// In en, this message translates to:
  /// **'Rendered terminal document'**
  String get renderedTerminalDocument;

  /// No description provided for @closeRenderedDocument.
  ///
  /// In en, this message translates to:
  /// **'Close rendered document'**
  String get closeRenderedDocument;

  /// No description provided for @closeTerminalTextDocument.
  ///
  /// In en, this message translates to:
  /// **'Close terminal text document'**
  String get closeTerminalTextDocument;

  /// No description provided for @openTerminalImagePreview.
  ///
  /// In en, this message translates to:
  /// **'Open terminal image preview'**
  String get openTerminalImagePreview;

  /// No description provided for @terminalImagePreview.
  ///
  /// In en, this message translates to:
  /// **'Terminal image preview'**
  String get terminalImagePreview;

  /// No description provided for @closeImagePreview.
  ///
  /// In en, this message translates to:
  /// **'Close image preview'**
  String get closeImagePreview;

  /// No description provided for @current.
  ///
  /// In en, this message translates to:
  /// **'current'**
  String get current;

  /// No description provided for @oscClipboardCopied.
  ///
  /// In en, this message translates to:
  /// **'{protocol} copied {count} characters to the clipboard'**
  String oscClipboardCopied(String protocol, int count);

  /// No description provided for @oscClipboardCopyBlocked.
  ///
  /// In en, this message translates to:
  /// **'{protocol} clipboard copy blocked by policy'**
  String oscClipboardCopyBlocked(String protocol);

  /// No description provided for @oscClipboardCopyInvalid.
  ///
  /// In en, this message translates to:
  /// **'{protocol} clipboard copy ignored: invalid payload'**
  String oscClipboardCopyInvalid(String protocol);

  /// No description provided for @oscPasteReadReplied.
  ///
  /// In en, this message translates to:
  /// **'{protocol} paste read replied with {count} characters'**
  String oscPasteReadReplied(String protocol, int count);

  /// No description provided for @oscPasteReadBlocked.
  ///
  /// In en, this message translates to:
  /// **'{protocol} paste read blocked by policy'**
  String oscPasteReadBlocked(String protocol);

  /// No description provided for @oscPasteReadInvalid.
  ///
  /// In en, this message translates to:
  /// **'{protocol} paste read ignored: invalid payload'**
  String oscPasteReadInvalid(String protocol);

  /// No description provided for @oscMimeWriteSucceeded.
  ///
  /// In en, this message translates to:
  /// **'OSC 5522 wrote {types} MIME types ({bytes} bytes)'**
  String oscMimeWriteSucceeded(int types, int bytes);

  /// No description provided for @oscMimeWriteBlocked.
  ///
  /// In en, this message translates to:
  /// **'OSC 5522 MIME clipboard write blocked by policy'**
  String get oscMimeWriteBlocked;

  /// No description provided for @oscMimeWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'OSC 5522 MIME clipboard write failed'**
  String get oscMimeWriteFailed;

  /// No description provided for @oscMimeReadSucceeded.
  ///
  /// In en, this message translates to:
  /// **'OSC 5522 replied with {types} MIME types ({bytes} bytes)'**
  String oscMimeReadSucceeded(int types, int bytes);

  /// No description provided for @oscMimeReadBlocked.
  ///
  /// In en, this message translates to:
  /// **'OSC 5522 MIME clipboard read blocked by policy'**
  String get oscMimeReadBlocked;

  /// No description provided for @oscMimeReadFailed.
  ///
  /// In en, this message translates to:
  /// **'OSC 5522 MIME clipboard read failed'**
  String get oscMimeReadFailed;

  /// No description provided for @terminalNotification.
  ///
  /// In en, this message translates to:
  /// **'Terminal notification'**
  String get terminalNotification;

  /// No description provided for @notificationOnRemoteInSession.
  ///
  /// In en, this message translates to:
  /// **'{title} on {remote} in {session}'**
  String notificationOnRemoteInSession(
    String title,
    String remote,
    String session,
  );

  /// No description provided for @bell.
  ///
  /// In en, this message translates to:
  /// **'Bell'**
  String get bell;

  /// No description provided for @terminalRequestedAttentionBody.
  ///
  /// In en, this message translates to:
  /// **'The terminal requested attention.'**
  String get terminalRequestedAttentionBody;

  /// No description provided for @commandFinished.
  ///
  /// In en, this message translates to:
  /// **'Command finished'**
  String get commandFinished;

  /// No description provided for @commandFinishedInSession.
  ///
  /// In en, this message translates to:
  /// **'Command finished in {session}'**
  String commandFinishedInSession(String session);

  /// No description provided for @commandFinishedOnRemoteInSession.
  ///
  /// In en, this message translates to:
  /// **'Command finished on {remote} in {session}'**
  String commandFinishedOnRemoteInSession(String remote, String session);

  /// No description provided for @terminalSettingsCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Terminal settings could not be loaded: {error}'**
  String terminalSettingsCouldNotLoad(String error);

  /// No description provided for @shortcutValue.
  ///
  /// In en, this message translates to:
  /// **'shortcut: {shortcut}'**
  String shortcutValue(String shortcut);

  /// No description provided for @errorValue.
  ///
  /// In en, this message translates to:
  /// **'error: {error}'**
  String errorValue(String error);

  /// No description provided for @backInShell.
  ///
  /// In en, this message translates to:
  /// **'Back in shell'**
  String get backInShell;

  /// No description provided for @newOutput.
  ///
  /// In en, this message translates to:
  /// **'New output'**
  String get newOutput;

  /// No description provided for @clickFocusFirstPaneWithNewOutput.
  ///
  /// In en, this message translates to:
  /// **'Click to focus the first pane with new output.'**
  String get clickFocusFirstPaneWithNewOutput;

  /// No description provided for @newOutputInSplitPane.
  ///
  /// In en, this message translates to:
  /// **'New output in a split pane.'**
  String get newOutputInSplitPane;

  /// No description provided for @newOutputInSplitPanes.
  ///
  /// In en, this message translates to:
  /// **'New output in {count} split panes.'**
  String newOutputInSplitPanes(int count);

  /// No description provided for @hiddenTabsHaveNewOutput.
  ///
  /// In en, this message translates to:
  /// **'Hidden tabs have new output'**
  String get hiddenTabsHaveNewOutput;

  /// No description provided for @newOutputInHiddenTab.
  ///
  /// In en, this message translates to:
  /// **'New output in a hidden tab.'**
  String get newOutputInHiddenTab;

  /// No description provided for @tabSessionDetails.
  ///
  /// In en, this message translates to:
  /// **'Tab: {title} ({id})'**
  String tabSessionDetails(String title, String id);

  /// No description provided for @paneAlreadyFocused.
  ///
  /// In en, this message translates to:
  /// **'Pane already focused.'**
  String get paneAlreadyFocused;

  /// No description provided for @newOutputInHiddenPanes.
  ///
  /// In en, this message translates to:
  /// **'New output in {count} hidden panes.'**
  String newOutputInHiddenPanes(int count);

  /// No description provided for @noActivePaneAvailable.
  ///
  /// In en, this message translates to:
  /// **'No active pane is available.'**
  String get noActivePaneAvailable;

  /// No description provided for @paneTooNarrow.
  ///
  /// In en, this message translates to:
  /// **'Another pane would become narrower than {columns} columns.'**
  String paneTooNarrow(int columns);

  /// No description provided for @paneTooShort.
  ///
  /// In en, this message translates to:
  /// **'Another pane would become shorter than {rows} rows.'**
  String paneTooShort(int rows);

  /// No description provided for @unzoomActivePaneToManage.
  ///
  /// In en, this message translates to:
  /// **'Unzoom the active pane to manage other panes.'**
  String get unzoomActivePaneToManage;

  /// No description provided for @closeNamedTab.
  ///
  /// In en, this message translates to:
  /// **'Close {title} tab'**
  String closeNamedTab(String title);

  /// No description provided for @closeNamed.
  ///
  /// In en, this message translates to:
  /// **'Close {title}'**
  String closeNamed(String title);

  /// No description provided for @osc21337Status.
  ///
  /// In en, this message translates to:
  /// **'OSC 21337 status: {status}'**
  String osc21337Status(String status);

  /// No description provided for @remoteApiBaseUrlWithoutCredentials.
  ///
  /// In en, this message translates to:
  /// **'The remote data API URL must be an http(s) base URL without credentials, query, or fragment.'**
  String get remoteApiBaseUrlWithoutCredentials;

  /// No description provided for @remoteApiRequiresHttps.
  ///
  /// In en, this message translates to:
  /// **'Remote data API authentication requires HTTPS. HTTP is allowed only for a loopback development endpoint.'**
  String get remoteApiRequiresHttps;

  /// No description provided for @shell.
  ///
  /// In en, this message translates to:
  /// **'Shell'**
  String get shell;

  /// No description provided for @fieldIsRequired.
  ///
  /// In en, this message translates to:
  /// **'{field} is required'**
  String fieldIsRequired(String field);

  /// No description provided for @fieldMustBePositiveInteger.
  ///
  /// In en, this message translates to:
  /// **'{field} must be a positive integer'**
  String fieldMustBePositiveInteger(String field);

  /// No description provided for @fieldMustBeAtMost.
  ///
  /// In en, this message translates to:
  /// **'{field} must be {maximum} or less'**
  String fieldMustBeAtMost(String field, int maximum);

  /// No description provided for @fieldMustBeGreaterThanZero.
  ///
  /// In en, this message translates to:
  /// **'{field} must be greater than 0'**
  String fieldMustBeGreaterThanZero(String field);

  /// No description provided for @environmentKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'Key is required'**
  String get environmentKeyRequired;

  /// No description provided for @environmentKeyUnique.
  ///
  /// In en, this message translates to:
  /// **'Key must be unique'**
  String get environmentKeyUnique;

  /// No description provided for @newProfileDefaultName.
  ///
  /// In en, this message translates to:
  /// **'New Profile'**
  String get newProfileDefaultName;

  /// No description provided for @terminalTabSemantics.
  ///
  /// In en, this message translates to:
  /// **'{title} tab'**
  String terminalTabSemantics(String title);

  /// No description provided for @terminalStatus.
  ///
  /// In en, this message translates to:
  /// **'status {status}'**
  String terminalStatus(String status);

  /// No description provided for @terminalStatusFromActivePane.
  ///
  /// In en, this message translates to:
  /// **'status {status} from active pane'**
  String terminalStatusFromActivePane(String status);

  /// No description provided for @statusIndicatorActive.
  ///
  /// In en, this message translates to:
  /// **'status indicator active'**
  String get statusIndicatorActive;

  /// No description provided for @statusIndicatorActiveOnActivePane.
  ///
  /// In en, this message translates to:
  /// **'status indicator active on active pane'**
  String get statusIndicatorActiveOnActivePane;

  /// No description provided for @terminalBadgeFromPane.
  ///
  /// In en, this message translates to:
  /// **'badge {badge} from {state}'**
  String terminalBadgeFromPane(String badge, String state);

  /// No description provided for @badgeSemanticsValue.
  ///
  /// In en, this message translates to:
  /// **'badge {badge}'**
  String badgeSemanticsValue(String badge);

  /// No description provided for @plusOtherPaneBadges.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{plus 1 other pane badge} other{plus {count} other pane badges}}'**
  String plusOtherPaneBadges(int count);

  /// No description provided for @signalFromPane.
  ///
  /// In en, this message translates to:
  /// **' from {state}'**
  String signalFromPane(String state);

  /// No description provided for @terminalSignalSummary.
  ///
  /// In en, this message translates to:
  /// **'{title}: {summary}{scope}'**
  String terminalSignalSummary(String title, String summary, String scope);

  /// No description provided for @plusOtherPaneSignals.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{plus 1 other pane signal} other{plus {count} other pane signals}}'**
  String plusOtherPaneSignals(int count);

  /// No description provided for @newOutputLower.
  ///
  /// In en, this message translates to:
  /// **'new output'**
  String get newOutputLower;

  /// No description provided for @newOutputInSplitPaneLower.
  ///
  /// In en, this message translates to:
  /// **'new output in split pane'**
  String get newOutputInSplitPaneLower;

  /// No description provided for @commandShortcut.
  ///
  /// In en, this message translates to:
  /// **'Command {index}'**
  String commandShortcut(int index);

  /// No description provided for @otherPaneBadges.
  ///
  /// In en, this message translates to:
  /// **'Other pane badges:'**
  String get otherPaneBadges;

  /// No description provided for @terminalBadgeValue.
  ///
  /// In en, this message translates to:
  /// **'Terminal badge: {badge}'**
  String terminalBadgeValue(String badge);

  /// No description provided for @otherPaneBadgeCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 other pane badge} other{{count} other pane badges}}'**
  String otherPaneBadgeCount(int count);

  /// No description provided for @additionalOsc1337Badge.
  ///
  /// In en, this message translates to:
  /// **'Additional OSC 1337 badge: {badge}'**
  String additionalOsc1337Badge(String badge);

  /// No description provided for @additionalOsc1337BadgesSplitTab.
  ///
  /// In en, this message translates to:
  /// **'Additional OSC 1337 badges in this split tab.'**
  String get additionalOsc1337BadgesSplitTab;

  /// No description provided for @clickFocusFirstRemainingBadgePane.
  ///
  /// In en, this message translates to:
  /// **'Click to focus the first remaining badge pane.'**
  String get clickFocusFirstRemainingBadgePane;

  /// No description provided for @firstRemainingBadgePaneFocused.
  ///
  /// In en, this message translates to:
  /// **'First remaining badge pane is already focused.'**
  String get firstRemainingBadgePaneFocused;

  /// No description provided for @terminalBadgesAdditional.
  ///
  /// In en, this message translates to:
  /// **'Terminal badges: {count} additional pane badges in {title}; {action}'**
  String terminalBadgesAdditional(int count, String title, String action);

  /// No description provided for @clickFocusPaneSemantics.
  ///
  /// In en, this message translates to:
  /// **'click to focus this pane'**
  String get clickFocusPaneSemantics;

  /// No description provided for @paneAlreadyFocusedSemantics.
  ///
  /// In en, this message translates to:
  /// **'pane already focused'**
  String get paneAlreadyFocusedSemantics;

  /// No description provided for @clickFocusFirstRemainingBadgePaneSemantics.
  ///
  /// In en, this message translates to:
  /// **'click to focus the first remaining badge pane'**
  String get clickFocusFirstRemainingBadgePaneSemantics;

  /// No description provided for @firstRemainingBadgePaneFocusedSemantics.
  ///
  /// In en, this message translates to:
  /// **'first remaining badge pane is already focused'**
  String get firstRemainingBadgePaneFocusedSemantics;

  /// No description provided for @terminalProgressAbbreviation.
  ///
  /// In en, this message translates to:
  /// **'PROG'**
  String get terminalProgressAbbreviation;

  /// No description provided for @terminalProgress.
  ///
  /// In en, this message translates to:
  /// **'Terminal progress'**
  String get terminalProgress;

  /// No description provided for @terminalNotificationAbbreviation.
  ///
  /// In en, this message translates to:
  /// **'NOTE'**
  String get terminalNotificationAbbreviation;

  /// No description provided for @paneSignalAbbreviation.
  ///
  /// In en, this message translates to:
  /// **'PANE'**
  String get paneSignalAbbreviation;

  /// No description provided for @otherPaneSignals.
  ///
  /// In en, this message translates to:
  /// **'Other pane signals:'**
  String get otherPaneSignals;

  /// No description provided for @signalInSplitPane.
  ///
  /// In en, this message translates to:
  /// **'{signal} in a split pane.'**
  String signalInSplitPane(String signal);

  /// No description provided for @clickInspectRecentNotifications.
  ///
  /// In en, this message translates to:
  /// **'Click to inspect recent notifications.'**
  String get clickInspectRecentNotifications;

  /// No description provided for @clickFocusFirstPaneWithSignal.
  ///
  /// In en, this message translates to:
  /// **'Click to focus the first pane with a signal.'**
  String get clickFocusFirstPaneWithSignal;

  /// No description provided for @clickInspectNotificationActionsSemantics.
  ///
  /// In en, this message translates to:
  /// **'click to inspect notification actions'**
  String get clickInspectNotificationActionsSemantics;

  /// No description provided for @otherPaneSignalCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 other pane signal} other{{count} other pane signals}}'**
  String otherPaneSignalCount(int count);

  /// No description provided for @terminalProgressReportedBy.
  ///
  /// In en, this message translates to:
  /// **'Terminal progress reported by {source}.'**
  String terminalProgressReportedBy(String source);

  /// No description provided for @labelValue.
  ///
  /// In en, this message translates to:
  /// **'Label: {value}'**
  String labelValue(String value);

  /// No description provided for @progressPercentValue.
  ///
  /// In en, this message translates to:
  /// **'Percent: {value}%'**
  String progressPercentValue(int value);

  /// No description provided for @stateValue.
  ///
  /// In en, this message translates to:
  /// **'State: {value}'**
  String stateValue(String value);

  /// No description provided for @idValue.
  ///
  /// In en, this message translates to:
  /// **'ID: {value}'**
  String idValue(String value);

  /// No description provided for @terminalNotificationReportedBy.
  ///
  /// In en, this message translates to:
  /// **'Terminal notification reported by {source}.'**
  String terminalNotificationReportedBy(String source);

  /// No description provided for @titleValue.
  ///
  /// In en, this message translates to:
  /// **'Title: {value}'**
  String titleValue(String value);

  /// No description provided for @messageValue.
  ///
  /// In en, this message translates to:
  /// **'Message: {value}'**
  String messageValue(String value);

  /// No description provided for @remoteHostValue.
  ///
  /// In en, this message translates to:
  /// **'Remote host: {value}'**
  String remoteHostValue(String value);

  /// No description provided for @remoteUserValue.
  ///
  /// In en, this message translates to:
  /// **'Remote user: {value}'**
  String remoteUserValue(String value);

  /// No description provided for @countValue.
  ///
  /// In en, this message translates to:
  /// **'Count: {value}'**
  String countValue(int value);

  /// No description provided for @osc1337BadgeInHiddenTab.
  ///
  /// In en, this message translates to:
  /// **'OSC 1337 badge in a hidden tab.'**
  String get osc1337BadgeInHiddenTab;

  /// No description provided for @osc1337BadgesInHiddenPanes.
  ///
  /// In en, this message translates to:
  /// **'OSC 1337 badges in {count} hidden panes.'**
  String osc1337BadgesInHiddenPanes(int count);

  /// No description provided for @clickFocusFirstBadgePane.
  ///
  /// In en, this message translates to:
  /// **'Click to focus the first badge pane.'**
  String get clickFocusFirstBadgePane;

  /// No description provided for @signalInHiddenTab.
  ///
  /// In en, this message translates to:
  /// **'{signal} in a hidden tab.'**
  String signalInHiddenTab(String signal);

  /// No description provided for @paneSignalsInHiddenPanes.
  ///
  /// In en, this message translates to:
  /// **'Pane signals in {count} hidden panes.'**
  String paneSignalsInHiddenPanes(int count);

  /// No description provided for @showHiddenTabs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Show 1 hidden tab} other{Show {count} hidden tabs}}'**
  String showHiddenTabs(int count);

  /// No description provided for @hiddenOsc1337BadgePanesTooltip.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Hidden OSC 1337 badge: 1 pane} other{Hidden OSC 1337 badges: {count} panes}}'**
  String hiddenOsc1337BadgePanesTooltip(int count);

  /// No description provided for @hiddenPaneSignalsTooltip.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Hidden pane signal: 1 pane} other{Hidden pane signals: {count} panes}}'**
  String hiddenPaneSignalsTooltip(int count);

  /// No description provided for @hiddenNewOutputTabsTooltip.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Hidden new output: 1 tab} other{Hidden new output: {count} tabs}}'**
  String hiddenNewOutputTabsTooltip(int count);

  /// No description provided for @signalMarkersFocusSources.
  ///
  /// In en, this message translates to:
  /// **'Signal markers can focus their source panes.'**
  String get signalMarkersFocusSources;

  /// No description provided for @hiddenOsc1337BadgePanesSemantics.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hidden OSC 1337 badge pane} other{{count} hidden OSC 1337 badge panes}}'**
  String hiddenOsc1337BadgePanesSemantics(int count);

  /// No description provided for @hiddenPaneSignalsSemantics.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hidden pane signal} other{{count} hidden pane signals}}'**
  String hiddenPaneSignalsSemantics(int count);

  /// No description provided for @hiddenNewOutputTabsSemantics.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hidden tab with new output} other{{count} hidden tabs with new output}}'**
  String hiddenNewOutputTabsSemantics(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
