// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Ianvs 终端';

  @override
  String get cancel => '取消';

  @override
  String get close => '关闭';

  @override
  String get retry => '重试';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get continueAction => '继续';

  @override
  String get username => '用户名';

  @override
  String get password => '密码';

  @override
  String get importAction => '导入';

  @override
  String get preview => '预览';

  @override
  String dialogSemantics(String title) {
    return '$title对话框';
  }

  @override
  String get closeDialog => '关闭对话框';

  @override
  String startingAppAttempt(int attempt) {
    return '正在启动 Ianvs 终端，第 $attempt 次尝试';
  }

  @override
  String get preparingTerminalRuntime => '正在准备终端运行时…';

  @override
  String loadingTerminalSession(String profile) {
    return '正在加载 $profile…';
  }

  @override
  String startupStage(String stage) {
    return '阶段：$stage';
  }

  @override
  String get retryStartup => '重试启动';

  @override
  String get dataServiceSettings => '数据服务设置';

  @override
  String get connectAndContinue => '连接并继续';

  @override
  String get disableDataServiceQuestion => '停用数据服务？';

  @override
  String get disableDataServiceExplanation =>
      '下次尝试启动时将明确切换为仅本地终端模式。不会启动 API 进程，也不会删除现有远程数据。';

  @override
  String get useLocalTerminal => '使用本地终端';

  @override
  String get dataServiceRecovery => '数据服务恢复';

  @override
  String get configurationReadFailed => '无法读取当前配置，但你仍可明确选择“停用”。';

  @override
  String get reconnectConfiguredOrigin => '请先重新连接已配置的远程服务，再重试启动。此处无法更改服务地址。';

  @override
  String get masterKeyFromAnotherDeviceOptional => '来自其他设备的主密钥（可选）';

  @override
  String get masterKeyImportHelp => '如果此设备还没有主密钥，请粘贴导出的 ianvs-key-v1 密钥。';

  @override
  String get localDataServiceStartFailed =>
      '本地数据服务无法启动。请选择本地终端模式，在不使用 API 的情况下继续。本地 API 数据会保留。';

  @override
  String get alreadyUsingLocalTerminal => '应用已处于本地终端模式。请重试启动，或再次保存此模式以清除恢复锁。';

  @override
  String get reconnectAndRetry => '重新连接并重试';

  @override
  String get appleMasterKeySynchronized => '主密钥会通过 iCloud 钥匙串自动存储和同步，无需手动输入。';

  @override
  String get masterKeyImportUnavailable => '无法导入主密钥。';

  @override
  String get httpApiUrl => 'HTTP API 地址';

  @override
  String get chooseDataMode => '选择数据模式';

  @override
  String get dataModeLocalBundledOrRemote =>
      '你可以仅使用本地终端、启动内置离线 API，或连接远程 API 以跨设备同步。';

  @override
  String get dataModeLocalOrRemote =>
      '你可以在不使用数据服务的情况下进行一次性 SSH 连接，或连接远程 API 来保存并同步 Profile。';

  @override
  String get remoteApiRequiredOnIos => '在 iOS 上使用 Ianvs 终端前，必须先连接远程 HTTP API。';

  @override
  String get masterKeyOpenExistingHelp => '粘贴导出的 ianvs-key-v1 密钥，以打开现有加密数据。';

  @override
  String get continueWithoutDataService => '不使用数据服务并继续';

  @override
  String get connectRemoteApi => '连接远程 API';

  @override
  String get useBundledLocalApi => '使用内置本地 API';

  @override
  String get useLocalTerminalOnly => '仅使用本地终端';

  @override
  String get appCouldNotStart => 'Ianvs 终端无法启动';

  @override
  String startupStageName(String stage) {
    String _temp0 = intl.Intl.selectLogic(stage, {
      'paths': '文件路径',
      'secureRecovery': '安全恢复',
      'configuration': '配置',
      'dataBootstrap': '数据服务启动',
      'platform': '平台初始化',
      'pty': '终端运行时',
      'configurationValidation': '配置验证',
      'runtimeComposition': '运行时组装',
      'runtimeShutdown': '运行时关闭',
      'other': '$stage',
    });
    return '$_temp0';
  }

  @override
  String get openCommandPalette => '打开命令面板';

  @override
  String get commandPalette => '命令面板';

  @override
  String get closeCommandPalette => '关闭命令面板';

  @override
  String get searchActions => '搜索操作';

  @override
  String get typeActionAndPressEnter => '输入操作并按回车键';

  @override
  String noActionMatches(String query) {
    return '没有与“$query”匹配的操作。';
  }

  @override
  String get quickActions => '快捷操作';

  @override
  String get appActions => '应用操作';

  @override
  String get sessionActions => '会话操作';

  @override
  String get replay => '回放';

  @override
  String get shellTools => 'Shell 工具';

  @override
  String get openTerminalTabFirst => '请先打开一个终端标签页。';

  @override
  String get noDefaultProfileConfigured => '尚未配置默认 Profile。';

  @override
  String get noRecentlyClosedTab => '没有可重新打开的近期标签页。';

  @override
  String get searchTerminalOutput => '搜索终端输出';

  @override
  String get searchTerminalOutputDescription => '置顶操作 • 在当前面板中打开终端搜索。';

  @override
  String get newTab => '新建标签页';

  @override
  String get newTabTitleCase => '新建标签页';

  @override
  String get newTabDescription => '置顶操作 • 打开默认 Profile。';

  @override
  String get toolbelt => '工具带';

  @override
  String get toolbeltDescription => '置顶操作 • 打开当前面板的终端工具。';

  @override
  String get defaultsAppearance => '默认设置与外观';

  @override
  String get defaultsAppearanceDescription => '应用操作 • 选择默认 Profile 和主题。';

  @override
  String get reopenClosedTab => '重新打开已关闭的标签页';

  @override
  String get reopenClosedTabDescription => '应用操作 • 恢复最近关闭的标签页。';

  @override
  String get terminalColorPresets => '终端配色预设';

  @override
  String get terminalColorPresetsDescription => '应用操作 • 打开“默认设置与外观”以选择终端配色。';

  @override
  String commandFinishedNotifications(String enabled) {
    String _temp0 = intl.Intl.selectLogic(enabled, {
      'true': '停用命令完成通知',
      'other': '启用命令完成通知',
    });
    return '$_temp0';
  }

  @override
  String get commandFinishedNotificationsDescription =>
      '应用操作 • 切换 Shell Hook 的完成提醒。';

  @override
  String get commandFinishedNotificationsBlockedDescription =>
      '应用操作 • 切换 Shell Hook 的完成提醒。macOS 通知目前在系统设置中被阻止。';

  @override
  String activityMonitor(String enabled) {
    String _temp0 = intl.Intl.selectLogic(enabled, {
      'true': '停用活动监视器',
      'other': '启用活动监视器',
    });
    return '$_temp0';
  }

  @override
  String get activityMonitorDescription => '应用操作 • 切换非活动会话的活动提醒。';

  @override
  String get activityMonitorBlockedDescription =>
      '应用操作 • 切换非活动会话的活动提醒。macOS 通知目前在系统设置中被阻止。';

  @override
  String get profilesEllipsis => 'Profile…';

  @override
  String get profilesDescription => '应用操作 • 打开或编辑 Shell Profile。';

  @override
  String get requiresActiveShellSession => '需要一个活动的 Shell 会话。';

  @override
  String readOnlyMode(String enabled) {
    String _temp0 = intl.Intl.selectLogic(enabled, {
      'true': '停用只读模式',
      'other': '启用只读模式',
    });
    return '$_temp0';
  }

  @override
  String get readOnlyModeDescription => '会话操作 • 阻止向当前面板的终端输入。';

  @override
  String get clearBuffer => '清空缓冲区';

  @override
  String get clearBufferDescription => '会话操作 • 清除可见输出和历史记录，但保留当前命令行。';

  @override
  String get openSftpPanel => '打开 SFTP 面板';

  @override
  String get openSftpPanelDescription => '会话操作 • 在右侧面板浏览当前 SSH 连接中的文件。';

  @override
  String get requiresActiveSshSession => '需要一个活动的 SSH 会话。';

  @override
  String get exportTerminalHistory => '导出终端历史记录';

  @override
  String get exportTerminalHistoryDescription =>
      '会话操作 • 将保留的文本保存为 .txt 文件，以便共享或稍后查看。';

  @override
  String get exportDiagnostics => '导出诊断信息';

  @override
  String get exportDiagnosticsDescription => '会话操作 • 保存本地资源诊断包。';

  @override
  String get replayRecentActivity => '回放近期活动';

  @override
  String get replayRecentActivityDescription => '回放 • 查看当前面板滚动保存的帧历史。';

  @override
  String get stopAndSaveRecording => '停止并保存录制';

  @override
  String get retrySavingRecording => '重试保存录制';

  @override
  String get startRecordingForReplay => '开始录制以供回放';

  @override
  String get recordingDescription =>
      '回放 • 将此会话保存为持久录制。按键内容会被隐藏；如果可用，会包含 Shell 命令元数据。';

  @override
  String get recordingOperationInProgress => '录制操作正在进行。';

  @override
  String get openRecordingInReplay => '在回放中打开录制…';

  @override
  String get openRecordingInReplayDescription => '回放 • 打开一个已保存的终端录制，但不导入它。';

  @override
  String get globalSearch => '全局搜索';

  @override
  String get globalSearchDescription => 'Shell 工具 • 同时搜索所有标签页。';

  @override
  String openCommandPaletteWith(String shortcut) {
    return '使用 $shortcut 打开命令面板';
  }

  @override
  String get configurationWarningsSummary => '部分终端 Profile 配置值已被忽略，并重置为安全默认值。';

  @override
  String get dismissConfigurationWarnings => '关闭配置警告';

  @override
  String get reviewProfiles => '检查 Profile';

  @override
  String get dismiss => '关闭';

  @override
  String get terminalRuntimeError => '终端运行时错误。';

  @override
  String get dismissRuntimeError => '关闭运行时错误';

  @override
  String get terminalCouldNotStart => '终端无法启动';

  @override
  String get terminalCouldNotStartHelp => '请检查启动错误，然后尝试重新加载布局。';

  @override
  String get useLastRemoteSnapshot => '使用本地快照';

  @override
  String get switchingToLocalSnapshot => '正在切换到本地…';

  @override
  String get remoteFallbackTitle => '使用最后一次远程快照？';

  @override
  String remoteFallbackDescription(String capturedAt, int resourceCount) {
    return '远程服务当前不可用。Ianvs 终端可以切换到内置本地 API，使用 $capturedAt 最后同步的 $resourceCount 项资源。远程数据不会被删除，重启应用后生效。';
  }

  @override
  String get switchToLocalApi => '切换到本地 API';

  @override
  String get remoteFallbackCompleteTitle => '本地降级已就绪';

  @override
  String remoteFallbackCompleteDescription(String capturedAt) {
    return '内置本地 API 将使用 $capturedAt 同步的远程数据。请重启 Ianvs 终端以应用更改。';
  }

  @override
  String remoteFallbackFailed(String error) {
    return '无法切换到本地快照：$error';
  }

  @override
  String get repairTerminalSettings => '修复设置';

  @override
  String get repairTerminalSettingsTitle => '修复终端设置？';

  @override
  String get repairTerminalSettingsDescription =>
      'Ianvs 终端会先将原始远端文档保存为恢复副本，再补齐当前格式要求的字段并重试启动。Profile 和会话数据不会更改。';

  @override
  String get repairAndRetry => '修复并重试';

  @override
  String terminalSettingsRepairFailed(String error) {
    return '无法修复终端设置：$error';
  }

  @override
  String get shellLayoutIdle => 'Shell 布局当前空闲';

  @override
  String get startShellLayout => '开始使用 Shell 布局';

  @override
  String get lastSessionClosedHelp => '最后一个会话已关闭。请打开新标签页以继续使用 Shell 布局。';

  @override
  String get openNewTabToStart => '请打开新标签页以开始使用 Shell 布局。';

  @override
  String currentNewTabProfile(String profile) {
    return '当前新标签页 Profile • $profile';
  }

  @override
  String configuredDefaultProfile(String profile) {
    return '已配置的默认 Profile • $profile';
  }

  @override
  String get noProfileAvailable => '没有可用的 Profile';

  @override
  String get connectWithSsh => '通过 SSH 连接';

  @override
  String get createSshConnectionFirstTab => '创建 SSH 连接以打开第一个标签页。';

  @override
  String get chooseSavedProfileForTab => '选择已保存的 Profile 以打开终端标签页。';

  @override
  String get localSessionsUnavailableOnIphone => 'iPhone 上无法使用本地终端会话。';

  @override
  String get noSshProfilesYet => '还没有 SSH Profile';

  @override
  String get newSshConnection => '新建 SSH 连接';

  @override
  String get newTerminalTab => '新建终端标签页';

  @override
  String get newSshTab => '新建 SSH 标签页';

  @override
  String get chooseLocalShellOrSsh => '选择本地 Shell 或连接到 SSH 主机。';

  @override
  String get chooseSavedSshOrCreate => '选择已保存的 SSH Profile 或创建一个新的 Profile。';

  @override
  String get localShell => '本地 Shell';

  @override
  String get sshSession => 'SSH 会话';

  @override
  String get newSshConnectionLower => '新建 SSH 连接';

  @override
  String get newOneTimeSshConnection => '新建一次性 SSH 连接';

  @override
  String get connectionWillNotBeSaved => '此连接不会被保存';

  @override
  String get remoteDataRequiredToSaveSsh =>
      '连接远程数据服务后才能保存可复用的 SSH Profile。即使没有 Ianvs 账号或数据服务，你仍可进行一次性连接。';

  @override
  String get searchSshProfiles => '搜索 SSH Profile';

  @override
  String get searchByNameHostUser => '按名称、主机或用户搜索';

  @override
  String get clearSearch => '清除搜索';

  @override
  String get savedSshProfiles => '已保存的 SSH Profile';

  @override
  String get fromOpenSshConfig => '来自 ~/.ssh/config';

  @override
  String get openSshProfilesUnavailable => 'OpenSSH Profile 不可用';

  @override
  String get noConcreteSshHosts => '未找到具体的 SSH 主机';

  @override
  String get noMatchingSshProfiles => '没有匹配的 SSH Profile';

  @override
  String get tryDifferentNameHostUser => '请尝试其他名称、主机或用户。';

  @override
  String moreActionsFor(String name) {
    return '$name的更多操作';
  }

  @override
  String get connect => '连接';

  @override
  String get profiles => 'Profile';

  @override
  String get savedSshProfilesRequireRemote =>
      '在 iPhone 上保存 SSH Profile 需要远程数据服务。';

  @override
  String get openSavedSshOrEdit => '打开已保存的 SSH Profile，或编辑其终端设置。';

  @override
  String get openSavedProfileOrEdit => '使用任意已保存的 Profile 打开标签页，或编辑其终端设置。';

  @override
  String get noMatchingProfiles => '没有匹配的 Profile';

  @override
  String get noSavedProfiles => '没有已保存的 Profile';

  @override
  String get noProfilesYet => '还没有 Profile';

  @override
  String get tryDifferentProfileSearch => '请尝试其他 Profile 名称、Shell 或标签。';

  @override
  String get connectRemoteToCreateSyncSsh => '连接远程数据服务以创建和同步 SSH Profile。';

  @override
  String get createSshProfileToConnect => '创建 SSH Profile 以连接远程主机。';

  @override
  String get createProfileToCustomize => '创建 Profile 以自定义终端会话。';

  @override
  String get createProfile => '创建 Profile';

  @override
  String get connectRemoteToCreateSavedSsh => '连接远程数据服务以创建可保存的 SSH Profile';

  @override
  String get newAction => '新建';

  @override
  String get closeProfiles => '关闭 Profile';

  @override
  String get searchProfilesOrTags => '搜索 Profile 或标签';

  @override
  String editNamedItem(String name) {
    return '编辑$name';
  }

  @override
  String deleteNamedItem(String name) {
    return '删除$name';
  }

  @override
  String get newProfile => '新建 Profile';

  @override
  String get runShellOnDevice => '在此设备上运行 Shell。';

  @override
  String get connectRemoteHost => '连接到远程主机。';

  @override
  String scrollbackLineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 行',
    );
    return '$_temp0';
  }

  @override
  String get defaultProfile => '默认 Profile';

  @override
  String get defaultsAppearanceSubtitle =>
      '选择新标签页的默认 Profile，并设置 Shell 如何跟随应用主题。';

  @override
  String get closeDefaults => '关闭默认设置';

  @override
  String get useAutomaticFallback => '使用自动回退';

  @override
  String get noProfileForNewTabs => '没有可用于新标签页的 Profile。';

  @override
  String newTabsUseProfileAutomatically(String profile) {
    return '在你选择固定默认值之前，新标签页会自动使用 $profile。';
  }

  @override
  String automaticFallbackProfile(String profile) {
    return '自动回退 • $profile';
  }

  @override
  String get unknownProfile => '未知 Profile';

  @override
  String get terminalPreset => '终端预设';

  @override
  String get createProfileBeforeColors => '请先创建 Profile，再选择终端配色。';

  @override
  String applyPaletteToProfile(String profile) {
    return '为 $profile 应用精选的终端配色。';
  }

  @override
  String get filterTerminalPresets => '筛选终端预设';

  @override
  String get keepCurrent => '保持当前设置';

  @override
  String get customColors => '自定义颜色';

  @override
  String currentlyPreset(String preset) {
    return '当前为 $preset';
  }

  @override
  String selectedTerminalPreset(String preset) {
    return '$preset，已选择';
  }

  @override
  String noTerminalPresetsMatch(String query) {
    return '没有与“$query”匹配的终端预设。';
  }

  @override
  String get startup => '启动';

  @override
  String get startupLayoutDescription => '选择终端启动时是否重建上次的标签页和面板布局。';

  @override
  String get restoreTabsAndPanes => '启动时恢复标签页和面板';

  @override
  String get restoreTabsAndPanesDescription =>
      '会启动新的 Shell 进程并恢复其文件夹；不会恢复仍在运行的进程。';

  @override
  String get language => '语言';

  @override
  String get languageDescription => '选择应用界面使用的语言。';

  @override
  String languageModeName(String mode) {
    String _temp0 = intl.Intl.selectLogic(mode, {
      'system': '跟随系统',
      'english': 'English',
      'simplifiedChinese': '简体中文',
      'other': '$mode',
    });
    return '$_temp0';
  }

  @override
  String languageModeDescription(String mode) {
    String _temp0 = intl.Intl.selectLogic(mode, {
      'system': '使用当前设备的首选语言。',
      'english': '始终使用 English 显示应用。',
      'simplifiedChinese': '始终使用简体中文显示应用。',
      'other': '$mode',
    });
    return '$_temp0';
  }

  @override
  String get generalSettingsDescription => '选择新标签页的默认 Profile 和应用界面语言。';

  @override
  String get appearanceSettingsDescription => '自定义终端配色、启动行为和应用主题。';

  @override
  String get appearance => '外观';

  @override
  String themeModeName(String mode) {
    String _temp0 = intl.Intl.selectLogic(mode, {
      'system': '跟随系统',
      'light': '浅色',
      'dark': '深色',
      'other': '$mode',
    });
    return '$_temp0';
  }

  @override
  String themeModeDescription(String mode) {
    String _temp0 = intl.Intl.selectLogic(mode, {
      'system': '跟随当前设备外观。',
      'light': '始终以浅色模式显示 Shell 应用。',
      'dark': '始终以深色模式显示 Shell 应用。',
      'other': '$mode',
    });
    return '$_temp0';
  }

  @override
  String get terminalCanvasInset => '终端画布边距';

  @override
  String get terminalCanvasInsetDescription => '调整 Shell 边框与终端文本之间的空白。';

  @override
  String get viewportPadding => '视口内边距';

  @override
  String pixelCount(int count) {
    return '$count 像素';
  }

  @override
  String get decreaseViewportPadding => '减小视口内边距';

  @override
  String get increaseViewportPadding => '增大视口内边距';

  @override
  String viewportPaddingRange(int minimum, int maximum) {
    return '范围 $minimum–$maximum px';
  }

  @override
  String get viewportPaddingDescription => '较小的值让提示符更靠近边缘；较大的值会增加终端留白。';

  @override
  String get resetDefault => '重置默认值';

  @override
  String get resetTheme => '重置主题';

  @override
  String get migrateToRemoteApi => '迁移到远程 API';

  @override
  String get migrateToLocalApi => '迁移到本地 API';

  @override
  String get saveChanges => '保存更改';

  @override
  String get detailedSettingsInProfiles => '详细的终端设置位于 Profile 中。';

  @override
  String get editTerminalDetailsInProfiles =>
      '可在 Profile 编辑器中修改字体、颜色、光标、回滚行数和启动参数。';

  @override
  String editProfileInProfiles(String profile) {
    return '在 Profile 中编辑 $profile';
  }

  @override
  String get keyboardShortcuts => '键盘快捷键';

  @override
  String get keyboardShortcutsDescription => '选择一个快捷键以录入新的组合键。保存后更改会立即生效。';

  @override
  String get keyboardShortcutsNavigationDescription => '自定义终端操作的组合键。';

  @override
  String get manageShortcuts => '管理快捷键';

  @override
  String get backToDefaultsAppearance => '返回默认设置与外观';

  @override
  String get moreShortcutActions => '更多快捷键操作';

  @override
  String get done => '完成';

  @override
  String get filterShortcutActions => '筛选快捷键操作';

  @override
  String get filterActions => '筛选操作';

  @override
  String get category => '类别';

  @override
  String get allActions => '所有操作';

  @override
  String get restoreAllDefaults => '恢复全部默认值';

  @override
  String get noMatchingActions => '没有匹配的操作';

  @override
  String get tryAnotherActionOrCategory => '请尝试其他操作名称或类别。';

  @override
  String shortcutConflictSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '存在 $count 个快捷键冲突。请先解决冲突再保存。',
    );
    return '$_temp0';
  }

  @override
  String get resolveShortcutConflicts => '请先解决快捷键冲突再保存';

  @override
  String get addShortcut => '添加快捷键';

  @override
  String editShortcutFor(String action) {
    return '编辑“$action”的快捷键';
  }

  @override
  String disableShortcutFor(String action) {
    return '停用“$action”的快捷键';
  }

  @override
  String restoreShortcutFor(String action) {
    return '恢复“$action”的默认快捷键';
  }

  @override
  String get recordShortcut => '录入快捷键';

  @override
  String get activeWhen => '生效范围';

  @override
  String get waitingForShortcut => '正在等待快捷键';

  @override
  String recordedShortcut(String shortcut) {
    return '已录入 $shortcut';
  }

  @override
  String get pressShortcut => '请按下快捷键';

  @override
  String get shortcutCaptureHelp => '按 Escape 取消，或按 Delete 停用此快捷键。';

  @override
  String get disableShortcut => '停用快捷键';

  @override
  String get apply => '应用';

  @override
  String get copyMasterKeyQuestion => '复制主密钥？';

  @override
  String get copyMasterKeyWarning =>
      '任何获得此密钥的人都可以解密你的 Ianvs 数据。密钥会被复制到系统剪贴板；请将其粘贴到目标应用，然后清空剪贴板。';

  @override
  String get copyKey => '复制密钥';

  @override
  String get importMasterKey => '导入主密钥';

  @override
  String get ianvsMasterKey => 'Ianvs 主密钥';

  @override
  String get masterKeyPasteHelp => '请粘贴以 ianvs-key-v1 开头的完整内容。';

  @override
  String get masterKey => '主密钥';

  @override
  String get appleEncryptionManagedAutomatically => '此 Apple 设备会自动管理加密。';

  @override
  String get portableMasterKeyDescription =>
      '一个可移植密钥即可在支持的平台上解锁本地、远程和 SSH Profile 加密。';

  @override
  String get appleMasterKeyStorageDescription =>
      'Ianvs 终端会将主密钥存储在 iCloud 钥匙串中并自动请求同步，无需手动输入密钥。';

  @override
  String get copyForAnotherDevice => '复制到其他设备';

  @override
  String get pasteFromAnotherDevice => '从其他设备粘贴';

  @override
  String get closeSftpPanel => '关闭 SFTP 面板';

  @override
  String get copyFullPath => '复制完整路径';

  @override
  String get editLocally => '在本地编辑';

  @override
  String get createDirectory => '创建目录';

  @override
  String copiedPath(String path) {
    return '已复制 $path';
  }

  @override
  String createdNamedItem(String name) {
    return '已创建 $name';
  }

  @override
  String couldNotCreateNamedItem(String name) {
    return '无法创建 $name。';
  }

  @override
  String get name => '名称';

  @override
  String get create => '创建';

  @override
  String deleteNamedItemQuestion(String name) {
    return '删除 $name？';
  }

  @override
  String get directoryMustBeEmpty => '必须先清空目录，才能将其删除。';

  @override
  String get remoteFileDeletedPermanently => '此远程文件将被永久删除。';

  @override
  String deletedNamedItem(String name) {
    return '已删除 $name';
  }

  @override
  String couldNotDeleteNamedItem(String name) {
    return '无法删除 $name。';
  }

  @override
  String sftpPanelFor(String address) {
    return '$address 的 SFTP 面板';
  }

  @override
  String get remoteRoot => '远程根目录';

  @override
  String get parentDirectory => '上级目录';

  @override
  String get refreshRemoteDirectory => '刷新远程目录';

  @override
  String get loadingRemoteDirectory => '正在加载远程目录';

  @override
  String get unableLoadRemoteDirectory => '无法加载远程目录。';

  @override
  String get remoteFilesUnavailable => '远程文件不可用';

  @override
  String get remoteDirectoryEmpty => '此远程目录为空。';

  @override
  String remoteEntrySemantics(String type, String name) {
    return '$type $name';
  }

  @override
  String get folder => '文件夹';

  @override
  String get file => '文件';

  @override
  String get sshHostKeyChanged => 'SSH 主机密钥已更改';

  @override
  String get trustThisSshHost => '信任此 SSH 主机？';

  @override
  String get sshHostKeyChangedWarning =>
      '此服务器当前提供的密钥与已保存的密钥不一致。仅当你已验证新指纹时才应继续；接受后会替换已保存的密钥。';

  @override
  String get sshUnknownHostWarning => '严格验证模式下没有此服务器的已保存密钥。请先验证指纹，再决定是否信任。';

  @override
  String get server => '服务器';

  @override
  String get algorithm => '算法';

  @override
  String get sha256Fingerprint => 'SHA-256 指纹';

  @override
  String get reject => '拒绝';

  @override
  String get replaceKeyAndContinue => '替换密钥并继续';

  @override
  String get trustAndContinue => '信任并继续';

  @override
  String get sshAuthentication => 'SSH 身份验证';

  @override
  String responseNumber(int number) {
    return '回答 $number';
  }

  @override
  String get responseHidden => '你的回答会被隐藏。';

  @override
  String get editProfile => '编辑 Profile';

  @override
  String get discardChangesQuestion => '放弃更改？';

  @override
  String get discardProfileChangesWarning => 'Profile 中有未保存的更改。要关闭编辑器并丢失这些更改吗？';

  @override
  String get keepEditing => '继续编辑';

  @override
  String get discardChanges => '放弃更改';

  @override
  String get findProfileSetting => '查找 Profile 设置';

  @override
  String get findSetting => '查找设置';

  @override
  String get clearSettingsSearch => '清除设置搜索';

  @override
  String get noSettingsFound => '未找到设置';

  @override
  String sectionsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '找到 $count 个部分',
    );
    return '$_temp0';
  }

  @override
  String modifiedSections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已修改 $count 个部分',
    );
    return '$_temp0';
  }

  @override
  String noProfileSettingsMatch(String query) {
    return '没有与“$query”匹配的 Profile 设置。';
  }

  @override
  String get profileEditorSectionNavigation => 'Profile 编辑器分区导航';

  @override
  String get profileEditorDialog => 'Profile 编辑器对话框';

  @override
  String get profileChangesNewSessionsOnly =>
      '更改仅应用于新会话。现有标签页会保留其启动时的 Profile 快照。';

  @override
  String get closeProfileEditor => '关闭 Profile 编辑器';

  @override
  String profileSectionName(String section) {
    String _temp0 = intl.Intl.selectLogic(section, {
      'general': '常规',
      'startup': '启动',
      'terminal': '终端',
      'appearance': '外观',
      'keys': '按键',
      'automation': '自动化',
      'advanced': '高级',
      'other': '$section',
    });
    return '$_temp0';
  }

  @override
  String resetProfileSection(String section) {
    return '重置$section';
  }

  @override
  String profileSectionSemantics(String section, String modified) {
    String _temp0 = intl.Intl.selectLogic(modified, {
      'true': '，已修改',
      'other': '',
    });
    return '$section Profile 部分$_temp0';
  }

  @override
  String get sshConnection => 'SSH 连接';

  @override
  String get connectOnceOrSaveProfile => '进行一次性连接，或保存为可复用的会话 Profile。';

  @override
  String get connection => '连接';

  @override
  String get connectionSectionDescription => '为会话命名并输入目标地址。';

  @override
  String get sessionName => '会话名称';

  @override
  String get exampleProduction => '例如：生产环境';

  @override
  String get host => '主机';

  @override
  String get hostnameOrIp => '主机名或 IP 地址';

  @override
  String get user => '用户';

  @override
  String get remoteUser => '远程用户';

  @override
  String get port => '端口';

  @override
  String get authentication => '身份验证';

  @override
  String get authenticationDescription => '选择服务器验证你身份的方式。';

  @override
  String get method => '方式';

  @override
  String get authenticationMethod => '身份验证方式';

  @override
  String get automaticKeysThenPassword => '自动（先密钥，后密码）';

  @override
  String get privateKey => '私钥';

  @override
  String get keyboardInteractiveOtp => '键盘交互 / OTP';

  @override
  String get passwordFallback => '密码回退';

  @override
  String get passwordFallbackHelp => '仅在密钥身份验证不可用时使用。';

  @override
  String get forgetSavedPassword => '忘记已保存的密码';

  @override
  String get privateKeyDescription => '此处显示所选路径，但只会保存加密后的密钥内容。';

  @override
  String get privateKeyFile => '私钥文件';

  @override
  String get select => '选择';

  @override
  String get replace => '替换';

  @override
  String get forgetSavedPrivateKey => '忘记已保存的私钥';

  @override
  String get privateKeyPassphrase => '私钥口令';

  @override
  String get privateKeyPassphraseHelp => '未加密的私钥请留空。';

  @override
  String get forgetSavedKeyPassphrase => '忘记已保存的密钥口令';

  @override
  String get keyboardInteractiveHelp => '连接开始后，服务器会逐项询问所需回答，包括多步骤 OTP 质询。';

  @override
  String get hostVerificationAdvanced => '主机验证与高级选项';

  @override
  String get hostVerificationAdvancedDescription =>
      '主机密钥、跳板机、隧道、Agent 和 X11 转发';

  @override
  String get hostKeyPolicy => '主机密钥策略';

  @override
  String get acceptNewHostsRecommended => '接受新主机（推荐）';

  @override
  String get askBeforeTrusting => '信任前询问';

  @override
  String get doNotVerifyUnsafe => '不验证（不安全）';

  @override
  String get knownHostsFileOptional => 'known_hosts 文件（可选）';

  @override
  String get proxyCommandOptional => 'ProxyCommand（可选）';

  @override
  String get proxyJumpOptional => 'ProxyJump（可选）';

  @override
  String get proxyJumpHelp =>
      '用逗号分隔 [user@]host[:port]；IPv6 主机请使用方括号。新跳点使用独立的自动身份验证。';

  @override
  String get portForwards => '端口转发';

  @override
  String get portForwardsHelp =>
      '每行一项：L bind:port target:port、R bind:port target:port 或 D bind:port。';

  @override
  String get forwardSshAgent => '转发 SSH Agent';

  @override
  String get agentSocketHelp => 'Socket 路径留空时使用 SSH_AUTH_SOCK。';

  @override
  String get agentSocketOptional => 'Agent Socket（可选）';

  @override
  String get forwardX11 => '转发 X11';

  @override
  String get x11ForwardingHelp =>
      '目标留空时使用 DISPLAY；必须提供 32 字符的 MIT-MAGIC-COOKIE。';

  @override
  String get localX11Target => '本地 X11 目标 host:port';

  @override
  String get x11AuthenticationCookie => 'X11 身份验证 Cookie';

  @override
  String get x11CookieRequired => '必须正好为 32 个十六进制字符。';

  @override
  String get forgetSavedX11Cookie => '忘记已保存的 X11 Cookie';

  @override
  String get saveThisSshSession => '保存此 SSH 会话';

  @override
  String get secretsEncryptedDescription => '机密信息会被加密，密钥保留在平台安全存储中。';

  @override
  String get remoteServiceRequiredToSaveProfile =>
      '保存 Profile 需要远程数据服务。此连接仅使用一次。';

  @override
  String get requiredField => '必填';

  @override
  String enterRange(int minimum, int maximum) {
    return '请输入 $minimum–$maximum';
  }

  @override
  String get connectTimeoutSeconds => '连接超时（秒）';

  @override
  String get keepaliveSeconds => '保活间隔（秒）';

  @override
  String get keepaliveRetries => '保活重试次数';

  @override
  String get general => '常规';

  @override
  String get generalProfileDescription => '先为 Profile 命名并添加标签，再配置启动行为。';

  @override
  String get tags => '标签';

  @override
  String get tagsCommaHelp => '用逗号分隔标签。';

  @override
  String get profileStartupDescription => '配置命令、工作目录和进程环境。';

  @override
  String get command => '命令';

  @override
  String get shellProgram => 'Shell / 程序';

  @override
  String get workingDirectory => '工作目录';

  @override
  String get workingDirectoryHelp => '留空以使用默认工作目录。';

  @override
  String get argumentsAndEnvironment => '参数与环境';

  @override
  String get arguments => '参数';

  @override
  String get addArgument => '添加参数';

  @override
  String get noLaunchArguments => '暂无启动参数';

  @override
  String get terminal => '终端';

  @override
  String get terminalProfileDescription => '为新会话选择终端仿真和保留的回滚行数。';

  @override
  String get emulation => '仿真';

  @override
  String get terminalEmulationHelp => '选择向应用程序报告的终端仿真类型。';

  @override
  String get scrollbackLines => '回滚行数';

  @override
  String get scrollbackLinesHelp => '保留在回滚缓冲区中的最大行数。';

  @override
  String get linesUnit => '行';

  @override
  String get profileAppearanceDescription => '控制排版、颜色和光标行为。';

  @override
  String get typography => '排版';

  @override
  String get fontFamily => '字体族';

  @override
  String get fallbackFonts => '备用字体';

  @override
  String get addFallbackFont => '添加备用字体';

  @override
  String get noFallbackFonts => '暂无备用字体';

  @override
  String get fontSize => '字体大小';

  @override
  String get lineHeight => '行高';

  @override
  String get colors => '颜色';

  @override
  String get specialColors => '特殊颜色';

  @override
  String get ansiNormal => 'ANSI 标准色';

  @override
  String get ansiBright => 'ANSI 亮色';

  @override
  String get cursor => '光标';

  @override
  String get cursorShape => '光标形状';

  @override
  String get blinkCursor => '光标闪烁';

  @override
  String get keys => '按键';

  @override
  String get keysProfileDescription => '选择新打开会话的默认选择行为。';

  @override
  String get selection => '选择';

  @override
  String get copyOnSelect => '选择时复制';

  @override
  String get optionDragMode => 'Option 拖动模式';

  @override
  String get normalSelection => '普通选择';

  @override
  String get blockSelection => '块选择';

  @override
  String get automation => '自动化';

  @override
  String get automationProfileDescription => '匹配终端输出后通知你，或输入固定回答。';

  @override
  String get rules => '规则';

  @override
  String get triggers => '触发器';

  @override
  String get triggerExamples => '示例：ERROR => notify，Password: => send: secret';

  @override
  String get automaticProfileSwitching => '自动切换 Profile';

  @override
  String get automaticProfileSwitchingHelp => '主机、用户或目录更改后切换此 Profile。';

  @override
  String get advanced => '高级';

  @override
  String get advancedProfileDescription => '控制新会话中与 Shell 感知相关的 Profile 行为。';

  @override
  String get integration => '集成';

  @override
  String get shellIntegration => 'Shell 集成';

  @override
  String get shellIntegrationDescription => '启用提示符标记、徽章、命令导航和 Shell 感知操作。';

  @override
  String get enabledStatus => '已启用';

  @override
  String get disabledStatus => '已停用';

  @override
  String get toolbeltTerminalTools => '终端工具带';

  @override
  String get closeToolbelt => '关闭工具带';

  @override
  String get promptMarks => '提示符标记';

  @override
  String promptMarkCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个标记',
    );
    return '$_temp0';
  }

  @override
  String get tmuxIntegration => 'tmux 集成';

  @override
  String get controlModeActive => '控制模式已启用';

  @override
  String get startOrAttach => '启动或附加';

  @override
  String get coprocess => '协同进程';

  @override
  String get automationActive => '自动化已启用';

  @override
  String get runAutomation => '运行自动化';

  @override
  String get annotations => '注释';

  @override
  String annotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条注释',
    );
    return '$_temp0';
  }

  @override
  String get recentFrames => '近期帧';

  @override
  String get passwordManager => '密码管理器';

  @override
  String get promptGatedSends => '仅在提示后发送';

  @override
  String get commands => '命令';

  @override
  String get directoriesShort => '目录';

  @override
  String get output => '输出';

  @override
  String get paste => '粘贴';

  @override
  String get commandHistory => '命令历史';

  @override
  String commandCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条命令',
    );
    return '$_temp0';
  }

  @override
  String get all => '全部';

  @override
  String get runCommandToFillHistory => '在此标签页中运行命令后，命令历史会显示在这里。';

  @override
  String get insertCommand => '插入命令';

  @override
  String get recentDirectories => '最近目录';

  @override
  String directoryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个目录',
    );
    return '$_temp0';
  }

  @override
  String get changeDirectoriesToFillHistory => '切换目录后，最近目录会显示在这里。';

  @override
  String get insertCdCommand => '插入 cd 命令';

  @override
  String get capturedOutput => '捕获的输出';

  @override
  String capturedLineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已捕获 $count 行',
    );
    return '$_temp0';
  }

  @override
  String get open => '打开';

  @override
  String get profileAutomationCapturesOutput => 'Profile 触发器和协同进程可捕获输出。';

  @override
  String capturedOutputLocation(String pattern, int row) {
    return '模式 $pattern · 第 $row 行';
  }

  @override
  String get pasteHistory => '粘贴历史';

  @override
  String recentItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个最近项目',
    );
    return '$_temp0';
  }

  @override
  String get copiedAndPastedTextAppearsHere => '复制和粘贴的文本会显示在这里。';

  @override
  String get copied => '已复制';

  @override
  String get pasted => '已粘贴';

  @override
  String get advancedPaste => '高级粘贴';

  @override
  String get closeAdvancedPaste => '关闭高级粘贴';

  @override
  String get pasteText => '粘贴文本';

  @override
  String get text => '文本';

  @override
  String get escapeSpecialCharacters => '转义特殊字符';

  @override
  String get base64Encode => 'Base64 编码';

  @override
  String get appendNewline => '追加换行符';

  @override
  String byteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 字节',
    );
    return '$_temp0';
  }

  @override
  String get closeCapturedOutput => '关闭捕获的输出';

  @override
  String get clear => '清除';

  @override
  String get startCapturingMatchingOutput => '开始捕获匹配的输出';

  @override
  String get capturedOutputEmptyBody => 'Profile 触发器或协同进程模式匹配终端输出后，捕获的行会显示在这里。';

  @override
  String get openProfilesAndAddTrigger => '打开 Profile 并添加触发模式。';

  @override
  String get runCommandThatPrintsPattern => '运行会输出该模式的命令。';

  @override
  String get reopenCapturedOutput => '重新打开“捕获的输出”，查看并复制匹配项。';

  @override
  String get copyCapturedOutput => '复制捕获的输出';

  @override
  String get closeAnnotations => '关闭注释';

  @override
  String get selectTerminalTextToAnnotate => '选择终端文本后即可添加注释。';

  @override
  String get note => '备注';

  @override
  String get addAnnotation => '添加注释';

  @override
  String get addFirstAnnotation => '添加第一条注释';

  @override
  String get selectOutputBeforeAnnotating => '先选择输出再添加注释';

  @override
  String get annotationSelectionReadyBody => '使用上方备注字段，为选中的终端输出附加备注。';

  @override
  String get annotationSelectionRequiredBody => '注释基于活动窗格中选中的终端文本创建。';

  @override
  String get enterNoteForSelectedOutput => '为选中的输出输入备注。';

  @override
  String get saveAnnotation => '保存注释。';

  @override
  String get useAnnotationBadge => '稍后可通过注释徽章重新打开备注。';

  @override
  String get selectTerminalOutputInPane => '在窗格中选择终端输出。';

  @override
  String get openAnnotationsAgain => '再次打开注释。';

  @override
  String get enterNoteAndSave => '输入备注并保存。';

  @override
  String get removeAnnotation => '移除注释';

  @override
  String get closePasteHistory => '关闭粘贴历史';

  @override
  String get saveHistoryToDisk => '将历史记录保存到磁盘';

  @override
  String get keepPasteHistoryAcrossLaunches => '在应用重启后保留最近复制和粘贴的文本。';

  @override
  String get noPasteHistoryYet => '还没有复制或粘贴的文本。';

  @override
  String get closePasswordManager => '关闭密码管理器';

  @override
  String get passwordPromptDetected => '活动会话中检测到密码提示。';

  @override
  String get openPasswordPromptFirst => '请先打开密码提示，再发送密码。';

  @override
  String get passwordManagerSessionSecurity =>
      '密码仅保留在本次应用会话中，并且只有当活动终端看起来正在请求密码时才能发送。';

  @override
  String get label => '标签';

  @override
  String get serverOrAccount => '服务器或账户';

  @override
  String get passwordEntered => '已输入密码';

  @override
  String get add => '添加';

  @override
  String get noSavedSessionPasswords => '本次会话中没有保存的密码。请先在上方添加，再打开密码提示后发送。';

  @override
  String get readyToSend => '可以发送';

  @override
  String get waitingForPasswordPrompt => '正在等待密码提示';

  @override
  String get removePassword => '移除密码';

  @override
  String get send => '发送';

  @override
  String get closeCoprocess => '关闭协同进程';

  @override
  String get runCoprocess => '运行协同进程';

  @override
  String get onePerSession => '每个会话一个';

  @override
  String get commandLabel => '命令标签';

  @override
  String get inputPattern => '输入模式';

  @override
  String get coprocessOutput => '协同进程输出';

  @override
  String get run => '运行';

  @override
  String lineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 行',
    );
    return '$_temp0';
  }

  @override
  String patternValue(String pattern) {
    return '模式 $pattern';
  }

  @override
  String get stop => '停止';

  @override
  String get closeTmuxIntegration => '关闭 tmux 集成';

  @override
  String get controlMode => '控制模式';

  @override
  String get startTmuxControlMode => '启动 tmux -CC';

  @override
  String get startTmuxControlModeDescription => '创建新的 tmux 控制模式会话。';

  @override
  String get attachTmuxControlMode => '附加 tmux -CC';

  @override
  String get attachTmuxControlModeDescription => '附加到现有的 tmux 会话。';

  @override
  String get tmuxActions => 'tmux 操作';

  @override
  String get available => '可用';

  @override
  String get waiting => '等待中';

  @override
  String get newWindow => '新建窗口';

  @override
  String get newWindowDescription => '向 tmux 控制模式发送 new-window。';

  @override
  String get splitPaneRight => '向右拆分窗格';

  @override
  String get splitPaneRightDescription => '发送 split-window -h。';

  @override
  String get splitPaneDown => '向下拆分窗格';

  @override
  String get splitPaneDownDescription => '发送 split-window -v。';

  @override
  String get detachClient => '分离客户端';

  @override
  String get detachClientDescription => '保持 tmux 运行并分离客户端。';

  @override
  String get sendTmuxCommand => '发送 tmux 命令';

  @override
  String get tmuxCommand => 'tmux 命令';

  @override
  String get controlModeDetected => '检测到控制模式';

  @override
  String get noTmuxControlModeDetected => '未检测到 tmux 控制模式';

  @override
  String get closeShellIntegration => '关闭 Shell 集成';

  @override
  String get runCommandAfterOpeningTab => '打开此标签页后运行命令，命令历史会显示在这里。';

  @override
  String get insertPreviousCommand => '插入上一条命令';

  @override
  String get changeDirectoriesAfterOpeningTab => '打开此标签页后切换目录，最近目录会显示在这里。';

  @override
  String get promptMarksAppearAfterPrompt => 'Shell 绘制新提示符后，提示符标记会显示在这里。';

  @override
  String get commandSucceededShort => '成功';

  @override
  String commandExitCodeShort(int code) {
    return '退出码 $code';
  }

  @override
  String globalLine(int line) {
    return '全局第 $line 行';
  }

  @override
  String scrollbackOffset(int offset) {
    return '偏移 $offset';
  }

  @override
  String get shellPromptMark => 'Shell 提示符标记';

  @override
  String get regexError => '正则表达式错误';

  @override
  String get noMatches => '无匹配项';

  @override
  String get smartCaseSubstring => '智能大小写子字符串';

  @override
  String get caseSensitiveSubstring => '区分大小写的子字符串';

  @override
  String get caseInsensitiveSubstring => '不区分大小写的子字符串';

  @override
  String get caseSensitiveRegex => '区分大小写的正则表达式';

  @override
  String get caseInsensitiveRegex => '不区分大小写的正则表达式';

  @override
  String searchFilterValue(String filter) {
    return '搜索筛选：$filter';
  }

  @override
  String get searchFilter => '搜索筛选';

  @override
  String get filter => '筛选';

  @override
  String get currentTab => '当前标签页';

  @override
  String get allTabs => '所有标签页';

  @override
  String get paneShort => '窗格';

  @override
  String get tabShort => '标签页';

  @override
  String get scope => '范围';

  @override
  String searchScopeValue(String scope) {
    return '搜索范围：$scope';
  }

  @override
  String get clearSearchText => '清除搜索文本';

  @override
  String searchResultValue(String result) {
    return '搜索结果：$result';
  }

  @override
  String get search => '搜索';

  @override
  String get previousMatch => '上一个匹配项';

  @override
  String get nextMatch => '下一个匹配项';

  @override
  String get closeSearch => '关闭搜索';

  @override
  String searchingAcrossSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个会话',
    );
    return '正在搜索 $_temp0';
  }

  @override
  String matchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个匹配项',
    );
    return '$_temp0';
  }

  @override
  String get closeGlobalSearch => '关闭全局搜索';

  @override
  String searchResultLocation(String session, int row) {
    return '$session · 第 $row 行';
  }

  @override
  String get noMatchesInReplayHistory => '回放历史中没有匹配项。';

  @override
  String uniqueReplayMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个唯一匹配项',
    );
    return '回放中有 $_temp0';
  }

  @override
  String idleGapValue(String duration) {
    return '空闲间隔：$duration';
  }

  @override
  String get noReplayFrames => '没有回放帧';

  @override
  String recordedAtDimensions(int columns, int rows) {
    return '录制尺寸 $columns×$rows';
  }

  @override
  String get noReplayFramesCapturedYet => '尚未捕获回放帧。';

  @override
  String get replayRecentActivityLayout => '近期活动回放布局';

  @override
  String get closeReplay => '关闭回放';

  @override
  String get terminalChanged => '终端已变化';

  @override
  String get replayControlsRecentActivity => '近期活动回放控件';

  @override
  String get retentionDisabled => '已停用保留';

  @override
  String retainsLatestFrames(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 帧',
    );
    return '保留最近 $_temp0';
  }

  @override
  String get recentActivity => '近期活动';

  @override
  String get stepBackInReplay => '回放后退一步';

  @override
  String get pauseReplay => '暂停回放';

  @override
  String get playReplay => '播放回放';

  @override
  String get stepForwardInReplay => '回放前进一步';

  @override
  String playbackSpeedValue(String speed) {
    return '播放速度 $speed 倍';
  }

  @override
  String get playbackSpeed => '播放速度';

  @override
  String get realTimeShort => '实时';

  @override
  String get smartTimeShort => '智能';

  @override
  String replayTimingValue(String mode) {
    return '$mode回放计时';
  }

  @override
  String get replayTiming => '回放计时';

  @override
  String get smartReplayTimingDescription => '智能 · 跳过较长空闲间隔';

  @override
  String get realReplayTimingDescription => '实时 · 保留所有间隔';

  @override
  String get fitRecordedSize => '适配录制尺寸';

  @override
  String get copyVisible => '复制可见内容';

  @override
  String get copySelection => '复制选中内容';

  @override
  String get clearHistory => '清除历史记录';

  @override
  String get searchReplay => '搜索回放';

  @override
  String get previousSearchMatch => '上一个搜索匹配项';

  @override
  String get nextSearchMatch => '下一个搜索匹配项';

  @override
  String get savedTerminalRecordings => '已保存的终端录制';

  @override
  String get savedRecordings => '已保存的录制';

  @override
  String get importEllipsis => '导入…';

  @override
  String get refreshRecordings => '刷新录制';

  @override
  String get closeSavedRecordings => '关闭已保存的录制';

  @override
  String get searchRecordings => '搜索录制';

  @override
  String get filterPlayableOnly => '筛选：仅可播放';

  @override
  String get filterAllRecordings => '筛选：所有录制';

  @override
  String get filterRecordings => '筛选录制';

  @override
  String get allRecordings => '所有录制';

  @override
  String get playableOnly => '仅可播放';

  @override
  String recordingSortValue(String sort) {
    return '排序：$sort';
  }

  @override
  String get recordingSortOrder => '录制排序方式';

  @override
  String get newest => '最新';

  @override
  String get oldest => '最早';

  @override
  String get recordingsMayContainSensitiveOutput => '录制中可能包含敏感的终端输出。';

  @override
  String get recordingMayContainSensitiveOutput => '此录制中可能包含敏感输出。';

  @override
  String recordingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个录制',
    );
    return '$_temp0';
  }

  @override
  String get noMatchingRecordings => '没有匹配的录制';

  @override
  String get noSavedRecordings => '没有已保存的录制';

  @override
  String actionsForNamedItem(String name) {
    return '$name 的操作';
  }

  @override
  String get recordingActions => '录制操作';

  @override
  String get renameEllipsis => '重命名…';

  @override
  String get revealInFinder => '在 Finder 中显示';

  @override
  String get exportEllipsis => '导出…';

  @override
  String get moveToTrash => '移到废纸篓';

  @override
  String couldNotStartReplay(String error) {
    return '无法开始回放：$error';
  }

  @override
  String couldNotSeekRecording(String error) {
    return '无法定位录制：$error';
  }

  @override
  String get inputIncluded => '包含输入';

  @override
  String get keystrokesRedactedCommandMetadataIncluded => '已隐去按键 · 包含命令元数据';

  @override
  String get keystrokesRedacted => '已隐去按键';

  @override
  String get recordedSession => '录制的会话';

  @override
  String recordingDetail(String session, String disclosure) {
    return '$session · $disclosure';
  }

  @override
  String get preparingReplay => '正在准备回放…';

  @override
  String replayRecordingLayout(String name) {
    return '$name 的录制回放布局';
  }

  @override
  String get recording => '录制';

  @override
  String matchesAcrossReplay(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个匹配项',
    );
    return '回放中有 $_temp0';
  }

  @override
  String get replayControlsForRecording => '录制回放控件';

  @override
  String get idleInterval => '空闲区间';

  @override
  String get inputEvent => '输入事件';

  @override
  String get terminalResized => '终端尺寸已调整';

  @override
  String get sessionExited => '会话已退出';

  @override
  String get outputEvent => '输出事件';

  @override
  String get activity => '活动';

  @override
  String get remoteActivity => '远程活动';

  @override
  String commandNumber(int number) {
    return '命令 $number';
  }

  @override
  String replayTimelineSemantics(
    String context,
    String position,
    String duration,
  ) {
    return '$context，$position / $duration';
  }

  @override
  String exitCode(int code) {
    return '退出码 $code';
  }

  @override
  String jumpToReplaySegment(String segment, String time) {
    return '跳转到 $time 的$segment';
  }

  @override
  String get remote => '远程';

  @override
  String get idle => '空闲';

  @override
  String get remoteSession => '远程会话';

  @override
  String get idleGap => '空闲间隔';

  @override
  String get shellSemantics => 'Shell 语义';

  @override
  String get activityFallbackNoShellHook => '活动回退 · 无 Shell 钩子';

  @override
  String terminalActionName(String action) {
    String _temp0 = intl.Intl.selectLogic(action, {
      'new_tab': '新建标签页',
      'new_ssh_session': '新建 SSH 会话',
      'new_tab_at_folder': '在文件夹中新建标签页',
      'open_recording_for_replay': '打开录制进行回放',
      'duplicate_current_cwd': '复制当前目录会话',
      'reopen_closed_tab': '重新打开关闭的标签页',
      'open_launcher': '打开启动器',
      'open_command_menu': '打开命令菜单',
      'toolbelt': '工具带',
      'open_sftp_panel': '打开 SFTP 面板',
      'split_right': '向右拆分',
      'split_down': '向下拆分',
      'focus_next_pane': '聚焦下一个窗格',
      'focus_previous_pane': '聚焦上一个窗格',
      'resize_pane': '调整窗格大小',
      'swap_pane': '交换窗格',
      'zoom_pane': '缩放窗格',
      'close_pane': '关闭窗格',
      'reopen_closed_pane': '重新打开关闭的窗格',
      'close_active_tab': '关闭活动标签页',
      'open_defaults': '打开默认设置',
      'activate_tab': '激活标签页',
      'copy': '复制',
      'copy_mode': '复制模式',
      'copy_command_output': '复制命令输出',
      'paste': '粘贴',
      'advanced_paste': '高级粘贴',
      'paste_history': '粘贴历史',
      'toggle_read_only': '切换只读模式',
      'toggle_replay_recording': '切换回放录制',
      'clear_buffer': '清除缓冲区',
      'shell_integration': 'Shell 集成',
      'select_command_output': '选择命令输出',
      'open_recent_directory': '打开最近目录',
      'tmux_integration': 'tmux 集成',
      'coprocess': '协同进程',
      'annotations': '注释',
      'captured_output': '捕获的输出',
      'password_manager': '密码管理器',
      'replay_recent_activity': '回放近期活动',
      'search_scrollback': '搜索回滚内容',
      'next_search_match': '下一个搜索匹配项',
      'previous_search_match': '上一个搜索匹配项',
      'clear_search': '清除搜索',
      'global_search': '全局搜索',
      'autocomplete': '自动补全',
      'auto_composer': '自动编写器',
      'hotkey_window': '快捷键窗口',
      'defaults': '默认设置',
      'profiles': 'Profile',
      'dynamic_profiles': '动态 Profile',
      'request_quit_confirmation': '请求退出确认',
      'previous_prompt': '上一个提示符',
      'next_prompt': '下一个提示符',
      'toggle_command_finished_notify': '切换命令完成通知',
      'toggle_bell_notify': '切换响铃通知',
      'toggle_activity_monitor': '切换活动监视器',
      'export_scrollback': '导出回滚内容',
      'export_diagnostics': '导出诊断',
      'open_theme_picker': '打开主题选择器',
      'apply_theme': '应用主题',
      'apply_layout_template': '应用布局模板',
      'other': '$action',
    });
    return '$_temp0';
  }

  @override
  String get appCategory => '应用';

  @override
  String get sessionCategory => '会话';

  @override
  String get replayCategory => '回放';

  @override
  String get paneCategory => '窗格';

  @override
  String get layoutCategory => '布局';

  @override
  String get navigationCategory => '导航';

  @override
  String get integrationCategory => '集成';

  @override
  String get appFocused => '应用聚焦时';

  @override
  String get terminalFocused => '终端聚焦时';

  @override
  String get appWideFallback => '应用级回退';

  @override
  String get commandMenuOpen => '命令菜单打开时';

  @override
  String get notAssigned => '未分配';

  @override
  String get noShortcut => '无快捷键';

  @override
  String get shortcutConflict => '冲突';

  @override
  String get shortcutDisabled => '已停用';

  @override
  String get shortcutCustom => '自定义';

  @override
  String get shortcutUnassigned => '未分配';

  @override
  String get shortcutActionColumn => '操作';

  @override
  String get shortcutValueColumn => '快捷键';

  @override
  String get shortcutDefault => '默认';

  @override
  String shortcutActionSemantics(String action, String state, String shortcut) {
    return '$action，$state，$shortcut';
  }

  @override
  String get listAndSeparator => '、';

  @override
  String profileColorName(String color) {
    String _temp0 = intl.Intl.selectLogic(color, {
      'special_foreground': '前景色',
      'special_background': '背景色',
      'special_cursor': '光标颜色',
      'special_selection': '选择颜色',
      'special_tab': '标签页颜色',
      'normal_black': '黑色',
      'normal_red': '红色',
      'normal_green': '绿色',
      'normal_yellow': '黄色',
      'normal_blue': '蓝色',
      'normal_magenta': '品红色',
      'normal_cyan': '青色',
      'normal_white': '白色',
      'bright_black': '亮黑色',
      'bright_red': '亮红色',
      'bright_green': '亮绿色',
      'bright_yellow': '亮黄色',
      'bright_blue': '亮蓝色',
      'bright_magenta': '亮品红色',
      'bright_cyan': '亮青色',
      'bright_white': '亮白色',
      'other': '$color',
    });
    return '$_temp0';
  }

  @override
  String get moveUp => '上移';

  @override
  String get moveDown => '下移';

  @override
  String get remove => '移除';

  @override
  String get environmentVariables => '环境变量';

  @override
  String get addVariable => '添加变量';

  @override
  String get noEnvironmentVariables => '没有环境变量';

  @override
  String get key => '键';

  @override
  String get value => '值';

  @override
  String environmentVariableKey(int number) {
    return '环境变量键 $number';
  }

  @override
  String environmentVariableValue(int number) {
    return '环境变量值 $number';
  }

  @override
  String get variableName => '变量名称';

  @override
  String get removeVariable => '移除变量';

  @override
  String get themePresets => '主题预设';

  @override
  String get themePresetsDescription => '跟随应用主题、应用精选配色，或微调各个颜色。';

  @override
  String get followApplicationThemeColors => '跟随应用主题颜色';

  @override
  String get followAppTheme => '跟随应用主题';

  @override
  String get followAppThemeDescription => '应用主题变化时，终端背景和文本会同步更新。';

  @override
  String get pickColor => '选择颜色';

  @override
  String get inheritingDefaultTerminalColor => '正在继承默认终端颜色';

  @override
  String currentColorValue(String color) {
    return '当前颜色 $color';
  }

  @override
  String get hexColorOrEmpty => '#RRGGBB 或留空';

  @override
  String get hex => '十六进制';

  @override
  String get palette => '调色板';

  @override
  String get hue => '色相';

  @override
  String get resetToDefault => '重置为默认值';

  @override
  String get pick => '选择';

  @override
  String get reset => '重置';

  @override
  String pickNamedColor(String name) {
    return '选择$name';
  }

  @override
  String resetNamedColor(String name) {
    return '重置$name';
  }

  @override
  String get colorPalette => '颜色调色板';

  @override
  String get hueSlider => '色相滑块';

  @override
  String get hexColorValidation => '请输入 #RRGGBB，或留空。';

  @override
  String get dynamicProfilesTopLevelObject => '顶层 JSON 必须是对象。';

  @override
  String get dynamicProfilesNoneFound => 'JSON 中未找到 Profile。';

  @override
  String dynamicProfilesInvalid(String error) {
    return '无法读取 Profile：$error';
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
      other: '已准备 $profiles 个 Profile',
    );
    String _temp1 = intl.Intl.pluralLogic(
      warnings,
      locale: localeName,
      other: ' • $warnings 个警告',
      zero: '',
    );
    return '$_temp0 • 新增 $added 个 • 替换 $replacements 个$_temp1';
  }

  @override
  String get replacesExisting => '替换现有项';

  @override
  String get dynamicProfiles => '动态 Profile';

  @override
  String get closeDynamicProfiles => '关闭动态 Profile';

  @override
  String get dynamicProfilesPasteHelp =>
      '请粘贴 iTerm2 动态 Profile JSON 文档。此本地构建仅会启动本地命令。';

  @override
  String get import => '导入';

  @override
  String get osc52Clipboard => 'OSC 52 剪贴板';

  @override
  String get osc52ClipboardDescription => '选择终端转义序列访问系统剪贴板的方式。';

  @override
  String get securityPermissions => '安全与权限';

  @override
  String get securityPermissionsDescription => '控制终端会话与应用及远程系统的交互行为，平衡安全与便捷。';

  @override
  String get sessionInteractionsPermissions => '会话交互与权限';

  @override
  String get sessionInteractionsPermissionsDescription =>
      '管理终端应用或远程系统发起的请求及其可能的安全风险。';

  @override
  String get securityImpact => '安全影响';

  @override
  String get currentPolicy => '当前策略';

  @override
  String get riskLevel => '风险等级';

  @override
  String riskLevelName(String level) {
    String _temp0 = intl.Intl.selectLogic(level, {
      'low': '低',
      'medium': '中',
      'high': '高',
      'other': '$level',
    });
    return '$_temp0';
  }

  @override
  String get behaviorBoundary => '行为边界';

  @override
  String get recommendation => '推荐理由';

  @override
  String get recommendedSetting => '推荐设置';

  @override
  String permissionRecommendation(String permission) {
    String _temp0 = intl.Intl.selectLogic(permission, {
      'osc52': '按 Profile 控制可在剪贴板便利性和敏感内容保护之间取得平衡。',
      'openUrl': '逐次确认可阻止远程内容在未明确同意时打开外部链接。',
      'attention': '拒绝非必要提醒可避免干扰；需要时可选择受限提醒。',
      'other': '保留明确的用户确认有助于控制终端发起的交互。',
    });
    return '$_temp0';
  }

  @override
  String get manageDecisions => '管理决定';

  @override
  String get terminalUrlRequests => '终端 URL 请求';

  @override
  String get terminalUrlRequestsDescription =>
      '选择 OSC 1337 OpenURL 请求能否申请权限。URL 永远不会自动打开。';

  @override
  String get terminalAttentionRequests => '终端注意请求';

  @override
  String get terminalAttentionRequestsDescription =>
      '选择 OSC 1337 RequestAttention 能否使用受限的 Dock 提醒或光标附近的视觉效果。请求不会激活应用或使其获得焦点。';

  @override
  String get terminalVariableReports => '终端变量报告';

  @override
  String get terminalVariableReportsDescription =>
      'OSC 1337 ReportVariable 请求首次会被拒绝。记住的决定仅适用于具名的 session.* 或 user.* 变量。';

  @override
  String get noRememberedDecisions => '没有记住的决定';

  @override
  String rememberedDecisionSummary(int count, int allowed, int denied) {
    return '已记住 $count 项 · 允许 $allowed 项 · 拒绝 $denied 项';
  }

  @override
  String get forgettingDecisionsHelp => '忘记决定会恢复安全的首次请求拒绝，并允许应用稍后再次询问。';

  @override
  String get allow => '允许';

  @override
  String get deny => '拒绝';

  @override
  String forgetDecisionFor(String name) {
    return '忘记 $name 的决定';
  }

  @override
  String get forgetAllDecisions => '忘记所有决定';

  @override
  String get dataService => '数据服务';

  @override
  String get dataServiceDescriptionLocalAvailable => '选择让应用启动本地数据服务，或连接远程数据服务。';

  @override
  String get dataServiceDescriptionRemoteOnly =>
      '无需数据服务即可建立一次性 SSH 连接；也可连接远程服务以保存 Profile 并同步。';

  @override
  String activeDataService(String service) {
    return '活动数据服务：$service';
  }

  @override
  String activeNow(String service) {
    return '当前活动：$service';
  }

  @override
  String currentlyRunning(String service) {
    return '当前运行：$service';
  }

  @override
  String get running => '运行中';

  @override
  String get selected => '已选择';

  @override
  String get dataServiceMode => '模式';

  @override
  String get apiService => 'API 服务';

  @override
  String get configurationAndStorage => '配置与数据存储';

  @override
  String get crossDeviceSync => '跨设备同步';

  @override
  String dataModeApiSummary(String deployment) {
    String _temp0 = intl.Intl.selectLogic(deployment, {
      'disabled': '不启动 API 进程',
      'local': '启动本地 API 服务',
      'remote': '连接远程 API 服务',
      'other': '$deployment',
    });
    return '$_temp0';
  }

  @override
  String dataModeStorageSummary(String deployment) {
    String _temp0 = intl.Intl.selectLogic(deployment, {
      'disabled': '使用本地 Shell 配置',
      'local': '此 Mac 上离线持久保存',
      'remote': '由远程服务统一保存',
      'other': '$deployment',
    });
    return '$_temp0';
  }

  @override
  String dataModeSyncSummary(String deployment) {
    String _temp0 = intl.Intl.selectLogic(deployment, {
      'disabled': '不同步',
      'local': '不同步',
      'remote': '登录后跨设备同步',
      'other': '$deployment',
    });
    return '$_temp0';
  }

  @override
  String get localTerminal => '本地终端';

  @override
  String get noDataService => '无数据服务';

  @override
  String get bundledLocalService => '内置本地服务';

  @override
  String get remoteService => '远程服务';

  @override
  String get localTerminalNoApiDescription =>
      '不启动 API 进程。仅使用本地 Shell 和 ~/.ssh/config 中的主机。';

  @override
  String get noDataServiceDescription => '不启动 API 进程。可建立不保存的一次性 SSH 连接。';

  @override
  String get bundledLocalServiceDescription =>
      '在此 Mac 上离线持久保存 API 数据和自定义 SSH Profile。';

  @override
  String get migrateRemoteApiData => '迁移远程 API 数据';

  @override
  String get migrateRemoteApiDataDescription =>
      '应用会启动临时内置 API，并在切换前合并远程资源。如果启动、导出或合并失败，远程数据会保留。';

  @override
  String get remoteServiceDescription =>
      '通过 HTTPS 使用自定义 SSH Profile、持久设置和跨设备同步。';

  @override
  String get migrateLocalApiData => '迁移本地 API 数据';

  @override
  String get migrateLocalApiDataDescription =>
      '应用会在切换前导出并合并本地资源。如果身份验证、导出或合并失败，本地数据会保留。';

  @override
  String get reconnectRequested => '已请求重新连接';

  @override
  String get reconnectSignIn => '重新连接 / 登录';

  @override
  String get remoteApiBaseUrl => '远程 API 基础 URL';

  @override
  String get loginPasswordHelp => '仅用于此次登录请求。';

  @override
  String get appleMasterKeyEncryptionDescription =>
      '加密使用由 iCloud 钥匙串自动管理的唯一 Ianvs 主密钥。';

  @override
  String get deviceMasterKeyEncryptionDescription =>
      '加密使用存储在此设备上的唯一 Ianvs 主密钥。迁移到其他平台时，请在主密钥管理中导出或导入。';

  @override
  String get dataServiceRestartNotice => '此选择会保存到应用配置中，并在重启后生效。';

  @override
  String get enterRemoteApiBaseUrl => '请输入远程 API 基础 URL。';

  @override
  String get invalidRemoteApiBaseUrl => '请输入有效的远程 API 基础 URL。';

  @override
  String get usernameValidation => '请使用 3–64 个小写字母、数字、.、_ 或 -。';

  @override
  String get passwordValidation => '请输入 12–72 个 UTF-8 字节。';

  @override
  String osc52PolicyName(String policy) {
    String _temp0 = intl.Intl.selectLogic(policy, {
      'disabled': '拒绝',
      'profile': '按 Profile',
      'allow': '允许',
      'ask': '询问',
      'other': '$policy',
    });
    return '$_temp0';
  }

  @override
  String osc52PolicyDescription(String policy) {
    String _temp0 = intl.Intl.selectLogic(policy, {
      'disabled': '阻止 OSC 52 剪贴板复制和粘贴读取请求。',
      'profile': '允许写入剪贴板，并在读取粘贴内容前询问。',
      'allow': '允许受信任终端会话使用 OSC 52，无需询问。',
      'ask': '每次 OSC 52 剪贴板写入或粘贴读取请求前都询问。',
      'other': '$policy',
    });
    return '$_temp0';
  }

  @override
  String openUrlPolicyName(String policy) {
    String _temp0 = intl.Intl.selectLogic(policy, {
      'disabled': '拒绝',
      'ask': '每次询问',
      'other': '$policy',
    });
    return '$_temp0';
  }

  @override
  String openUrlPolicyDescription(String policy) {
    String _temp0 = intl.Intl.selectLogic(policy, {
      'disabled': '阻止所有 OSC 1337 OpenURL 请求，且不显示对话框。',
      'ask': '活动终端每个获准请求都必须确认。',
      'other': '$policy',
    });
    return '$_temp0';
  }

  @override
  String requestAttentionPolicyName(String policy) {
    String _temp0 = intl.Intl.selectLogic(policy, {
      'disabled': '拒绝',
      'allow': '受限允许',
      'other': '$policy',
    });
    return '$_temp0';
  }

  @override
  String requestAttentionPolicyDescription(String policy) {
    String _temp0 = intl.Intl.selectLogic(policy, {
      'disabled': '阻止 OSC 1337 RequestAttention，但仍会处理取消请求。',
      'allow': '允许限频的 Dock 提醒和短暂的光标附近视觉效果。',
      'other': '$policy',
    });
    return '$_temp0';
  }

  @override
  String get osc5522PasteDeliveryFailed => '无法传递 OSC 5522 粘贴事件。';

  @override
  String get confirmPaste => '确认粘贴';

  @override
  String pasteCharacterLineCount(int characters, int lines) {
    String _temp0 = intl.Intl.pluralLogic(
      characters,
      locale: localeName,
      other: '$characters 个字符',
    );
    String _temp1 = intl.Intl.pluralLogic(
      lines,
      locale: localeName,
      other: '$lines 行',
    );
    return '要粘贴 $_temp0（共 $_temp1）吗？';
  }

  @override
  String get clearRecentReplayHistoryQuestion => '清除近期回放历史？';

  @override
  String get clearRecentReplayHistoryWarning => '此窗格的近期活动帧会从回放中移除。此操作无法撤销。';

  @override
  String get recordingReplayStarted => '已开始为回放录制。按键会被隐去；可用时会包含 Shell 命令元数据。';

  @override
  String recordingSavedNamed(String name) {
    return '录制已保存 · $name';
  }

  @override
  String get reveal => '显示';

  @override
  String couldNotOpenRecording(String error) {
    return '无法打开录制：$error';
  }

  @override
  String couldNotLoadRecordings(String error) {
    return '无法加载录制：$error';
  }

  @override
  String get recordingImported => '录制已导入';

  @override
  String couldNotImportRecording(String error) {
    return '无法导入录制：$error';
  }

  @override
  String get renameRecording => '重命名录制';

  @override
  String get recordingName => '录制名称';

  @override
  String get rename => '重命名';

  @override
  String couldNotRenameRecording(String error) {
    return '无法重命名录制：$error';
  }

  @override
  String couldNotRevealRecording(String error) {
    return '无法显示录制：$error';
  }

  @override
  String get recordingExported => '录制已导出';

  @override
  String couldNotExportRecording(String error) {
    return '无法导出录制：$error';
  }

  @override
  String get moveRecordingToTrashQuestion => '将录制移到废纸篓？';

  @override
  String recordingRemovedFromSaved(String name) {
    return '“$name”将从已保存的录制中移除。';
  }

  @override
  String get recordingMovedToTrash => '录制已移到废纸篓';

  @override
  String couldNotRemoveRecording(String error) {
    return '无法移除录制：$error';
  }

  @override
  String get noTerminalSessionOptionAvailable => '没有可用的终端会话选项。';

  @override
  String get closeTabRequiresActiveSession => '关闭标签页需要活动会话。';

  @override
  String get closeTabRequiresActiveTab => '关闭标签页需要活动标签页。';

  @override
  String get duplicateCwdRequiresProfileSession => '复制当前目录需要默认 Profile 和活动会话。';

  @override
  String get noCurrentDirectoryAvailable => '没有可用的当前目录。';

  @override
  String get remoteDirectoryCannotDuplicate => '远程报告的当前目录无法复制为本地会话。';

  @override
  String get noDuplicatedSessionCreated => '未创建重复会话。';

  @override
  String get noRecentlyClosedTabAvailable => '没有最近关闭的标签页。';

  @override
  String get noRecentlyClosedPaneForTab => '此标签页没有最近关闭的窗格。';

  @override
  String get noRecentlyClosedPaneReopened => '无法重新打开最近关闭的窗格。';

  @override
  String get closePaneRequiresActiveSession => '关闭窗格需要活动会话。';

  @override
  String get splitRightRequiresProfileSession => '向右拆分需要默认 Profile 和活动会话。';

  @override
  String get splitRightUnavailable => '无法向右拆分。';

  @override
  String get splitDownRequiresProfileSession => '向下拆分需要默认 Profile 和活动会话。';

  @override
  String get splitDownUnavailable => '无法向下拆分。';

  @override
  String get focusNextPaneRequiresSession => '聚焦下一个窗格需要活动会话。';

  @override
  String get noNextPaneAvailable => '没有下一个可用窗格。';

  @override
  String get focusPreviousPaneRequiresSession => '聚焦上一个窗格需要活动会话。';

  @override
  String get noPreviousPaneAvailable => '没有上一个可用窗格。';

  @override
  String get resizePaneRequiresSession => '调整窗格大小需要活动会话。';

  @override
  String get resizePaneRequiresTwoPanes => '调整窗格大小至少需要两个窗格。';

  @override
  String get swapPaneRequiresSession => '交换窗格需要活动会话。';

  @override
  String get swapPaneRequiresTwoPanes => '交换窗格至少需要两个窗格。';

  @override
  String get zoomPaneRequiresSession => '缩放窗格需要活动会话。';

  @override
  String get zoomPaneRequiresTwoPanes => '缩放窗格至少需要两个窗格。';

  @override
  String get copyRequiresSession => '复制需要活动会话。';

  @override
  String get copyRequiresSelectionController => '复制需要活动的选择控制器。';

  @override
  String get copyCommandOutputRequiresSession => '复制命令输出需要活动会话。';

  @override
  String get noCommandOutputAvailable => '没有可复制的命令输出。';

  @override
  String get copyModeRequiresSession => '复制模式需要活动会话。';

  @override
  String get pasteRequiresSession => '粘贴需要活动会话。';

  @override
  String get advancedPasteRequiresSession => '高级粘贴需要活动会话。';

  @override
  String get pasteHistoryRequiresSession => '粘贴历史需要活动会话。';

  @override
  String get replayRequiresSession => '回放近期活动需要活动会话。';

  @override
  String get readOnlyRequiresSession => '只读模式需要活动会话。';

  @override
  String get readOnlyEnabledNotice => '只读模式已启用。此窗格的输入已被阻止。';

  @override
  String get readOnlyDisabledNotice => '只读模式已停用。此窗格可以输入。';

  @override
  String get clearBufferRequiresSession => '清除缓冲区需要活动会话。';

  @override
  String get bufferClearedCommandKept => '缓冲区已清除，当前命令行已保留。';

  @override
  String get clearBufferRequiresNative => '清除缓冲区需要原生运行时支持。';

  @override
  String get bufferCleared => '缓冲区已清除。';

  @override
  String get clearBufferUnsupported => '此运行时不支持清除缓冲区。';

  @override
  String get globalSearchRequiresTab => '全局搜索至少需要一个标签页。';

  @override
  String get autocompleteRequiresSession => '自动补全需要活动会话。';

  @override
  String get autoComposerRequiresSession => '自动编写器需要活动会话。';

  @override
  String get searchRequiresSession => '搜索需要活动会话。';

  @override
  String get previousPromptRequiresSession => '上一个提示符需要活动会话。';

  @override
  String get nextPromptRequiresSession => '下一个提示符需要活动会话。';

  @override
  String get selectCommandOutputRequiresSession => '选择命令输出需要活动会话。';

  @override
  String get shellIntegrationRequiresSession => 'Shell 集成工具需要活动会话。';

  @override
  String get openRecentDirectoryRequiresSession => '打开最近目录需要活动会话。';

  @override
  String get noRecentDirectoryAvailable => '没有可用的最近目录。';

  @override
  String get tmuxIntegrationRequiresSession => 'tmux 集成需要活动会话。';

  @override
  String get coprocessRequiresSession => '协同进程需要活动会话。';

  @override
  String get annotationsRequireSession => '注释需要活动会话。';

  @override
  String get capturedOutputRequiresSession => '捕获的输出需要活动会话。';

  @override
  String get passwordManagerRequiresSession => '密码管理器需要活动会话。';

  @override
  String get hotkeyWindowUnavailable => '快捷键窗口不可用。';

  @override
  String get layoutTemplateRequiresProfileSession =>
      '应用布局模板需要默认 Profile 和活动会话。';

  @override
  String get noActiveTabForLayoutTemplates => '没有可用于布局模板的活动标签页。';

  @override
  String get twoPaneLayoutAlreadySatisfied => '当前已满足双窗格布局模板。';

  @override
  String get layoutTemplateUnavailable => '无法应用布局模板。';

  @override
  String get exportScrollbackRequiresSession => '导出回滚内容需要活动会话。';

  @override
  String get noVisibleContentToExport => '没有可导出的可见终端内容。';

  @override
  String get scrollbackExported => '回滚内容已导出';

  @override
  String get exportedTerminalScrollback => '终端回滚内容已导出。';

  @override
  String get exportDiagnosticsRequiresSession => '导出诊断需要活动会话。';

  @override
  String get diagnosticsExportUnavailable => '活动会话无法导出诊断。';

  @override
  String get diagnosticsExported => '诊断已导出';

  @override
  String get exportedTerminalDiagnostics => '终端诊断已导出。';

  @override
  String commandFinishedNotificationsSaved(String enabled) {
    String _temp0 = intl.Intl.selectLogic(enabled, {
      'true': '启用',
      'other': '停用',
    });
    return '命令完成通知已$_temp0并保存。';
  }

  @override
  String bellNotificationsSaved(String enabled) {
    String _temp0 = intl.Intl.selectLogic(enabled, {
      'true': '启用',
      'other': '停用',
    });
    return '响铃通知已$_temp0并保存。';
  }

  @override
  String activityMonitorSaved(String enabled) {
    String _temp0 = intl.Intl.selectLogic(enabled, {
      'true': '启用',
      'other': '停用',
    });
    return '活动监视器已$_temp0并保存。';
  }

  @override
  String unableSaveNotifications(String error) {
    return '无法保存通知：$error';
  }

  @override
  String get unableSaveCommandFinishedNotifications => '无法保存命令完成通知。';

  @override
  String get unableSaveBellNotifications => '无法保存响铃通知。';

  @override
  String get unableSaveActivityMonitor => '无法保存活动监视器通知。';

  @override
  String get noDefaultProfileAvailable => '没有可用的默认 Profile。';

  @override
  String get addAnotherPaneForAction => '请添加另一个窗格后再使用此操作。';

  @override
  String unavailableReason(String reason) {
    return '不可用：$reason';
  }

  @override
  String get duplicateCurrentDirectory => '复制当前目录';

  @override
  String get applyTwoPaneLayout => '应用双窗格布局';

  @override
  String get tabAlreadyMultiplePanes => '此标签页已有多个窗格。';

  @override
  String get growActivePane => '增大活动窗格';

  @override
  String get swapActivePane => '交换活动窗格';

  @override
  String get closeActivePane => '关闭活动窗格';

  @override
  String get movedToNewTab => '已移到新标签页';

  @override
  String panePosition(int index, int count) {
    return '窗格 $index/$count';
  }

  @override
  String get splitRight => '向右拆分';

  @override
  String get splitDown => '向下拆分';

  @override
  String splitRightUnavailableReason(String reason) {
    return '无法向右拆分：$reason';
  }

  @override
  String splitDownUnavailableReason(String reason) {
    return '无法向下拆分：$reason';
  }

  @override
  String get activePane => '活动窗格';

  @override
  String get inactivePane => '非活动窗格';

  @override
  String paneContextUntitled(String id, String state) {
    return '窗格：$id · $state';
  }

  @override
  String paneContextTitled(String title, String id, String state) {
    return '窗格：$title（$id）· $state';
  }

  @override
  String get openLink => '打开链接';

  @override
  String get copyLink => '复制链接';

  @override
  String get copyLinkText => '复制链接文本';

  @override
  String get showTarget => '显示目标';

  @override
  String get copiedLinkTarget => '链接目标已复制';

  @override
  String get copiedLinkText => '链接文本已复制';

  @override
  String get unknown => '未知';

  @override
  String blockedLinkScheme(String scheme) {
    return '已阻止链接协议：$scheme';
  }

  @override
  String get blockedFileLink => '已阻止文件链接';

  @override
  String get couldNotOpenLink => '无法打开链接';

  @override
  String couldNotOpenLinkDetails(String error) {
    return '无法打开链接：$error';
  }

  @override
  String get openLocalFileLinkQuestion => '打开本地文件链接？';

  @override
  String get terminalRequestsLocalFile => '终端正在请求打开本地文件 URL。';

  @override
  String sourceValue(String source) {
    return '来源：$source';
  }

  @override
  String linkTextOpensTarget(String text, String target) {
    return '链接文本“$text”会打开 $target';
  }

  @override
  String linkTargetValue(String target) {
    return '链接目标：$target';
  }

  @override
  String get clickToFocusPane => '点击以聚焦此窗格。';

  @override
  String get remoteContextReported => 'Shell 集成报告了远程上下文。';

  @override
  String hostValue(String host) {
    return '主机：$host';
  }

  @override
  String userValue(String user) {
    return '用户：$user';
  }

  @override
  String get localFileActionsDisabledRemote => '远程路径仍会停用本地文件操作。';

  @override
  String get terminalProgressInPane => '此窗格中的终端进度。';

  @override
  String osc1337BadgeValue(String badge) {
    return 'OSC 1337 徽章：$badge';
  }

  @override
  String get alternateScreenActive => '备用屏幕缓冲区已启用。';

  @override
  String mouseReportingActive(String mode, String encoding) {
    return '鼠标报告已启用：$mode，$encoding。';
  }

  @override
  String get mimePasteActive => 'OSC 5522 粘贴事件已启用，并优先于括号粘贴。';

  @override
  String get bracketedPasteActive => '括号粘贴模式已启用。';

  @override
  String get focusReportingActive => '焦点报告已启用。应用会收到焦点进入和离开事件。';

  @override
  String get synchronizedOutputActive => '同步输出模式已启用。在应用刷新前，中间更新会被保留。';

  @override
  String get readOnlyPaneActive => '此窗格已启用只读模式，输入和粘贴发送会被阻止。';

  @override
  String get terminalRequestedAttention => '终端请求注意';

  @override
  String dragPaneToSplit(String title) {
    return '拖动 $title 以拆分，或将其移到标签栏';
  }

  @override
  String dropToTarget(String target) {
    return '放到$target';
  }

  @override
  String get unzoomPane => '取消窗格缩放';

  @override
  String get zoomPane => '缩放窗格';

  @override
  String get localFile => '本地文件';

  @override
  String protocolHost(String protocol, String host) {
    return '$protocol 主机：$host';
  }

  @override
  String get openTerminalRequestedUrlQuestion => '打开终端请求的 URL？';

  @override
  String get terminalRequestedUrlWarning => '活动终端请求打开此 URL 的权限。终端输出可能不可信。';

  @override
  String destinationValue(String destination) {
    return '目标：$destination';
  }

  @override
  String get osc1337OpenUrlBlocked => '已阻止 OSC 1337 Open URL';

  @override
  String get osc1337OpenUrlSourceInactive => '已阻止 OSC 1337 Open URL：来源不再活动';

  @override
  String get allowFutureVariableReportsQuestion => '允许未来的变量报告？';

  @override
  String get variableReportDeniedHelp => '当前请求已被拒绝并收到空响应。请选择未来的终端程序能否读取此变量。';

  @override
  String get variable => '变量';

  @override
  String get variableReportPrivacyHelp =>
      'Ianvs 只报告会话拥有的标题、尺寸、Shell 上下文和 user.* 值。此请求绝不会读取主机环境变量或文件。';

  @override
  String get notNow => '暂不';

  @override
  String get alwaysAllow => '始终允许';

  @override
  String get alwaysDeny => '始终拒绝';

  @override
  String get variableDecisionSourceInactive => '未保存变量报告决定：来源不再活动';

  @override
  String futureVariableReportsAllowed(String name) {
    return '已允许未来报告 $name';
  }

  @override
  String futureVariableReportsDenied(String name) {
    return '已拒绝未来报告 $name';
  }

  @override
  String receivedFile(String name, String size) {
    return '已接收 $name（$size）';
  }

  @override
  String allowClipboardCopyQuestion(String protocol) {
    return '允许 $protocol 复制到剪贴板？';
  }

  @override
  String allowPasteReadQuestion(String protocol) {
    return '允许 $protocol 读取粘贴内容？';
  }

  @override
  String allowClipboardWriteQuestion(String protocol) {
    return '允许 $protocol 写入剪贴板？';
  }

  @override
  String allowClipboardReadQuestion(String protocol) {
    return '允许 $protocol 读取剪贴板？';
  }

  @override
  String get alwaysAllowLower => '始终允许';

  @override
  String get session => '会话';

  @override
  String get mimeTypes => 'MIME 类型';

  @override
  String get application => '应用程序';

  @override
  String get size => '大小';

  @override
  String characterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个字符',
    );
    return '$_temp0';
  }

  @override
  String get previewUnavailable => '预览不可用';

  @override
  String get clipboardEmpty => '剪贴板为空';

  @override
  String get previewTruncated => '预览已截断';

  @override
  String get terminalRequestsClipboardRead => '终端正在请求剪贴板内容；若允许，内容会发送回会话。';

  @override
  String get terminalRequestsClipboardWrite => '终端想要将以下文本写入剪贴板。';

  @override
  String get alwaysAllowClipboardHelp =>
      '“始终允许”仅会为当前终端会话放行未来使用完全相同应用名称和密码的 OSC 5522 剪贴板读写。';

  @override
  String get trustedSessionsOnly => '仅对受信任的会话允许此操作。';

  @override
  String get sessionEnded => '会话已结束';

  @override
  String sessionExitedBody(String session, String code) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'none': '',
      'other': '，退出码 $code',
    });
    return '$session已退出$_temp0。';
  }

  @override
  String sessionNamed(String id) {
    return '会话 $id';
  }

  @override
  String paneNamed(int number) {
    return '窗格 $number';
  }

  @override
  String get newTerminalOutputAvailable => '有新的终端输出。';

  @override
  String get osc1337OpenUrlBlockedByPolicy => '策略已阻止 OSC 1337 Open URL';

  @override
  String get couldNotOpenSaveDialog => '无法打开保存对话框';

  @override
  String get receivedFileDiscarded => '收到的文件已丢弃';

  @override
  String get receivedFileUnavailable => '收到的文件已不可用';

  @override
  String couldNotSaveFile(String name) {
    return '无法保存 $name';
  }

  @override
  String savedFile(String name) {
    return '已保存 $name';
  }

  @override
  String fileDownloadRejected(String reason) {
    return '文件下载被拒绝：$reason';
  }

  @override
  String get fileUploadRequestBlocked => '文件上传请求已阻止';

  @override
  String zmodemTransportFailed(String session, int bytes, int chunks) {
    return '会话 $session 的 ZMODEM 传输失败：$chunks 个排队写入中的 $bytes 字节未确认。终端连接已关闭。';
  }

  @override
  String notificationInSession(String title, String session) {
    return '$session 中的$title';
  }

  @override
  String get zmodemFilePreserved => 'ZMODEM 文件已保留';

  @override
  String get zmodemFilePreservedBody => 'ZMODEM 发布失败。完整文件已保留；请聚焦窗格以显示或丢弃。';

  @override
  String get zmodemReceiveCompleted => 'ZMODEM 接收完成';

  @override
  String get zmodemSendCompleted => 'ZMODEM 发送完成';

  @override
  String get zmodemTransferCancelled => 'ZMODEM 传输已取消';

  @override
  String get zmodemPreservedUnavailable => 'ZMODEM 发布失败；保留的文件无法显示';

  @override
  String zmodemTransferFailed(String reason) {
    return 'ZMODEM 传输失败：$reason';
  }

  @override
  String get protocolError => '协议错误';

  @override
  String get zmodemTransferUpdate => 'ZMODEM 传输更新';

  @override
  String get zmodemTransferNeedsAttention => 'ZMODEM 传输需要处理';

  @override
  String get zmodemStateLost => '事件中断后传输状态丢失。请聚焦窗格以重试取消。';

  @override
  String get remoteSkippedZmodemFile => '远程端跳过了一个 ZMODEM 文件；继续处理批次';

  @override
  String remoteSkippedNamedFile(String name) {
    return '远程端跳过了 $name；继续处理批次';
  }

  @override
  String get zmodemDirectionUnsupported => '此终端运行时不支持这个方向的 ZMODEM 传输。';

  @override
  String get zmodemFileSelectionUnavailable => '此平台无法选择 ZMODEM 文件。';

  @override
  String get retryCancellation => '请重试取消。';

  @override
  String get transferWasCancelled => '传输已取消。';

  @override
  String get inactiveTransferWasCancelled => '非活动传输已取消。';

  @override
  String get focusPaneRetryCancellation => '请聚焦窗格以重试取消。';

  @override
  String get zmodemRequestCancelled => 'ZMODEM 请求已取消';

  @override
  String get zmodemRequestNeedsAttention => 'ZMODEM 请求需要处理';

  @override
  String get couldNotCancelAfterSessionChanged => '会话更改后无法取消。请重试或再次取消。';

  @override
  String remoteZmodemRequestCancelled(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'send': '发送',
      'other': '接收',
    });
    return '远程$_temp0请求因窗格处于非活动状态而被取消。';
  }

  @override
  String remoteZmodemRequestCancelFailed(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'send': '发送',
      'other': '接收',
    });
    return '无法取消远程$_temp0请求。请聚焦窗格后重试。';
  }

  @override
  String get zmodemPickerAlreadyOpen => '上一个 ZMODEM 文件选择器仍然打开。请关闭后重试此传输。';

  @override
  String get zmodemDestinationSelectionUnavailable => '此平台无法选择 ZMODEM 目标目录。';

  @override
  String get couldNotOpenDestinationPicker => '无法打开目标目录选择器。请重试或取消传输。';

  @override
  String get sessionChangedCancellationFailed => '会话已更改且取消失败。请重试取消。';

  @override
  String get destinationSelectionCancelled => '已取消选择目标目录。请重试或取消传输。';

  @override
  String get couldNotAuthorizeDestination => '无法授权此目标目录。请重试或取消传输。';

  @override
  String get couldNotOpenFilePicker => '无法打开文件选择器。请重试或取消传输。';

  @override
  String get fileSelectionCancelled => '已取消选择文件。请重试或取消传输。';

  @override
  String get zmodemFileLimit => '最多可发送 256 个文件。请减少文件后重试。';

  @override
  String get couldNotAuthorizeFiles => '无法授权这些文件。请重试或取消传输。';

  @override
  String get zmodemPickerResultIgnored => 'ZMODEM 传输已结束，文件选择结果未使用。';

  @override
  String get couldNotCancelZmodem => '无法取消 ZMODEM 传输。请重试取消。';

  @override
  String get couldNotRevealExport => '此平台无法显示导出文件';

  @override
  String couldNotRevealExportDetails(String error) {
    return '无法显示导出文件：$error';
  }

  @override
  String get zmodemRecoveryUnavailable => '保留的 ZMODEM 文件已不可用';

  @override
  String get zmodemRecoveryResolveFailed => '无法解析保留的 ZMODEM 文件，请重试';

  @override
  String get couldNotRevealPreservedZmodem => '无法显示保留的 ZMODEM 文件';

  @override
  String get couldNotReleaseZmodemRecovery => '无法释放 ZMODEM 恢复令牌';

  @override
  String get couldNotDismissZmodemRecovery => '无法关闭 ZMODEM 恢复通知';

  @override
  String get preservedZmodemFile => '保留的 ZMODEM 文件';

  @override
  String get permanentlyDiscardFileQuestion => '永久丢弃文件？';

  @override
  String zmodemDiscardWarning(String filename) {
    return '$filename 是 Ianvs Terminal 保留的唯一恢复副本。永久丢弃后文件将被删除，且无法撤销。';
  }

  @override
  String get discardFile => '丢弃文件';

  @override
  String zmodemPreservedSemantics(String filename, String source) {
    return 'ZMODEM 文件已保留。$filename，来源：$source。';
  }

  @override
  String zmodemPublishFailedPreserved(String filename, String source) {
    return 'ZMODEM 发布失败。完整文件已保留为 $filename，来源：$source。';
  }

  @override
  String get permanentlyDeletePreservedZmodem => '永久删除保留的 ZMODEM 文件';

  @override
  String get discardFileEllipsis => '丢弃文件…';

  @override
  String get zmodemProgress => 'ZMODEM 进度';

  @override
  String get indeterminate => '不确定';

  @override
  String percentValue(int percent) {
    return '$percent%';
  }

  @override
  String get cancelling => '正在取消…';

  @override
  String notificationButton(int number) {
    return '按钮 $number';
  }

  @override
  String notificationAction(int number) {
    return '通知操作 $number';
  }

  @override
  String get closeAndReportToTerminal => '关闭并报告给终端进程';

  @override
  String get removeNotification => '移除此通知';

  @override
  String get profileTabColor => '配置文件标签页颜色';

  @override
  String get osc21337StatusIndicator => 'OSC 21337 会话状态指示器';

  @override
  String get dataServiceWarning => '数据服务警告。';

  @override
  String get dismissDataServiceWarning => '关闭数据服务警告';

  @override
  String replaySource(String source) {
    return '回放来源：$source';
  }

  @override
  String get dragResizePanesHorizontally => '拖动以水平调整窗格大小';

  @override
  String get dragResizePanesVertically => '拖动以垂直调整窗格大小';

  @override
  String get completions => '补全建议';

  @override
  String completePrefix(String prefix) {
    return '补全“$prefix”';
  }

  @override
  String get previousCompletion => '上一个补全建议';

  @override
  String get nextCompletion => '下一个补全建议';

  @override
  String get closeCompletions => '关闭补全建议';

  @override
  String get composeCommand => '编写命令';

  @override
  String get sendCommand => '发送命令';

  @override
  String get closeComposer => '关闭命令编辑器';

  @override
  String get terminalKeyboardShortcuts => '终端键盘快捷键';

  @override
  String get decreaseTerminalTextSize => '减小终端文字';

  @override
  String get resetTerminalTextSize => '重置终端文字大小';

  @override
  String get increaseTerminalTextSize => '增大终端文字';

  @override
  String insertTerminalKey(String key) {
    return '输入 $key';
  }

  @override
  String get dismissKeyboard => '收起键盘';

  @override
  String get sshHostKeyPromptInactive => 'SSH 主机密钥确认已失效。';

  @override
  String get sshAuthenticationPromptInactive => 'SSH 身份验证请求已失效。';

  @override
  String get dataServiceConfigurationUnavailable => '此构建版本不支持数据服务配置。';

  @override
  String get remoteAuthenticationUnavailable => '此构建版本不支持远程身份验证。';

  @override
  String get localApiMigrationUnavailable => '当前内置本地 API 无法用于迁移。';

  @override
  String get remoteToLocalMigrationUnavailable => '此构建版本不支持从远程迁移到本地。';

  @override
  String migrationToRemoteSummary(
    int resources,
    int created,
    int updated,
    int skipped,
  ) {
    return '已迁移 $resources 个本地资源：新建 $created 个、更新 $updated 个、$skipped 个已是最新。重启应用后将使用远程 API。';
  }

  @override
  String migrationToLocalSummary(
    int resources,
    int created,
    int updated,
    int skipped,
  ) {
    return '已迁移 $resources 个远程资源：新建 $created 个、更新 $updated 个、$skipped 个已是最新。重启应用后将使用内置本地 API。';
  }

  @override
  String get dataServiceConfigurationSaved => '数据服务配置已保存。重启应用后生效。';

  @override
  String unableToSaveDataServiceConfiguration(String error) {
    return '无法保存数据服务配置：$error';
  }

  @override
  String get deleteProfileQuestion => '删除配置文件？';

  @override
  String deleteProfileWarning(String name) {
    return '删除“$name”？已打开的终端标签页会保留当前会话设置。';
  }

  @override
  String deletedProfile(String name) {
    return '已删除配置文件“$name”。';
  }

  @override
  String get profileWasNotDeleted => '未能删除配置文件';

  @override
  String profileStillStored(String name, String destination) {
    return '“$name”仍存储在$destination中。';
  }

  @override
  String get newSshProfile => '新建 SSH 配置文件';

  @override
  String savedProfileTo(String name, String destination) {
    return '已将配置文件“$name”保存到$destination。';
  }

  @override
  String profileStorageDestination(String deployment) {
    String _temp0 = intl.Intl.selectLogic(deployment, {
      'remote': '远程服务',
      'local': '内置本地服务',
      'other': '配置文件存储',
    });
    return '$_temp0';
  }

  @override
  String get profileWasNotSaved => '未能保存配置文件';

  @override
  String profileNotWritten(String name, String destination) {
    return '“$name”未写入$destination，因此不会出现在其他设备上。';
  }

  @override
  String get profileSaveFailureConnectOnceHelp => '你可以取消并重试保存，也可以明确选择仅连接一次。';

  @override
  String get cancelConnection => '取消连接';

  @override
  String get ok => '确定';

  @override
  String get connectOnceWithoutSaving => '不保存，仅连接一次';

  @override
  String get profilesChangedElsewhere => '保存期间其他设备上的配置文件已更改。请重新加载配置文件后重试。';

  @override
  String get remoteServiceAuthenticationExpired =>
      '远程服务会话已失去身份验证。请打开数据服务设置，重新登录后再保存。';

  @override
  String get remoteServiceTimeout => '远程服务未及时响应。请检查网络连接后重试。';

  @override
  String remoteServiceRejectedSave(int status, String code, String message) {
    return '远程服务拒绝保存（$status/$code）：$message';
  }

  @override
  String remoteServiceInvalidResponse(String message) {
    return '远程服务返回了无效响应：$message';
  }

  @override
  String get persistentSshProfilesRequireService =>
      '持久 SSH 配置文件需要已连接的内置本地服务或远程服务。请先打开数据服务设置并连接服务。';

  @override
  String saveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String dynamicProfilesImported(
    int total,
    int added,
    int replaced,
    int warnings,
  ) {
    return '已导入 $total 个动态配置文件（新增 $added 个、替换 $replaced 个、警告 $warnings 条）。';
  }

  @override
  String get passwordSendBlockedNoPrompt => '密码发送已阻止：当前没有活动的密码提示。';

  @override
  String sshProfileStored(String action, String name, String destination) {
    String _temp0 = intl.Intl.selectLogic(action, {
      'saved': '保存',
      'other': '导入',
    });
    return '已将 SSH 配置文件“$name”$_temp0到$destination。';
  }

  @override
  String get dragReplayControls => '拖动回放控件。双击可重置位置。';

  @override
  String get localTerminalObjectiveComplete => '本地终端目标已完成';

  @override
  String get localTerminalObjectiveBlocked => '本地终端目标受阻';

  @override
  String get milestones => '里程碑';

  @override
  String get backlog => '待办';

  @override
  String get verification => '验证';

  @override
  String get blockedMilestones => '受阻的里程碑';

  @override
  String get missingProductionMilestones => '缺失的生产里程碑';

  @override
  String get blockedRealWiringBacklog => '受阻的真实接线待办';

  @override
  String get missingRealWiringBacklog => '缺失的真实接线待办';

  @override
  String get blockedVerificationGates => '受阻的验证关卡';

  @override
  String get missingVerificationGates => '缺失的验证关卡';

  @override
  String get completion => '完成情况';

  @override
  String get unavailableInCurrentContext => '当前上下文中不可用。';

  @override
  String get terminalModeAlt => '备用屏幕';

  @override
  String get terminalModeMouse => '鼠标';

  @override
  String get terminalModeMimePaste => 'MIME 粘贴';

  @override
  String get terminalModePaste => '粘贴';

  @override
  String get terminalModeFocus => '焦点';

  @override
  String get terminalModeKeys => '按键';

  @override
  String get terminalModeSync => '同步';

  @override
  String get terminalModeReadOnly => '只读';

  @override
  String get saveImageAs => '图像另存为…';

  @override
  String get copyImage => '复制图像';

  @override
  String get openImage => '打开图像';

  @override
  String get inspect => '检查';

  @override
  String get imageInformation => '图像信息';

  @override
  String get protocol => '协议';

  @override
  String get sourceSize => '源尺寸';

  @override
  String get displaySize => '显示尺寸';

  @override
  String get visibleArea => '可见区域';

  @override
  String get cellPosition => '单元格位置';

  @override
  String get renderId => '渲染 ID';

  @override
  String get placementId => '放置 ID';

  @override
  String get asset => '资源';

  @override
  String get couldNotOpenImageSaveDialog => '无法打开图像保存对话框';

  @override
  String get couldNotSaveImage => '无法保存图像';

  @override
  String get savedImage => '图像已保存';

  @override
  String get couldNotCopyImage => '无法复制图像';

  @override
  String get copiedImage => '图像已复制';

  @override
  String get unfoldTerminalBlock => '展开终端块';

  @override
  String get foldTerminalBlock => '折叠终端块';

  @override
  String get unfoldBlock => '展开块';

  @override
  String get foldBlock => '折叠块';

  @override
  String get renderedTerminalDocument => '已渲染的终端文档';

  @override
  String get closeRenderedDocument => '关闭已渲染文档';

  @override
  String get closeTerminalTextDocument => '关闭终端文本文档';

  @override
  String get openTerminalImagePreview => '打开终端图像预览';

  @override
  String get terminalImagePreview => '终端图像预览';

  @override
  String get closeImagePreview => '关闭图像预览';

  @override
  String get current => '当前会话';

  @override
  String oscClipboardCopied(String protocol, int count) {
    return '$protocol 已将 $count 个字符复制到剪贴板';
  }

  @override
  String oscClipboardCopyBlocked(String protocol) {
    return '策略已阻止 $protocol 复制剪贴板';
  }

  @override
  String oscClipboardCopyInvalid(String protocol) {
    return '$protocol 剪贴板复制已忽略：负载无效';
  }

  @override
  String oscPasteReadReplied(String protocol, int count) {
    return '$protocol 已返回 $count 个粘贴字符';
  }

  @override
  String oscPasteReadBlocked(String protocol) {
    return '策略已阻止 $protocol 读取粘贴内容';
  }

  @override
  String oscPasteReadInvalid(String protocol) {
    return '$protocol 粘贴读取已忽略：负载无效';
  }

  @override
  String oscMimeWriteSucceeded(int types, int bytes) {
    return 'OSC 5522 已写入 $types 种 MIME 类型（$bytes 字节）';
  }

  @override
  String get oscMimeWriteBlocked => '策略已阻止 OSC 5522 MIME 剪贴板写入';

  @override
  String get oscMimeWriteFailed => 'OSC 5522 MIME 剪贴板写入失败';

  @override
  String oscMimeReadSucceeded(int types, int bytes) {
    return 'OSC 5522 已返回 $types 种 MIME 类型（$bytes 字节）';
  }

  @override
  String get oscMimeReadBlocked => '策略已阻止 OSC 5522 MIME 剪贴板读取';

  @override
  String get oscMimeReadFailed => 'OSC 5522 MIME 剪贴板读取失败';

  @override
  String get terminalNotification => '终端通知';

  @override
  String notificationOnRemoteInSession(
    String title,
    String remote,
    String session,
  ) {
    return '$session 中 $remote 上的$title';
  }

  @override
  String get bell => '响铃';

  @override
  String get terminalRequestedAttentionBody => '终端请求关注。';

  @override
  String get commandFinished => '命令已完成';

  @override
  String commandFinishedInSession(String session) {
    return '$session 中的命令已完成';
  }

  @override
  String commandFinishedOnRemoteInSession(String remote, String session) {
    return '$session 中 $remote 上的命令已完成';
  }

  @override
  String terminalSettingsCouldNotLoad(String error) {
    return '无法加载终端设置：$error';
  }

  @override
  String shortcutValue(String shortcut) {
    return '快捷键：$shortcut';
  }

  @override
  String errorValue(String error) {
    return '错误：$error';
  }

  @override
  String get backInShell => '返回终端';

  @override
  String get newOutput => '新输出';

  @override
  String get clickFocusFirstPaneWithNewOutput => '点击以聚焦第一个有新输出的窗格。';

  @override
  String get newOutputInSplitPane => '分屏窗格中有新输出。';

  @override
  String newOutputInSplitPanes(int count) {
    return '$count 个分屏窗格中有新输出。';
  }

  @override
  String get hiddenTabsHaveNewOutput => '隐藏标签页中有新输出';

  @override
  String get newOutputInHiddenTab => '隐藏标签页中有新输出。';

  @override
  String tabSessionDetails(String title, String id) {
    return '标签页：$title（$id）';
  }

  @override
  String get paneAlreadyFocused => '窗格已聚焦。';

  @override
  String newOutputInHiddenPanes(int count) {
    return '$count 个隐藏窗格中有新输出。';
  }

  @override
  String get noActivePaneAvailable => '没有可用的活动窗格。';

  @override
  String paneTooNarrow(int columns) {
    return '另一个窗格将窄于 $columns 列。';
  }

  @override
  String paneTooShort(int rows) {
    return '另一个窗格将短于 $rows 行。';
  }

  @override
  String get unzoomActivePaneToManage => '请取消活动窗格缩放后再管理其他窗格。';

  @override
  String closeNamedTab(String title) {
    return '关闭$title标签页';
  }

  @override
  String closeNamed(String title) {
    return '关闭$title';
  }

  @override
  String osc21337Status(String status) {
    return 'OSC 21337 状态：$status';
  }

  @override
  String get remoteApiBaseUrlWithoutCredentials =>
      '远程数据 API URL 必须是 http(s) 基础 URL，且不能包含凭据、查询参数或片段。';

  @override
  String get remoteApiRequiresHttps =>
      '远程数据 API 身份验证需要 HTTPS。HTTP 仅允许用于环回开发端点。';

  @override
  String get shell => 'Shell';

  @override
  String fieldIsRequired(String field) {
    return '$field为必填项';
  }

  @override
  String fieldMustBePositiveInteger(String field) {
    return '$field必须是正整数';
  }

  @override
  String fieldMustBeAtMost(String field, int maximum) {
    return '$field必须不大于 $maximum';
  }

  @override
  String fieldMustBeGreaterThanZero(String field) {
    return '$field必须大于 0';
  }

  @override
  String get environmentKeyRequired => '键为必填项';

  @override
  String get environmentKeyUnique => '键必须唯一';

  @override
  String get newProfileDefaultName => '新建 Profile';

  @override
  String terminalTabSemantics(String title) {
    return '$title标签页';
  }

  @override
  String terminalStatus(String status) {
    return '状态：$status';
  }

  @override
  String terminalStatusFromActivePane(String status) {
    return '活动窗格状态：$status';
  }

  @override
  String get statusIndicatorActive => '状态指示器已启用';

  @override
  String get statusIndicatorActiveOnActivePane => '活动窗格的状态指示器已启用';

  @override
  String terminalBadgeFromPane(String badge, String state) {
    return '来自$state的徽章：$badge';
  }

  @override
  String badgeSemanticsValue(String badge) {
    return '徽章：$badge';
  }

  @override
  String plusOtherPaneBadges(int count) {
    return '另有 $count 个窗格徽章';
  }

  @override
  String signalFromPane(String state) {
    return '，来自$state';
  }

  @override
  String terminalSignalSummary(String title, String summary, String scope) {
    return '$title：$summary$scope';
  }

  @override
  String plusOtherPaneSignals(int count) {
    return '另有 $count 个窗格信号';
  }

  @override
  String get newOutputLower => '新输出';

  @override
  String get newOutputInSplitPaneLower => '分屏窗格中有新输出';

  @override
  String commandShortcut(int index) {
    return 'Command $index';
  }

  @override
  String get otherPaneBadges => '其他窗格徽章：';

  @override
  String terminalBadgeValue(String badge) {
    return '终端徽章：$badge';
  }

  @override
  String otherPaneBadgeCount(int count) {
    return '其他 $count 个窗格徽章';
  }

  @override
  String additionalOsc1337Badge(String badge) {
    return '其他 OSC 1337 徽章：$badge';
  }

  @override
  String get additionalOsc1337BadgesSplitTab => '此分屏标签页中的其他 OSC 1337 徽章。';

  @override
  String get clickFocusFirstRemainingBadgePane => '点击以聚焦第一个剩余的徽章窗格。';

  @override
  String get firstRemainingBadgePaneFocused => '第一个剩余的徽章窗格已聚焦。';

  @override
  String terminalBadgesAdditional(int count, String title, String action) {
    return '终端徽章：$title 中另有 $count 个窗格徽章；$action';
  }

  @override
  String get clickFocusPaneSemantics => '点击以聚焦此窗格';

  @override
  String get paneAlreadyFocusedSemantics => '窗格已聚焦';

  @override
  String get clickFocusFirstRemainingBadgePaneSemantics => '点击以聚焦第一个剩余的徽章窗格';

  @override
  String get firstRemainingBadgePaneFocusedSemantics => '第一个剩余的徽章窗格已聚焦';

  @override
  String get terminalProgressAbbreviation => '进度';

  @override
  String get terminalProgress => '终端进度';

  @override
  String get terminalNotificationAbbreviation => '通知';

  @override
  String get paneSignalAbbreviation => '窗格';

  @override
  String get otherPaneSignals => '其他窗格信号：';

  @override
  String signalInSplitPane(String signal) {
    return '分屏窗格中的$signal。';
  }

  @override
  String get clickInspectRecentNotifications => '点击以查看最近的通知。';

  @override
  String get clickFocusFirstPaneWithSignal => '点击以聚焦第一个有信号的窗格。';

  @override
  String get clickInspectNotificationActionsSemantics => '点击以查看通知操作';

  @override
  String otherPaneSignalCount(int count) {
    return '其他 $count 个窗格信号';
  }

  @override
  String terminalProgressReportedBy(String source) {
    return '由 $source 报告的终端进度。';
  }

  @override
  String labelValue(String value) {
    return '标签：$value';
  }

  @override
  String progressPercentValue(int value) {
    return '百分比：$value%';
  }

  @override
  String stateValue(String value) {
    return '状态：$value';
  }

  @override
  String idValue(String value) {
    return 'ID：$value';
  }

  @override
  String terminalNotificationReportedBy(String source) {
    return '由 $source 报告的终端通知。';
  }

  @override
  String titleValue(String value) {
    return '标题：$value';
  }

  @override
  String messageValue(String value) {
    return '消息：$value';
  }

  @override
  String remoteHostValue(String value) {
    return '远程主机：$value';
  }

  @override
  String remoteUserValue(String value) {
    return '远程用户：$value';
  }

  @override
  String countValue(int value) {
    return '数量：$value';
  }

  @override
  String get osc1337BadgeInHiddenTab => '隐藏标签页中的 OSC 1337 徽章。';

  @override
  String osc1337BadgesInHiddenPanes(int count) {
    return '$count 个隐藏窗格中有 OSC 1337 徽章。';
  }

  @override
  String get clickFocusFirstBadgePane => '点击以聚焦第一个徽章窗格。';

  @override
  String signalInHiddenTab(String signal) {
    return '隐藏标签页中的$signal。';
  }

  @override
  String paneSignalsInHiddenPanes(int count) {
    return '$count 个隐藏窗格中有窗格信号。';
  }

  @override
  String showHiddenTabs(int count) {
    return '显示 $count 个隐藏标签页';
  }

  @override
  String hiddenOsc1337BadgePanesTooltip(int count) {
    return '隐藏的 OSC 1337 徽章：$count 个窗格';
  }

  @override
  String hiddenPaneSignalsTooltip(int count) {
    return '隐藏的窗格信号：$count 个窗格';
  }

  @override
  String hiddenNewOutputTabsTooltip(int count) {
    return '隐藏的新输出：$count 个标签页';
  }

  @override
  String get signalMarkersFocusSources => '信号标记可聚焦其来源窗格。';

  @override
  String hiddenOsc1337BadgePanesSemantics(int count) {
    return '$count 个隐藏的 OSC 1337 徽章窗格';
  }

  @override
  String hiddenPaneSignalsSemantics(int count) {
    return '$count 个隐藏的窗格信号';
  }

  @override
  String hiddenNewOutputTabsSemantics(int count) {
    return '$count 个有新输出的隐藏标签页';
  }
}
