import 'package:flutter/material.dart';

import '../preferences/app_preferences_models.dart';
import '../profiles/profile_models.dart';
import '../terminal/terminal_viewport_colors.dart';
import '../../ui/app_ui.dart';

class DefaultsAndAppearanceSelection {
  const DefaultsAndAppearanceSelection({
    required this.configuredDefaultProfileId,
    required this.themeMode,
    required this.terminalViewportPadding,
    this.updatedProfile,
    this.openProfiles = false,
  });

  final String? configuredDefaultProfileId;
  final TerminalThemeMode themeMode;
  final double terminalViewportPadding;
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
  });

  final List<TerminalProfile> profiles;
  final String? configuredDefaultProfileId;
  final String? effectiveDefaultProfileId;
  final TerminalThemeMode themeMode;
  final double terminalViewportPadding;

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

  @override
  void initState() {
    super.initState();
    _selectedProfileId = widget.configuredDefaultProfileId;
    _selectedThemeMode = widget.themeMode;
    _selectedTerminalViewportPadding = widget.terminalViewportPadding;
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

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final effectiveProfile = _effectiveProfileFor(
      configuredProfileId: _selectedProfileId,
      effectiveProfileId: widget.effectiveDefaultProfileId,
    );
    final isUsingFallback = _selectedProfileId == null;
    final selectedPreset = _selectedPreset;

    return AppDialogScaffold(
      key: const Key('defaults-dialog'),
      title: 'Defaults & appearance',
      subtitle:
          'Pick the default profile for new tabs and choose how the shell follows the app theme.',
      onClose: () => Navigator.of(context).pop(),
      closeTooltip: 'Close defaults',
      constraints: const BoxConstraints(maxWidth: 520),
      height: 580,
      expandBody: true,
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
            Wrap(
              spacing: theme.spacing.sm,
              runSpacing: theme.spacing.sm,
              children: [
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
                for (final preset in terminalThemePresets)
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
