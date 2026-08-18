import 'dart:async';

final class TerminalSftpCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }
}

enum TerminalSftpDirectoryEntryKind { directory, file, symbolicLink, other }

final class TerminalSftpDirectoryEntry {
  const TerminalSftpDirectoryEntry({
    required this.name,
    required this.kind,
    this.sizeBytes,
    this.modifiedAt,
    this.permissions,
  });

  final String name;
  final TerminalSftpDirectoryEntryKind kind;
  final int? sizeBytes;
  final DateTime? modifiedAt;
  final String? permissions;

  factory TerminalSftpDirectoryEntry.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    if (name is! String ||
        name.isEmpty ||
        name.length > 1024 ||
        name.contains('/') ||
        name.runes.any(_isControlCodePoint)) {
      throw const FormatException('invalid SFTP directory entry name');
    }
    final kind = switch (json['kind']) {
      'directory' => TerminalSftpDirectoryEntryKind.directory,
      'file' => TerminalSftpDirectoryEntryKind.file,
      'symbolic_link' => TerminalSftpDirectoryEntryKind.symbolicLink,
      'other' => TerminalSftpDirectoryEntryKind.other,
      _ => throw const FormatException('invalid SFTP directory entry kind'),
    };
    final rawSize = json['size_bytes'];
    final sizeBytes = switch (rawSize) {
      null => null,
      final int value when value >= 0 => value,
      _ => throw const FormatException('invalid SFTP directory entry size'),
    };
    final rawModified = json['modified_at_epoch_seconds'];
    final modifiedAt = switch (rawModified) {
      null => null,
      final int value when value >= 0 && value <= 0xffffffff =>
        DateTime.fromMillisecondsSinceEpoch(
          value * Duration.millisecondsPerSecond,
          isUtc: true,
        ),
      _ => throw const FormatException(
        'invalid SFTP directory entry modification time',
      ),
    };
    final rawPermissions = json['permissions'];
    final permissions = switch (rawPermissions) {
      null => null,
      final String value when value.isNotEmpty && value.length <= 16 => value,
      _ => throw const FormatException(
        'invalid SFTP directory entry permissions',
      ),
    };
    return TerminalSftpDirectoryEntry(
      name: name,
      kind: kind,
      sizeBytes: sizeBytes,
      modifiedAt: modifiedAt,
      permissions: permissions,
    );
  }
}

bool _isControlCodePoint(int codePoint) =>
    codePoint <= 0x1f || (codePoint >= 0x7f && codePoint <= 0x9f);

final class TerminalSftpDirectorySnapshot {
  const TerminalSftpDirectorySnapshot({
    required this.path,
    required this.entries,
  });

  final String path;
  final List<TerminalSftpDirectoryEntry> entries;

  factory TerminalSftpDirectorySnapshot.fromJson(Map<String, Object?> json) {
    final path = json['path'];
    final rawEntries = json['entries'];
    if (path is! String ||
        path.isEmpty ||
        path.length > 4096 ||
        !path.startsWith('/') ||
        path.contains('\u0000')) {
      throw const FormatException('invalid SFTP directory path');
    }
    if (rawEntries is! List || rawEntries.length > 10000) {
      throw const FormatException('invalid SFTP directory entries');
    }
    final entries = <TerminalSftpDirectoryEntry>[];
    for (final rawEntry in rawEntries) {
      if (rawEntry is! Map) {
        throw const FormatException('invalid SFTP directory entry');
      }
      entries.add(
        TerminalSftpDirectoryEntry.fromJson(rawEntry.cast<String, Object?>()),
      );
    }
    return TerminalSftpDirectorySnapshot(
      path: path,
      entries: List.unmodifiable(entries),
    );
  }
}

enum TerminalSftpDirectoryPollStatus { pending, complete, failed }

final class TerminalSftpDirectoryPollResult {
  const TerminalSftpDirectoryPollResult._(this.status, this.snapshot);

  const TerminalSftpDirectoryPollResult.pending()
    : this._(TerminalSftpDirectoryPollStatus.pending, null);

  const TerminalSftpDirectoryPollResult.failed()
    : this._(TerminalSftpDirectoryPollStatus.failed, null);

  const TerminalSftpDirectoryPollResult.complete(
    TerminalSftpDirectorySnapshot snapshot,
  ) : this._(TerminalSftpDirectoryPollStatus.complete, snapshot);

  final TerminalSftpDirectoryPollStatus status;
  final TerminalSftpDirectorySnapshot? snapshot;

  factory TerminalSftpDirectoryPollResult.fromJson(Map<String, Object?> json) {
    return switch (json['status']) {
      'pending' => const TerminalSftpDirectoryPollResult.pending(),
      'failed' => const TerminalSftpDirectoryPollResult.failed(),
      'complete' => TerminalSftpDirectoryPollResult.complete(
        TerminalSftpDirectorySnapshot.fromJson(json),
      ),
      _ => throw const FormatException('invalid SFTP directory job status'),
    };
  }
}

enum TerminalSftpOperationAction {
  downloadFile('download_file'),
  uploadFile('upload_file'),
  createDirectory('create_directory'),
  deleteEntry('delete_entry');

  const TerminalSftpOperationAction(this.wireName);

  final String wireName;
}

enum TerminalSftpOperationPollStatus { pending, complete, failed }

final class TerminalSftpOperationPollResult {
  const TerminalSftpOperationPollResult(this.status);

  final TerminalSftpOperationPollStatus status;

  factory TerminalSftpOperationPollResult.fromJson(Map<String, Object?> json) {
    return TerminalSftpOperationPollResult(switch (json['status']) {
      'pending' => TerminalSftpOperationPollStatus.pending,
      'complete' => TerminalSftpOperationPollStatus.complete,
      'failed' => TerminalSftpOperationPollStatus.failed,
      _ => throw const FormatException('invalid SFTP operation status'),
    });
  }
}

final class TerminalSftpException implements Exception {
  const TerminalSftpException(this.message);

  final String message;

  @override
  String toString() => message;
}
