import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/local_terminal_config_models.dart';
import '../config/local_terminal_keybinding_resolver.dart';
import '../policies/local_terminal_policy_models.dart';
import '../preferences/app_preferences_models.dart';
import '../profiles/profile_models.dart';
import '../profiles/widgets/toggle_setting_row.dart';
import '../terminal/terminal_viewport_colors.dart';
import '../../ui/app_ui.dart';
import 'shell_action_registry.dart';

class DefaultsAndAppearanceSelection {
  const DefaultsAndAppearanceSelection({
    required this.configuredDefaultProfileId,
    required this.themeMode,
    required this.terminalViewportPadding,
    required this.osc52Policy,
    required this.openUrlPolicy,
    required this.requestAttentionPolicy,
    required this.reportVariableDecisions,
    required this.keybindings,
    required this.workspace,
    required this.globalCopyOnSelect,
    required this.paste,
    required this.shellIntegration,
    required this.notifications,
    required this.hotkeyWindow,
    this.updatedProfile,
    this.openProfiles = false,
  });

  final String? configuredDefaultProfileId;
  final TerminalThemeMode themeMode;
  final double terminalViewportPadding;
  final LocalTerminalOsc52Policy osc52Policy;
  final LocalTerminalOpenUrlPolicy openUrlPolicy;
  final LocalTerminalRequestAttentionPolicy requestAttentionPolicy;
  final Map<String, LocalTerminalReportVariablePolicy> reportVariableDecisions;
  final LocalTerminalKeybindingsConfig keybindings;
  final LocalTerminalWorkspaceConfig workspace;
  final bool globalCopyOnSelect;
  final LocalTerminalPasteConfig paste;
  final LocalTerminalShellIntegrationConfig shellIntegration;
  final LocalTerminalNotificationsConfig notifications;
  final LocalTerminalHotkeyWindowConfig hotkeyWindow;
  final TerminalProfile? updatedProfile;
  final bool openProfiles;
}

class DefaultsAndAppearanceDialog extends StatefulWidget {
  const DefaultsAndAppearanceDialog({
    super.key,
    required this.profiles,
    required this.configuredDefaultProfileId,
    required this.effectiveDefaultProfileId,
    required this.themeMode,
    required this.terminalViewportPadding,
    required this.osc52Policy,
    required this.openUrlPolicy,
    required this.requestAttentionPolicy,
    required this.reportVariableDecisions,
    required this.localConfig,
  });

  final List<TerminalProfile> profiles;
  final String? configuredDefaultProfileId;
  final String? effectiveDefaultProfileId;
  final TerminalThemeMode themeMode;
  final double terminalViewportPadding;
  final LocalTerminalOsc52Policy osc52Policy;
  final LocalTerminalOpenUrlPolicy openUrlPolicy;
  final LocalTerminalRequestAttentionPolicy requestAttentionPolicy;
  final Map<String, LocalTerminalReportVariablePolicy> reportVariableDecisions;
  final LocalTerminalConfigDocument localConfig;

  @override
  State<DefaultsAndAppearanceDialog> createState() =>
      _DefaultsAndAppearanceDialogState();
}

