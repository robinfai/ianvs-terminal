import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/services/portable_master_key.dart';
import '../../ui/app_ui.dart';

typedef MasterKeyClipboardWriter = Future<void> Function(String value);

final class MasterKeyManagementController extends ChangeNotifier {
  MasterKeyManagementController({
    required PortableMasterKeyRepository repository,
    MasterKeyClipboardWriter? clipboardWriter,
  }) : _repository = repository,
       _clipboardWriter = clipboardWriter ?? _writeClipboard;

  final PortableMasterKeyRepository _repository;
  final MasterKeyClipboardWriter _clipboardWriter;

  bool _busy = false;
  String? _status;
  String? _error;

  bool get busy => _busy;
  String? get status => _status;
  String? get error => _error;

  Future<void> copyForTransfer() {
    return _run(() async {
      final encoded = await _repository.exportPortable();
      await _clipboardWriter(encoded);
      _status = 'Master key copied. Paste it only into another Ianvs app.';
    });
  }

  Future<void> importFromTransfer(String encoded) {
    return _run(() async {
      await _repository.importPortable(encoded);
      _status = 'Master key imported successfully.';
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) {
      return;
    }
    _busy = true;
    _status = null;
    _error = null;
    notifyListeners();
    try {
      await operation();
    } on Object catch (error) {
      _error = error.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  static Future<void> _writeClipboard(String value) {
    return Clipboard.setData(ClipboardData(text: value));
  }
}

final class MasterKeyManagementPanel extends StatefulWidget {
  const MasterKeyManagementPanel({
    required this.repository,
    this.clipboardWriter,
    super.key,
  });

  final PortableMasterKeyRepository repository;
  final MasterKeyClipboardWriter? clipboardWriter;

  @override
  State<MasterKeyManagementPanel> createState() =>
      _MasterKeyManagementPanelState();
}

final class _MasterKeyManagementPanelState
    extends State<MasterKeyManagementPanel> {
  late MasterKeyManagementController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MasterKeyManagementController(
      repository: widget.repository,
      clipboardWriter: widget.clipboardWriter,
    );
  }

  @override
  void didUpdateWidget(MasterKeyManagementPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.clipboardWriter != widget.clipboardWriter) {
      _controller.dispose();
      _controller = MasterKeyManagementController(
        repository: widget.repository,
        clipboardWriter: widget.clipboardWriter,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmAndCopy() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Copy the master key?'),
        content: const Text(
          'Anyone with this key can decrypt your Ianvs data. The key will be '
          'placed on the system clipboard; paste it into the destination app '
          'and then clear the clipboard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('master-key-confirm-copy'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Copy key'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _controller.copyForTransfer();
    }
  }

  Future<void> _showImportDialog() async {
    var input = '';
    final encoded = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Import master key'),
        content: TextField(
          key: const Key('master-key-import-field'),
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (value) => input = value,
          decoration: const InputDecoration(
            labelText: 'Ianvs master key',
            helperText: 'Paste the complete value beginning with ianvs-key-v1.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('master-key-confirm-import'),
            onPressed: () => Navigator.of(context).pop(input),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (encoded != null && encoded.trim().isNotEmpty && mounted) {
      await _controller.importFromTransfer(encoded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final usesAppleKeychain = usesAutomaticallySynchronizedAppleKeychain;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionHeader(
              title: 'Master key',
              description: usesAppleKeychain
                  ? 'Encryption is managed automatically on this Apple device.'
                  : 'One portable key unlocks local, remote, and SSH profile '
                        'encryption across supported platforms.',
            ),
            SizedBox(height: theme.spacing.sm),
            AppPanel(
              key: const Key('master-key-management-panel'),
              tone: AppPanelTone.panel,
              padding: EdgeInsets.all(theme.spacing.xl),
              child: usesAppleKeychain
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            Icons.cloud_done_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        SizedBox(width: theme.spacing.sm),
                        const Expanded(
                          child: Text(
                            'Ianvs Terminal stores the master key in iCloud '
                            'Keychain and requests synchronization '
                            'automatically. No manual key entry is required.',
                            key: Key('master-key-apple-keychain-status'),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: theme.spacing.sm,
                          runSpacing: theme.spacing.sm,
                          children: [
                            AppActionButton(
                              buttonKey: const Key('master-key-copy'),
                              tone: AppActionTone.secondary,
                              size: AppActionSize.compact,
                              icon: Icons.copy_rounded,
                              label: 'Copy for another device',
                              onPressed: _controller.busy
                                  ? null
                                  : _confirmAndCopy,
                            ),
                            AppActionButton(
                              buttonKey: const Key('master-key-import'),
                              tone: AppActionTone.secondary,
                              size: AppActionSize.compact,
                              icon: Icons.content_paste_rounded,
                              label: 'Paste from another device',
                              onPressed: _controller.busy
                                  ? null
                                  : _showImportDialog,
                            ),
                          ],
                        ),
                        if (_controller.busy) ...[
                          SizedBox(height: theme.spacing.sm),
                          const LinearProgressIndicator(),
                        ],
                        if (_controller.status case final status?) ...[
                          SizedBox(height: theme.spacing.sm),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              status,
                              key: const Key('master-key-status'),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: theme.textSubtle),
                            ),
                          ),
                        ],
                        if (_controller.error case final error?) ...[
                          SizedBox(height: theme.spacing.sm),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              error,
                              key: const Key('master-key-error'),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}
