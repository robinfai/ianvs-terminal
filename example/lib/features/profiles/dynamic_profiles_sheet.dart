import 'dart:convert';

import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';
import 'profile_models.dart';

class DynamicProfilesImportResult {
  const DynamicProfilesImportResult({
    required this.profiles,
    required this.warningCount,
  });

  final List<TerminalProfile> profiles;
  final int warningCount;
}

class DynamicProfilesSheet extends StatefulWidget {
  const DynamicProfilesSheet({super.key});

  @override
  State<DynamicProfilesSheet> createState() => _DynamicProfilesSheetState();
}

class _DynamicProfilesSheetState extends State<DynamicProfilesSheet> {
  late final TextEditingController _controller;
  String? _errorText;

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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _importProfiles() {
    try {
      final decoded = jsonDecode(_controller.text);
      if (decoded is! Map) {
        setState(() {
          _errorText = 'Top-level JSON must be an object.';
        });
        return;
      }
      final document = TerminalProfilesDocument.fromJson(
        decoded.cast<String, Object?>(),
      );
      if (document.profiles.isEmpty) {
        setState(() {
          _errorText = 'No profiles found in JSON.';
        });
        return;
      }
      Navigator.of(context).pop(
        DynamicProfilesImportResult(
          profiles: document.profiles,
          warningCount: document.loadWarnings.length,
        ),
      );
    } on FormatException catch (error) {
      setState(() {
        _errorText = error.message;
      });
    } on Object catch (error) {
      setState(() {
        _errorText = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
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
                    child: TextField(
                      key: const Key('dynamic-profiles-json-field'),
                      controller: _controller,
                      maxLines: null,
                      expands: true,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const Key('dynamic-profiles-import'),
                      onPressed: _importProfiles,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Import'),
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
