import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/app_ui.dart';
import '../sessions/session_controller.dart';
import '../terminal/terminal.dart' as terminal;
import 'sftp_file_actions.dart';

final sftpDirectoryDataSourceProvider = Provider<SftpDirectoryDataSource>((
  ref,
) {
  return TerminalRuntimeSftpDirectoryDataSource(
    ref.watch(terminalRuntimeControllerProvider),
  );
});

final sftpFileActionsProvider = Provider<SftpFileActions>((ref) {
  final actions = SftpFileActions();
  ref.onDispose(actions.dispose);
  return actions;
});

abstract interface class SftpDirectoryDataSource {
  SftpDirectoryLoadOperation startListDirectory(SftpDirectoryRequest request);
}

abstract interface class SftpFileDataSource {
  Future<void> downloadFile(SftpFileTransferRequest request);

  Future<void> uploadFile(SftpFileTransferRequest request);

  Future<void> createDirectory(SftpEntryMutationRequest request);

  Future<void> deleteEntry(SftpEntryMutationRequest request);
}

final class SftpDirectoryLoadOperation {
  SftpDirectoryLoadOperation({
    required this.future,
    required VoidCallback onCancel,
  }) : _onCancel = onCancel;

  final Future<SftpDirectorySnapshot> future;
  VoidCallback? _onCancel;

  void cancel() {
    final onCancel = _onCancel;
    _onCancel = null;
    onCancel?.call();
  }
}

class TerminalRuntimeSftpDirectoryDataSource
    implements SftpDirectoryDataSource, SftpFileDataSource {
  const TerminalRuntimeSftpDirectoryDataSource(this.runtime);

  final terminal.TerminalRuntimeController runtime;

  @override
  SftpDirectoryLoadOperation startListDirectory(SftpDirectoryRequest request) {
    final cancellation = terminal.TerminalSftpCancellation();
    return SftpDirectoryLoadOperation(
      future: _listDirectory(request, cancellation),
      onCancel: cancellation.cancel,
    );
  }

  Future<SftpDirectorySnapshot> _listDirectory(
    SftpDirectoryRequest request,
    terminal.TerminalSftpCancellation cancellation,
  ) async {
    try {
      final snapshot = await runtime.listSftpDirectory(
        request.target.sessionId,
        request.path,
        cancellation: cancellation,
      );
      return SftpDirectorySnapshot(
        path: snapshot.path,
        entries: snapshot.entries
            .map(
              (entry) => SftpDirectoryEntry(
                name: entry.name,
                kind: switch (entry.kind) {
                  terminal.TerminalSftpDirectoryEntryKind.directory =>
                    SftpDirectoryEntryKind.directory,
                  terminal.TerminalSftpDirectoryEntryKind.file =>
                    SftpDirectoryEntryKind.file,
                  terminal.TerminalSftpDirectoryEntryKind.symbolicLink =>
                    SftpDirectoryEntryKind.symbolicLink,
                  terminal.TerminalSftpDirectoryEntryKind.other =>
                    SftpDirectoryEntryKind.other,
                },
                sizeBytes: entry.sizeBytes,
                modifiedAt: entry.modifiedAt,
                permissions: entry.permissions,
              ),
            )
            .toList(growable: false),
      );
    } on terminal.TerminalSftpException catch (error) {
      throw SftpDirectoryUnavailableException(error.message);
    }
  }

  @override
  Future<void> downloadFile(SftpFileTransferRequest request) {
    return _translateFileOperation(
      runtime.downloadSftpFile(
        request.target.sessionId,
        request.remotePath,
        request.localPath,
      ),
    );
  }

  @override
  Future<void> uploadFile(SftpFileTransferRequest request) {
    return _translateFileOperation(
      runtime.uploadSftpFile(
        request.target.sessionId,
        request.localPath,
        request.remotePath,
      ),
    );
  }

  @override
  Future<void> createDirectory(SftpEntryMutationRequest request) {
    return _translateFileOperation(
      runtime.createSftpDirectory(request.target.sessionId, request.remotePath),
    );
  }

  @override
  Future<void> deleteEntry(SftpEntryMutationRequest request) {
    return _translateFileOperation(
      runtime.deleteSftpEntry(
        request.target.sessionId,
        request.remotePath,
        isDirectory: request.isDirectory,
      ),
    );
  }

  Future<void> _translateFileOperation(Future<void> operation) async {
    try {
      await operation;
    } on terminal.TerminalSftpException catch (error) {
      throw SftpDirectoryUnavailableException(error.message);
    }
  }
}

