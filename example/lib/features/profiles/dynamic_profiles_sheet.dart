import 'dart:convert';

import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';
import 'profile_models.dart';

class DynamicProfilesImportResult {
  const DynamicProfilesImportResult({
    required this.profiles,
    required this.warningCount,
    required this.addedCount,
    required this.replacementCount,
  });

  final List<TerminalProfile> profiles;
  final int warningCount;
  final int addedCount;
  final int replacementCount;
}

class DynamicProfilesSheet extends StatefulWidget {
  const DynamicProfilesSheet({super.key, this.existingProfiles = const []});

  final List<TerminalProfile> existingProfiles;

  @override
  State<DynamicProfilesSheet> createState() => _DynamicProfilesSheetState();
}

class _DynamicProfilesImportPreview {
  const _DynamicProfilesImportPreview({
    required this.profiles,
    required this.warningCount,
    required this.replacementIds,
  });

  final List<TerminalProfile> profiles;
  final int warningCount;
  final Set<String> replacementIds;

  int get replacementCount => replacementIds.length;
  int get addedCount => profiles.length - replacementCount;
}

class _DynamicProfilesSheetState extends State<DynamicProfilesSheet> {
  late final TextEditingController _controller;
  String? _errorText;
  _DynamicProfilesImportPreview? _preview;
  Set<String> _selectedProfileIds = const <String>{};

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text:
          '{\n'
          '  "Profiles": [\n'
          '    {\n'
          '      "Name": "Local shell",\n'
          '      "Guid": "example-local-shell-profile",\n'
          '      "Custom Command": "Yes",\n'
          '      "Command": "/bin/zsh"\n'
          '    }\n'
          '  ]\n'
          '}',
    );
    _controller.addListener(_clearPreviewAfterEdit);
  }

  @override
  void dispose() {
    _controller.removeListener(_clearPreviewAfterEdit);
    _controller.dispose();
    super.dispose();
  }

  void _clearPreviewAfterEdit() {
    if (_preview == null && _errorText == null) {
      return;
    }
    setState(() {
      _preview = null;
      _errorText = null;
      _selectedProfileIds = const <String>{};
    });
  }

  void _previewProfiles() {
    try {
      final decoded = jsonDecode(_controller.text);
      if (decoded is! Map) {
        setState(() {
          _errorText = 'Top-level JSON must be an object.';
          _preview = null;
          _selectedProfileIds = const <String>{};
        });
        return;
      }
      final document = TerminalProfilesDocument.fromJson(
        decoded.cast<String, Object?>(),
      );
      if (document.profiles.isEmpty) {
        setState(() {
          _errorText = 'No profiles found in JSON.';
          _preview = null;
          _selectedProfileIds = const <String>{};
        });
        return;
      }
      final existingIds = {
        for (final profile in widget.existingProfiles) profile.id,
      };
      setState(() {
        _errorText = null;
        _preview = _DynamicProfilesImportPreview(
          profiles: document.profiles,
          warningCount: document.loadWarnings.length,
          replacementIds: {
            for (final profile in document.profiles)
              if (existingIds.contains(profile.id)) profile.id,
          },
        );
        _selectedProfileIds = {
          for (final profile in document.profiles) profile.id,
        };
      });
    } on FormatException catch (error) {
      setState(() {
        _errorText = error.message;
        _preview = null;
        _selectedProfileIds = const <String>{};
      });
    } on Object catch (error) {
      setState(() {
        _errorText = error.toString();
        _preview = null;
        _selectedProfileIds = const <String>{};
      });
    }
  }

  void _importProfiles() {
    final preview = _preview;
    if (preview == null) {
      return;
    }
    final selectedProfiles = preview.profiles
        .where((profile) => _selectedProfileIds.contains(profile.id))
        .toList(growable: false);
    if (selectedProfiles.isEmpty) {
      return;
    }
    final selectedReplacementCount = selectedProfiles
        .where((profile) => preview.replacementIds.contains(profile.id))
        .length;
    Navigator.of(context).pop(
      DynamicProfilesImportResult(
        profiles: selectedProfiles,
        warningCount: preview.warningCount,
        addedCount: selectedProfiles.length - selectedReplacementCount,
        replacementCount: selectedReplacementCount,
      ),
    );
  }

  Widget _buildPreview(_DynamicProfilesImportPreview preview) {
    final palette = context.appTheme;
    final selectedProfiles = preview.profiles
        .where((profile) => _selectedProfileIds.contains(profile.id))
        .toList(growable: false);
    final selectedReplacementCount = selectedProfiles
        .where((profile) => preview.replacementIds.contains(profile.id))
        .length;
    final selectedAddedCount =
        selectedProfiles.length - selectedReplacementCount;
    final summary =
        '${selectedProfiles.length} of ${preview.profiles.length} profile${preview.profiles.length == 1 ? '' : 's'} selected'
        ' • $selectedAddedCount new'
        ' • $selectedReplacementCount replacement${selectedReplacementCount == 1 ? '' : 's'}'
        '${preview.warningCount == 0 ? '' : ' • ${preview.warningCount} warning${preview.warningCount == 1 ? '' : 's'}'}';
    return AppPanel(
      key: const Key('dynamic-profiles-preview'),
      tone: AppPanelTone.chrome,
      padding: EdgeInsets.all(palette.spacing.md),
      borderRadius: BorderRadius.circular(palette.radius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  summary,
                  key: const Key('dynamic-profiles-preview-summary'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                key: const Key('dynamic-profiles-toggle-all'),
                onPressed: () {
                  setState(() {
                    _selectedProfileIds =
                        _selectedProfileIds.length == preview.profiles.length
                        ? const <String>{}
                        : Set.unmodifiable({
                            for (final profile in preview.profiles) profile.id,
                          });
                  });
                },
                child: Text(
                  _selectedProfileIds.length == preview.profiles.length
                      ? 'Clear all'
                      : 'Select all',
                ),
              ),
            ],
          ),
          SizedBox(height: palette.spacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: preview.profiles.length,
              itemBuilder: (context, index) {
                final profile = preview.profiles[index];
                final replacesExisting = preview.replacementIds.contains(
                  profile.id,
                );
                return Padding(
                  padding: EdgeInsets.only(bottom: palette.spacing.xs),
                  child: Row(
                    key: Key('dynamic-profiles-preview-${profile.id}'),
                    children: [
                      Icon(
                        replacesExisting
                            ? Icons.sync_alt_rounded
                            : Icons.add_circle_outline_rounded,
                        size: 16,
                        color: replacesExisting
                            ? palette.warning
                            : palette.success,
                      ),
                      SizedBox(width: palette.spacing.sm),
                      Expanded(
                        child: Text(
                          profile.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      SizedBox(width: palette.spacing.sm),
                      Text(
                        replacesExisting ? 'Replaces existing' : 'New profile',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: replacesExisting
                              ? palette.warning
                              : palette.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: palette.spacing.xs),
                      Checkbox(
                        key: Key('dynamic-profiles-select-${profile.id}'),
                        value: _selectedProfileIds.contains(profile.id),
                        semanticLabel: 'Import ${profile.name}',
                        onChanged: (selected) {
                          setState(() {
                            final next = <String>{..._selectedProfileIds};
                            if (selected ?? false) {
                              next.add(profile.id);
                            } else {
                              next.remove(profile.id);
                            }
                            _selectedProfileIds = Set.unmodifiable(next);
                          });
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final preview = _preview;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        key: const Key('dynamic-profiles-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Dynamic Profiles',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      AppActionButton(
                        tooltip: 'Close dynamic profiles',
                        tone: AppActionTone.ghost,
                        size: AppActionSize.dense,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icons.close_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Paste an iTerm2 dynamic profile JSON document. This local build only launches local commands.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: Column(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('dynamic-profiles-json-field'),
                            controller: _controller,
                            maxLines: null,
                            expands: true,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: palette.textPrimary,
                                  fontFamily: 'monospace',
                                ),
                            decoration: InputDecoration(
                              alignLabelWithHint: true,
                              labelText: 'JSON',
                              errorText: _errorText,
                            ),
                          ),
                        ),
                        if (preview != null) ...[
                          const SizedBox(height: 12),
                          _buildPreview(preview),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: palette.spacing.sm,
                      runSpacing: palette.spacing.sm,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('dynamic-profiles-preview-action'),
                          onPressed: _previewProfiles,
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('Preview'),
                        ),
                        FilledButton.icon(
                          key: const Key('dynamic-profiles-import'),
                          onPressed:
                              preview == null || _selectedProfileIds.isEmpty
                              ? null
                              : _importProfiles,
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Import'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
