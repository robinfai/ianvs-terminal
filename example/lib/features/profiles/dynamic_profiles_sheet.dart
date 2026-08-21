import 'dart:convert';

import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';
import 'iterm_dynamic_profile_importer.dart';
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
    });
  }

  void _previewProfiles() {
    try {
      final decoded = jsonDecode(_controller.text);
      if (decoded is! Map) {
        setState(() {
          _errorText = context.l10n.dynamicProfilesTopLevelObject;
          _preview = null;
        });
        return;
      }
      final document = const ITermDynamicProfileImporter().decode(
        decoded.cast<String, Object?>(),
      );
      if (document.profiles.isEmpty) {
        setState(() {
          _errorText = context.l10n.dynamicProfilesNoneFound;
          _preview = null;
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
      });
    } on FormatException catch (error) {
      setState(() {
        _errorText = context.l10n.dynamicProfilesInvalid(error.message);
        _preview = null;
      });
    } on Object catch (error) {
      setState(() {
        _errorText = context.l10n.dynamicProfilesInvalid(error.toString());
        _preview = null;
      });
    }
  }

  void _importProfiles() {
    final preview = _preview;
    if (preview == null) {
      return;
    }
    Navigator.of(context).pop(
      DynamicProfilesImportResult(
        profiles: preview.profiles,
        warningCount: preview.warningCount,
        addedCount: preview.addedCount,
        replacementCount: preview.replacementCount,
      ),
    );
  }

  Widget _buildPreview(_DynamicProfilesImportPreview preview) {
    final palette = context.appTheme;
    final summary = context.l10n.dynamicProfilesPreviewSummary(
      preview.profiles.length,
      preview.addedCount,
      preview.replacementCount,
      preview.warningCount,
    );
    return AppPanel(
      key: const Key('dynamic-profiles-preview'),
      tone: AppPanelTone.chrome,
      padding: EdgeInsets.all(palette.spacing.md),
      borderRadius: BorderRadius.circular(palette.radius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary,
            key: const Key('dynamic-profiles-preview-summary'),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: palette.spacing.sm),
          for (final profile in preview.profiles)
            Padding(
              padding: EdgeInsets.only(bottom: palette.spacing.xs),
              child: Row(
                key: Key('dynamic-profiles-preview-${profile.id}'),
                children: [
                  Icon(
                    preview.replacementIds.contains(profile.id)
                        ? Icons.sync_alt_rounded
                        : Icons.add_circle_outline_rounded,
                    size: 16,
                    color: preview.replacementIds.contains(profile.id)
                        ? palette.warning
                        : palette.success,
                  ),
                  SizedBox(width: palette.spacing.sm),
                  Expanded(
                    child: Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: palette.spacing.sm),
                  Text(
                    preview.replacementIds.contains(profile.id)
                        ? context.l10n.replacesExisting
                        : context.l10n.newProfile,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: preview.replacementIds.contains(profile.id)
                          ? palette.warning
                          : palette.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
                          context.l10n.dynamicProfiles,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      AppActionButton(
                        tooltip: context.l10n.closeDynamicProfiles,
                        tone: AppActionTone.ghost,
                        size: AppActionSize.dense,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icons.close_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.dynamicProfilesPasteHelp,
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
                          label: Text(context.l10n.preview),
                        ),
                        FilledButton.icon(
                          key: const Key('dynamic-profiles-import'),
                          onPressed: preview == null ? null : _importProfiles,
                          icon: const Icon(Icons.download_rounded),
                          label: Text(context.l10n.import),
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
