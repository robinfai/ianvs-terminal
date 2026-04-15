import 'package:flutter/material.dart';

import 'profile_models.dart';

class ProfileEditorDialog extends StatefulWidget {
  const ProfileEditorDialog({super.key, required this.initialValue});

  final TerminalProfile initialValue;

  @override
  State<ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<ProfileEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _shellController;
  late final TextEditingController _cwdController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialValue.name);
    _shellController = TextEditingController(text: widget.initialValue.shell);
    _cwdController = TextEditingController(text: widget.initialValue.cwd ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _shellController.dispose();
    _cwdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Profile'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _shellController,
              decoration: const InputDecoration(labelText: 'Shell'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cwdController,
              decoration: const InputDecoration(labelText: 'Working Directory'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              widget.initialValue.copyWith(
                name: _nameController.text.trim(),
                shell: _shellController.text.trim(),
                cwd: _cwdController.text.trim().isEmpty
                    ? null
                    : _cwdController.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
