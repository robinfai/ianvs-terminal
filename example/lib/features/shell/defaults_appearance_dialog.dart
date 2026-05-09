import 'package:flutter/material.dart';

import '../preferences/app_preferences_models.dart';
import '../profiles/profile_models.dart';
import '../../ui/app_ui.dart';

class DefaultsAndAppearanceSelection {
  const DefaultsAndAppearanceSelection({
    required this.configuredDefaultProfileId,
    required this.themeMode,
    this.openProfiles = false,
  });

  final String? configuredDefaultProfileId;
  final TerminalThemeMode themeMode;
  final bool openProfiles;
}

class DefaultsAndAppearanceDialog extends StatefulWidget {
  const DefaultsAndAppearanceDialog({
    super.key,
    required this.profiles,
    required this.configuredDefaultProfileId,
    required this.effectiveDefaultProfileId,
    required this.themeMode,
  });

  final List<TerminalProfile> profiles;
  final String? configuredDefaultProfileId;
  final String? effectiveDefaultProfileId;
  final TerminalThemeMode themeMode;

  @override
  State<DefaultsAndAppearanceDialog> createState() =>
      _DefaultsAndAppearanceDialogState();
}

class _DefaultsAndAppearanceDialogState
    extends State<DefaultsAndAppearanceDialog> {
  late String? _selectedProfileId;
  late TerminalThemeMode _selectedThemeMode;

  @override
  void initState() {
    super.initState();
    _selectedProfileId = widget.configuredDefaultProfileId;
    _selectedThemeMode = widget.themeMode;
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

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final effectiveProfile = _effectiveProfileFor(
      configuredProfileId: _selectedProfileId,
      effectiveProfileId: widget.effectiveDefaultProfileId,
    );
    final isUsingFallback = _selectedProfileId == null;

    return AppDialogScaffold(
      key: const Key('defaults-dialog'),
      title: 'Defaults & appearance',
      subtitle:
          'Pick the default profile for new tabs and choose how the shell follows the app theme.',
      onClose: () => Navigator.of(context).pop(),
      closeTooltip: 'Close defaults',
      constraints: const BoxConstraints(maxWidth: 520),
      height: 520,
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
              tone: AppPanelTone.panel,
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
                });
              },
              child: Column(
                children: [
                  RadioListTile<String?>(
                    key: const Key('default-profile-option-fallback'),
                    value: null,
                    dense: true,
                    visualDensity: const VisualDensity(
                      horizontal: -2,
                      vertical: -2,
                    ),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('No configured default'),
                    subtitle: Text(
                      effectiveProfile == null
                          ? 'New tabs stay ready even when no default is configured.'
                          : 'New tabs use ${effectiveProfile.name} until you choose a default.',
                    ),
                  ),
                  for (final profile in widget.profiles)
                    RadioListTile<String?>(
                      key: Key('default-profile-option-${profile.id}'),
                      value: profile.id,
                      dense: true,
                      visualDensity: const VisualDensity(
                        horizontal: -2,
                        vertical: -2,
                      ),
                      contentPadding: EdgeInsets.zero,
                      title: Text(profile.name),
                      subtitle: Text(profile.shell),
                    ),
                ],
              ),
            ),
            AppPanel(
              tone: AppPanelTone.panel,
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
                    RadioListTile<TerminalThemeMode>(
                      key: Key('default-theme-option-${themeMode.name}'),
                      value: themeMode,
                      dense: true,
                      visualDensity: const VisualDensity(
                        horizontal: -2,
                        vertical: -2,
                      ),
                      contentPadding: EdgeInsets.zero,
                      title: Text(themeModeLabel(themeMode)),
                      subtitle: Text(_themeModeDescription(themeMode)),
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
                    });
                  },
          ),
          AppActionButton(
            tone: AppActionTone.ghost,
            size: AppActionSize.compact,
            label: 'Reset theme',
            onPressed: _selectedThemeMode == TerminalThemeMode.system
                ? null
                : () {
                    setState(() {
                      _selectedThemeMode = TerminalThemeMode.system;
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