class SftpDirectoryUnavailableException implements Exception {
  const SftpDirectoryUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

@immutable
class SftpSessionTarget {
  const SftpSessionTarget({
    required this.sessionId,
    required this.profileName,
    required this.host,
    required this.user,
    required this.port,
  });

  final String sessionId;
  final String profileName;
  final String host;
  final String user;
  final int port;

  String get displayAddress {
    final normalizedHost = host.contains(':') ? '[$host]' : host;
    final userPrefix = user.trim().isEmpty ? '' : '${user.trim()}@';
    return '$userPrefix$normalizedHost:$port';
  }

  @override
  bool operator ==(Object other) {
    return other is SftpSessionTarget &&
        other.sessionId == sessionId &&
        other.profileName == profileName &&
        other.host == host &&
        other.user == user &&
        other.port == port;
  }

  @override
  int get hashCode => Object.hash(sessionId, profileName, host, user, port);
}

@immutable
class SftpDirectoryRequest {
  const SftpDirectoryRequest({required this.target, required this.path});

  final SftpSessionTarget target;
  final String path;
}

@immutable
class SftpFileTransferRequest {
  const SftpFileTransferRequest({
    required this.target,
    required this.remotePath,
    required this.localPath,
  });

  final SftpSessionTarget target;
  final String remotePath;
  final String localPath;
}

@immutable
class SftpEntryMutationRequest {
  const SftpEntryMutationRequest({
    required this.target,
    required this.remotePath,
    required this.isDirectory,
  });

  final SftpSessionTarget target;
  final String remotePath;
  final bool isDirectory;
}

@immutable
class SftpDirectorySnapshot {
  const SftpDirectorySnapshot({required this.path, required this.entries});

  final String path;
  final List<SftpDirectoryEntry> entries;
}

enum SftpDirectoryEntryKind { directory, file, symbolicLink, other }

@immutable
class SftpDirectoryEntry {
  const SftpDirectoryEntry({
    required this.name,
    required this.kind,
    this.sizeBytes,
    this.modifiedAt,
    this.permissions,
  });

  final String name;
  final SftpDirectoryEntryKind kind;
  final int? sizeBytes;
  final DateTime? modifiedAt;
  final String? permissions;

  bool get isDirectory => kind == SftpDirectoryEntryKind.directory;
  bool get isFile => kind == SftpDirectoryEntryKind.file;
}

class SftpSupportingPaneLayout extends StatelessWidget {
  const SftpSupportingPaneLayout({
    super.key,
    required this.primary,
    required this.supportingPane,
    required this.onDismissSupportingPane,
  });

  static const double dockedBreakpoint = 840;
  static const double minimumDockedWidth = 300;
  static const double maximumDockedWidth = 420;
  static const double maximumModalWidth = 380;

  final Widget primary;
  final Widget? supportingPane;
  final VoidCallback onDismissSupportingPane;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pane = supportingPane;
        if (pane == null) {
          return primary;
        }

