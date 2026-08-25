import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/configuration/data_api_configuration.dart';
import '../../data/configuration/data_api_configuration_repository.dart';
import '../../data/services/data_api_auth_contract.dart';
import '../../data/services/portable_master_key.dart';
import '../../ui/app_ui.dart';
import '../config/local_terminal_config_models.dart';
import '../config/local_terminal_keybinding_resolver.dart';
import '../config/shortcut_editor.dart';
import '../preferences/app_preferences_models.dart';
import '../profiles/profile_models.dart';
import '../security/master_key_management.dart';
import '../terminal/terminal_viewport_colors.dart';

class DefaultsAndAppearanceSelection {
  const DefaultsAndAppearanceSelection({
    required this.configuredDefaultProfileId,
    required this.themeMode,
    required this.languageMode,
    required this.terminalViewportPadding,
    required this.restoreLayout,
    required this.osc52Policy,
    required this.openUrlPolicy,
    required this.requestAttentionPolicy,
    required this.reportVariableDecisions,
    required this.keybindings,
    this.dataApiConfiguration = const DataApiConfiguration.disabled(),
    this.dataApiRemoteLogin,
    this.migrateLocalDataToRemote = false,
    this.migrateRemoteDataToLocal = false,
    this.updatedProfile,
    this.openProfiles = false,
  });

  final String? configuredDefaultProfileId;
  final TerminalThemeMode themeMode;
  final TerminalLanguageMode languageMode;
  final double terminalViewportPadding;
  final bool restoreLayout;
  final LocalTerminalOsc52Policy osc52Policy;
  final LocalTerminalOpenUrlPolicy openUrlPolicy;
  final LocalTerminalRequestAttentionPolicy requestAttentionPolicy;
  final Map<String, LocalTerminalReportVariablePolicy> reportVariableDecisions;
  final LocalTerminalKeybindingsConfig keybindings;
  final DataApiConfiguration dataApiConfiguration;
  final DataApiRemoteLoginRequest? dataApiRemoteLogin;
  final bool migrateLocalDataToRemote;
  final bool migrateRemoteDataToLocal;
  final TerminalProfile? updatedProfile;
  final bool openProfiles;
}

enum _DefaultsSection { general, appearance, shortcuts, security, data }

enum _TerminalPermissionKind { osc52, openUrl, requestAttention }

enum _PermissionRisk { low, medium, high }

List<Widget> _visibleDefaultsSectionChildren({
  required bool showAll,
  required _DefaultsSection selectedSection,
  required List<Widget> children,
}) {
  final visibleChildren = <Widget>[];
  var currentSection = _DefaultsSection.general;
  for (final child in children) {
    if (child is _DefaultsSectionMarker) {
      currentSection = child.section;
    } else if (showAll || currentSection == selectedSection) {
      visibleChildren.add(child);
    }
  }
  return visibleChildren;
}

class _DefaultsSectionMarker extends StatelessWidget {
  const _DefaultsSectionMarker(this.section);

  final _DefaultsSection section;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _DefaultsSectionColumn extends StatelessWidget {
  const _DefaultsSectionColumn({
    required this.showAll,
    required this.selectedSection,
    required this.children,
    this.mainAxisSize = MainAxisSize.max,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final bool showAll;
  final _DefaultsSection selectedSection;
  final List<Widget> children;
  final MainAxisSize mainAxisSize;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: crossAxisAlignment,
      children: _visibleDefaultsSectionChildren(
        showAll: showAll,
        selectedSection: selectedSection,
        children: children,
      ),
    );
  }
}

class DefaultsAndAppearanceDialog extends StatefulWidget {
  const DefaultsAndAppearanceDialog({
    super.key,
    required this.profiles,
    required this.configuredDefaultProfileId,
    required this.effectiveDefaultProfileId,
    required this.themeMode,
    this.languageMode = TerminalLanguageMode.system,
    required this.terminalViewportPadding,
    required this.restoreLayout,
    required this.osc52Policy,
    required this.openUrlPolicy,
    required this.requestAttentionPolicy,
    required this.reportVariableDecisions,
    this.keybindings = const LocalTerminalKeybindingsConfig(),
    this.dataApiConfiguration = const DataApiConfiguration.disabled(),
    this.activeDataApiDeployment,
    this.dataApiConfigurationRecoveryRequired = false,
    this.localDataApiAvailable = false,
    this.localSessionsEnabled = true,
    this.masterKeyRepository,
    this.openDataServiceInitially = false,
  });

  final List<TerminalProfile> profiles;
  final String? configuredDefaultProfileId;
  final String? effectiveDefaultProfileId;
  final TerminalThemeMode themeMode;
  final TerminalLanguageMode languageMode;
  final double terminalViewportPadding;
  final bool restoreLayout;
  final LocalTerminalOsc52Policy osc52Policy;
  final LocalTerminalOpenUrlPolicy openUrlPolicy;
  final LocalTerminalRequestAttentionPolicy requestAttentionPolicy;
  final Map<String, LocalTerminalReportVariablePolicy> reportVariableDecisions;
  final LocalTerminalKeybindingsConfig keybindings;
  final DataApiConfiguration dataApiConfiguration;
  final DataApiDeployment? activeDataApiDeployment;
  final bool dataApiConfigurationRecoveryRequired;
  final bool localDataApiAvailable;
  final bool localSessionsEnabled;
  final PortableMasterKeyRepository? masterKeyRepository;
  final bool openDataServiceInitially;

  @override
  State<DefaultsAndAppearanceDialog> createState() =>
      _DefaultsAndAppearanceDialogState();
}

class _DefaultsAndAppearanceDialogState
    extends State<DefaultsAndAppearanceDialog> {
  final ScrollController _scrollController = ScrollController();
  late final TextEditingController _remoteDataApiUrlController;
  late final TextEditingController _remoteDataApiUsernameController;
  late final TextEditingController _remoteDataApiPasswordController;
  late String? _selectedProfileId;
  late String? _selectedTerminalPresetId;
  late TerminalThemeMode _selectedThemeMode;
  late TerminalLanguageMode _selectedLanguageMode;
  late double _selectedTerminalViewportPadding;
  late bool _selectedRestoreLayout;
  late LocalTerminalOsc52Policy _selectedOsc52Policy;
  late LocalTerminalOpenUrlPolicy _selectedOpenUrlPolicy;
  late LocalTerminalRequestAttentionPolicy _selectedRequestAttentionPolicy;
  late Map<String, LocalTerminalReportVariablePolicy>
  _selectedReportVariableDecisions;
  late LocalTerminalKeybindingsConfig _selectedKeybindings;
  late DataApiDeployment _selectedDataApiDeployment;
  bool _remoteReconnectRequested = false;
  bool _remoteDataApiUrlEdited = false;
  bool _remoteDataApiUsernameEdited = false;
  bool _remoteDataApiPasswordEdited = false;
  bool _showShortcutEditor = false;
  bool _showReportVariableManagement = false;
  String _terminalPresetFilter = '';
  late _DefaultsSection _selectedSection;
  _TerminalPermissionKind _selectedPermissionDetail =
      _TerminalPermissionKind.openUrl;

  @override
  void initState() {
    super.initState();
    _selectedProfileId = widget.configuredDefaultProfileId;
    _selectedSection = widget.openDataServiceInitially
        ? _DefaultsSection.data
        : _DefaultsSection.general;
    _selectedThemeMode = widget.themeMode;
    _selectedLanguageMode = widget.languageMode;
    _selectedTerminalViewportPadding = widget.terminalViewportPadding;
    _selectedRestoreLayout = widget.restoreLayout;
    _selectedOsc52Policy = widget.osc52Policy;
    _selectedOpenUrlPolicy = widget.openUrlPolicy;
    _selectedRequestAttentionPolicy = widget.requestAttentionPolicy;
    _selectedReportVariableDecisions = Map.unmodifiable(
      widget.reportVariableDecisions,
    );
    _selectedKeybindings = widget.keybindings;
    _selectedDataApiDeployment = widget.dataApiConfiguration.deployment;
    _remoteDataApiUrlController = TextEditingController(
      text:
          widget.dataApiConfiguration.remoteBaseUri?.toString() ??
          defaultRemoteDataApiBaseUrl,
    );
    _remoteDataApiUsernameController = TextEditingController();
    _remoteDataApiPasswordController = TextEditingController();
    for (final controller in <TextEditingController>[
      _remoteDataApiUrlController,
      _remoteDataApiUsernameController,
      _remoteDataApiPasswordController,
    ]) {
      controller.addListener(_handleRemoteDataApiFieldChanged);
    }
    _selectedTerminalPresetId = _matchingPresetIdFor(
      _effectiveProfileFor(
        configuredProfileId: _selectedProfileId,
        effectiveProfileId: widget.effectiveDefaultProfileId,
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _remoteDataApiUrlController,
      _remoteDataApiUsernameController,
      _remoteDataApiPasswordController,
    ]) {
      controller
        ..removeListener(_handleRemoteDataApiFieldChanged)
        ..dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _handleRemoteDataApiFieldChanged() {
    setState(() {});
  }

  DataApiConfiguration? get _selectedDataApiConfiguration {
    return switch (_selectedDataApiDeployment) {
      DataApiDeployment.disabled => const DataApiConfiguration.disabled(),
      DataApiDeployment.local =>
        widget.localDataApiAvailable
            ? const DataApiConfiguration.local()
            : null,
      DataApiDeployment.remote =>
        _remoteDataApiUrlController.text.trim().isEmpty
            ? null
            : _tryRemoteDataApiConfiguration(_remoteDataApiUrlController.text),
    };
  }

  DataApiConfiguration? _tryRemoteDataApiConfiguration(String value) {
    try {
      return DataApiConfiguration.remote(value);
    } on FormatException {
      return null;
    }
  }

  String? get _remoteDataApiUrlError {
    if (!_remoteDataApiUrlEdited) {
      return null;
    }
    final value = _remoteDataApiUrlController.text.trim();
    if (value.isEmpty) {
      return context.l10n.enterRemoteApiBaseUrl;
    }
    try {
      DataApiConfiguration.remote(value);
      return null;
    } on FormatException catch (error) {
      return error.message.contains('requires HTTPS')
          ? context.l10n.remoteApiRequiresHttps
          : context.l10n.remoteApiBaseUrlWithoutCredentials;
    }
  }

  bool get _requiresRemoteLogin {
    final selected = _selectedDataApiConfiguration;
    return selected?.deployment == DataApiDeployment.remote &&
        (selected != widget.dataApiConfiguration || _remoteReconnectRequested);
  }

  bool get _migratesLocalDataToRemote {
    return _sourceDataApiDeployment == DataApiDeployment.local &&
        _selectedDataApiDeployment == DataApiDeployment.remote;
  }

  bool get _migratesRemoteDataToLocal {
    return _sourceDataApiDeployment == DataApiDeployment.remote &&
        _selectedDataApiDeployment == DataApiDeployment.local;
  }

  DataApiDeployment get _sourceDataApiDeployment =>
      widget.activeDataApiDeployment ?? widget.dataApiConfiguration.deployment;

  DataApiRemoteLoginRequest? get _remoteLoginRequest {
    final configuration = _selectedDataApiConfiguration;
    final baseUri = configuration?.remoteBaseUri;
    if (!_requiresRemoteLogin || baseUri == null) {
      return null;
    }
    try {
      return DataApiRemoteLoginRequest(
        baseUri: baseUri,
        username: _remoteDataApiUsernameController.text,
        password: _remoteDataApiPasswordController.text,
      );
    } on FormatException {
      return null;
    }
  }

  String? get _remoteUsernameError {
    if (!_requiresRemoteLogin || !_remoteDataApiUsernameEdited) {
      return null;
    }
    try {
      normalizeDataApiUsername(_remoteDataApiUsernameController.text);
      return null;
    } on FormatException {
      return context.l10n.usernameValidation;
    }
  }

  String? get _remotePasswordError {
    if (!_requiresRemoteLogin || !_remoteDataApiPasswordEdited) {
      return null;
    }
    try {
      validateDataApiPassword(_remoteDataApiPasswordController.text);
      return null;
    } on FormatException {
      return context.l10n.passwordValidation;
    }
  }

  InputDecoration _dataServiceInputDecoration({
    required String labelText,
    String? hintText,
    String? helperText,
    String? errorText,
  }) {
    final theme = context.appTheme;
    final textTheme = Theme.of(context).textTheme;
    return InputDecoration(
      isDense: true,
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      errorText: errorText,
      errorMaxLines: 2,
      constraints: BoxConstraints(minHeight: theme.controls.regular),
      contentPadding: EdgeInsets.symmetric(
        horizontal: theme.spacing.md,
        vertical: theme.spacing.sm,
      ),
      labelStyle: textTheme.labelMedium?.copyWith(color: theme.textMuted),
      floatingLabelStyle: textTheme.labelMedium?.copyWith(
        color: theme.focusRing,
        fontWeight: FontWeight.w600,
      ),
      helperStyle: textTheme.bodySmall?.copyWith(color: theme.textSubtle),
    );
  }

  TerminalProfile? _effectiveProfileFor({
    required String? configuredProfileId,
    required String? effectiveProfileId,
  }) {
    for (final profile in widget.profiles) {
      if (profile.id == configuredProfileId) {
        return profile;
      }
    }
    for (final profile in widget.profiles) {
      if (profile.id == effectiveProfileId) {
        return profile;
      }
    }
    if (widget.profiles.isEmpty) {
      return null;
    }
    return widget.profiles.first;
  }

  String? _matchingPresetIdFor(TerminalProfile? profile) {
    if (profile == null) {
      return null;
    }
    for (final preset in terminalThemePresets) {
      if (preset.matchesColors(profile.appearance.colors)) {
        return preset.id;
      }
    }
    return null;
  }

  TerminalThemePreset? get _selectedPreset {
    final selectedPresetId = _selectedTerminalPresetId;
    if (selectedPresetId == null) {
      return null;
    }
    for (final preset in terminalThemePresets) {
      if (preset.id == selectedPresetId) {
        return preset;
      }
    }
    return null;
  }

  TerminalProfile? _updatedProfileForPreset(TerminalProfile? effectiveProfile) {
    final preset = _selectedPreset;
    if (preset == null || effectiveProfile == null) {
      return null;
    }
    if (preset.matchesColors(effectiveProfile.appearance.colors)) {
      return null;
    }
    return effectiveProfile.copyWith(
      appearance: effectiveProfile.appearance.copyWith(colors: preset.palette),
    );
  }

  bool _terminalPresetMatchesFilter(TerminalThemePreset preset, String filter) {
    if (filter.isEmpty) {
      return true;
    }
    return '${preset.name} ${preset.tone.label}'.toLowerCase().contains(filter);
  }

  void _setShortcutEditorVisible(bool visible) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _showShortcutEditor = visible;
    });
  }