class _DefaultsAndAppearanceDialogState
    extends State<DefaultsAndAppearanceDialog> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _generalSectionKey = GlobalKey();
  final GlobalKey _appearanceSectionKey = GlobalKey();
  final GlobalKey _clipboardSectionKey = GlobalKey();
  final GlobalKey _notificationsSectionKey = GlobalKey();
  final GlobalKey _keyboardSectionKey = GlobalKey();
  final GlobalKey _securitySectionKey = GlobalKey();
  final GlobalKey _advancedSectionKey = GlobalKey();
  late String? _selectedProfileId;
  late String? _selectedTerminalPresetId;
  late TerminalThemeMode _selectedThemeMode;
  late double _selectedTerminalViewportPadding;
  late LocalTerminalOsc52Policy _selectedOsc52Policy;
  late LocalTerminalOpenUrlPolicy _selectedOpenUrlPolicy;
  late LocalTerminalRequestAttentionPolicy _selectedRequestAttentionPolicy;
  late Map<String, LocalTerminalReportVariablePolicy>
  _selectedReportVariableDecisions;
  late LocalTerminalKeybindingsConfig _selectedKeybindings;
  late LocalTerminalWorkspaceConfig _selectedWorkspace;
  late bool _selectedGlobalCopyOnSelect;
  late LocalTerminalPasteConfig _selectedPaste;
  late LocalTerminalShellIntegrationConfig _selectedShellIntegration;
  late LocalTerminalNotificationsConfig _selectedNotifications;
  late LocalTerminalHotkeyWindowConfig _selectedHotkeyWindow;
  String _terminalPresetFilter = '';

  @override
  void initState() {
    super.initState();
    _selectedProfileId = widget.configuredDefaultProfileId;
    _selectedThemeMode = widget.themeMode;
    _selectedTerminalViewportPadding = widget.terminalViewportPadding;
    _selectedOsc52Policy = widget.osc52Policy;
    _selectedOpenUrlPolicy = widget.openUrlPolicy;
    _selectedRequestAttentionPolicy = widget.requestAttentionPolicy;
    _selectedReportVariableDecisions = Map.unmodifiable(
      widget.reportVariableDecisions,
    );
    _selectedKeybindings = widget.localConfig.keybindings;
    _selectedWorkspace = widget.localConfig.workspace;
    _selectedGlobalCopyOnSelect = widget.localConfig.clipboard.copyOnSelect;
    _selectedPaste = widget.localConfig.paste;
    _selectedShellIntegration = widget.localConfig.shellIntegration;
    _selectedNotifications = widget.localConfig.notifications;
    _selectedHotkeyWindow = widget.localConfig.hotkeyWindow;
    _selectedTerminalPresetId = _matchingPresetIdFor(
      _effectiveProfileFor(
        configuredProfileId: _selectedProfileId,
        effectiveProfileId: widget.effectiveDefaultProfileId,
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

  bool _jsonMatches(Object? left, Object? right) {
    return jsonEncode(left) == jsonEncode(right);
  }

  bool _hasChanges(TerminalProfile? effectiveProfile) {
    return _selectedProfileId != widget.configuredDefaultProfileId ||
        _selectedThemeMode != widget.themeMode ||
        _selectedTerminalViewportPadding != widget.terminalViewportPadding ||
        _selectedOsc52Policy != widget.osc52Policy ||
        _selectedOpenUrlPolicy != widget.openUrlPolicy ||
        _selectedRequestAttentionPolicy != widget.requestAttentionPolicy ||
        !_jsonMatches(
          _selectedReportVariableDecisions.map(
            (key, value) => MapEntry(key, value.name),
          ),
          widget.reportVariableDecisions.map(
            (key, value) => MapEntry(key, value.name),
          ),
        ) ||
        !_jsonMatches(
          _selectedKeybindings.toJson(),
          widget.localConfig.keybindings.toJson(),
        ) ||
        !_jsonMatches(
          _selectedWorkspace.toJson(),
          widget.localConfig.workspace.toJson(),
        ) ||
        _selectedGlobalCopyOnSelect !=
            widget.localConfig.clipboard.copyOnSelect ||
        !_jsonMatches(
          _selectedPaste.toJson(),
          widget.localConfig.paste.toJson(),
        ) ||
        !_jsonMatches(
          _selectedShellIntegration.toJson(),
          widget.localConfig.shellIntegration.toJson(),
        ) ||
        !_jsonMatches(
          _selectedNotifications.toJson(),
          widget.localConfig.notifications.toJson(),
        ) ||
        !_jsonMatches(
          _selectedHotkeyWindow.toJson(),
          widget.localConfig.hotkeyWindow.toJson(),
        ) ||
        _updatedProfileForPreset(effectiveProfile) != null;
  }

  bool _terminalPresetMatchesFilter(TerminalThemePreset preset, String filter) {
    if (filter.isEmpty) {
      return true;
    }
    return '${preset.name} ${preset.tone.label}'.toLowerCase().contains(filter);
  }

  Future<void> _jumpToSection(GlobalKey sectionKey) async {
    final sectionContext = sectionKey.currentContext;
    if (sectionContext == null) {
      return;
    }
    await Scrollable.ensureVisible(
      sectionContext,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final mediaSize = MediaQuery.sizeOf(context);
    final dialogWidth = (mediaSize.width - theme.spacing.xxl * 2)
        .clamp(0.0, 720.0)
        .toDouble();
    final dialogHeight = (mediaSize.height - theme.spacing.xxl * 2)
        .clamp(520.0, 720.0)
        .toDouble();
    final effectiveProfile = _effectiveProfileFor(
      configuredProfileId: _selectedProfileId,
      effectiveProfileId: widget.effectiveDefaultProfileId,
    );
    final isUsingFallback = _selectedProfileId == null;
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

    return AppDialogScaffold(
      key: const Key('defaults-dialog'),
      title: 'Settings',
      subtitle:
          'Manage app-wide behavior, profiles, security, notifications, and keyboard access.',
      onClose: () => Navigator.of(context).pop(),
      closeTooltip: 'Close settings',
      constraints: const BoxConstraints(maxWidth: 720),
      width: dialogWidth,
      height: dialogHeight,
      expandBody: true,
      centerInViewport: false,
      titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: theme.textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
      subtitleTextStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: theme.textSubtle),
      headerPadding: EdgeInsets.fromLTRB(
        theme.spacing.xxl,
        theme.spacing.xl,
        theme.spacing.xxl,
        theme.spacing.md,
      ),
      bodyPadding: EdgeInsets.fromLTRB(
        theme.spacing.xxl,
        theme.spacing.xl,
        theme.spacing.md,
        theme.spacing.xl,
      ),
      footerPadding: EdgeInsets.fromLTRB(
        theme.spacing.xxl,
        theme.spacing.md,
        theme.spacing.xxl,
        theme.spacing.md,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsJumpNavigation(
            onGeneral: () => _jumpToSection(_generalSectionKey),
            onAppearance: () => _jumpToSection(_appearanceSectionKey),
            onClipboard: () => _jumpToSection(_clipboardSectionKey),
            onNotifications: () => _jumpToSection(_notificationsSectionKey),
            onKeyboard: () => _jumpToSection(_keyboardSectionKey),
            onSecurity: () => _jumpToSection(_securitySectionKey),
            onAdvanced: () => _jumpToSection(_advancedSectionKey),
          ),
          SizedBox(height: theme.spacing.md),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              radius: Radius.circular(theme.radius.sm),
              thickness: theme.spacing.xs,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsets.only(right: theme.spacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                  terminalViewportPadding:
                                      _selectedTerminalViewportPadding,
                                  osc52Policy: _selectedOsc52Policy,
                                  openUrlPolicy: _selectedOpenUrlPolicy,
                                  requestAttentionPolicy:
                                      _selectedRequestAttentionPolicy,
                                  reportVariableDecisions:
                                      _selectedReportVariableDecisions,
                                  keybindings: _selectedKeybindings,
                                  workspace: _selectedWorkspace,
                                  globalCopyOnSelect:
                                      _selectedGlobalCopyOnSelect,
                                  paste: _selectedPaste,
                                  shellIntegration: _selectedShellIntegration,
                                  notifications: _selectedNotifications,
                                  hotkeyWindow: _selectedHotkeyWindow,
                                  updatedProfile: null,
                                  openProfiles: true,
                                ),
                              );
                            },
                    ),
                    SizedBox(height: theme.spacing.xl),
                    AppSectionHeader(
                      key: _generalSectionKey,
                      title: 'Default profile',
                      description: 'App-wide · Used for newly opened tabs.',
                    ),
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
                                    title: const Text('No configured default'),
                                    subtitle: Text(
                                      effectiveProfile == null
                                          ? 'New tabs stay ready even when no default is configured.'
                                          : 'New tabs use ${effectiveProfile.name} until you choose a default.',
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
                                      subtitle: Text(profile.shell),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Container(
                            key: const Key('defaults-current-profile-summary'),
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                              horizontal: theme.spacing.lg,
                              vertical: theme.spacing.sm + theme.spacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: theme.selected.withValues(alpha: 0.24),
                              borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(theme.radius.md),
                              ),
                            ),
                            child: Text(
                              isUsingFallback
                                  ? 'Current new-tab profile • ${effectiveProfile?.name ?? 'No profile available'}'
                                  : 'Configured default • ${effectiveProfile?.name ?? 'Unknown profile'}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: theme.textMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: theme.spacing.xl),
                    AppSectionHeader(
                      key: _appearanceSectionKey,
                      title: 'Terminal preset',
                      description: effectiveProfile == null
                          ? 'Create a profile before choosing terminal colors.'
                          : 'Apply a curated terminal color palette to ${effectiveProfile.name}.',
                    ),
                    SizedBox(height: theme.spacing.sm),
                    TextField(
                      key: const Key('defaults-terminal-preset-filter'),
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Filter terminal presets',
                      ),
                      onChanged: (value) {
                        setState(() {
                          _terminalPresetFilter = value;
                        });
                      },
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
                                theme.spacing.sm * (columnCount - 1)) /
                            columnCount;
                        return Wrap(
                          key: const Key('defaults-terminal-preset-grid'),
                          spacing: theme.spacing.sm,
                          runSpacing: theme.spacing.sm,
                          children: [
                            if (showCurrentPreset)
                              _TerminalPresetChoice(
                                key: const Key(
                                  'defaults-terminal-preset-current',
                                ),
                                width: cardWidth,
                                label: 'Keep current',
                                subtitle: selectedPreset == null
                                    ? 'Custom colors'
                                    : 'Currently ${selectedPreset.name}',
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
                                    'No terminal presets match "$_terminalPresetFilter".',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: theme.textSubtle),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    SizedBox(height: theme.spacing.xxl),
                    const AppSectionHeader(title: 'Appearance'),
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
                            title: themeModeLabel(themeMode),
                            subtitle: _themeModeDescription(themeMode),
                          ),
                      ],
                    ),
                    SizedBox(height: theme.spacing.xxl),
                    AppSectionHeader(
                      key: _clipboardSectionKey,
                      title: 'Paste & clipboard',
                      description:
                          'App-wide · Applies immediately to selection and future paste actions.',
                    ),
                    SizedBox(height: theme.spacing.sm),
                    AppPanel(
                      key: const Key('settings-paste-clipboard-panel'),
                      tone: AppPanelTone.panel,
                      padding: EdgeInsets.all(theme.spacing.xl),
                      child: Column(
                        children: [
                          ToggleSettingRow(
                            key: const Key('settings-global-copy-on-select'),
                            label: 'Copy selection automatically',
                            description:
                                'Use as the app-wide default; a Profile can also enable this for its own sessions.',
                            value: _selectedGlobalCopyOnSelect,
                            onChanged: (value) {
                              setState(() {
                                _selectedGlobalCopyOnSelect = value;
                              });
                            },
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: theme.spacing.lg,
                            ),
                            child: const Divider(height: 1),
                          ),
                          DropdownButtonFormField<
                            LocalTerminalBracketedPastePolicy
                          >(
                            key: const Key('settings-bracketed-paste'),
                            initialValue: _selectedPaste.bracketedPaste,
                            decoration: const InputDecoration(
                              labelText: 'Bracketed paste',
                              helperText:
                                  'Auto follows the terminal mode; Force and Plain override it.',
                            ),
                            items: [
                              for (final policy
                                  in LocalTerminalBracketedPastePolicy.values)
                                DropdownMenuItem(
                                  value: policy,
                                  child: Text(
                                    _bracketedPastePolicyLabel(policy),
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _selectedPaste = _selectedPaste.copyWith(
                                  bracketedPaste: value,
                                );
                              });
                            },
                          ),
                          SizedBox(height: theme.spacing.md),
                          ToggleSettingRow(
                            key: const Key('settings-confirm-large-paste'),
                            label: 'Confirm large pastes',
                            description:
                                'Ask before sending unusually large clipboard content.',
                            value: _selectedPaste.confirmLargePaste,
                            onChanged: (value) {
                              setState(() {
                                _selectedPaste = _selectedPaste.copyWith(
                                  confirmLargePaste: value,
                                );
                              });
                            },
                          ),
                          ToggleSettingRow(
                            key: const Key('settings-confirm-multiline-paste'),
                            label: 'Confirm multiline pastes',
                            description:
                                'Ask before multiple commands can be submitted together.',
                            value: _selectedPaste.confirmMultilinePaste,
                            onChanged: (value) {
                              setState(() {
                                _selectedPaste = _selectedPaste.copyWith(
                                  confirmMultilinePaste: value,
                                );
                              });
                            },
                          ),
                          SizedBox(height: theme.spacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Paste history',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Text(
                                _selectedPaste.historySize == 0
                                    ? 'Off'
                                    : '${_selectedPaste.historySize} entries',
                                key: const Key('settings-paste-history-value'),
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(color: theme.textMuted),
                              ),
                            ],
                          ),
                          Slider(
                            key: const Key('settings-paste-history-size'),
                            value: _selectedPaste.historySize.toDouble(),
                            min: 0,
                            max: defaultLocalTerminalPasteHistoryEntries
                                .toDouble(),
                            divisions: defaultLocalTerminalPasteHistoryEntries,
                            label: _selectedPaste.historySize == 0
                                ? 'Off'
                                : '${_selectedPaste.historySize}',
                            onChanged: (value) {
                              setState(() {
                                _selectedPaste = _selectedPaste.copyWith(
                                  historySize: value.round(),
                                );
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: theme.spacing.xxl),
                    AppSectionHeader(
                      key: _notificationsSectionKey,
                      title: 'Notifications',
                      description:
                          'App-wide · Saved together here; command-palette toggles remain quick shortcuts.',
                    ),
                    SizedBox(height: theme.spacing.sm),
                    AppPanel(
                      key: const Key('settings-notifications-panel'),
                      tone: AppPanelTone.panel,
                      padding: EdgeInsets.all(theme.spacing.xl),
                      child: Column(
                        children: [
                          ToggleSettingRow(
                            key: const Key('settings-notifications-enabled'),
                            label: 'Enable notifications',
                            description:
                                'Master control for background terminal notifications.',
                            value: _selectedNotifications.enabled,
                            onChanged: (value) {
                              setState(() {
                                _selectedNotifications =
                                    LocalTerminalNotificationsConfig(
                                      enabled: value,
                                      commandFinished: value,
                                      bell: value,
                                      activity: value,
                                    );
                              });
                            },
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: theme.spacing.lg,
                            ),
                            child: const Divider(height: 1),
                          ),
                          ToggleSettingRow(
                            key: const Key('settings-notify-command-finished'),
                            label: 'Command finished',
                            description:
                                'Notify when a shell-integrated command completes in the background.',
                            value: _selectedNotifications.commandFinished,
                            enabled: _selectedNotifications.enabled,
                            onChanged: (value) {
                              setState(() {
                                _selectedNotifications = _selectedNotifications
                                    .copyWith(commandFinished: value);
                              });
                            },
                          ),
                          ToggleSettingRow(
                            key: const Key('settings-notify-bell'),
                            label: 'Terminal bell',
                            description:
                                'Notify when an inactive session emits an audible bell event.',
                            value: _selectedNotifications.bell,
                            enabled: _selectedNotifications.enabled,
                            onChanged: (value) {
                              setState(() {
                                _selectedNotifications = _selectedNotifications
                                    .copyWith(bell: value);
                              });
                            },
                          ),
                          ToggleSettingRow(
                            key: const Key('settings-notify-activity'),
                            label: 'Background activity',
                            description:
                                'Notify when new output appears in an inactive session.',
                            value: _selectedNotifications.activity,
                            enabled: _selectedNotifications.enabled,
                            onChanged: (value) {
                              setState(() {
                                _selectedNotifications = _selectedNotifications
                                    .copyWith(activity: value);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: theme.spacing.xxl),
                    AppSectionHeader(
                      key: _keyboardSectionKey,
                      title: 'Keyboard shortcuts',
                      description:
                          'App-wide · Disable, restore, and inspect effective shortcuts.',
                    ),
                    SizedBox(height: theme.spacing.sm),
                    _KeybindingsSettingsPanel(
                      config: _selectedKeybindings,
                      onChanged: (value) {
                        setState(() {
                          _selectedKeybindings = value;
                        });
                      },
                    ),
                    SizedBox(height: theme.spacing.xxl),
                    AppSectionHeader(
                      key: _securitySectionKey,
                      title: 'Clipboard access from terminal apps',
                      description:
                          'Choose whether terminal programs may copy to or read from the system clipboard. Protocol: OSC 52.',
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
                        for (final policy in LocalTerminalOsc52Policy.values)
                          _SettingsRadioOptionData<LocalTerminalOsc52Policy>(
                            tileKey: Key('default-osc52-policy-${policy.name}'),
                            value: policy,
                            title: osc52PolicyLabel(policy),
                            subtitle: osc52PolicyDescription(policy),
                          ),
                      ],
                    ),
                    SizedBox(height: theme.spacing.xxl),
                    AppSectionHeader(
                      title: 'Terminal URL requests',
                      description:
                          'Choose whether terminal apps can request opening a URL. Every accepted request still requires confirmation. Protocol: OSC 1337 OpenURL.',
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
                        for (final policy in LocalTerminalOpenUrlPolicy.values)
                          _SettingsRadioOptionData<LocalTerminalOpenUrlPolicy>(
                            tileKey: Key(
                              'default-osc1337-open-url-policy-${policy.name}',
                            ),
                            value: policy,
                            title: openUrlPolicyLabel(policy),
                            subtitle: openUrlPolicyDescription(policy),
                          ),
                      ],
                    ),
                    SizedBox(height: theme.spacing.xxl),
                    const AppSectionHeader(
                      title: 'Attention alerts from terminal apps',
                      description:
                          'Allow bounded Dock alerts or a short cursor-local effect. Requests never activate or focus the app. Protocol: OSC 1337 RequestAttention.',
                    ),
                    SizedBox(height: theme.spacing.sm),
                    _SettingsRadioPanel<LocalTerminalRequestAttentionPolicy>(
                      panelKey: const Key('defaults-request-attention-options'),
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
                            title: requestAttentionPolicyLabel(policy),
                            subtitle: requestAttentionPolicyDescription(policy),
                          ),
                      ],
                    ),
                    SizedBox(height: theme.spacing.xxl),
                    const AppSectionHeader(
                      title: 'Terminal information requests',
                      description:
                          'The first request is denied safely. Remembered decisions apply only to the named session.* or user.* value. Protocol: OSC 1337 ReportVariable.',
                    ),
                    SizedBox(height: theme.spacing.sm),
                    AppPanel(
                      key: const Key('defaults-report-variable-panel'),
                      tone: AppPanelTone.panel,
                      padding: EdgeInsets.all(theme.spacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedReportVariableDecisions.isEmpty
                                ? 'No remembered decisions'
                                : '${_selectedReportVariableDecisions.length} remembered · $allowedReportVariables allowed · $deniedReportVariables denied',
                            key: const Key(
                              'default-osc1337-report-variable-decision-summary',
                            ),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: theme.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          SizedBox(height: theme.spacing.xs),
                          Text(
                            'Forgetting decisions restores the safe first-request denial and lets the app ask again later.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: theme.textSubtle),
                          ),
                          if (reportVariableDecisionEntries.isNotEmpty) ...[
                            SizedBox(height: theme.spacing.md),
                            for (final entry in reportVariableDecisionEntries)
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
                                              ? 'Allow'
                                              : 'Deny',
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
                                          tooltip:
                                              'Forget decision for ${entry.key}',
                                          visualDensity: VisualDensity.compact,
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
                                          icon: const Icon(Icons.close_rounded),
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
                            label: 'Forget all decisions',
                            onPressed: _selectedReportVariableDecisions.isEmpty
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
                    AppSectionHeader(
                      key: _advancedSectionKey,
                      title: 'Advanced',
                      description:
                          'App-wide · Integration changes apply to newly opened sessions or the next launch.',
                    ),
                    SizedBox(height: theme.spacing.sm),
                    AppPanel(
                      key: const Key('settings-advanced-panel'),
                      tone: AppPanelTone.panel,
                      padding: EdgeInsets.all(theme.spacing.xl),
                      child: Column(
                        children: [
                          ToggleSettingRow(
                            key: const Key('settings-global-shell-integration'),
                            label: 'Shell integration by default',
                            description:
                                'Enable prompt marks, command navigation, badges, and shell-aware actions for new sessions.',
                            value: _selectedShellIntegration.enabled,
                            onChanged: (value) {
                              setState(() {
                                _selectedShellIntegration =
                                    _selectedShellIntegration.copyWith(
                                      enabled: value,
                                    );
                              });
                            },
                          ),
                          ToggleSettingRow(
                            key: const Key('settings-hotkey-window'),
                            label: 'Global hotkey window',
                            description:
                                'Register ⌥⌘Space system-wide to show or hide Ianvs Terminal.',
                            value: _selectedHotkeyWindow.enabled,
                            onChanged: (value) {
                              setState(() {
                                _selectedHotkeyWindow = _selectedHotkeyWindow
                                    .copyWith(enabled: value);
                              });
                            },
                          ),
                          ToggleSettingRow(
                            key: const Key('settings-restore-workspace'),
                            label: 'Restore previous workspace',
                            description:
                                'Reopen the saved local tab and pane layout on the next launch.',
                            value: _selectedWorkspace.restoreLayout,
                            onChanged: (value) {
                              setState(() {
                                _selectedWorkspace = _selectedWorkspace
                                    .copyWith(restoreLayout: value);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: theme.spacing.xxl),
                    const AppSectionHeader(
                      title: 'Terminal canvas inset',
                      description:
                          'Adjust the empty space between the shell frame and terminal text.',
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
                                  'Viewport padding',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: theme.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              Text(
                                '${_selectedTerminalViewportPadding.round()} px',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: theme.textMuted,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'monospace',
                                    ),
                              ),
                            ],
                          ),
                          Slider(
                            key: const Key('default-terminal-viewport-padding'),
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
                            label:
                                '${_selectedTerminalViewportPadding.round()} px',
                            onChanged: (value) {
                              setState(() {
                                _selectedTerminalViewportPadding = value
                                    .roundToDouble();
                              });
                            },
                          ),
                          Text(
                            'Lower values keep the prompt close to the edges; higher values create a larger terminal gutter.',
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
          ),
        ],
      ),
      footer: LayoutBuilder(
        builder: (context, constraints) {
          final resetActions = Wrap(
            key: const Key('defaults-footer-reset-actions'),
            spacing: theme.spacing.sm,
            runSpacing: theme.spacing.sm,
            children: [
              AppActionButton(
                tone: AppActionTone.secondary,
                size: AppActionSize.compact,
                label: 'Reset default',
                onPressed: _selectedProfileId == null
                    ? null
                    : () {
                        setState(() {
                          _selectedProfileId = null;
                          _selectedTerminalPresetId = _matchingPresetIdFor(
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
                label: 'Reset theme',
                onPressed:
                    _selectedThemeMode == TerminalThemeMode.system &&
                        _selectedTerminalViewportPadding ==
                            TerminalAppAppearance.defaultTerminalViewportPadding
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
                tone: AppActionTone.secondary,
                size: AppActionSize.compact,
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(),
              ),
              AppActionButton(
                buttonKey: const Key('defaults-save'),
                label: 'Save changes',
                onPressed: !_hasChanges(effectiveProfile)
                    ? null
                    : () {
                        Navigator.of(context).pop(
                          DefaultsAndAppearanceSelection(
                            configuredDefaultProfileId: _selectedProfileId,
                            themeMode: _selectedThemeMode,
                            terminalViewportPadding:
                                _selectedTerminalViewportPadding,
                            osc52Policy: _selectedOsc52Policy,
                            openUrlPolicy: _selectedOpenUrlPolicy,
                            requestAttentionPolicy:
                                _selectedRequestAttentionPolicy,
                            reportVariableDecisions:
                                _selectedReportVariableDecisions,
                            keybindings: _selectedKeybindings,
                            workspace: _selectedWorkspace,
                            globalCopyOnSelect: _selectedGlobalCopyOnSelect,
                            paste: _selectedPaste,
                            shellIntegration: _selectedShellIntegration,
                            notifications: _selectedNotifications,
                            hotkeyWindow: _selectedHotkeyWindow,
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
          if (constraints.maxWidth < 440) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.centerLeft, child: resetActions),
                SizedBox(height: theme.spacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: confirmationActions,
                ),
              ],
            );
          }
          return Row(
            children: [resetActions, const Spacer(), confirmationActions],
          );
        },
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
    return DecoratedBox(
      key: const Key('defaults-profiles-notice'),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          theme.selected.withValues(alpha: 0.20),
          theme.panelElevated,
        ),
        borderRadius: BorderRadius.circular(theme.radius.lg),
        border: Border.all(color: theme.focusRing.withValues(alpha: 0.20)),
      ),
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.xl),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: theme.spacing.xs),
              child: Icon(
                Icons.info_outline_rounded,
                size: theme.controls.dense - theme.spacing.lg,
                color: theme.focusRing,
              ),
            ),
            SizedBox(width: theme.spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Detailed terminal settings live in Profiles.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: theme.spacing.xs),
                  Text(
                    'Edit font, colors, cursor, scrollback, and startup arguments from the Profiles editor.',
                    style: textTheme.bodySmall?.copyWith(
                      color: theme.textSubtle,
                    ),
                  ),
                  if (effectiveProfile != null) ...[
                    SizedBox(height: theme.spacing.md),
                    AppActionButton(
                      buttonKey: const Key('defaults-open-profiles'),
                      tone: AppActionTone.secondary,
                      size: AppActionSize.compact,
                      icon: Icons.tune_rounded,
                      label: 'Edit ${effectiveProfile!.name} in Profiles',
                      onPressed: onOpenProfiles,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
                    color: options[index].value == groupValue
                        ? theme.selected.withValues(alpha: 0.56)
                        : null,
                    padding: EdgeInsets.symmetric(
                      horizontal: theme.spacing.md,
                      vertical: theme.spacing.xs,
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

class _SettingsJumpNavigation extends StatelessWidget {
  const _SettingsJumpNavigation({
    required this.onGeneral,
    required this.onAppearance,
    required this.onClipboard,
    required this.onNotifications,
    required this.onKeyboard,
    required this.onSecurity,
    required this.onAdvanced,
  });

  final VoidCallback onGeneral;
  final VoidCallback onAppearance;
  final VoidCallback onClipboard;
  final VoidCallback onNotifications;
  final VoidCallback onKeyboard;
  final VoidCallback onSecurity;
  final VoidCallback onAdvanced;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final items = <({IconData icon, String label, VoidCallback onPressed})>[
      (icon: Icons.tune_rounded, label: 'General', onPressed: onGeneral),
      (
        icon: Icons.palette_outlined,
        label: 'Appearance',
        onPressed: onAppearance,
      ),
      (
        icon: Icons.content_paste_rounded,
        label: 'Paste & Clipboard',
        onPressed: onClipboard,
      ),
      (
        icon: Icons.notifications_outlined,
        label: 'Notifications',
        onPressed: onNotifications,
      ),
      (icon: Icons.keyboard_outlined, label: 'Keyboard', onPressed: onKeyboard),
      (icon: Icons.shield_outlined, label: 'Security', onPressed: onSecurity),
      (
        icon: Icons.settings_suggest_outlined,
        label: 'Advanced',
        onPressed: onAdvanced,
      ),
    ];
    return AppPanel(
      key: const Key('settings-section-navigation'),
      tone: AppPanelTone.elevated,
      padding: EdgeInsets.all(theme.spacing.md),
      child: Wrap(
        spacing: theme.spacing.sm,
        runSpacing: theme.spacing.sm,
        children: [
          for (final item in items)
            AppActionButton(
              buttonKey: Key(
                'settings-nav-${item.label.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '-')}',
              ),
              tone: AppActionTone.secondary,
              size: AppActionSize.compact,
              icon: item.icon,
              label: item.label,
              onPressed: item.onPressed,
            ),
        ],
      ),
    );
  }
}

class _KeybindingsSettingsPanel extends StatelessWidget {
  const _KeybindingsSettingsPanel({
    required this.config,
    required this.onChanged,
  });

  final LocalTerminalKeybindingsConfig config;
  final ValueChanged<LocalTerminalKeybindingsConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final descriptors =
        ShellActionRegistry.actions.values
            .where(
              (descriptor) =>
                  descriptor.defaultKeyBinding != null ||
                  config.overrides.containsKey(descriptor.id),
            )
            .toList(growable: false)
          ..sort((left, right) => left.label.compareTo(right.label));
    return AppPanel(
      key: const Key('settings-keybindings-panel'),
      tone: AppPanelTone.panel,
      padding: EdgeInsets.all(theme.spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, descriptor) in descriptors.indexed) ...[
            _KeybindingSettingRow(
              descriptor: descriptor,
              config: config,
              onChanged: onChanged,
            ),
            if (index != descriptors.length - 1)
              Padding(
                padding: EdgeInsets.symmetric(vertical: theme.spacing.sm),
                child: const Divider(height: 1),
              ),
          ],
        ],
      ),
    );
  }
}

class _KeybindingSettingRow extends StatelessWidget {
  const _KeybindingSettingRow({
    required this.descriptor,
    required this.config,
    required this.onChanged,
  });

  final TerminalActionDescriptor descriptor;
  final LocalTerminalKeybindingsConfig config;
  final ValueChanged<LocalTerminalKeybindingsConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final override = config.overrides[descriptor.id];
    final overrideBinding = override?.binding;
    final disabled =
        config.disabledDefaultActions.contains(descriptor.id) ||
        override?.enabled == false;
    final shortcut = overrideBinding == null
        ? _terminalKeyBindingLabel(descriptor.defaultKeyBinding)
        : _localKeyBindingLabel(overrideBinding);
    return Semantics(
      container: true,
      label: '${_humanizedActionLabel(descriptor.label)} shortcut',
      child: Row(
        key: Key('settings-keybinding-${descriptor.id.name}'),
        children: [
          Icon(
            descriptor.icon ?? Icons.keyboard_outlined,
            size: 18,
            color: disabled ? theme.textSubtle : theme.textMuted,
          ),
          SizedBox(width: theme.spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _humanizedActionLabel(descriptor.label),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: disabled ? theme.textMuted : theme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: theme.spacing.xs),
                Text(
                  shortcut ?? 'No shortcut assigned',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: theme.textSubtle,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          if (override != null) ...[
            AppActionButton(
              tooltip: 'Restore default shortcut',
              tone: AppActionTone.ghost,
              size: AppActionSize.dense,
              icon: Icons.restart_alt_rounded,
              onPressed: () {
                final overrides = {...config.overrides}..remove(descriptor.id);
                final disabledDefaults = {...config.disabledDefaultActions}
                  ..remove(descriptor.id);
                onChanged(
                  config.copyWith(
                    overrides: overrides,
                    disabledDefaultActions: disabledDefaults,
                  ),
                );
              },
            ),
            SizedBox(width: theme.spacing.sm),
          ],
          AppActionButton(
            tooltip: 'Edit shortcut',
            tone: AppActionTone.ghost,
            size: AppActionSize.dense,
            icon: Icons.edit_outlined,
            onPressed: () async {
              final occupiedSignatures =
                  LocalTerminalKeyBindingResolver.resolve(config: config)
                      .where((binding) => binding.actionId != descriptor.id)
                      .map((binding) => binding.signature)
                      .toSet();
              final binding = await showDialog<LocalTerminalKeyBinding>(
                context: context,
                builder: (dialogContext) => _KeybindingEditDialog(
                  actionLabel: _humanizedActionLabel(descriptor.label),
                  initialBinding:
                      overrideBinding ??
                      _localKeyBindingFromTerminal(
                        descriptor.defaultKeyBinding,
                      ),
                  occupiedSignatures: occupiedSignatures,
                ),
              );
              if (binding == null || !context.mounted) {
                return;
              }
              final overrides = {
                ...config.overrides,
                descriptor.id: LocalTerminalKeyBindingOverride(
                  binding: binding,
                ),
              };
              final disabledDefaults = {...config.disabledDefaultActions}
                ..remove(descriptor.id);
              onChanged(
                config.copyWith(
                  overrides: overrides,
                  disabledDefaultActions: disabledDefaults,
                ),
              );
            },
          ),
          SizedBox(width: theme.spacing.sm),
          Switch(
            key: Key('settings-keybinding-enabled-${descriptor.id.name}'),
            value: !disabled,
            onChanged: (enabled) {
              final disabledDefaults = {...config.disabledDefaultActions};
              final overrides = {...config.overrides};
              if (enabled) {
                disabledDefaults.remove(descriptor.id);
                if (override != null && !override.enabled) {
                  overrides[descriptor.id] = LocalTerminalKeyBindingOverride(
                    binding: override.binding,
                  );
                }
              } else {
                disabledDefaults.add(descriptor.id);
              }
              onChanged(
                config.copyWith(
                  disabledDefaultActions: disabledDefaults,
                  overrides: overrides,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _KeybindingEditDialog extends StatefulWidget {
  const _KeybindingEditDialog({
    required this.actionLabel,
    required this.initialBinding,
    required this.occupiedSignatures,
  });

  final String actionLabel;
  final LocalTerminalKeyBinding? initialBinding;
  final Set<String> occupiedSignatures;

  @override
  State<_KeybindingEditDialog> createState() => _KeybindingEditDialogState();
}

class _KeybindingEditDialogState extends State<_KeybindingEditDialog> {
  final FocusNode _captureFocusNode = FocusNode(
    debugLabel: 'settings-keybinding-capture',
  );
  late TerminalKeyBindingScope _scope;
  late String _key;
  late bool _meta;
  late bool _control;
  late bool _shift;
  late bool _alt;

  @override
  void initState() {
    super.initState();
    _captureFocusNode.addListener(_handleCaptureFocusChange);
    final binding = widget.initialBinding;
    _scope = binding?.scope ?? TerminalKeyBindingScope.focusedApp;
    _key = binding?.key ?? '';
    _meta = binding?.meta ?? true;
    _control = binding?.control ?? false;
    _shift = binding?.shift ?? false;
    _alt = binding?.alt ?? false;
  }

  @override
  void dispose() {
    _captureFocusNode.removeListener(_handleCaptureFocusChange);
    _captureFocusNode.dispose();
    super.dispose();
  }

  void _handleCaptureFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  LocalTerminalKeyBinding? get _binding {
    final key = _key.trim();
    if (key.isEmpty) {
      return null;
    }
    return LocalTerminalKeyBinding(
      scope: _scope,
      key: key,
      meta: _meta,
      control: _control,
      shift: _shift,
      alt: _alt,
    );
  }

  bool get _hasConflict {
    final binding = _binding;
    return binding != null &&
        widget.occupiedSignatures.contains(binding.signature);
  }

  KeyEventResult _captureKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    final logicalKey = event.logicalKey;
    if (_isModifierKey(logicalKey)) {
      return KeyEventResult.handled;
    }
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    setState(() {
      _key = logicalKey.debugName ?? logicalKey.keyLabel;
      _meta =
          pressed.contains(LogicalKeyboardKey.metaLeft) ||
          pressed.contains(LogicalKeyboardKey.metaRight);
      _control =
          pressed.contains(LogicalKeyboardKey.controlLeft) ||
          pressed.contains(LogicalKeyboardKey.controlRight);
      _shift =
          pressed.contains(LogicalKeyboardKey.shiftLeft) ||
          pressed.contains(LogicalKeyboardKey.shiftRight);
      _alt =
          pressed.contains(LogicalKeyboardKey.altLeft) ||
          pressed.contains(LogicalKeyboardKey.altRight);
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final binding = _binding;
    return AlertDialog(
      key: const Key('settings-keybinding-edit-dialog'),
      title: Text('Edit ${widget.actionLabel}'),
      content: SizedBox(
        width: 420,
        child: FocusTraversalGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<TerminalKeyBindingScope>(
                key: const Key('settings-keybinding-scope'),
                initialValue: _scope,
                decoration: const InputDecoration(labelText: 'Scope'),
                items: [
                  for (final scope in TerminalKeyBindingScope.values)
                    DropdownMenuItem(
                      value: scope,
                      child: Text(_keyBindingScopeLabel(scope)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _scope = value;
                  });
                },
              ),
              SizedBox(height: theme.spacing.lg),
              Text(
                'Shortcut',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: theme.spacing.sm),
              Focus(
                focusNode: _captureFocusNode,
                autofocus: true,
                onKeyEvent: _captureKey,
                child: Semantics(
                  button: true,
                  label: 'Record shortcut for ${widget.actionLabel}',
                  child: InkWell(
                    key: const Key('settings-keybinding-record'),
                    onTap: _captureFocusNode.requestFocus,
                    borderRadius: BorderRadius.circular(theme.radius.md),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      constraints: const BoxConstraints(minHeight: 64),
                      padding: EdgeInsets.all(theme.spacing.lg),
                      decoration: BoxDecoration(
                        color: _captureFocusNode.hasFocus
                            ? theme.selected.withValues(alpha: 0.38)
                            : theme.chrome,
                        borderRadius: BorderRadius.circular(theme.radius.md),
                        border: Border.all(
                          color: _captureFocusNode.hasFocus
                              ? theme.focusRing
                              : theme.borderStrong,
                          width: _captureFocusNode.hasFocus ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            binding == null
                                ? 'Press a shortcut'
                                : _localKeyBindingLabel(
                                    binding,
                                  ).split(' · ').first,
                            key: const Key(
                              'settings-keybinding-recorded-value',
                            ),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: theme.textPrimary,
                                  fontFamily: 'monospace',
                                ),
                          ),
                          SizedBox(height: theme.spacing.xs),
                          Text(
                            'Click here, then press the complete key combination.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: theme.textSubtle),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: theme.spacing.md),
              Wrap(
                spacing: theme.spacing.sm,
                runSpacing: theme.spacing.sm,
                children: [
                  FilterChip(
                    label: const Text('⌘ Command'),
                    selected: _meta,
                    onSelected: (value) => setState(() => _meta = value),
                  ),
                  FilterChip(
                    label: const Text('⌥ Option'),
                    selected: _alt,
                    onSelected: (value) => setState(() => _alt = value),
                  ),
                  FilterChip(
                    label: const Text('⌃ Control'),
                    selected: _control,
                    onSelected: (value) => setState(() => _control = value),
                  ),
                  FilterChip(
                    label: const Text('⇧ Shift'),
                    selected: _shift,
                    onSelected: (value) => setState(() => _shift = value),
                  ),
                ],
              ),
              if (_hasConflict) ...[
                SizedBox(height: theme.spacing.md),
                Text(
                  'This shortcut is already assigned in the same scope.',
                  key: const Key('settings-keybinding-conflict'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: theme.danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('settings-keybinding-save'),
          onPressed: binding == null || _hasConflict
              ? null
              : () => Navigator.of(context).pop(binding),
          child: const Text('Save shortcut'),
        ),
      ],
    );
  }
}

bool _isModifierKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight;
}

LocalTerminalKeyBinding? _localKeyBindingFromTerminal(
  TerminalKeyBinding? binding,
) {
  if (binding == null) {
    return null;
  }
  return LocalTerminalKeyBinding(
    scope: binding.scope,
    key: binding.key.debugName ?? binding.key.keyLabel,
    meta: binding.meta,
    control: binding.control,
    shift: binding.shift,
    alt: binding.alt,
  );
}

String _humanizedActionLabel(String value) {
  final words = value
      .split('_')
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) {
    return value;
  }
  final label = words.join(' ');
  return '${label[0].toUpperCase()}${label.substring(1)}';
}

String? _terminalKeyBindingLabel(TerminalKeyBinding? binding) {
  if (binding == null) {
    return null;
  }
  return _shortcutLabel(
    scope: binding.scope,
    key: binding.key.debugName ?? binding.key.keyLabel,
    meta: binding.meta,
    control: binding.control,
    shift: binding.shift,
    alt: binding.alt,
  );
}

String _localKeyBindingLabel(LocalTerminalKeyBinding binding) {
  return _shortcutLabel(
    scope: binding.scope,
    key: binding.key,
    meta: binding.meta,
    control: binding.control,
    shift: binding.shift,
    alt: binding.alt,
  );
}

String _shortcutLabel({
  required TerminalKeyBindingScope scope,
  required String key,
  required bool meta,
  required bool control,
  required bool shift,
  required bool alt,
}) {
  final shortcut = [
    if (control) '⌃',
    if (alt) '⌥',
    if (shift) '⇧',
    if (meta) '⌘',
    key.replaceFirst('Key ', '').replaceFirst('Key', ''),
  ].join();
  return '$shortcut · ${_keyBindingScopeLabel(scope)}';
}

String _keyBindingScopeLabel(TerminalKeyBindingScope scope) {
  return switch (scope) {
    TerminalKeyBindingScope.global => 'Global',
    TerminalKeyBindingScope.focusedApp => 'App focused',
    TerminalKeyBindingScope.terminalFocused => 'Terminal focused',
    TerminalKeyBindingScope.commandPaletteOpen => 'Command palette',
  };
}

String _bracketedPastePolicyLabel(LocalTerminalBracketedPastePolicy policy) {
  return switch (policy) {
    LocalTerminalBracketedPastePolicy.auto => 'Auto',
    LocalTerminalBracketedPastePolicy.force => 'Force bracketed paste',
    LocalTerminalBracketedPastePolicy.plain => 'Always plain text',
  };
}

String themeModeLabel(TerminalThemeMode mode) {
  return switch (mode) {
    TerminalThemeMode.system => 'System',
    TerminalThemeMode.light => 'Light',
    TerminalThemeMode.dark => 'Dark',
  };
}

String _themeModeDescription(TerminalThemeMode mode) {
  return switch (mode) {
    TerminalThemeMode.system => 'Follow the current device appearance.',
    TerminalThemeMode.light => 'Keep the shell app in light mode.',
    TerminalThemeMode.dark => 'Keep the shell app in dark mode.',
  };
}

String osc52PolicyLabel(LocalTerminalOsc52Policy policy) {
  return switch (policy) {
    LocalTerminalOsc52Policy.disabled => 'Deny',
    LocalTerminalOsc52Policy.profile => 'Profile-controlled (Recommended)',
    LocalTerminalOsc52Policy.allow => 'Allow',
    LocalTerminalOsc52Policy.ask => 'Ask',
  };
}

String osc52PolicyDescription(LocalTerminalOsc52Policy policy) {
  return switch (policy) {
    LocalTerminalOsc52Policy.disabled =>
      'Block terminal programs from copying to or reading from the clipboard.',
    LocalTerminalOsc52Policy.profile =>
      'Allow clipboard writes and ask before a program reads clipboard content.',
    LocalTerminalOsc52Policy.allow =>
      'Let trusted terminal sessions use the clipboard without prompting.',
    LocalTerminalOsc52Policy.ask =>
      'Ask before every clipboard write or read request.',
  };
}

String openUrlPolicyLabel(LocalTerminalOpenUrlPolicy policy) {
  return switch (policy) {
    LocalTerminalOpenUrlPolicy.disabled => 'Deny',
    LocalTerminalOpenUrlPolicy.ask => 'Ask every time (Recommended)',
  };
}

String openUrlPolicyDescription(LocalTerminalOpenUrlPolicy policy) {
  return switch (policy) {
    LocalTerminalOpenUrlPolicy.disabled =>
      'Block every terminal URL request without showing a dialog.',
    LocalTerminalOpenUrlPolicy.ask =>
      'Require confirmation for each accepted request from the active terminal.',
  };
}

String requestAttentionPolicyLabel(LocalTerminalRequestAttentionPolicy policy) {
  return switch (policy) {
    LocalTerminalRequestAttentionPolicy.disabled => 'Deny (Recommended)',
    LocalTerminalRequestAttentionPolicy.allow => 'Allow with limits',
  };
}

String requestAttentionPolicyDescription(
  LocalTerminalRequestAttentionPolicy policy,
) {
  return switch (policy) {
    LocalTerminalRequestAttentionPolicy.disabled =>
      'Block terminal attention alerts. Cancellation requests are still honored.',
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
      label: 'terminal-preset-$label',
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(theme.radius.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: width,
          constraints: BoxConstraints(
            minHeight: theme.controls.regular * 2 + theme.spacing.lg,
          ),
          padding: EdgeInsets.all(theme.spacing.lg),
          decoration: BoxDecoration(
            color: selected
                ? theme.selected.withValues(alpha: 0.46)
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
                            ? FontWeight.w700
                            : FontWeight.w600,
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
      child: const SizedBox(height: 12),
    );
  }
}