        final palette = context.appTheme;
        if (constraints.maxWidth >= dockedBreakpoint) {
          final paneWidth = (constraints.maxWidth * 0.34).clamp(
            minimumDockedWidth,
            maximumDockedWidth,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: primary),
              VerticalDivider(
                key: const Key('sftp-right-panel-divider'),
                width: 1,
                thickness: 1,
                color: palette.border,
              ),
              SizedBox(
                key: const Key('sftp-right-panel-container'),
                width: paneWidth,
                child: pane,
              ),
            ],
          );
        }

        final paneWidth = (constraints.maxWidth * 0.88).clamp(
          0.0,
          maximumModalWidth,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(child: ExcludeFocus(child: primary)),
            Positioned.fill(
              child: Semantics(
                button: true,
                label: 'Close SFTP panel',
                child: GestureDetector(
                  key: const Key('sftp-right-panel-scrim'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onDismissSupportingPane,
                  child: ColoredBox(color: palette.inactiveScrim),
                ),
              ),
            ),
            PositionedDirectional(
              top: 0,
              bottom: 0,
              end: 0,
              width: paneWidth,
              child: DecoratedBox(
                key: const Key('sftp-right-panel-container'),
                decoration: BoxDecoration(
                  boxShadow: palette.elevation.floating,
                ),
                // FocusScopeNode defaults to a closed loop for sequential
                // traversal. Together with ExcludeFocus above this keeps the
                // modal sheet keyboard-modal without relying on route APIs.
                child: FocusScope(child: pane),
              ),
            ),
          ],
        );
      },
    );
  }
}

class SftpSidePanel extends StatefulWidget {
  const SftpSidePanel({
    super.key,
    required this.target,
    required this.dataSource,
    required this.fileActions,
    required this.onClose,
  });

  final SftpSessionTarget target;
  final SftpDirectoryDataSource dataSource;
  final SftpFileActions fileActions;
  final VoidCallback onClose;

  @override
  State<SftpSidePanel> createState() => _SftpSidePanelState();
}

class _SftpSidePanelState extends State<SftpSidePanel> {
  String _path = '/';
  late Future<SftpDirectorySnapshot> _snapshot;
  SftpDirectoryLoadOperation? _loadOperation;
  StreamSubscription<SftpFileActionEvent>? _fileActionSubscription;
  StreamSubscription<SftpRemotePathBusyEvent>? _busySubscription;
  final Set<String> _busyPaths = <String>{};

  SftpFileDataSource? get _fileDataSource {
    final dataSource = widget.dataSource;
    return dataSource is SftpFileDataSource
        ? dataSource as SftpFileDataSource
        : null;
  }

  @override
  void initState() {
    super.initState();
    _listenForFileActionEvents();
    _reload();
  }

