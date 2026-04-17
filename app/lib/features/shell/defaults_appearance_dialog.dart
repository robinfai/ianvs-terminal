import 'package:flutter/material.dart';

import '../preferences/app_preferences_models.dart';
import '../profiles/profile_models.dart';

class DefaultsAndAppearanceSelection {
  const DefaultsAndAppearanceSelection({
    required this.configuredDefaultProfileId,
    required this.themeMode,
  });

  final String? configuredDefaultProfileId;
  final TerminalThemeMode themeMode;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF111111) : Colors.white;
    final panel = isDark ? const Color(0xFF171717) : const Color(0xFFF5F5F5);
    final border = isDark ? const Color(0xFF262626) : const Color(0xFFD2D2D2);
    final primaryText = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF111111);
    final subtleText = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF4B5563);
    final effectiveProfile = _effectiveProfileFor(
      configuredProfileId: _selectedProfileId,
      effectiveProfileId: widget.effectiveDefaultProfileId,
    );
    final isUsingFallback = _selectedProfileId == null;

    return Dialog(
      key: const Key('defaults-dialog'),
      backgroundColor: background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Defaults & appearance',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close defaults',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, color: subtleText),
                    ),
                  ],
                ),
                Text(
                  'Pick the default profile for new tabs and choose how the shell follows the app theme.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: subtleText,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Default profile',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
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
                        contentPadding: EdgeInsets.zero,
                        activeColor: const Color(0xFFF6C344),
                        fillColor: WidgetStatePropertyAll(
                          isDark ? const Color(0xFFF6C344) : const Color(0xFF111111),
                        ),
                        title: const Text('Use the first available profile'),
                        subtitle: Text(
                          effectiveProfile == null
                              ? 'Fallback mode stays ready even when no saved default exists.'
                              : 'Fallback • new tabs use ${effectiveProfile.name} until you configure a default.',
                        ),
                      ),
                      for (final profile in widget.profiles)
                        RadioListTile<String?>(
                          key: Key('default-profile-option-${profile.id}'),
                          value: profile.id,
                          contentPadding: EdgeInsets.zero,
                          activeColor: const Color(0xFFF6C344),
                          fillColor: WidgetStatePropertyAll(
                            isDark ? const Color(0xFFF6C344) : const Color(0xFF111111),
                          ),
                          title: Text(profile.name),
                          subtitle: Text(profile.shell),
                        ),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Text(
                    isUsingFallback
                        ? 'Fallback default • ${effectiveProfile?.name ?? 'No profile available'}'
                        : 'Configured default • ${effectiveProfile?.name ?? 'Unknown profile'}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: primaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
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
                          contentPadding: EdgeInsets.zero,
                          activeColor: const Color(0xFFF6C344),
                          fillColor: WidgetStatePropertyAll(
                            isDark ? const Color(0xFFF6C344) : const Color(0xFF111111),
                          ),
                          title: Text(themeModeLabel(themeMode)),
                          subtitle: Text(_themeModeDescription(themeMode)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.end,
                  runAlignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _selectedProfileId == null
                          ? null
                          : () {
                              setState(() {
                                _selectedProfileId = null;
                              });
                            },
                      child: const Text('Reset default'),
                    ),
                    TextButton(
                      onPressed: _selectedThemeMode == TerminalThemeMode.system
                          ? null
                          : () {
                              setState(() {
                                _selectedThemeMode = TerminalThemeMode.system;
                              });
                            },
                      child: const Text('Reset theme'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      key: const Key('defaults-save'),
                      onPressed: () {
                        Navigator.of(context).pop(
                          DefaultsAndAppearanceSelection(
                            configuredDefaultProfileId: _selectedProfileId,
                            themeMode: _selectedThemeMode,
                          ),
                        );
                      },
                      child: const Text('Save changes'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
