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
  late TerminalEmulation _terminalEmulation;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialValue.name);
    _shellController = TextEditingController(text: widget.initialValue.shell);
    _cwdController = TextEditingController(text: widget.initialValue.cwd ?? '');
    _terminalEmulation = widget.initialValue.terminalEmulation;
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
            const SizedBox(height: 12),
            DropdownButtonFormField<TerminalEmulation>(
              initialValue: _terminalEmulation,
              decoration: const InputDecoration(labelText: 'Emulation'),
              items: TerminalEmulation.values
                  .map(
                    (value) => DropdownMenuItem<TerminalEmulation>(
                      value: value,
                      child: Text(switch (value) {
                        TerminalEmulation.xterm256 => 'xterm-256color',
                        TerminalEmulation.vt220 => 'VT220',
                      }),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _terminalEmulation = value;
                });
              },
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
                terminalEmulation: _terminalEmulation,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
