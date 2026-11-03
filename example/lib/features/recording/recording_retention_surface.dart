import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';
import 'recording_retention_policy.dart';

/// Form presentation is independent of native/file operations for previews.
class RecordingRetentionSurface extends StatefulWidget {
  const RecordingRetentionSurface({
    super.key,
    required this.policy,
    required this.loading,
    required this.saving,
    required this.onSave,
    required this.onClose,
    required this.onRetry,
    this.usedBytes,
    this.error,
  });
  final RecordingRetentionPolicy policy;
  final bool loading;
  final bool saving;
  final int? usedBytes;
  final String? error;
  final ValueChanged<RecordingRetentionPolicy> onSave;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  @override
  State<RecordingRetentionSurface> createState() =>
      _RecordingRetentionSurfaceState();
}

class _RecordingRetentionSurfaceState extends State<RecordingRetentionSurface> {
  static const int _gib = 1024 * 1024 * 1024;
  final _form = GlobalKey<FormState>();
  late final _days = TextEditingController(
    text: '${widget.policy.maximumAgeDays}',
  );
  late final _capacity = TextEditingController(
    text: widget.policy.maximumBytes % _gib == 0
        ? '${widget.policy.maximumBytes ~/ _gib}'
        : '${widget.policy.maximumBytes / _gib}',
  );

  @override
  void dispose() {
    _days.dispose();
    _capacity.dispose();
    super.dispose();
  }

  int? _capacityBytes(String? value) {
    final gib = double.tryParse(value?.trim() ?? '');
    if (gib == null || !gib.isFinite || gib <= 0) return null;
    final bytes = gib * _gib;
    return bytes >= 1 && bytes <= 9007199254740991 ? bytes.round() : null;
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    widget.onSave(
      RecordingRetentionPolicy(
        maximumAgeDays: int.parse(_days.text.trim()),
        maximumBytes: _capacityBytes(_capacity.text)!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.appTheme;
    final busy = widget.loading || widget.saving;
    return PopScope(
      canPop: !widget.saving,
      child: AppDialogScaffold(
        title: l10n.recordingRetentionTitle,
        width: 520,
        height: 550,
        expandBody: true,
        insetPadding: EdgeInsets.all(tokens.spacing.md),
        onClose: widget.saving ? null : widget.onClose,
        body: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.recordingRetentionExplanation),
                SizedBox(height: tokens.spacing.md),
                if (busy) const LinearProgressIndicator(),
                if (widget.error != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      widget.error!,
                      style: TextStyle(color: tokens.danger),
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: busy ? null : widget.onRetry,
                      child: Text(l10n.retry),
                    ),
                  ),
                ],
                if (widget.usedBytes != null) ...[
                  Text(
                    l10n.recordingRetentionUsage(
                      (widget.usedBytes! / _gib).toStringAsFixed(2),
                    ),
                  ),
                  SizedBox(height: tokens.spacing.md),
                ],
                TextFormField(
                  key: const Key('recording-retention-days'),
                  controller: _days,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  maxLength: 5,
                  decoration: InputDecoration(
                    labelText: l10n.recordingRetentionDays,
                    counterText: '',
                  ),
                  validator: (value) {
                    final days = int.tryParse(value?.trim() ?? '');
                    return days != null && days >= 1 && days <= 36500
                        ? null
                        : l10n.recordingRetentionDaysError;
                  },
                ),
                SizedBox(height: tokens.spacing.md),
                TextFormField(
                  key: const Key('recording-retention-capacity'),
                  controller: _capacity,
                  enabled: !busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  maxLength: 32,
                  decoration: InputDecoration(
                    labelText: l10n.recordingRetentionCapacity,
                    counterText: '',
                  ),
                  validator: (value) => _capacityBytes(value) == null
                      ? l10n.recordingRetentionCapacityError
                      : null,
                ),
                SizedBox(height: tokens.spacing.md),
                Text(
                  l10n.recordingRetentionApplyWarning,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        footer: Wrap(
          alignment: WrapAlignment.end,
          spacing: tokens.spacing.sm,
          runSpacing: tokens.spacing.sm,
          children: [
            TextButton(
              onPressed: widget.saving ? null : widget.onClose,
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const Key('recording-retention-save'),
              onPressed: busy ? null : _save,
              child: Text(
                widget.saving
                    ? l10n.recordingRetentionApplying
                    : l10n.recordingRetentionSave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