  @override
  void didUpdateWidget(SftpSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target ||
        oldWidget.dataSource != widget.dataSource) {
      _path = '/';
      _busyPaths.clear();
      _reload();
    }
    if (oldWidget.fileActions != widget.fileActions) {
      unawaited(_fileActionSubscription?.cancel());
      unawaited(_busySubscription?.cancel());
      _listenForFileActionEvents();
    }
  }

  void _listenForFileActionEvents() {
    _fileActionSubscription = widget.fileActions.events.listen((event) {
      if (!mounted || event.sessionId != widget.target.sessionId) {
        return;
      }
      _showMessage(event.message);
    });
    _busySubscription = widget.fileActions.busyEvents.listen((event) {
      if (!mounted || event.sessionId != widget.target.sessionId) {
        return;
      }
      setState(() {
        if (event.isBusy) {
          _busyPaths.add(event.remotePath);
        } else {
          _busyPaths.remove(event.remotePath);
        }
      });
    });
    final unresolved = widget.fileActions
        .unresolvedFailuresForSession(widget.target.sessionId)
        .toList(growable: false);
    if (unresolved.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showMessage(unresolved.last.message);
        }
      });
    }
  }

  void _reload() {
    _loadOperation?.cancel();
    try {
      final operation = widget.dataSource.startListDirectory(
        SftpDirectoryRequest(target: widget.target, path: _path),
      );
      _loadOperation = operation;
      _snapshot = operation.future;
    } catch (error, stackTrace) {
      _loadOperation = null;
      _snapshot = Future<SftpDirectorySnapshot>.error(error, stackTrace);
    }
  }

  @override
  void dispose() {
    _loadOperation?.cancel();
    unawaited(_fileActionSubscription?.cancel());
    unawaited(_busySubscription?.cancel());
    super.dispose();
  }

  void _refresh() {
    setState(_reload);
  }

  void _openPath(String path) {
    setState(() {
      _path = _normalizeSftpPath(path);
      _reload();
    });
  }

  Future<void> _downloadFile(SftpDirectoryEntry entry) async {
    final dataSource = _fileDataSource;
    if (dataSource == null || !entry.isFile) {
      return;
    }
    final remotePath = _childSftpPath(_path, entry.name);
    await _withBusyPath(remotePath, () {
      return widget.fileActions.downloadAs(
        sessionId: widget.target.sessionId,
        remotePath: remotePath,
        suggestedName: entry.name,
        download: (localPath) => dataSource.downloadFile(
          SftpFileTransferRequest(
            target: widget.target,
            remotePath: remotePath,
            localPath: localPath,
          ),
        ),
      );
    });
  }

  Future<void> _editLocally(SftpDirectoryEntry entry) async {
    final dataSource = _fileDataSource;
    if (dataSource == null || !entry.isFile) {
      return;
    }
    final remotePath = _childSftpPath(_path, entry.name);
    await _withBusyPath(remotePath, () {
      return widget.fileActions.editLocally(
        sessionId: widget.target.sessionId,
        remotePath: remotePath,
        fileName: entry.name,
        download: (localPath) => dataSource.downloadFile(
          SftpFileTransferRequest(
            target: widget.target,
            remotePath: remotePath,
            localPath: localPath,
          ),
        ),
        upload: (localPath) => dataSource.uploadFile(
          SftpFileTransferRequest(
            target: widget.target,
            remotePath: remotePath,
            localPath: localPath,
          ),
        ),
      );
    });
  }

  Future<void> _withBusyPath(
    String remotePath,
    Future<Object?> Function() action,
  ) async {
    if (widget.fileActions.isRemotePathBusy(
      widget.target.sessionId,
      remotePath,
    )) {
      return;
    }
    try {
      await action();
    } on Object {
      // File-action services publish a concise user-facing failure event.
    }
  }

  Future<void> _showEntryMenu(
    SftpDirectoryEntry entry,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) {
      return;
    }
    final remotePath = _childSftpPath(_path, entry.name);
    final isBusy = widget.fileActions.isRemotePathBusy(
      widget.target.sessionId,
      remotePath,
    );
    final action = await showMenu<_SftpEntryMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<_SftpEntryMenuAction>>[
        const PopupMenuItem<_SftpEntryMenuAction>(
          key: Key('sftp-context-copy-full-path'),
          value: _SftpEntryMenuAction.copyFullPath,
          child: Text('Copy full path'),
        ),
        if (entry.isFile)
          PopupMenuItem<_SftpEntryMenuAction>(
            key: const Key('sftp-context-edit-locally'),
            value: _SftpEntryMenuAction.editLocally,
            enabled: _fileDataSource != null && !isBusy,
            child: const Text('Edit locally'),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<_SftpEntryMenuAction>(
          key: const Key('sftp-context-create-directory'),
          value: _SftpEntryMenuAction.createDirectory,
          enabled: _fileDataSource != null,
          child: const Text('Create directory'),
        ),
        PopupMenuItem<_SftpEntryMenuAction>(
          key: const Key('sftp-context-delete'),
          value: _SftpEntryMenuAction.delete,
          enabled: _fileDataSource != null && !isBusy,
          child: const Text('Delete'),
        ),
      ],
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _SftpEntryMenuAction.copyFullPath:
        await Clipboard.setData(ClipboardData(text: remotePath));
        if (mounted) {
          _showMessage('Copied $remotePath');
        }
      case _SftpEntryMenuAction.editLocally:
        await _editLocally(entry);
      case _SftpEntryMenuAction.createDirectory:
        await _createDirectory();
      case _SftpEntryMenuAction.delete:
        await _deleteEntry(entry);
    }
  }

  Future<void> _createDirectory() async {
    final dataSource = _fileDataSource;
    if (dataSource == null) {
      return;
    }
    final name = await _promptForDirectoryName();
    if (!mounted || name == null) {
      return;
    }
    final remotePath = _childSftpPath(_path, name);
    try {
      await widget.fileActions.runRemoteOperation(
        sessionId: widget.target.sessionId,
        remotePath: remotePath,
        operation: () => dataSource.createDirectory(
          SftpEntryMutationRequest(
            target: widget.target,
            remotePath: remotePath,
            isDirectory: true,
          ),
        ),
      );
      if (mounted) {
        _showMessage('Created $name');
        _refresh();
      }
    } on Object {
      if (mounted) {
        _showMessage('Could not create $name.');
      }
    }
  }

  Future<String?> _promptForDirectoryName() async {
    var name = '';
    String? validationMessage;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create directory'),
              content: TextField(
                key: const Key('sftp-create-directory-name'),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Name',
                  errorText: validationMessage,
                ),
                onSubmitted: (value) {
                  final error = _directoryNameError(value);
                  if (error != null) {
                    setDialogState(() => validationMessage = error);
                    return;
                  }
                  Navigator.of(dialogContext).pop(value.trim());
                },
                onChanged: (value) => name = value,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const Key('sftp-create-directory-confirm'),
                  onPressed: () {
                    final error = _directoryNameError(name);
                    if (error != null) {
                      setDialogState(() => validationMessage = error);
                      return;
                    }
                    Navigator.of(dialogContext).pop(name.trim());
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
    return result;
  }

  Future<void> _deleteEntry(SftpDirectoryEntry entry) async {
    final dataSource = _fileDataSource;
    if (dataSource == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${entry.name}?'),
        content: Text(
          entry.isDirectory
              ? 'The directory must be empty before it can be deleted.'
              : 'This remote file will be deleted permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('sftp-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    final remotePath = _childSftpPath(_path, entry.name);
    try {
      await widget.fileActions.runRemoteOperation(
        sessionId: widget.target.sessionId,
        remotePath: remotePath,
        operation: () => dataSource.deleteEntry(
          SftpEntryMutationRequest(
            target: widget.target,
            remotePath: remotePath,
            isDirectory: entry.isDirectory,
          ),
        ),
      );
      if (mounted) {
        _showMessage('Deleted ${entry.name}');
        _refresh();
      }
    } on Object {
      if (mounted) {
        _showMessage('Could not delete ${entry.name}.');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return FocusTraversalGroup(
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
        },
        child: Focus(
          autofocus: true,
          child: Semantics(
            key: const Key('sftp-right-panel'),
            identifier: 'sftp-right-panel',
            container: true,
            label: 'SFTP panel for ${widget.target.displayAddress}',
            explicitChildNodes: true,
            child: Material(
              color: palette.panel,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SftpPanelHeader(
                    target: widget.target,
                    onClose: widget.onClose,
                  ),
                  Divider(height: 1, thickness: 1, color: palette.border),
                  _SftpPathToolbar(
                    path: _path,
                    onGoHome: _path == '/' ? null : () => _openPath('/'),
                    onGoUp: _path == '/'
                        ? null
                        : () => _openPath(_parentSftpPath(_path)),
                    onRefresh: _refresh,
                  ),
                  Divider(height: 1, thickness: 1, color: palette.border),
                  Expanded(
                    child: FutureBuilder<SftpDirectorySnapshot>(
                      future: _snapshot,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const _SftpLoadingState();
                        }
                        if (snapshot.hasError) {
                          return _SftpErrorState(
                            error: snapshot.error!,
                            onRetry: _refresh,
                          );
                        }
                        return _SftpDirectoryList(
                          snapshot: snapshot.requireData,
                          onOpenDirectory: (name) =>
                              _openPath(_childSftpPath(_path, name)),
                          onDownloadFile: _downloadFile,
                          onShowContextMenu: _showEntryMenu,
                          busyPaths: _busyPaths,
                          isRemotePathBusy: (remotePath) =>
                              widget.fileActions.isRemotePathBusy(
                                widget.target.sessionId,
                                remotePath,
                              ),
                          parentPath: _path,
                        );
                      },
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

class _SftpPanelHeader extends StatelessWidget {
  const _SftpPanelHeader({required this.target, required this.onClose});

  final SftpSessionTarget target;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return ConstrainedBox(
      key: const Key('sftp-panel-header'),
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          palette.spacing.lg,
          palette.spacing.xs,
          4,
          palette.spacing.xs,
        ),
        child: Row(
          children: [
            Icon(Icons.folder_open_rounded, size: 19, color: palette.accent),
            SizedBox(width: palette.spacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SFTP',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    target.displayAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: palette.textSubtle),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: 'Close SFTP panel',
              child: IconButton(
                key: const Key('sftp-right-panel-close'),
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SftpPathToolbar extends StatelessWidget {
  const _SftpPathToolbar({
    required this.path,
    required this.onGoHome,
    required this.onGoUp,
    required this.onRefresh,
  });

  final String path;
  final VoidCallback? onGoHome;
  final VoidCallback? onGoUp;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return SizedBox(
      height: 42,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: palette.spacing.sm),
        child: Row(
          children: [
            Tooltip(
              message: 'Remote root',
              child: IconButton(
                key: const Key('sftp-go-root'),
                onPressed: onGoHome,
                icon: const Icon(Icons.home_outlined),
              ),
            ),
            Tooltip(
              message: 'Parent directory',
              child: IconButton(
                key: const Key('sftp-go-up'),
                onPressed: onGoUp,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ),
            SizedBox(width: palette.spacing.xs),
            Expanded(
              child: Tooltip(
                message: path,
                child: SelectableText(
                  path,
                  key: const Key('sftp-current-path'),
                  maxLines: 1,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.textMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            Tooltip(
              message: 'Refresh remote directory',
              child: IconButton(
                key: const Key('sftp-refresh'),
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SftpLoadingState extends StatelessWidget {
  const _SftpLoadingState();

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return Center(
      child: Semantics(
        label: 'Loading remote directory',
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: palette.accent,
          ),
        ),
      ),
    );
  }
}

class _SftpErrorState extends StatelessWidget {
  const _SftpErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final message = error is SftpDirectoryUnavailableException
        ? (error as SftpDirectoryUnavailableException).message
        : 'Unable to load the remote directory.';
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: palette.spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 30, color: palette.textSubtle),
            SizedBox(height: palette.spacing.lg),
            Text(
              'Remote files unavailable',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: palette.spacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
            SizedBox(height: palette.spacing.lg),
            TextButton.icon(
              key: const Key('sftp-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SftpDirectoryList extends StatelessWidget {
  const _SftpDirectoryList({
    required this.snapshot,
    required this.onOpenDirectory,
    required this.onDownloadFile,
    required this.onShowContextMenu,
    required this.busyPaths,
    required this.isRemotePathBusy,
    required this.parentPath,
  });

  final SftpDirectorySnapshot snapshot;
  final ValueChanged<String> onOpenDirectory;
  final ValueChanged<SftpDirectoryEntry> onDownloadFile;
  final Future<void> Function(SftpDirectoryEntry entry, Offset position)
  onShowContextMenu;
  final Set<String> busyPaths;
  final bool Function(String remotePath) isRemotePathBusy;
  final String parentPath;

  @override
  Widget build(BuildContext context) {
    final entries = snapshot.entries.toList()
      ..sort((left, right) {
        if (left.isDirectory != right.isDirectory) {
          return left.isDirectory ? -1 : 1;
        }
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });
    if (entries.isEmpty) {
      return const Center(child: Text('This remote directory is empty.'));
    }
    return Scrollbar(
      child: ListView.separated(
        key: const Key('sftp-directory-list'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 1),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final remotePath = _childSftpPath(parentPath, entry.name);
          return _SftpDirectoryRow(
            entry: entry,
            busy:
                busyPaths.contains(remotePath) || isRemotePathBusy(remotePath),
            onOpen: () {
              if (entry.isDirectory) {
                onOpenDirectory(entry.name);
              } else if (entry.isFile) {
                onDownloadFile(entry);
              }
            },
            onShowContextMenu: (position) => onShowContextMenu(entry, position),
          );
        },
      ),
    );
  }
}

class _SftpDirectoryRow extends StatelessWidget {
  const _SftpDirectoryRow({
    required this.entry,
    required this.busy,
    required this.onOpen,
    required this.onShowContextMenu,
  });

  final SftpDirectoryEntry entry;
  final bool busy;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onShowContextMenu;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final icon = switch (entry.kind) {
      SftpDirectoryEntryKind.directory => Icons.folder_rounded,
      SftpDirectoryEntryKind.file => Icons.insert_drive_file_outlined,
      SftpDirectoryEntryKind.symbolicLink => Icons.link_rounded,
      SftpDirectoryEntryKind.other => Icons.description_outlined,
    };
    final metadata = <String>[
      if (entry.sizeBytes case final size?) _formatByteSize(size),
      ?entry.permissions,
    ].join('  ');
    return Semantics(
      button: true,
      label: '${entry.isDirectory ? 'Folder' : 'File'} ${entry.name}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) =>
            onShowContextMenu(details.globalPosition),
        child: ListTile(
          key: ValueKey('sftp-entry-${entry.name}'),
          dense: true,
          enabled: !busy,
          minTileHeight: 42,
          contentPadding: EdgeInsets.symmetric(horizontal: palette.spacing.lg),
          leading: Icon(icon, size: 19, color: palette.accent),
          title: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
          ),
          subtitle: metadata.isEmpty
              ? null
              : Text(
                  metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: palette.textSubtle),
                ),
          trailing: busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : entry.isDirectory
              ? Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: palette.textSubtle,
                )
              : null,
          hoverColor: palette.selected.withValues(alpha: 0.56),
          focusColor: palette.selected.withValues(alpha: 0.72),
          onTap: busy ? null : onOpen,
        ),
      ),
    );
  }
}

enum _SftpEntryMenuAction { copyFullPath, editLocally, createDirectory, delete }

String _normalizeSftpPath(String path) {
  final segments = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isNotEmpty) {
        segments.removeLast();
      }
      continue;
    }
    segments.add(segment);
  }
  return segments.isEmpty ? '/' : '/${segments.join('/')}';
}

String _childSftpPath(String parent, String name) {
  return _normalizeSftpPath(parent == '/' ? '/$name' : '$parent/$name');
}

String _parentSftpPath(String path) {
  final normalized = _normalizeSftpPath(path);
  if (normalized == '/') {
    return '/';
  }
  final segments = normalized.split('/')..removeLast();
  return _normalizeSftpPath(segments.join('/'));
}

String _formatByteSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

String? _directoryNameError(String rawName) {
  final name = rawName.trim();
  if (name.isEmpty) {
    return 'Enter a directory name.';
  }
  if (name == '.' || name == '..' || name.contains('/')) {
    return 'Use a single directory name.';
  }
  if (name.length > 255 || name.runes.any(_isControlRune)) {
    return 'The directory name is not valid.';
  }
  return null;
}

bool _isControlRune(int rune) => rune <= 0x1f || (rune >= 0x7f && rune <= 0x9f);