  void _selectSection(_DefaultsSection section) {
    if (_selectedSection == section) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _selectedSection = section;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  bool _hasChanges(TerminalProfile? effectiveProfile) {
    final selectedDataApiConfiguration = _selectedDataApiConfiguration;
    return widget.dataApiConfigurationRecoveryRequired ||
        _selectedProfileId != widget.configuredDefaultProfileId ||
        _selectedThemeMode != widget.themeMode ||
        _selectedLanguageMode != widget.languageMode ||
        _selectedTerminalViewportPadding != widget.terminalViewportPadding ||
        _selectedRestoreLayout != widget.restoreLayout ||
        _selectedOsc52Policy != widget.osc52Policy ||
        _selectedOpenUrlPolicy != widget.openUrlPolicy ||
        _selectedRequestAttentionPolicy != widget.requestAttentionPolicy ||
        !mapEquals(
          _selectedReportVariableDecisions,
          widget.reportVariableDecisions,
        ) ||
        _selectedKeybindings != widget.keybindings ||
        (selectedDataApiConfiguration != null &&
            selectedDataApiConfiguration != widget.dataApiConfiguration) ||
        _remoteReconnectRequested ||
        _updatedProfileForPreset(effectiveProfile) != null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final dataServiceFieldTextStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: theme.textPrimary);
    final mediaSize = MediaQuery.sizeOf(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardVisible = keyboardInset > 0;
    final compactLayout = mediaSize.width < 600;
    final compactKeyboardLayout =
        keyboardVisible &&
        (compactLayout || mediaSize.height < mediaSize.width);
    final desktopPlatform = switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => false,
    };
    final dialogInset = compactLayout ? 0.0 : theme.spacing.xxl;
    final dialogWidth = compactLayout
        ? mediaSize.width
        : (mediaSize.width - dialogInset * 2).clamp(0.0, 960.0);
    final dialogHeight = compactLayout
        ? mediaSize.height - keyboardInset
        : (mediaSize.height - keyboardInset - dialogInset * 2).clamp(
            0.0,
            760.0,
          );
    final showSectionNavigation =
        desktopPlatform &&
        !compactLayout &&
        !keyboardVisible &&
        dialogWidth >= 720 &&
        dialogHeight >= 480;
    final showStandaloneShortcutEditor =
        _showShortcutEditor && !showSectionNavigation;
    final effectiveProfile = _effectiveProfileFor(
      configuredProfileId: _selectedProfileId,
      effectiveProfileId: widget.effectiveDefaultProfileId,
    );
    final hasChanges = _hasChanges(effectiveProfile);
    final selectedDataApiConfiguration = _selectedDataApiConfiguration;
    final remoteLoginRequest = _remoteLoginRequest;
    final selectedPreset = _selectedPreset;
    final terminalPresetFilter = _terminalPresetFilter.trim().toLowerCase();
    final showCurrentPreset =
        terminalPresetFilter.isEmpty ||
        'keep current custom colors'.contains(terminalPresetFilter);
    final visibleTerminalPresets = terminalThemePresets
        .where(
          (preset) =>
              _terminalPresetMatchesFilter(preset, terminalPresetFilter),
        )
        .toList(growable: false);
    final allowedReportVariables = _selectedReportVariableDecisions.values
        .where((policy) => policy == LocalTerminalReportVariablePolicy.allow)
        .length;
    final deniedReportVariables =
        _selectedReportVariableDecisions.length - allowedReportVariables;
    final reportVariableDecisionEntries =
        _selectedReportVariableDecisions.entries.toList(growable: false)
          ..sort((left, right) => left.key.compareTo(right.key));
    final shortcutHasCustomizations =
        _selectedKeybindings.disabledDefaultActions.isNotEmpty ||
        _selectedKeybindings.overrides.isNotEmpty;

    return Semantics(
      identifier: 'defaults-dialog',
      container: true,
      explicitChildNodes: true,
      child: AppDialogScaffold(
        key: const Key('defaults-dialog'),
        title: showStandaloneShortcutEditor
            ? context.l10n.keyboardShortcuts
            : context.l10n.defaultsAppearance,
        subtitle: compactLayout || compactKeyboardLayout
            ? null
            : showStandaloneShortcutEditor
            ? context.l10n.keyboardShortcutsDescription
            : context.l10n.defaultsAppearanceSubtitle,
        leading: showStandaloneShortcutEditor
            ? AppActionButton(
                buttonKey: const Key('defaults-shortcuts-back'),
                tooltip: context.l10n.backToDefaultsAppearance,
                tone: AppActionTone.ghost,
                size: AppActionSize.dense,
                icon: Icons.arrow_back_rounded,
                onPressed: () => _setShortcutEditorVisible(false),
              )
            : compactLayout
            ? AppActionButton(
                buttonKey: const Key('defaults-mobile-back'),
                tooltip: context.l10n.closeDefaults,
                tone: AppActionTone.ghost,
                size: AppActionSize.dense,
                icon: Icons.arrow_back_rounded,
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        actions: showStandaloneShortcutEditor && compactLayout
            ? [
                PopupMenuButton<bool>(
                  key: const Key('shortcut-editor-mobile-menu'),
                  tooltip: context.l10n.moreShortcutActions,
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (_) {
                    setState(() {
                      _selectedKeybindings =
                          const LocalTerminalKeybindingsConfig();
                    });
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<bool>(
                      key: const Key('shortcut-editor-restore-all'),
                      value: true,
                      enabled: shortcutHasCustomizations,
                      child: Row(
                        children: [
                          const Icon(Icons.restart_alt_rounded, size: 20),
                          SizedBox(width: theme.spacing.sm),
                          Text(context.l10n.restoreAllDefaults),
                        ],
                      ),
                    ),
                  ],
                ),
              ]
            : const [],
        onClose: compactLayout ? null : () => Navigator.of(context).pop(),
        closeTooltip: context.l10n.closeDefaults,
        insetPadding: EdgeInsets.all(dialogInset),
        constraints: compactLayout
            ? const BoxConstraints()
            : const BoxConstraints(maxWidth: 960),
        width: dialogWidth,
        height: dialogHeight,
        expandBody: true,
        centerInViewport: !compactLayout,
        borderRadius: compactLayout ? BorderRadius.zero : null,
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: theme.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        subtitleTextStyle: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: theme.textSubtle),
        headerPadding: EdgeInsets.fromLTRB(
          compactLayout ? theme.spacing.md : theme.spacing.xxl,
          compactKeyboardLayout ? theme.spacing.sm : theme.spacing.xl,
          compactLayout ? theme.spacing.md : theme.spacing.xxl,
          compactKeyboardLayout ? theme.spacing.sm : theme.spacing.md,
        ),
        bodyPadding: showSectionNavigation && !showStandaloneShortcutEditor
            ? EdgeInsets.zero
            : EdgeInsets.fromLTRB(
                compactLayout ? theme.spacing.md : theme.spacing.xxl,
                compactKeyboardLayout ? theme.spacing.sm : theme.spacing.md,
                compactLayout ? theme.spacing.md : theme.spacing.xxl,
                compactKeyboardLayout ? theme.spacing.sm : theme.spacing.md,
              ),
        footerPadding: EdgeInsets.fromLTRB(
          compactLayout ? theme.spacing.md : theme.spacing.xxl,
          theme.spacing.md,
          compactLayout ? theme.spacing.md : theme.spacing.xxl,
          theme.spacing.md,
        ),
        body: showStandaloneShortcutEditor
            ? ShortcutEditorPanel(
                config: _selectedKeybindings,
                expandList: true,
                showHeader: false,
                showRestoreAction: !compactLayout,
                onChanged: (value) {
                  setState(() {
                    _selectedKeybindings = value;
                  });
                },
              )
            : showSectionNavigation &&
                  _selectedSection == _DefaultsSection.shortcuts
            ? _DefaultsBodyLayout(
                showNavigation: showSectionNavigation,
                selectedSection: _selectedSection,
                onSectionSelected: _selectSection,
                child: Padding(
                  key: const Key('defaults-shortcuts-tab-panel'),
                  padding: EdgeInsets.fromLTRB(
                    theme.spacing.xxl,
                    theme.spacing.xl,
                    theme.spacing.xxl,
                    theme.spacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DefaultsSectionIntro(
                        title: context.l10n.keyboardShortcuts,
                        description: context.l10n.keyboardShortcutsDescription,
                      ),
                      SizedBox(height: theme.spacing.xl),
                      Expanded(
                        child: ShortcutEditorPanel(
                          config: _selectedKeybindings,
                          expandList: true,
                          showHeader: false,
                          onChanged: (value) {
                            setState(() {
                              _selectedKeybindings = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : _DefaultsBodyLayout(
                showNavigation: showSectionNavigation,
                selectedSection: _selectedSection,
                onSectionSelected: _selectSection,
                child: SingleChildScrollView(
                  key: const Key('defaults-appearance-scroll'),
                  controller: _scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: showSectionNavigation
                      ? EdgeInsets.fromLTRB(
                          theme.spacing.xxl,
                          theme.spacing.xl,
                          theme.spacing.xxl,
                          theme.spacing.xl,
                        )
                      : EdgeInsets.only(right: theme.spacing.md),
                  child: _DefaultsSectionColumn(
                    showAll: !showSectionNavigation,
                    selectedSection: _selectedSection,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _DefaultsSectionMarker(_DefaultsSection.general),
                      if (showSectionNavigation) ...[
                        _DefaultsSectionIntro(
                          title: context.l10n.general,
                          description: context.l10n.generalSettingsDescription,
                        ),
                        SizedBox(height: theme.spacing.xl),
                      ],
                      _ProfilesNotice(
                        effectiveProfile: effectiveProfile,
                        onOpenProfiles: effectiveProfile == null
                            ? null
                            : () {
                                Navigator.of(context).pop(
                                  DefaultsAndAppearanceSelection(
                                    configuredDefaultProfileId:
                                        _selectedProfileId,
                                    themeMode: _selectedThemeMode,
                                    languageMode: _selectedLanguageMode,
                                    terminalViewportPadding:
                                        _selectedTerminalViewportPadding,
                                    restoreLayout: _selectedRestoreLayout,
                                    osc52Policy: _selectedOsc52Policy,
                                    openUrlPolicy: _selectedOpenUrlPolicy,
                                    requestAttentionPolicy:
                                        _selectedRequestAttentionPolicy,
                                    reportVariableDecisions:
                                        _selectedReportVariableDecisions,
                                    keybindings: _selectedKeybindings,
                                    dataApiConfiguration:
                                        selectedDataApiConfiguration ??
                                        widget.dataApiConfiguration,
                                    dataApiRemoteLogin: null,
                                    updatedProfile: null,
                                    openProfiles: true,
                                  ),
                                );
                              },
                      ),
                      SizedBox(height: theme.spacing.xl),
                      AppSectionHeader(title: context.l10n.defaultProfile),
                      SizedBox(height: theme.spacing.sm),
                      AppPanel(
                        tone: AppPanelTone.panel,
                        child: Column(
                          children: [
                            RadioGroup<String?>(
                              groupValue: _selectedProfileId,
                              onChanged: (value) {
                                setState(() {
                                  _selectedProfileId = value;
                                  _selectedTerminalPresetId =
                                      _matchingPresetIdFor(
                                        _effectiveProfileFor(
                                          configuredProfileId: value,
                                          effectiveProfileId:
                                              widget.effectiveDefaultProfileId,
                                        ),
                                      );
                                });
                              },
                              child: Column(
                                children: [
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: theme.spacing.md,
                                      vertical: theme.spacing.xs,
                                    ),
                                    child: AppCompactRadioTile<String?>(
                                      tileKey: const Key(
                                        'default-profile-option-fallback',
                                      ),
                                      value: null,
                                      title: Text(
                                        context.l10n.useAutomaticFallback,
                                      ),
                                      subtitle: Text(
                                        effectiveProfile == null
                                            ? context.l10n.noProfileForNewTabs
                                            : context.l10n
                                                  .newTabsUseProfileAutomatically(
                                                    effectiveProfile.name,
                                                  ),
                                      ),
                                    ),
                                  ),
                                  for (final profile in widget.profiles)
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: theme.spacing.md,
                                        vertical: theme.spacing.xs,
                                      ),
                                      child: AppCompactRadioTile<String?>(
                                        tileKey: Key(
                                          'default-profile-option-${profile.id}',
                                        ),
                                        value: profile.id,
                                        title: Text(profile.name),
                                        subtitle: Text(
                                          _defaultProfileSubtitle(profile),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: theme.spacing.xl),
                      AppSectionHeader(
                        title: context.l10n.language,
                        description: context.l10n.languageDescription,
                      ),
                      SizedBox(height: theme.spacing.sm),
                      _SettingsRadioPanel<TerminalLanguageMode>(
                        panelKey: const Key('defaults-language-options'),
                        groupValue: _selectedLanguageMode,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _selectedLanguageMode = value;
                          });
                        },
                        options: [
                          for (final mode in TerminalLanguageMode.values)
                            _SettingsRadioOptionData<TerminalLanguageMode>(
                              tileKey: Key(
                                'default-language-option-${mode.name}',
                              ),
                              value: mode,
                              title: context.l10n.languageModeName(mode.name),
                              subtitle: context.l10n.languageModeDescription(
                                mode.name,
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: theme.spacing.xl),
                      const _DefaultsSectionMarker(_DefaultsSection.appearance),
                      if (showSectionNavigation) ...[
                        _DefaultsSectionIntro(
                          title: context.l10n.appearance,
                          description:
                              context.l10n.appearanceSettingsDescription,
                        ),
                        SizedBox(height: theme.spacing.lg),
                      ],
                      AppSectionHeader(
                        title: context.l10n.terminalPreset,
                        description: effectiveProfile == null
                            ? context.l10n.createProfileBeforeColors
                            : context.l10n.applyPaletteToProfile(
                                effectiveProfile.name,
                              ),
                      ),
                      SizedBox(height: theme.spacing.sm),
                      Semantics(
                        label: context.l10n.filterTerminalPresets,
                        container: true,
                        explicitChildNodes: true,
                        child: TextField(
                          key: const Key('defaults-terminal-preset-filter'),
                          textInputAction: TextInputAction.search,
                          onTapOutside: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: theme.panel,
                            prefixIcon: const Icon(Icons.search_rounded),
                            labelText: context.l10n.filterTerminalPresets,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _terminalPresetFilter = value;
                            });
                          },
                        ),
                      ),
                      SizedBox(height: theme.spacing.sm),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columnCount = constraints.maxWidth >= 560
                              ? 3
                              : constraints.maxWidth >= 340
                              ? 2
                              : 1;
                          final cardWidth =
                              (constraints.maxWidth -
                                  theme.spacing.lg * (columnCount - 1)) /
                              columnCount;
                          return Wrap(
                            key: const Key('defaults-terminal-preset-grid'),
                            spacing: theme.spacing.lg,
                            runSpacing: theme.spacing.lg,
                            children: [
                              if (showCurrentPreset)
                                _TerminalPresetChoice(
                                  key: const Key(
                                    'defaults-terminal-preset-current',
                                  ),
                                  width: cardWidth,
                                  label: context.l10n.keepCurrent,
                                  subtitle: selectedPreset == null
                                      ? context.l10n.customColors
                                      : context.l10n.currentlyPreset(
                                          selectedPreset.name,
                                        ),
                                  selected: _selectedTerminalPresetId == null,
                                  enabled: effectiveProfile != null,
                                  previewColors: effectiveProfile == null
                                      ? const <String>[]
                                      : _previewColorsForPalette(
                                          effectiveProfile.appearance.colors,
                                        ),
                                  onPressed: () {
                                    setState(() {
                                      _selectedTerminalPresetId = null;
                                    });
                                  },
                                ),
                              for (final preset in visibleTerminalPresets)
                                _TerminalPresetChoice(
                                  key: Key(
                                    'defaults-terminal-preset-${preset.id}',
                                  ),
                                  width: cardWidth,
                                  label: preset.name,
                                  subtitle: preset.tone.label,
                                  selected:
                                      _selectedTerminalPresetId == preset.id,
                                  enabled: effectiveProfile != null,
                                  previewColors: preset.previewColors,
                                  onPressed: () {
                                    setState(() {
                                      _selectedTerminalPresetId = preset.id;
                                    });
                                  },
                                ),
                              if (!showCurrentPreset &&
                                  visibleTerminalPresets.isEmpty)
                                SizedBox(
                                  width: constraints.maxWidth,
                                  child: AppPanel(
                                    tone: AppPanelTone.elevated,
                                    padding: EdgeInsets.all(theme.spacing.md),
                                    child: Text(
                                      context.l10n.noTerminalPresetsMatch(
                                        _terminalPresetFilter,
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: theme.textSubtle),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      SizedBox(height: theme.spacing.lg),
                      AppSectionHeader(
                        title: context.l10n.startup,
                        description: context.l10n.startupLayoutDescription,
                      ),
                      SizedBox(height: theme.spacing.sm),
                      AppPanel(
                        key: const Key('defaults-layout-restore-panel'),
                        tone: AppPanelTone.panel,
                        padding: EdgeInsets.symmetric(
                          horizontal: theme.spacing.lg,
                          vertical: theme.spacing.sm,
                        ),
                        child: MergeSemantics(
                          child: SwitchListTile(
                            key: const Key('default-restore-layout'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              context.l10n.restoreTabsAndPanes,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: theme.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            subtitle: Text(
                              context.l10n.restoreTabsAndPanesDescription,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: theme.textSubtle),
                            ),
                            value: _selectedRestoreLayout,
                            onChanged: (value) {
                              setState(() {
                                _selectedRestoreLayout = value;
                              });
                            },
                          ),
                        ),
                      ),
                      SizedBox(height: theme.spacing.lg),
                      AppSectionHeader(title: context.l10n.appearance),
                      SizedBox(height: theme.spacing.sm),
                      _SettingsRadioPanel<TerminalThemeMode>(
                        panelKey: const Key('defaults-appearance-options'),
                        groupValue: _selectedThemeMode,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _selectedThemeMode = value;
                          });
                        },
                        options: [
                          for (final themeMode in TerminalThemeMode.values)
                            _SettingsRadioOptionData<TerminalThemeMode>(
                              tileKey: Key(
                                'default-theme-option-${themeMode.name}',
                              ),
                              value: themeMode,
                              title: context.l10n.themeModeName(themeMode.name),
                              subtitle: context.l10n.themeModeDescription(
                                themeMode.name,
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: theme.spacing.xxl),
                      const _DefaultsSectionMarker(_DefaultsSection.shortcuts),
                      if (!showSectionNavigation) ...[
                        AppSectionHeader(title: context.l10n.keyboardShortcuts),
                        SizedBox(height: theme.spacing.sm),
                        _ShortcutSettingsEntry(
                          compact: compactLayout,
                          onPressed: () => _setShortcutEditorVisible(true),
                        ),
                        SizedBox(height: theme.spacing.xxl),
                      ],
                      const _DefaultsSectionMarker(_DefaultsSection.security),
                      if (showSectionNavigation) ...[
                        _DefaultsSectionIntro(
                          title: context.l10n.securityPermissions,
                          description:
                              context.l10n.securityPermissionsDescription,
                        ),
                        SizedBox(height: theme.spacing.xl),
                        AppSectionHeader(
                          title: context.l10n.sessionInteractionsPermissions,
                          description: context
                              .l10n
                              .sessionInteractionsPermissionsDescription,
                        ),
                        SizedBox(height: theme.spacing.sm),
                        _TerminalPermissionsPanel(
                          osc52Policy: _selectedOsc52Policy,
                          openUrlPolicy: _selectedOpenUrlPolicy,
                          requestAttentionPolicy:
                              _selectedRequestAttentionPolicy,
                          selectedDetail: _selectedPermissionDetail,
                          reportVariableDecisionCount:
                              _selectedReportVariableDecisions.length,
                          allowedReportVariableCount: allowedReportVariables,
                          deniedReportVariableCount: deniedReportVariables,
                          reportVariableManagementOpen:
                              _showReportVariableManagement,
                          onOsc52Changed: (value) {
                            setState(() {
                              _selectedOsc52Policy = value;
                              _selectedPermissionDetail =
                                  _TerminalPermissionKind.osc52;
                            });
                          },
                          onOpenUrlChanged: (value) {
                            setState(() {
                              _selectedOpenUrlPolicy = value;
                              _selectedPermissionDetail =
                                  _TerminalPermissionKind.openUrl;
                            });
                          },
                          onRequestAttentionChanged: (value) {
                            setState(() {
                              _selectedRequestAttentionPolicy = value;
                              _selectedPermissionDetail =
                                  _TerminalPermissionKind.requestAttention;
                            });
                          },
                          onDetailSelected: (value) {
                            if (_selectedPermissionDetail == value) {
                              return;
                            }
                            setState(() {
                              _selectedPermissionDetail = value;
                            });
                          },
                          onManageReportVariables: () {
                            setState(() {
                              _showReportVariableManagement =
                                  !_showReportVariableManagement;
                            });
                          },
                        ),
                      ] else ...[
                        AppSectionHeader(
                          title: context.l10n.osc52Clipboard,
                          description: context.l10n.osc52ClipboardDescription,
                        ),
                        SizedBox(height: theme.spacing.sm),
                        _SettingsRadioPanel<LocalTerminalOsc52Policy>(
                          panelKey: const Key('defaults-osc52-options'),
                          groupValue: _selectedOsc52Policy,
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedOsc52Policy = value;
                            });
                          },
                          options: [
                            for (final policy
                                in LocalTerminalOsc52Policy.values)
                              _SettingsRadioOptionData<
                                LocalTerminalOsc52Policy
                              >(
                                tileKey: Key(
                                  'default-osc52-policy-${policy.name}',
                                ),
                                value: policy,
                                title: context.l10n.osc52PolicyName(
                                  policy.name,
                                ),
                                subtitle: context.l10n.osc52PolicyDescription(
                                  policy.name,
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: theme.spacing.xxl),
                        AppSectionHeader(
                          title: context.l10n.terminalUrlRequests,
                          description:
                              context.l10n.terminalUrlRequestsDescription,
                        ),
                        SizedBox(height: theme.spacing.sm),
                        _SettingsRadioPanel<LocalTerminalOpenUrlPolicy>(
                          panelKey: const Key('defaults-open-url-options'),
                          groupValue: _selectedOpenUrlPolicy,
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedOpenUrlPolicy = value;
                            });
                          },
                          options: [
                            for (final policy
                                in LocalTerminalOpenUrlPolicy.values)
                              _SettingsRadioOptionData<
                                LocalTerminalOpenUrlPolicy
                              >(
                                tileKey: Key(
                                  'default-osc1337-open-url-policy-${policy.name}',
                                ),
                                value: policy,
                                title: context.l10n.openUrlPolicyName(
                                  policy.name,
                                ),
                                subtitle: context.l10n.openUrlPolicyDescription(
                                  policy.name,
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: theme.spacing.xxl),
                        AppSectionHeader(
                          title: context.l10n.terminalAttentionRequests,
                          description:
                              context.l10n.terminalAttentionRequestsDescription,
                        ),
                        SizedBox(height: theme.spacing.sm),
                        _SettingsRadioPanel<
                          LocalTerminalRequestAttentionPolicy
                        >(
                          panelKey: const Key(
                            'defaults-request-attention-options',
                          ),
                          groupValue: _selectedRequestAttentionPolicy,
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedRequestAttentionPolicy = value;
                            });
                          },
                          options: [
                            for (final policy
                                in LocalTerminalRequestAttentionPolicy.values)
                              _SettingsRadioOptionData<
                                LocalTerminalRequestAttentionPolicy
                              >(
                                tileKey: Key(
                                  'default-osc1337-request-attention-policy-${policy.name}',
                                ),
                                value: policy,
                                title: context.l10n.requestAttentionPolicyName(
                                  policy.name,
                                ),
                                subtitle: context.l10n
                                    .requestAttentionPolicyDescription(
                                      policy.name,
                                    ),
                              ),
                          ],
                        ),
                        SizedBox(height: theme.spacing.xxl),
                        AppSectionHeader(
                          title: context.l10n.terminalVariableReports,
                          description:
                              context.l10n.terminalVariableReportsDescription,
                        ),
                        SizedBox(height: theme.spacing.sm),
                      ],
                      if (showSectionNavigation &&
                          _showReportVariableManagement)
                        SizedBox(height: theme.spacing.sm),
                      if (!showSectionNavigation ||
                          _showReportVariableManagement)
                        AppPanel(
                          key: showSectionNavigation
                              ? const Key('defaults-report-variable-management')
                              : const Key('defaults-report-variable-panel'),
                          tone: AppPanelTone.panel,
                          padding: EdgeInsets.all(theme.spacing.xl),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedReportVariableDecisions.isEmpty
                                    ? context.l10n.noRememberedDecisions
                                    : context.l10n.rememberedDecisionSummary(
                                        _selectedReportVariableDecisions.length,
                                        allowedReportVariables,
                                        deniedReportVariables,
                                      ),
                                key: showSectionNavigation
                                    ? const Key(
                                        'default-osc1337-report-variable-management-summary',
                                      )
                                    : const Key(
                                        'default-osc1337-report-variable-decision-summary',
                                      ),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: theme.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              SizedBox(height: theme.spacing.xs),
                              Text(
                                context.l10n.forgettingDecisionsHelp,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: theme.textSubtle),
                              ),
                              if (reportVariableDecisionEntries.isNotEmpty) ...[
                                SizedBox(height: theme.spacing.md),
                                for (final entry
                                    in reportVariableDecisionEntries)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      bottom: theme.spacing.xs,
                                    ),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: theme.overlay.withValues(
                                          alpha: 0.34,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          theme.radius.md,
                                        ),
                                        border: Border.all(color: theme.border),
                                      ),
                                      child: Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          theme.spacing.md,
                                          theme.spacing.xs,
                                          theme.spacing.xs,
                                          theme.spacing.xs,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                entry.key,
                                                key: ValueKey<String>(
                                                  'default-osc1337-report-variable-name-${entry.key}',
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: theme.textPrimary,
                                                    ),
                                              ),
                                            ),
                                            SizedBox(width: theme.spacing.sm),
                                            Text(
                                              entry.value ==
                                                      LocalTerminalReportVariablePolicy
                                                          .allow
                                                  ? context.l10n.allow
                                                  : context.l10n.deny,
                                              key: ValueKey<String>(
                                                'default-osc1337-report-variable-policy-${entry.key}',
                                              ),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color: theme.textSubtle,
                                                  ),
                                            ),
                                            SizedBox(width: theme.spacing.xs),
                                            IconButton(
                                              key: ValueKey<String>(
                                                'default-osc1337-report-variable-forget-${entry.key}',
                                              ),
                                              tooltip: context.l10n
                                                  .forgetDecisionFor(entry.key),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: () {
                                                setState(() {
                                                  final next =
                                                      <
                                                          String,
                                                          LocalTerminalReportVariablePolicy
                                                        >{
                                                          ..._selectedReportVariableDecisions,
                                                        }
                                                        ..remove(entry.key);
                                                  _selectedReportVariableDecisions =
                                                      Map.unmodifiable(next);
                                                });
                                              },
                                              icon: const Icon(
                                                Icons.close_rounded,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                              SizedBox(height: theme.spacing.sm),
                              AppActionButton(
                                buttonKey: const Key(
                                  'default-osc1337-report-variable-forget-all',
                                ),
                                tone: AppActionTone.secondary,
                                size: AppActionSize.compact,
                                icon: Icons.restart_alt_rounded,
                                label: context.l10n.forgetAllDecisions,
                                onPressed:
                                    _selectedReportVariableDecisions.isEmpty
                                    ? null
                                    : () {
                                        setState(() {
                                          _selectedReportVariableDecisions =
                                              const <
                                                String,
                                                LocalTerminalReportVariablePolicy
                                              >{};
                                        });
                                      },
                              ),
                            ],
                          ),
                        ),
                      SizedBox(height: theme.spacing.xxl),
                      const _DefaultsSectionMarker(_DefaultsSection.data),
                      if (showSectionNavigation) ...[
                        _DefaultsSectionIntro(
                          title: context.l10n.dataService,
                          description: widget.localDataApiAvailable
                              ? context
                                    .l10n
                                    .dataServiceDescriptionLocalAvailable
                              : context.l10n.dataServiceDescriptionRemoteOnly,
                        ),
                        SizedBox(height: theme.spacing.xl),
                      ] else
                        AppSectionHeader(
                          title: context.l10n.dataService,
                          description: widget.localDataApiAvailable
                              ? context
                                    .l10n
                                    .dataServiceDescriptionLocalAvailable
                              : context.l10n.dataServiceDescriptionRemoteOnly,
                        ),
                      SizedBox(height: theme.spacing.sm),
                      _DataServiceStatusBanner(
                        deployment: _sourceDataApiDeployment,
                        localSessionsEnabled: widget.localSessionsEnabled,
                      ),
                      SizedBox(height: theme.spacing.sm),
                      AppPanel(
                        key: const Key('defaults-data-api-panel'),
                        tone: AppPanelTone.panel,
                        padding: EdgeInsets.all(theme.spacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RadioGroup<DataApiDeployment>(
                              groupValue: _selectedDataApiDeployment,
                              onChanged: (deployment) {
                                if (deployment == null) {
                                  return;
                                }
                                setState(() {
                                  _selectedDataApiDeployment = deployment;
                                });
                              },
                              child: Column(
                                children: [
                                  if (showSectionNavigation) ...[
                                    const _DataServiceComparisonHeader(),
                                    SizedBox(height: theme.spacing.xs),
                                  ],
                                  _DataServiceModeChoice(
                                    tileKey: const Key('data-api-disabled'),
                                    value: DataApiDeployment.disabled,
                                    title: widget.localSessionsEnabled
                                        ? context.l10n.localTerminal
                                        : context.l10n.noDataService,
                                    description: widget.localSessionsEnabled
                                        ? context
                                              .l10n
                                              .localTerminalNoApiDescription
                                        : context.l10n.noDataServiceDescription,
                                    selected:
                                        _selectedDataApiDeployment ==
                                        DataApiDeployment.disabled,
                                    active:
                                        _sourceDataApiDeployment ==
                                        DataApiDeployment.disabled,
                                    showComparison: showSectionNavigation,
                                  ),
                                  if (widget.localDataApiAvailable)
                                    _DataServiceModeChoice(
                                      tileKey: const Key('data-api-local'),
                                      value: DataApiDeployment.local,
                                      title: context.l10n.bundledLocalService,
                                      description: context
                                          .l10n
                                          .bundledLocalServiceDescription,
                                      selected:
                                          _selectedDataApiDeployment ==
                                          DataApiDeployment.local,
                                      active:
                                          _sourceDataApiDeployment ==
                                          DataApiDeployment.local,
                                      showComparison: showSectionNavigation,
                                    ),
                                  if (_migratesRemoteDataToLocal)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        top: theme.spacing.sm,
                                        bottom: theme.spacing.sm,
                                      ),
                                      child: AppPanel(
                                        key: const Key(
                                          'data-api-remote-to-local-migration',
                                        ),
                                        tone: AppPanelTone.chrome,
                                        child: ListTile(
                                          leading: const Icon(
                                            Icons.cloud_download_outlined,
                                          ),
                                          title: Text(
                                            context.l10n.migrateRemoteApiData,
                                          ),
                                          subtitle: Text(
                                            context
                                                .l10n
                                                .migrateRemoteApiDataDescription,
                                          ),
                                        ),
                                      ),
                                    ),
                                  _DataServiceModeChoice(
                                    tileKey: const Key('data-api-remote'),
                                    value: DataApiDeployment.remote,
                                    title: context.l10n.remoteService,
                                    description:
                                        context.l10n.remoteServiceDescription,
                                    selected:
                                        _selectedDataApiDeployment ==
                                        DataApiDeployment.remote,
                                    active:
                                        _sourceDataApiDeployment ==
                                        DataApiDeployment.remote,
                                    showComparison: showSectionNavigation,
                                  ),
                                ],
                              ),
                            ),
                            if (_selectedDataApiDeployment ==
                                DataApiDeployment.remote) ...[
                              SizedBox(height: theme.spacing.sm),
                              if (_migratesLocalDataToRemote) ...[
                                AppPanel(
                                  key: const Key(
                                    'data-api-local-to-remote-migration',
                                  ),
                                  tone: AppPanelTone.chrome,
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.cloud_upload_outlined,
                                    ),
                                    title: Text(
                                      context.l10n.migrateLocalApiData,
                                    ),
                                    subtitle: Text(
                                      context
                                          .l10n
                                          .migrateLocalApiDataDescription,
                                    ),
                                  ),
                                ),
                                SizedBox(height: theme.spacing.sm),
                              ],
                              if (_selectedDataApiConfiguration ==
                                  widget.dataApiConfiguration)
                                AppActionButton(
                                  buttonKey: const Key(
                                    'data-api-remote-reconnect',
                                  ),
                                  tone: AppActionTone.secondary,
                                  size: AppActionSize.compact,
                                  icon: Icons.login_rounded,
                                  label: _remoteReconnectRequested
                                      ? context.l10n.reconnectRequested
                                      : context.l10n.reconnectSignIn,
                                  onPressed: _remoteReconnectRequested
                                      ? null
                                      : () {
                                          setState(() {
                                            _remoteReconnectRequested = true;
                                          });
                                        },
                                ),
                              if (_selectedDataApiConfiguration ==
                                  widget.dataApiConfiguration)
                                SizedBox(height: theme.spacing.sm),
                              TextField(
                                key: const Key('data-api-remote-url'),
                                controller: _remoteDataApiUrlController,
                                style: dataServiceFieldTextStyle,
                                onChanged: (_) {
                                  if (!_remoteDataApiUrlEdited) {
                                    setState(
                                      () => _remoteDataApiUrlEdited = true,
                                    );
                                  }
                                },
                                scrollPadding: EdgeInsets.only(
                                  bottom: theme.spacing.xxl * 2,
                                ),
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: _dataServiceInputDecoration(
                                  labelText: context.l10n.remoteApiBaseUrl,
                                  hintText: defaultRemoteDataApiBaseUrl,
                                  errorText: _remoteDataApiUrlError,
                                ),
                              ),
                              SizedBox(height: theme.spacing.sm),
                              TextField(
                                key: const Key('data-api-remote-username'),
                                controller: _remoteDataApiUsernameController,
                                style: dataServiceFieldTextStyle,
                                onChanged: (_) {
                                  if (!_remoteDataApiUsernameEdited) {
                                    setState(
                                      () => _remoteDataApiUsernameEdited = true,
                                    );
                                  }
                                },
                                scrollPadding: EdgeInsets.only(
                                  bottom: theme.spacing.xxl * 2,
                                ),
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: const <String>[
                                  AutofillHints.username,
                                ],
                                decoration: _dataServiceInputDecoration(
                                  labelText: context.l10n.username,
                                  errorText: _remoteUsernameError,
                                ),
                              ),
                              SizedBox(height: theme.spacing.sm),
                              TextField(
                                key: const Key('data-api-remote-password'),
                                controller: _remoteDataApiPasswordController,
                                style: dataServiceFieldTextStyle,
                                onChanged: (_) {
                                  if (!_remoteDataApiPasswordEdited) {
                                    setState(
                                      () => _remoteDataApiPasswordEdited = true,
                                    );
                                  }
                                },
                                scrollPadding: EdgeInsets.only(
                                  bottom: theme.spacing.xxl * 2,
                                ),
                                textInputAction: TextInputAction.done,
                                obscureText: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: const <String>[
                                  AutofillHints.password,
                                ],
                                decoration: _dataServiceInputDecoration(
                                  labelText: context.l10n.password,
                                  helperText: context.l10n.loginPasswordHelp,
                                  errorText: _remotePasswordError,
                                ),
                                onSubmitted: (_) => FocusManager
                                    .instance
                                    .primaryFocus
                                    ?.unfocus(),
                              ),
                              SizedBox(height: theme.spacing.sm),
                              Text(
                                usesAutomaticallySynchronizedAppleKeychain
                                    ? context
                                          .l10n
                                          .appleMasterKeyEncryptionDescription
                                    : context
                                          .l10n
                                          .deviceMasterKeyEncryptionDescription,
                              ),
                            ],
                            SizedBox(height: theme.spacing.sm),
                            Text(
                              context.l10n.dataServiceRestartNotice,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: theme.textSubtle),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: theme.spacing.xxl),
                      if (widget.masterKeyRepository
                          case final repository?) ...[
                        MasterKeyManagementPanel(repository: repository),
                        SizedBox(height: theme.spacing.xxl),
                      ],
                      const _DefaultsSectionMarker(_DefaultsSection.appearance),
                      AppSectionHeader(
                        title: context.l10n.terminalCanvasInset,
                        description:
                            context.l10n.terminalCanvasInsetDescription,
                      ),
                      SizedBox(height: theme.spacing.sm),
                      AppPanel(
                        key: const Key('defaults-canvas-inset-panel'),
                        tone: AppPanelTone.panel,
                        padding: EdgeInsets.all(theme.spacing.xl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    context.l10n.viewportPadding,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: theme.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                                Text(
                                  '${_selectedTerminalViewportPadding.round()} px',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: theme.textMuted,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'monospace',
                                      ),
                                ),
                              ],
                            ),
                            Semantics(
                              container: true,
                              label: context.l10n.viewportPadding,
                              value: context.l10n.pixelCount(
                                _selectedTerminalViewportPadding.round(),
                              ),
                              liveRegion: true,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: theme.accent,
                                  inactiveTrackColor: theme.border,
                                  thumbColor: theme.accent,
                                  overlayColor: theme.focusRing.withValues(
                                    alpha: 0.14,
                                  ),
                                  valueIndicatorColor: theme.panelElevated,
                                  valueIndicatorTextStyle: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(color: theme.textPrimary),
                                ),
                                child: Slider(
                                  key: const Key(
                                    'default-terminal-viewport-padding',
                                  ),
                                  value: _selectedTerminalViewportPadding,
                                  min: TerminalAppAppearance
                                      .minTerminalViewportPadding,
                                  max: TerminalAppAppearance
                                      .maxTerminalViewportPadding,
                                  divisions:
                                      (TerminalAppAppearance
                                                  .maxTerminalViewportPadding -
                                              TerminalAppAppearance
                                                  .minTerminalViewportPadding)
                                          .round(),
                                  label: context.l10n.pixelCount(
                                    _selectedTerminalViewportPadding.round(),
                                  ),
                                  semanticFormatterCallback: (value) =>
                                      context.l10n.pixelCount(value.round()),
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedTerminalViewportPadding = value;
                                    });
                                  },
                                ),
                              ),
                            ),
                            Center(
                              child: Text(
                                context.l10n.viewportPaddingRange(
                                  TerminalAppAppearance
                                      .minTerminalViewportPadding
                                      .round(),
                                  TerminalAppAppearance
                                      .maxTerminalViewportPadding
                                      .round(),
                                ),
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: theme.textSubtle,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            SizedBox(height: theme.spacing.sm),
                            Text(
                              context.l10n.viewportPaddingDescription,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: theme.textSubtle),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        footer:
            compactKeyboardLayout ||
                (showStandaloneShortcutEditor && compactLayout)
            ? null
            : showStandaloneShortcutEditor
            ? Align(
                alignment: Alignment.centerRight,
                child: AppActionButton(
                  buttonKey: const Key('defaults-shortcuts-done'),
                  label: context.l10n.done,
                  onPressed: () => _setShortcutEditorVisible(false),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final resetActions = Wrap(
                    key: const Key('defaults-footer-reset-actions'),
                    spacing: theme.spacing.sm,
                    runSpacing: theme.spacing.sm,
                    children: [
                      AppActionButton(
                        tone: AppActionTone.secondary,
                        size: AppActionSize.compact,
                        label: context.l10n.resetDefault,
                        onPressed: _selectedProfileId == null
                            ? null
                            : () {
                                setState(() {
                                  _selectedProfileId = null;
                                  _selectedTerminalPresetId =
                                      _matchingPresetIdFor(
                                        _effectiveProfileFor(
                                          configuredProfileId: null,
                                          effectiveProfileId:
                                              widget.effectiveDefaultProfileId,
                                        ),
                                      );
                                });
                              },
                      ),
                      AppActionButton(
                        tone: AppActionTone.secondary,
                        size: AppActionSize.compact,
                        label: context.l10n.resetTheme,
                        onPressed:
                            _selectedThemeMode == TerminalThemeMode.system &&
                                _selectedTerminalViewportPadding ==
                                    TerminalAppAppearance
                                        .defaultTerminalViewportPadding
                            ? null
                            : () {
                                setState(() {
                                  _selectedThemeMode = TerminalThemeMode.system;
                                  _selectedTerminalViewportPadding =
                                      TerminalAppAppearance
                                          .defaultTerminalViewportPadding;
                                });
                              },
                      ),
                    ],
                  );
                  final confirmationActions = Wrap(
                    key: const Key('defaults-footer-confirmation-actions'),
                    spacing: theme.spacing.sm,
                    runSpacing: theme.spacing.sm,
                    children: [
                      AppActionButton(
                        buttonKey: const Key('defaults-cancel'),
                        tone: AppActionTone.secondary,
                        label: context.l10n.cancel,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      AppActionButton(
                        buttonKey: const Key('defaults-save'),
                        label: _migratesLocalDataToRemote
                            ? context.l10n.migrateToRemoteApi
                            : _migratesRemoteDataToLocal
                            ? context.l10n.migrateToLocalApi
                            : context.l10n.saveChanges,
                        onPressed:
                            LocalTerminalKeyBindingResolver.conflicts(
                                  LocalTerminalKeyBindingResolver.resolve(
                                    config: _selectedKeybindings,
                                  ),
                                ).isNotEmpty ||
                                selectedDataApiConfiguration == null ||
                                (_requiresRemoteLogin &&
                                    remoteLoginRequest == null) ||
                                !hasChanges
                            ? null
                            : () {
                                Navigator.of(context).pop(
                                  DefaultsAndAppearanceSelection(
                                    configuredDefaultProfileId:
                                        _selectedProfileId,
                                    themeMode: _selectedThemeMode,
                                    languageMode: _selectedLanguageMode,
                                    terminalViewportPadding:
                                        _selectedTerminalViewportPadding,
                                    restoreLayout: _selectedRestoreLayout,
                                    osc52Policy: _selectedOsc52Policy,
                                    openUrlPolicy: _selectedOpenUrlPolicy,
                                    requestAttentionPolicy:
                                        _selectedRequestAttentionPolicy,
                                    reportVariableDecisions:
                                        _selectedReportVariableDecisions,
                                    keybindings: _selectedKeybindings,
                                    dataApiConfiguration:
                                        selectedDataApiConfiguration,
                                    dataApiRemoteLogin: remoteLoginRequest,
                                    migrateLocalDataToRemote:
                                        _migratesLocalDataToRemote,
                                    migrateRemoteDataToLocal:
                                        _migratesRemoteDataToLocal,
                                    updatedProfile: _updatedProfileForPreset(
                                      effectiveProfile,
                                    ),
                                    openProfiles: false,
                                  ),
                                );
                              },
                      ),
                    ],
                  );
                  if (constraints.maxWidth < 800) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: resetActions,
                        ),
                        SizedBox(height: theme.spacing.md),
                        Align(
                          alignment: Alignment.centerRight,
                          child: confirmationActions,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      resetActions,
                      const Spacer(),
                      confirmationActions,
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _DefaultsBodyLayout extends StatelessWidget {
  const _DefaultsBodyLayout({
    required this.showNavigation,
    required this.selectedSection,
    required this.onSectionSelected,
    required this.child,
  });

  final bool showNavigation;
  final _DefaultsSection selectedSection;
  final ValueChanged<_DefaultsSection> onSectionSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!showNavigation) {
      return child;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 196,
          child: _DefaultsSectionNavigation(
            selectedSection: selectedSection,
            onSectionSelected: onSectionSelected,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: child),
      ],
    );
  }
}

class _DefaultsSectionNavigation extends StatelessWidget {
  const _DefaultsSectionNavigation({
    required this.selectedSection,
    required this.onSectionSelected,
  });

  final _DefaultsSection selectedSection;
  final ValueChanged<_DefaultsSection> onSectionSelected;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final items =
        <({_DefaultsSection section, IconData icon, String label, Key key})>[
          (
            section: _DefaultsSection.general,
            icon: Icons.tune_rounded,
            label: context.l10n.general,
            key: const Key('defaults-section-general'),
          ),
          (
            section: _DefaultsSection.appearance,
            icon: Icons.palette_outlined,
            label: context.l10n.appearance,
            key: const Key('defaults-section-appearance'),
          ),
          (
            section: _DefaultsSection.shortcuts,
            icon: Icons.keyboard_outlined,
            label: context.l10n.keyboardShortcuts,
            key: const Key('defaults-section-shortcuts'),
          ),
          (
            section: _DefaultsSection.security,
            icon: Icons.shield_outlined,
            label: context.l10n.securityPermissions,
            key: const Key('defaults-section-security'),
          ),
          (
            section: _DefaultsSection.data,
            icon: Icons.storage_rounded,
            label: context.l10n.dataService,
            key: const Key('defaults-section-data'),
          ),
        ];
    return ColoredBox(
      color: theme.chrome.withValues(alpha: 0.42),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          theme.spacing.lg,
          theme.spacing.xl,
          theme.spacing.lg,
          theme.spacing.xl,
        ),
        child: FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in items) ...[
                _DefaultsSectionNavigationItem(
                  key: item.key,
                  icon: item.icon,
                  label: item.label,
                  selected: item.section == selectedSection,
                  onPressed: () => onSectionSelected(item.section),
                ),
                SizedBox(height: theme.spacing.xs),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DefaultsSectionNavigationItem extends StatelessWidget {
  const _DefaultsSectionNavigationItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final radius = BorderRadius.circular(theme.radius.md);
    final foreground = selected ? theme.accent : theme.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? theme.selected.withValues(alpha: 0.68)
            : theme.selected.withValues(alpha: 0),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
                  width: 3,
                  height: selected ? 30 : 0,
                  decoration: BoxDecoration(
                    color: selected
                        ? theme.accent
                        : theme.accent.withValues(alpha: 0),
                    borderRadius: BorderRadius.circular(theme.radius.sm),
                  ),
                ),
                SizedBox(width: theme.spacing.md),
                Icon(icon, size: 20, color: foreground),
                SizedBox(width: theme.spacing.md),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: selected ? theme.accent : theme.textPrimary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(width: theme.spacing.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DefaultsSectionIntro extends StatelessWidget {
  const _DefaultsSectionIntro({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: theme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: theme.spacing.xs),
        Text(
          description,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: theme.textSubtle),
        ),
        SizedBox(height: theme.spacing.xl),
        const Divider(height: 1),
      ],
    );
  }
}

class _TerminalPermissionsPanel extends StatelessWidget {
  const _TerminalPermissionsPanel({
    required this.osc52Policy,
    required this.openUrlPolicy,
    required this.requestAttentionPolicy,
    required this.selectedDetail,
    required this.reportVariableDecisionCount,
    required this.allowedReportVariableCount,
    required this.deniedReportVariableCount,
    required this.reportVariableManagementOpen,
    required this.onOsc52Changed,
    required this.onOpenUrlChanged,
    required this.onRequestAttentionChanged,
    required this.onDetailSelected,
    required this.onManageReportVariables,
  });

  final LocalTerminalOsc52Policy osc52Policy;
  final LocalTerminalOpenUrlPolicy openUrlPolicy;
  final LocalTerminalRequestAttentionPolicy requestAttentionPolicy;
  final _TerminalPermissionKind selectedDetail;
  final int reportVariableDecisionCount;
  final int allowedReportVariableCount;
  final int deniedReportVariableCount;
  final bool reportVariableManagementOpen;
  final ValueChanged<LocalTerminalOsc52Policy> onOsc52Changed;
  final ValueChanged<LocalTerminalOpenUrlPolicy> onOpenUrlChanged;
  final ValueChanged<LocalTerminalRequestAttentionPolicy>
  onRequestAttentionChanged;
  final ValueChanged<_TerminalPermissionKind> onDetailSelected;
  final VoidCallback onManageReportVariables;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final reportSummary = reportVariableDecisionCount == 0
        ? context.l10n.noRememberedDecisions
        : context.l10n.rememberedDecisionSummary(
            reportVariableDecisionCount,
            allowedReportVariableCount,
            deniedReportVariableCount,
          );
    final detail = switch (selectedDetail) {
      _TerminalPermissionKind.osc52 => (
        title: context.l10n.osc52Clipboard,
        protocol: 'OSC 52',
        policy: context.l10n.osc52PolicyName(osc52Policy.name),
        recommended: osc52Policy == LocalTerminalOsc52Policy.profile,
        risk: switch (osc52Policy) {
          LocalTerminalOsc52Policy.disabled ||
          LocalTerminalOsc52Policy.ask => _PermissionRisk.low,
          LocalTerminalOsc52Policy.profile => _PermissionRisk.medium,
          LocalTerminalOsc52Policy.allow => _PermissionRisk.high,
        },
        description: context.l10n.osc52PolicyDescription(osc52Policy.name),
        recommendation: context.l10n.permissionRecommendation('osc52'),
      ),
      _TerminalPermissionKind.openUrl => (
        title: context.l10n.terminalUrlRequests,
        protocol: 'OSC 1337 OpenURL',
        policy: context.l10n.openUrlPolicyName(openUrlPolicy.name),
        recommended: openUrlPolicy == LocalTerminalOpenUrlPolicy.ask,
        risk: switch (openUrlPolicy) {
          LocalTerminalOpenUrlPolicy.disabled => _PermissionRisk.low,
          LocalTerminalOpenUrlPolicy.ask => _PermissionRisk.medium,
        },
        description: context.l10n.openUrlPolicyDescription(openUrlPolicy.name),
        recommendation: context.l10n.permissionRecommendation('openUrl'),
      ),
      _TerminalPermissionKind.requestAttention => (
        title: context.l10n.terminalAttentionRequests,
        protocol: 'OSC 1337 RequestAttention',
        policy: context.l10n.requestAttentionPolicyName(
          requestAttentionPolicy.name,
        ),
        recommended:
            requestAttentionPolicy ==
            LocalTerminalRequestAttentionPolicy.disabled,
        risk: switch (requestAttentionPolicy) {
          LocalTerminalRequestAttentionPolicy.disabled => _PermissionRisk.low,
          LocalTerminalRequestAttentionPolicy.allow => _PermissionRisk.medium,
        },
        description: context.l10n.requestAttentionPolicyDescription(
          requestAttentionPolicy.name,
        ),
        recommendation: context.l10n.permissionRecommendation('attention'),
      ),
    };
    final policyList = AppPanel(
      tone: AppPanelTone.panel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(theme.radius.md),
        child: Column(
          children: [
            _PermissionPolicyRow<LocalTerminalOsc52Policy>(
              panelKey: const Key('defaults-osc52-options'),
              dropdownKey: const Key('defaults-osc52-policy-dropdown'),
              icon: Icons.content_paste_outlined,
              title: context.l10n.osc52Clipboard,
              description: context.l10n.osc52ClipboardDescription,
              protocol: 'OSC 52',
              selected: selectedDetail == _TerminalPermissionKind.osc52,
              value: osc52Policy,
              values: LocalTerminalOsc52Policy.values,
              labelFor: (value) => context.l10n.osc52PolicyName(value.name),
              optionKeyFor: (value) =>
                  Key('default-osc52-policy-${value.name}'),
              onChanged: onOsc52Changed,
              onFocused: () => onDetailSelected(_TerminalPermissionKind.osc52),
            ),
            const Divider(height: 1),
            _PermissionPolicyRow<LocalTerminalOpenUrlPolicy>(
              panelKey: const Key('defaults-open-url-options'),
              dropdownKey: const Key('defaults-open-url-policy-dropdown'),
              icon: Icons.link_rounded,
              title: context.l10n.terminalUrlRequests,
              description: context.l10n.terminalUrlRequestsDescription,
              protocol: 'OSC 1337 OpenURL',
              selected: selectedDetail == _TerminalPermissionKind.openUrl,
              value: openUrlPolicy,
              values: LocalTerminalOpenUrlPolicy.values,
              labelFor: (value) => context.l10n.openUrlPolicyName(value.name),
              optionKeyFor: (value) =>
                  Key('default-osc1337-open-url-policy-${value.name}'),
              onChanged: onOpenUrlChanged,
              onFocused: () =>
                  onDetailSelected(_TerminalPermissionKind.openUrl),
            ),
            const Divider(height: 1),
            _PermissionPolicyRow<LocalTerminalRequestAttentionPolicy>(
              panelKey: const Key('defaults-request-attention-options'),
              dropdownKey: const Key(
                'defaults-request-attention-policy-dropdown',
              ),
              icon: Icons.notifications_none_rounded,
              title: context.l10n.terminalAttentionRequests,
              description: context.l10n.terminalAttentionRequestsDescription,
              protocol: 'OSC 1337 RequestAttention',
              selected:
                  selectedDetail == _TerminalPermissionKind.requestAttention,
              value: requestAttentionPolicy,
              values: LocalTerminalRequestAttentionPolicy.values,
              labelFor: (value) =>
                  context.l10n.requestAttentionPolicyName(value.name),
              optionKeyFor: (value) =>
                  Key('default-osc1337-request-attention-policy-${value.name}'),
              onChanged: onRequestAttentionChanged,
              onFocused: () =>
                  onDetailSelected(_TerminalPermissionKind.requestAttention),
            ),
            const Divider(height: 1),
            KeyedSubtree(
              key: const Key('defaults-report-variable-panel'),
              child: _ReportVariablesRow(
                summary: reportSummary,
                expanded: reportVariableManagementOpen,
                onPressed: onManageReportVariables,
              ),
            ),
          ],
        ),
      ),
    );
    final detailPanel = _PermissionDetail(
      title: detail.title,
      protocol: detail.protocol,
      policy: detail.policy,
      recommended: detail.recommended,
      risk: detail.risk,
      description: detail.description,
      recommendation: detail.recommendation,
    );
    return KeyedSubtree(
      key: const Key('defaults-terminal-permissions-panel'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 680) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                policyList,
                SizedBox(height: theme.spacing.sm),
                detailPanel,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: policyList),
              SizedBox(width: theme.spacing.sm),
              Expanded(flex: 2, child: detailPanel),
            ],
          );
        },
      ),
    );
  }
}

