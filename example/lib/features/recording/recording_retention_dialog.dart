import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';
import 'recording_retention_policy.dart';
import 'recording_retention_surface.dart';
import 'sampled_recording_library.dart';

Future<bool?> showRecordingRetention({
  required BuildContext context,
  required SampledRecordingLibrary library,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _RetentionDialog(library: library),
);

class _RetentionDialog extends StatefulWidget {
  const _RetentionDialog({required this.library});
  final SampledRecordingLibrary library;
  @override
  State<_RetentionDialog> createState() => _RetentionDialogState();
}

class _RetentionDialogState extends State<_RetentionDialog> {
  RecordingRetentionPolicy _policy = RecordingRetentionPolicy(
    maximumAgeDays: 30,
    maximumBytes: 20 * 1024 * 1024 * 1024,
  );
  bool _loading = true;
  bool _saving = false;
  int _revision = 0;
  int? _usedBytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Localization is available after this dialog's first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted || _saving) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final policy = await widget.library.loadRetentionPolicy();
      final bytes = await widget.library.storageBytes();
      if (!mounted) return;
      setState(() {
        _policy = policy;
        _usedBytes = bytes;
        _revision++;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = context.l10n.recordingRetentionLoadError('$error'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(RecordingRetentionPolicy policy) async {
    if (_loading || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.library.saveRetentionPolicy(policy);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = context.l10n.recordingRetentionApplyError('$error');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => RecordingRetentionSurface(
    key: ValueKey(_revision),
    policy: _policy,
    usedBytes: _usedBytes,
    loading: _loading,
    saving: _saving,
    error: _error,
    onSave: _save,
    onRetry: _load,
    onClose: () => Navigator.of(context).pop(false),
  );
}
