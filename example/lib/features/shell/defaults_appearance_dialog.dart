import 'package:flutter/material.dart';

import '../config/local_terminal_config_models.dart';
import '../preferences/app_preferences_models.dart';
import '../profiles/profile_models.dart';
import '../terminal/terminal_viewport_colors.dart';
import '../../ui/app_ui.dart';

class DefaultsAndAppearanceSelection {
  const DefaultsAndAppearanceSelection({
    required this.configuredDefaultProfileId,
    required this.themeMode,
    required this.terminalViewportPadding,
    required this.osc52Policy,
    required this.openUrlPolicy,
    required this.requestAttentionPolicy,
    required this.reportVariableDecisions,
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

  @override
  State<DefaultsAndAppearanceDialog> createState() =>
      _DefaultsAndAppearanceDialogState();
}

class _DefaultsAndAppearanceDialogState
    extends State<DefaultsAndAppearanceDialog> {
  late String? _selectedProfileId;
  late String? _selectedTerminalPresetId;
  late TerminalThemeMode _selectedThemeMode;
  late double _selectedTerminalViewportPadding;
  late LocalTerminalOsc52Policy _selectedOsc52Policy;
  late LocalTerminalOpenUrlPolicy _selectedOpenUrlPolicy;
  late LocalTerminalRequestAttentionPolicy _selectedRequestAttentionPolicy;
  late Map<String, LocalTerminalReportVariablePolicy>
  _selectedReportVariableDecisions;
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
    _selectedTerminalPresetId = _matchingPresetIdFor(
      _effectiveProfileFor(
        configuredProfileId: _selectedProfileId,
        effectiveProfileId: widget.effectiveDefaultProfileId,
      ),
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

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final dialogHeight =
        (MediaQuery.sizeOf(context).height - theme.spacing.xxl * 2)
            .clamp(440.0, 580.0)
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
      title: 'Defaults & appearance',
      subtitle:
          'Pick the default profile for new tabs and choose how the shell follows the app theme.',
      onClose: () => Navigator.of(context).pop(),
      closeTooltip: 'Close defaults',
      constraints: const BoxConstraints(maxWidth: 520),
      height: dialogHeight,
      expandBody: true,
      centerInViewport: false,
      bodyPadding: EdgeInsets.fromLTRB(
        theme.spacing.lg,
        theme.spacing.lg,
        theme.spacing.lg,
        theme.spacing.md,
      ),
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppPanel(
              tone: AppPanelTone.elevated,
              padding: EdgeInsets.all(theme.spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Detailed terminal settings live in Profiles.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: theme.spacing.xs),
                  Text(
                    'Edit font, colors, cursor, scrollback, and startup arguments from the Profiles editor.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
                  ),
                  if (effectiveProfile != null) ...[
                    SizedBox(height: theme.spacing.md),
                    AppActionButton(
                      buttonKey: const Key('defaults-open-profiles'),
                      tone: AppActionTone.secondary,
                      size: AppActionSize.compact,
                      icon: Icons.tune_rounded,
                      label: 'Edit ${effectiveProfile.name} in Profiles',
                      onPressed: () {
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
                            updatedProfile: null,
                            openProfiles: true,
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: theme.spacing.xl),
            const AppSectionHeader(title: 'Default profile'),
            SizedBox(height: theme.spacing.sm),
            RadioGroup<String?>(
              groupValue: _selectedProfileId,
              onChanged: (value) {
                setState(() {
                  _selectedProfileId = value;
                  _selectedTerminalPresetId = _matchingPresetIdFor(
                    _effectiveProfileFor(
                      configuredProfileId: value,
                      effectiveProfileId: widget.effectiveDefaultProfileId,
                    ),
                  );
                });
              },
              child: Column(
                children: [
                  AppCompactRadioTile<String?>(
                    tileKey: const Key('default-profile-option-fallback'),
                    value: null,
                    title: const Text('No configured default'),
                    subtitle: Text(
                      effectiveProfile == null
                          ? 'New tabs stay ready even when no default is configured.'
                          : 'New tabs use ${effectiveProfile.name} until you choose a default.',
                    ),
                  ),
                  for (final profile in widget.profiles)
                    AppCompactRadioTile<String?>(
                      tileKey: Key('default-profile-option-${profile.id}'),
                      value: profile.id,
                      title: Text(profile.name),
                      subtitle: Text(profile.shell),
                    ),
                ],
              ),
            ),
            AppPanel(
              tone: AppPanelTone.selected,
              padding: EdgeInsets.all(theme.spacing.md),
              child: Text(
                isUsingFallback
                    ? 'Current new-tab profile • ${effectiveProfile?.name ?? 'No profile available'}'
                    : 'Configured default • ${effectiveProfile?.name ?? 'Unknown profile'}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: theme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(height: theme.spacing.xl),
            AppSectionHeader(
              title: 'Terminal preset',
              description: effectiveProfile == null
                  ? 'Create a profile before choosing terminal colors.'
                  : 'Apply a curated terminal color palette to ${effectiveProfile.name}.',
            ),
            SizedBox(height: theme.spacing.sm),
            TextField(
              key: const Key('defaults-terminal-preset-filter'),
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded),
                labelText: 'Filter terminal presets',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(theme.radius.lg),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _terminalPresetFilter = value;
                });
              },
            ),
            SizedBox(height: theme.spacing.sm),
            Wrap(
              spacing: theme.spacing.sm,
              runSpacing: theme.spacing.sm,
              children: [
                if (showCurrentPreset)
                  _TerminalPresetChoice(
                    key: const Key('defaults-terminal-preset-current'),
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
                    key: Key('defaults-terminal-preset-${preset.id}'),
                    label: preset.name,
                    subtitle: preset.tone.label,
                    selected: _selectedTerminalPresetId == preset.id,
                    enabled: effectiveProfile != null,
                    previewColors: preset.previewColors,
                    onPressed: () {
                      setState(() {
                        _selectedTerminalPresetId = preset.id;
                      });
                    },
                  ),
                if (!showCurrentPreset && visibleTerminalPresets.isEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: AppPanel(
                      tone: AppPanelTone.elevated,
                      padding: EdgeInsets.all(theme.spacing.md),
                      child: Text(
                        'No terminal presets match "$_terminalPresetFilter".',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: theme.textSubtle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: theme.spacing.xl),
            const AppSectionHeader(title: 'Appearance'),
            SizedBox(height: theme.spacing.sm),
            RadioGroup<TerminalThemeMode>(
              groupValue: _selectedThemeMode,
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedThemeMode = value;
                });
              },
              child: Column(
                children: [
                  for (final themeMode in TerminalThemeMode.values)
                    AppCompactRadioTile<TerminalThemeMode>(
                      tileKey: Key('default-theme-option-${themeMode.name}'),
                      value: themeMode,
                      title: Text(themeModeLabel(themeMode)),
                      subtitle: Text(_themeModeDescription(themeMode)),
                    ),
                ],
              ),
            ),
            SizedBox(height: theme.spacing.xl),
            const AppSectionHeader(
              title: 'OSC 52 clipboard',
              description:
                  'Choose how terminal escape sequences may access the system clipboard.',
            ),
            SizedBox(height: theme.spacing.sm),
            RadioGroup<LocalTerminalOsc52Policy>(
              groupValue: _selectedOsc52Policy,
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedOsc52Policy = value;
                });
              },
              child: Column(
                children: [
                  for (final policy in LocalTerminalOsc52Policy.values)
                    AppCompactRadioTile<LocalTerminalOsc52Policy>(
                      tileKey: Key('default-osc52-policy-${policy.name}'),
                      value: policy,
                      title: Text(osc52PolicyLabel(policy)),
                      subtitle: Text(osc52PolicyDescription(policy)),
                    ),
                ],
              ),
            ),
            SizedBox(height: theme.spacing.xl),
            const AppSectionHeader(
              title: 'Terminal URL requests',
              description:
                  'Choose whether OSC 1337 OpenURL requests may ask for permission. URLs are never opened automatically.',
            ),
            SizedBox(height: theme.spacing.sm),
            RadioGroup<LocalTerminalOpenUrlPolicy>(
              groupValue: _selectedOpenUrlPolicy,
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedOpenUrlPolicy = value;
                });
              },
              child: Column(
                children: [
                  for (final policy in LocalTerminalOpenUrlPolicy.values)
                    AppCompactRadioTile<LocalTerminalOpenUrlPolicy>(
                      tileKey: Key(
                        'default-osc1337-open-url-policy-${policy.name}',
                      ),
                      value: policy,
                      title: Text(openUrlPolicyLabel(policy)),
                      subtitle: Text(openUrlPolicyDescription(policy)),
                    ),
                ],
              ),
            ),
            SizedBox(height: theme.spacing.xl),
            const AppSectionHeader(
              title: 'Terminal attention requests',
              description:
                  'Choose whether OSC 1337 RequestAttention may use a bounded Dock alert or a cursor-local visual effect. Requests never activate or focus the app.',
            ),
            SizedBox(height: theme.spacing.sm),
            RadioGroup<LocalTerminalRequestAttentionPolicy>(
              groupValue: _selectedRequestAttentionPolicy,
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedRequestAttentionPolicy = value;
                });
              },
              child: Column(
                children: [
                  for (final policy
                      in LocalTerminalRequestAttentionPolicy.values)
                    AppCompactRadioTile<LocalTerminalRequestAttentionPolicy>(
                      tileKey: Key(
                        'default-osc1337-request-attention-policy-${policy.name}',
                      ),
                      value: policy,
                      title: Text(requestAttentionPolicyLabel(policy)),
                      subtitle: Text(requestAttentionPolicyDescription(policy)),
                    ),
                ],
              ),
            ),
            SizedBox(height: theme.spacing.xl),
            const AppSectionHeader(
              title: 'Terminal variable reports',
              description:
                  'OSC 1337 ReportVariable requests are denied the first time. Remembered decisions apply only to the named session.* or user.* variable.',
            ),
            SizedBox(height: theme.spacing.sm),
            AppPanel(
              tone: AppPanelTone.elevated,
              padding: EdgeInsets.all(theme.spacing.md),
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: theme.spacing.xs),
                  Text(
                    'Forgetting decisions restores the safe first-request denial and lets the app ask again later.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
                  ),
                  if (reportVariableDecisionEntries.isNotEmpty) ...[
                    SizedBox(height: theme.spacing.sm),
                    const Divider(height: 1),
                    SizedBox(height: theme.spacing.xs),
                    for (final entry in reportVariableDecisionEntries)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: theme.spacing.xs,
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
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: theme.textPrimary),
                              ),
                            ),
                            SizedBox(width: theme.spacing.sm),
                            Text(
                              entry.value ==
                                      LocalTerminalReportVariablePolicy.allow
                                  ? 'Allow'
                                  : 'Deny',
                              key: ValueKey<String>(
                                'default-osc1337-report-variable-policy-${entry.key}',
                              ),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: theme.textSubtle),
                            ),
                            SizedBox(width: theme.spacing.xs),
                            IconButton(
                              key: ValueKey<String>(
                                'default-osc1337-report-variable-forget-${entry.key}',
                              ),
                              tooltip: 'Forget decision for ${entry.key}',
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setState(() {
                                  final next =
                                      <
                                          String,
                                          LocalTerminalReportVariablePolicy
                                        >{..._selectedReportVariableDecisions}
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
            SizedBox(height: theme.spacing.xl),
            const AppSectionHeader(
              title: 'Terminal canvas inset',
              description:
                  'Adjust the empty space between the shell frame and terminal text.',
            ),
            SizedBox(height: theme.spacing.sm),
            AppPanel(
              tone: AppPanelTone.elevated,
              padding: EdgeInsets.all(theme.spacing.md),
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
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
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
                    min: TerminalAppAppearance.minTerminalViewportPadding,
                    max: TerminalAppAppearance.maxTerminalViewportPadding,
                    divisions:
                        (TerminalAppAppearance.maxTerminalViewportPadding -
                                TerminalAppAppearance
                                    .minTerminalViewportPadding)
                            .round(),
                    label: '${_selectedTerminalViewportPadding.round()} px',
                    onChanged: (value) {
                      setState(() {
                        _selectedTerminalViewportPadding = value
                            .roundToDouble();
                      });
                    },
                  ),
                  Text(
                    'Lower values keep the prompt close to the edges; higher values create a larger terminal gutter.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      footer: Wrap(
        alignment: WrapAlignment.end,
        runAlignment: WrapAlignment.end,
        spacing: theme.spacing.sm,
        runSpacing: theme.spacing.sm,
        children: [
          AppActionButton(
            tone: AppActionTone.ghost,
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
                          effectiveProfileId: widget.effectiveDefaultProfileId,
                        ),
                      );
                    });
                  },
          ),
          AppActionButton(
            tone: AppActionTone.ghost,
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
                          TerminalAppAppearance.defaultTerminalViewportPadding;
                    });
                  },
          ),
          AppActionButton(
            tone: AppActionTone.secondary,
            size: AppActionSize.compact,
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          AppActionButton(
            buttonKey: const Key('defaults-save'),
            icon: Icons.check_rounded,
            label: 'Save changes',
            onPressed: () {
              Navigator.of(context).pop(
                DefaultsAndAppearanceSelection(
                  configuredDefaultProfileId: _selectedProfileId,
                  themeMode: _selectedThemeMode,
                  terminalViewportPadding: _selectedTerminalViewportPadding,
                  osc52Policy: _selectedOsc52Policy,
                  openUrlPolicy: _selectedOpenUrlPolicy,
                  requestAttentionPolicy: _selectedRequestAttentionPolicy,
                  reportVariableDecisions: _selectedReportVariableDecisions,
                  updatedProfile: _updatedProfileForPreset(effectiveProfile),
                  openProfiles: false,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
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
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.previewColors,
    required this.onPressed,
  });

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
          width: 150,
          padding: EdgeInsets.all(theme.spacing.sm),
          decoration: BoxDecoration(
            color: selected
                ? theme.selected.withValues(alpha: 0.72)
                : theme.overlay.withValues(alpha: enabled ? 0.82 : 0.38),
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