class _PermissionPolicyRow<T extends Enum> extends StatelessWidget {
  const _PermissionPolicyRow({
    required this.panelKey,
    required this.dropdownKey,
    required this.icon,
    required this.title,
    required this.description,
    required this.protocol,
    required this.selected,
    required this.value,
    required this.values,
    required this.labelFor,
    required this.optionKeyFor,
    required this.onChanged,
    required this.onFocused,
  });

  final Key panelKey;
  final Key dropdownKey;
  final IconData icon;
  final String title;
  final String description;
  final String protocol;
  final bool selected;
  final T value;
  final List<T> values;
  final String Function(T value) labelFor;
  final Key Function(T value) optionKeyFor;
  final ValueChanged<T> onChanged;
  final VoidCallback onFocused;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final text = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: theme.spacing.xs),
          child: Icon(icon, size: 22, color: theme.textMuted),
        ),
        SizedBox(width: theme.spacing.xl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: theme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: theme.spacing.xs),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
              ),
              SizedBox(height: theme.spacing.xs),
              Text(
                '${context.l10n.protocol}: $protocol',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: theme.textSubtle),
              ),
            ],
          ),
        ),
      ],
    );
    final dropdown = Semantics(
      label: '$title, ${labelFor(value)}',
      child: Focus(
        onFocusChange: (focused) {
          if (focused) {
            onFocused();
          }
        },
        child: SizedBox(
          width: 136,
          child: KeyedSubtree(
            key: dropdownKey,
            child: AppDropdownFormField<T>(
              key: ValueKey<T>(value),
              initialValue: value,
              isExpanded: true,
              decoration: InputDecoration(filled: true, fillColor: theme.panel),
              items: [
                for (final option in values)
                  DropdownMenuItem<T>(
                    key: optionKeyFor(option),
                    value: option,
                    child: Text(
                      labelFor(option),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (next) {
                if (next != null) {
                  onChanged(next);
                }
              },
            ),
          ),
        ),
      ),
    );
    return KeyedSubtree(
      key: panelKey,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: selected
              ? theme.selected.withValues(alpha: 0.18)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? theme.accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: InkWell(
          onTap: onFocused,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: theme.spacing.lg,
              vertical: theme.spacing.lg,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 320) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      text,
                      SizedBox(height: theme.spacing.md),
                      Align(alignment: Alignment.centerRight, child: dropdown),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: text),
                    SizedBox(width: theme.spacing.md),
                    dropdown,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionDetail extends StatelessWidget {
  const _PermissionDetail({
    required this.title,
    required this.protocol,
    required this.policy,
    required this.recommended,
    required this.risk,
    required this.description,
    required this.recommendation,
  });

  final String title;
  final String protocol;
  final String policy;
  final bool recommended;
  final _PermissionRisk risk;
  final String description;
  final String recommendation;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final riskColor = switch (risk) {
      _PermissionRisk.low => theme.success,
      _PermissionRisk.medium => theme.warning,
      _PermissionRisk.high => theme.danger,
    };
    return AppPanel(
      key: const Key('defaults-permission-detail'),
      tone: AppPanelTone.selected,
      border: Border.all(color: theme.focusRing.withValues(alpha: 0.24)),
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.lg,
        vertical: theme.spacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: theme.accent),
              SizedBox(width: theme.spacing.sm),
              Expanded(
                child: Text(
                  context.l10n.securityImpact,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: theme.spacing.lg),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: theme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: theme.spacing.xs),
          Text(
            protocol,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: theme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: theme.spacing.lg),
          const Divider(height: 1),
          SizedBox(height: theme.spacing.lg),
          _PermissionDetailField(
            label: context.l10n.currentPolicy,
            value: policy,
            icon: Icons.verified_user_outlined,
            valueColor: theme.textPrimary,
            badge: recommended ? context.l10n.recommendedSetting : null,
          ),
          SizedBox(height: theme.spacing.lg),
          _PermissionDetailField(
            label: context.l10n.riskLevel,
            value: context.l10n.riskLevelName(risk.name),
            icon: switch (risk) {
              _PermissionRisk.low => Icons.shield_outlined,
              _PermissionRisk.medium => Icons.warning_amber_rounded,
              _PermissionRisk.high => Icons.error_outline_rounded,
            },
            valueColor: riskColor,
            iconColor: riskColor,
          ),
          SizedBox(height: theme.spacing.lg),
          _PermissionDetailField(
            label: context.l10n.behaviorBoundary,
            value: description,
            icon: Icons.rule_outlined,
            valueColor: theme.textMuted,
          ),
          SizedBox(height: theme.spacing.lg),
          _PermissionDetailField(
            label: context.l10n.recommendation,
            value: recommendation,
            icon: Icons.recommend_outlined,
            valueColor: theme.textMuted,
          ),
        ],
      ),
    );
  }
}

class _PermissionDetailField extends StatelessWidget {
  const _PermissionDetailField({
    required this.label,
    required this.value,
    required this.icon,
    required this.valueColor,
    this.iconColor,
    this.badge,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color valueColor;
  final Color? iconColor;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: theme.spacing.xs),
          child: Icon(icon, size: 14, color: iconColor ?? theme.textSubtle),
        ),
        SizedBox(width: theme.spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: theme.textSubtle,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: theme.spacing.xs),
              Wrap(
                spacing: theme.spacing.sm,
                runSpacing: theme.spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    value,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: valueColor),
                  ),
                  if (badge != null)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.selected.withValues(alpha: 0.44),
                        borderRadius: BorderRadius.circular(theme.radius.sm),
                        border: Border.all(
                          color: theme.focusRing.withValues(alpha: 0.42),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: theme.spacing.sm,
                          vertical: theme.spacing.xs / 2,
                        ),
                        child: Text(
                          badge!,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: theme.accent,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReportVariablesRow extends StatelessWidget {
  const _ReportVariablesRow({
    required this.summary,
    required this.expanded,
    required this.onPressed,
  });

  final String summary;
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.xl,
        vertical: theme.spacing.lg,
      ),
      child: Row(
        children: [
          Icon(Icons.terminal_rounded, size: 22, color: theme.textMuted),
          SizedBox(width: theme.spacing.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OSC 1337 ReportVariable',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: theme.spacing.xs),
                Text(
                  context.l10n.terminalVariableReportsDescription,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
                ),
                SizedBox(height: theme.spacing.xs),
                Text(
                  summary,
                  key: const Key(
                    'default-osc1337-report-variable-decision-summary',
                  ),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: theme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: theme.spacing.xl),
          AppActionButton(
            buttonKey: const Key('defaults-manage-report-variables'),
            tone: AppActionTone.secondary,
            size: AppActionSize.compact,
            icon: expanded ? Icons.expand_less_rounded : Icons.tune_rounded,
            label: context.l10n.manageDecisions,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

class _ShortcutSettingsEntry extends StatelessWidget {
  const _ShortcutSettingsEntry({
    required this.compact,
    required this.onPressed,
  });

  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(theme.radius.md);
    return AppPanel(
      tone: AppPanelTone.panel,
      borderRadius: radius,
      child: Semantics(
        button: true,
        label: context.l10n.manageShortcuts,
        hint: context.l10n.keyboardShortcutsNavigationDescription,
        child: InkWell(
          key: const Key('defaults-shortcuts-entry'),
          borderRadius: radius,
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 64 : 72),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: theme.spacing.md,
                vertical: theme.spacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.keyboard_rounded,
                    size: 20,
                    color: theme.textMuted,
                  ),
                  SizedBox(width: theme.spacing.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.keyboardShortcuts,
                          style: textTheme.bodyMedium?.copyWith(
                            color: theme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: theme.spacing.xs),
                        Text(
                          context.l10n.keyboardShortcutsNavigationDescription,
                          maxLines: compact ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: theme.textSubtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: theme.spacing.md),
                  if (!compact)
                    Text(
                      context.l10n.manageShortcuts,
                      style: textTheme.labelLarge?.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  SizedBox(width: theme.spacing.xs),
                  Icon(Icons.chevron_right_rounded, color: theme.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfilesNotice extends StatelessWidget {
  const _ProfilesNotice({
    required this.effectiveProfile,
    required this.onOpenProfiles,
  });

  final TerminalProfile? effectiveProfile;
  final VoidCallback? onOpenProfiles;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final textTheme = Theme.of(context).textTheme;
    return AppPanel(
      key: const Key('defaults-profiles-notice'),
      tone: AppPanelTone.panel,
      border: Border.all(color: theme.focusRing.withValues(alpha: 0.20)),
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.lg,
        vertical: theme.spacing.md,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summary = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: theme.spacing.xs),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: theme.focusRing,
                ),
              ),
              SizedBox(width: theme.spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.detailedSettingsInProfiles,
                      style: textTheme.bodyMedium?.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: theme.spacing.xs),
                    Text(
                      context.l10n.editTerminalDetailsInProfiles,
                      maxLines: constraints.maxWidth >= 620 ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: theme.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final profile = effectiveProfile;
          if (profile == null) {
            return summary;
          }
          final action = Tooltip(
            message: context.l10n.editProfileInProfiles(profile.name),
            child: AppActionButton(
              buttonKey: const Key('defaults-open-profiles'),
              tone: AppActionTone.secondary,
              size: AppActionSize.compact,
              icon: Icons.tune_rounded,
              label: context.l10n.editProfile,
              onPressed: onOpenProfiles,
            ),
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                SizedBox(height: theme.spacing.md),
                Align(alignment: Alignment.centerLeft, child: action),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: summary),
              SizedBox(width: theme.spacing.lg),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _SettingsRadioOptionData<T> {
  const _SettingsRadioOptionData({
    required this.tileKey,
    required this.value,
    required this.title,
    required this.subtitle,
  });

  final Key tileKey;
  final T value;
  final String title;
  final String subtitle;
}

class _SettingsRadioPanel<T> extends StatelessWidget {
  const _SettingsRadioPanel({
    required this.panelKey,
    required this.groupValue,
    required this.onChanged,
    required this.options,
  });

  final Key panelKey;
  final T groupValue;
  final ValueChanged<T?> onChanged;
  final List<_SettingsRadioOptionData<T>> options;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return AppPanel(
      key: panelKey,
      tone: AppPanelTone.panel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(theme.radius.md),
        child: Theme(
          data: Theme.of(
            context,
          ).copyWith(hoverColor: theme.focusRing.withValues(alpha: 0.05)),
          child: RadioGroup<T>(
            groupValue: groupValue,
            onChanged: onChanged,
            child: Column(
              children: [
                for (var index = 0; index < options.length; index++) ...[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: options[index].value == groupValue
                          ? theme.selected.withValues(alpha: 0.20)
                          : Colors.transparent,
                      border: Border(
                        left: BorderSide(
                          color: options[index].value == groupValue
                              ? theme.accent
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: theme.spacing.md,
                      vertical: 0,
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: AppCompactRadioTile<T>(
                        tileKey: options[index].tileKey,
                        value: options[index].value,
                        title: Text(options[index].title),
                        subtitle: Text(options[index].subtitle),
                      ),
                    ),
                  ),
                  if (index != options.length - 1)
                    Divider(
                      height: 1,
                      indent: theme.spacing.xl,
                      endIndent: theme.spacing.xl,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DataServiceComparisonHeader extends StatelessWidget {
  const _DataServiceComparisonHeader();

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: theme.textSubtle,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        theme.controls.regular + theme.spacing.sm,
        theme.spacing.xs,
        theme.spacing.md,
        theme.spacing.xs,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 132,
            child: Text(context.l10n.dataServiceMode, style: labelStyle),
          ),
          Expanded(child: Text(context.l10n.apiService, style: labelStyle)),
          Expanded(
            child: Text(
              context.l10n.configurationAndStorage,
              style: labelStyle,
            ),
          ),
          Expanded(
            child: Text(context.l10n.crossDeviceSync, style: labelStyle),
          ),
        ],
      ),
    );
  }
}

class _DataServiceModeChoice extends StatefulWidget {
  const _DataServiceModeChoice({
    required this.tileKey,
    required this.value,
    required this.title,
    required this.description,
    required this.selected,
    required this.active,
    required this.showComparison,
  });

  final Key tileKey;
  final DataApiDeployment value;
  final String title;
  final String description;
  final bool selected;
  final bool active;
  final bool showComparison;

  @override
  State<_DataServiceModeChoice> createState() => _DataServiceModeChoiceState();
}

class _DataServiceModeChoiceState extends State<_DataServiceModeChoice> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final selected = widget.selected;
    final highlighted = _hovered || _focused;
    final titleWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: theme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (selected) ...[
          SizedBox(height: theme.spacing.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 11,
                color: theme.accent,
              ),
              SizedBox(width: theme.spacing.xs),
              Text(
                context.l10n.selected,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: theme.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ] else if (widget.active) ...[
          SizedBox(height: theme.spacing.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: theme.success),
              SizedBox(width: theme.spacing.xs),
              Text(
                context.l10n.running,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: theme.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ],
    );
    final content = widget.showComparison
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 132, child: titleWidget),
              Expanded(
                child: _DataServiceMetric(
                  value: context.l10n.dataModeApiSummary(widget.value.name),
                ),
              ),
              Expanded(
                child: _DataServiceMetric(
                  value: context.l10n.dataModeStorageSummary(widget.value.name),
                ),
              ),
              Expanded(
                child: _DataServiceMetric(
                  value: context.l10n.dataModeSyncSummary(widget.value.name),
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleWidget,
              SizedBox(height: theme.spacing.xs),
              Text(
                widget.description,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
              ),
            ],
          );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        onFocusChange: (value) => setState(() => _focused = value),
        child: AnimatedContainer(
          key: Key('data-api-${widget.value.name}-surface'),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          margin: EdgeInsets.symmetric(vertical: theme.spacing.xs / 2),
          padding: EdgeInsets.symmetric(horizontal: theme.spacing.sm),
          decoration: BoxDecoration(
            color: selected
                ? theme.selected.withValues(alpha: highlighted ? 0.26 : 0.18)
                : highlighted
                ? theme.selected.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(theme.radius.md),
            border: Border.all(
              color: selected
                  ? theme.focusRing
                  : highlighted
                  ? theme.borderStrong
                  : theme.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: AppCompactRadioTile<DataApiDeployment>(
                tileKey: widget.tileKey,
                value: widget.value,
                title: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DataServiceMetric extends StatelessWidget {
  const _DataServiceMetric({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Padding(
      padding: EdgeInsets.only(right: theme.spacing.sm),
      child: Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: theme.textMuted),
      ),
    );
  }
}

class _DataServiceStatusBanner extends StatelessWidget {
  const _DataServiceStatusBanner({
    required this.deployment,
    required this.localSessionsEnabled,
  });

  final DataApiDeployment deployment;
  final bool localSessionsEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final serviceName = _dataServiceName(
      context.l10n,
      deployment,
      localSessionsEnabled: localSessionsEnabled,
    );
    final icon = switch (deployment) {
      DataApiDeployment.disabled => Icons.computer_rounded,
      DataApiDeployment.local => Icons.dns_rounded,
      DataApiDeployment.remote => Icons.cloud_outlined,
    };
    return Semantics(
      key: const Key('data-api-active-deployment'),
      container: true,
      label: context.l10n.activeDataService(serviceName),
      child: AppPanel(
        tone: AppPanelTone.selected,
        border: Border.all(color: theme.focusRing.withValues(alpha: 0.24)),
        padding: EdgeInsets.symmetric(
          horizontal: theme.spacing.lg,
          vertical: theme.spacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: theme.accent),
            SizedBox(width: theme.spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.currentlyRunning(serviceName),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: theme.spacing.xs),
                  Text(
                    _dataServiceDescription(
                      context.l10n,
                      deployment,
                      localSessionsEnabled: localSessionsEnabled,
                    ),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
                  ),
                ],
              ),
            ),
            SizedBox(width: theme.spacing.md),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 9, color: theme.success),
                SizedBox(width: theme.spacing.xs),
                Text(
                  context.l10n.running,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: theme.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _defaultProfileSubtitle(TerminalProfile profile) {
  if (!profile.isSsh) {
    return profile.shell;
  }
  final connection = profile.connection;
  final host = connection.host.contains(':')
      ? '[${connection.host}]'
      : connection.host;
  return 'SSH • ${connection.user}@$host:${connection.port}';
}

String _dataServiceName(
  AppLocalizations l10n,
  DataApiDeployment deployment, {
  required bool localSessionsEnabled,
}) {
  return switch (deployment) {
    DataApiDeployment.disabled =>
      localSessionsEnabled ? l10n.localTerminal : l10n.noDataService,
    DataApiDeployment.local => l10n.bundledLocalService,
    DataApiDeployment.remote => l10n.remoteService,
  };
}

String _dataServiceDescription(
  AppLocalizations l10n,
  DataApiDeployment deployment, {
  required bool localSessionsEnabled,
}) {
  return switch (deployment) {
    DataApiDeployment.disabled =>
      localSessionsEnabled
          ? l10n.localTerminalNoApiDescription
          : l10n.noDataServiceDescription,
    DataApiDeployment.local => l10n.bundledLocalServiceDescription,
    DataApiDeployment.remote => l10n.remoteServiceDescription,
  };
}

String themeModeLabel(TerminalThemeMode mode) {
  return switch (mode) {
    TerminalThemeMode.system => 'System',
    TerminalThemeMode.light => 'Light',
    TerminalThemeMode.dark => 'Dark',
  };
}

String osc52PolicyLabel(LocalTerminalOsc52Policy policy) {
  return switch (policy) {
    LocalTerminalOsc52Policy.disabled => 'Deny',
    LocalTerminalOsc52Policy.profile => 'Profile',
    LocalTerminalOsc52Policy.allow => 'Allow',
    LocalTerminalOsc52Policy.ask => 'Ask',
  };
}

String osc52PolicyDescription(LocalTerminalOsc52Policy policy) {
  return switch (policy) {
    LocalTerminalOsc52Policy.disabled =>
      'Block OSC 52 clipboard copy and paste-read requests.',
    LocalTerminalOsc52Policy.profile =>
      'Allow clipboard writes and prompt before paste-read requests.',
    LocalTerminalOsc52Policy.allow =>
      'Allow trusted terminal sessions to use OSC 52 without prompting.',
    LocalTerminalOsc52Policy.ask =>
      'Prompt before each OSC 52 clipboard write or paste-read request.',
  };
}

String openUrlPolicyLabel(LocalTerminalOpenUrlPolicy policy) {
  return switch (policy) {
    LocalTerminalOpenUrlPolicy.disabled => 'Deny',
    LocalTerminalOpenUrlPolicy.ask => 'Ask every time',
  };
}

String openUrlPolicyDescription(LocalTerminalOpenUrlPolicy policy) {
  return switch (policy) {
    LocalTerminalOpenUrlPolicy.disabled =>
      'Block every OSC 1337 OpenURL request without showing a dialog.',
    LocalTerminalOpenUrlPolicy.ask =>
      'Require confirmation for each accepted request from the active terminal.',
  };
}

String requestAttentionPolicyLabel(LocalTerminalRequestAttentionPolicy policy) {
  return switch (policy) {
    LocalTerminalRequestAttentionPolicy.disabled => 'Deny',
    LocalTerminalRequestAttentionPolicy.allow => 'Allow with limits',
  };
}

String requestAttentionPolicyDescription(
  LocalTerminalRequestAttentionPolicy policy,
) {
  return switch (policy) {
    LocalTerminalRequestAttentionPolicy.disabled =>
      'Block OSC 1337 RequestAttention. Cancellation requests are still honored.',
    LocalTerminalRequestAttentionPolicy.allow =>
      'Allow rate-limited Dock attention and a short cursor-local visual effect.',
  };
}

List<String> _previewColorsForPalette(TerminalColorPalette palette) {
  final resolved = palette.resolveWith();
  return <String>[
    resolved.special.foreground!,
    resolved.special.background!,
    resolved.normal.red!,
    resolved.normal.green!,
    resolved.normal.blue!,
    resolved.bright.yellow!,
    resolved.special.cursor!,
    resolved.special.selection!,
  ];
}

class _TerminalPresetChoice extends StatelessWidget {
  const _TerminalPresetChoice({
    super.key,
    required this.width,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.previewColors,
    required this.onPressed,
  });

  final double width;
  final String label;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final List<String> previewColors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final textTheme = Theme.of(context).textTheme;
    final foreground = enabled ? theme.textPrimary : theme.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? context.l10n.selectedTerminalPreset(label) : label,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(theme.radius.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: width,
          constraints: const BoxConstraints(minHeight: 68),
          padding: EdgeInsets.all(theme.spacing.md),
          decoration: BoxDecoration(
            color: selected
                ? theme.selected.withValues(alpha: 0.20)
                : theme.overlay.withValues(alpha: enabled ? 0.52 : 0.24),
            borderRadius: BorderRadius.circular(theme.radius.md),
            border: Border.all(
              color: selected ? theme.focusRing : theme.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 15,
                      color: theme.focusRing,
                    ),
                ],
              ),
              SizedBox(height: theme.spacing.xs),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: enabled ? theme.textSubtle : theme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: theme.spacing.sm),
              Row(
                children: [
                  for (final color in previewColors.take(6))
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: theme.spacing.xs / 2),
                        child: _TerminalPresetSwatch(color: color),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalPresetSwatch extends StatelessWidget {
  const _TerminalPresetSwatch({required this.color});

  final String color;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: terminalViewportColorFromHex(color) ?? Colors.transparent,
        borderRadius: BorderRadius.circular(theme.radius.sm / 2),
        border: Border.all(color: theme.borderStrong.withValues(alpha: 0.56)),
      ),
      child: const SizedBox(height: 16),
    );
  }
}
