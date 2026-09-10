import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../features/profiles/profile_secret_cipher.dart';
import '../../platform/local_json_file.dart';
import '../repositories/data_api_repository_helpers.dart';
import '../services/data_api_client.dart';
import 'json_three_way_merge.dart';

// Values in checkpoints can contain SSH secrets. Only authenticated ciphertext
// is written to disk, scoped to the destination and resource identity.
abstract interface class SyncCheckpointStore {
  Future<Map<String, Object?>?> read(String resource);
  Future<void> write(String resource, Map<String, Object?>? value);
}

class FileSyncCheckpointStore implements SyncCheckpointStore {
  FileSyncCheckpointStore({
    required this.directory,
    required this.destination,
    required this.cipher,
  });
  final Future<Directory> Function() directory;
  final String destination;
  final ProfileSecretCipher cipher;

  Future<File> _file(String resource) async {
    final digest = await Sha256().hash(
      utf8.encode('$destination\u0000$resource'),
    );
    final name = digest.bytes
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    return File('${(await directory()).path}/sync-checkpoints/$name.json');
  }

  @override
  Future<Map<String, Object?>?> read(String resource) async {
    final file = await _file(resource);
    if (!await file.exists()) return null;
    final clear = await cipher.decrypt(
      profileId: destination,
      field: resource,
      envelope: jsonDecode(await file.readAsString()),
    );
    final json = jsonDecode(clear);
    if (json is! Map<String, dynamic> || json['version'] != 1) {
      throw const FormatException('Unsupported sync checkpoint.');
    }
    return (json['value'] as Map?)?.cast<String, Object?>();
  }

  @override
  Future<void> write(String resource, Map<String, Object?>? value) async {
    final envelope = await cipher.encrypt(
      profileId: destination,
      field: resource,
      value: jsonEncode({'version': 1, 'value': value}),
    );
    await writeStringAtomically(await _file(resource), jsonEncode(envelope));
  }
}

typedef SyncJson = Map<String, Object?>;

/// Local mutation lock is never held during network I/O. A sync commit compares
/// the original local snapshot again under the lock before applying a pull.
class SyncDocumentBinding {
  SyncDocumentBinding({
    required this.kind,
    required this.id,
    required this.readLocal,
    required this.writeLocal,
    required this.decodeRemote,
    required this.encodeRemote,
    required this.validate,
  });
  final String kind;
  final String id;
  final Future<SyncJson?> Function() readLocal;
  final Future<void> Function(SyncJson?) writeLocal;
  final SyncJson Function(DataApiResource) decodeRemote;
  final ({Object? data, Object? sensitive}) Function(SyncJson) encodeRemote;
  final void Function(SyncJson?) validate;
  String get key => '$kind/$id';
  Future<void> _queue = Future<void>.value();
  Future<T> local<T>(Future<T> Function() action) {
    final operation = _queue.then((_) => action());
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }
}

enum LocalFirstSyncPhase {
  disabled,
  idle,
  syncing,
  pending,
  conflict,
  unavailable,
}

enum LocalFirstSyncFailureReason { authenticationRequired, unavailable }

class LocalFirstSyncCoordinator extends ChangeNotifier {
  LocalFirstSyncCoordinator({
    required this.documents,
    this.client,
    this.checkpoints,
    this.enabledButUnavailable = false,
    this.closeTransport,
    this.interval = const Duration(seconds: 30),
  });
  final List<SyncDocumentBinding> documents;
  DataApiResourceClient? client;
  SyncCheckpointStore? checkpoints;
  final Duration interval;
  bool enabledButUnavailable;
  Future<void> Function()? closeTransport;
  LocalFirstSyncPhase get phase => _paused
      ? (enabledButUnavailable
            ? LocalFirstSyncPhase.unavailable
            : LocalFirstSyncPhase.disabled)
      : client == null
      ? (enabledButUnavailable
            ? LocalFirstSyncPhase.unavailable
            : LocalFirstSyncPhase.disabled)
      : _phase;
  LocalFirstSyncPhase _phase = LocalFirstSyncPhase.idle;
  final Map<String, List<String>> conflicts = {};
  LocalFirstSyncFailureReason? get failureReason => _failureReason;
  LocalFirstSyncFailureReason? _failureReason;
  DateTime? lastSyncedAt;
  int pulledGeneration = 0;
  Timer? _timer;
  Timer? _debounce;
  Future<void>? _running;
  bool _closed = false;
  bool _paused = false;

  void start() {
    if (_closed || _paused || client == null || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(synchronize()));
    unawaited(synchronize());
  }

  void changed() {
    if (_closed || _paused || client == null) return;
    _phase = LocalFirstSyncPhase.pending;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(synchronize()),
    );
  }

  Future<void> synchronize({
    JsonConflictResolution resolution = JsonConflictResolution.unresolved,
  }) {
    if (_closed || _paused || client == null) return Future<void>.value();
    return _running ??= _synchronize(
      resolution,
    ).whenComplete(() => _running = null);
  }

  Future<void> _synchronize(JsonConflictResolution resolution) async {
    _phase = LocalFirstSyncPhase.syncing;
    notifyListeners();
    conflicts.clear();
    var failed = false;
    LocalFirstSyncFailureReason? syncFailureReason;
    for (final binding in documents) {
      if (_closed || _paused) break;
      try {
        await _synchronizeDocument(binding, resolution);
      } on Object catch (error) {
        // Local data and the last acknowledged checkpoint are intact. Never
        // expose exception payloads containing credentials in the status UI.
        failed = true;
        final reason = _failureReasonFor(error);
        if (syncFailureReason !=
                LocalFirstSyncFailureReason.authenticationRequired ||
            reason == LocalFirstSyncFailureReason.authenticationRequired) {
          syncFailureReason = reason;
        }
      }
    }
    if (_closed || _paused) return;
    _failureReason = failed ? syncFailureReason : null;
    _phase = conflicts.isNotEmpty
        ? LocalFirstSyncPhase.conflict
        : failed
        ? LocalFirstSyncPhase.unavailable
        : LocalFirstSyncPhase.idle;
    if (!failed && conflicts.isEmpty) lastSyncedAt = DateTime.now();
    notifyListeners();
  }

  Future<void> _synchronizeDocument(
    SyncDocumentBinding binding,
    JsonConflictResolution resolution,
  ) async {
    // Bounded CAS retries also cover an edit made locally while the request
    // was in flight. The unchanged checkpoint permits retry after lost ACKs.
    for (var attempt = 0; attempt < 3; attempt++) {
      final local = await binding.local(binding.readLocal);
      final base = await checkpoints!.read(binding.key);
      final resource = await client!.getResource(
        kind: binding.kind,
        id: binding.id,
        includeSensitive:
            binding.kind == 'profile' || binding.kind == 'paste_history',
      );
      if (_closed || _paused) return;
      final remote = resource == null ? null : binding.decodeRemote(resource);
      // A missing aggregate resource can mean a reset/replaced server, not
      // user deletion of every profile. Individual deletions are merged inside
      // the document; whole-resource disappearance requires a visible choice.
      final remoteAggregateMissing =
          base != null && remote == null && local != null;
      if (remoteAggregateMissing &&
          resolution == JsonConflictResolution.unresolved) {
        conflicts[binding.key] = const ['/'];
        return;
      }
      final result = mergeJsonDocuments(
        base: base,
        local: local,
        remote: remote,
        conflictResolution: resolution,
      );
      if (result.hasConflicts) {
        conflicts[binding.key] = result.conflicts.map((c) => c.path).toList();
        return;
      }
      final merged = remoteAggregateMissing
          ? (resolution == JsonConflictResolution.preferLocal ? local : null)
          : result.document;
      binding.validate(merged);
      try {
        if (!dataApiJsonEquivalent(merged, remote)) {
          if (merged == null) {
            await client!.deleteResource(
              kind: binding.kind,
              id: binding.id,
              expectedRevision: resource?.revision ?? 0,
            );
          } else {
            final payload = binding.encodeRemote(merged);
            await client!.putResource(
              kind: binding.kind,
              id: binding.id,
              data: payload.data,
              sensitive: payload.sensitive,
              clearSensitive: payload.sensitive == null,
              expectedRevision: resource?.revision ?? 0,
            );
          }
        }
      } on DataApiRevisionConflictException {
        if (attempt == 2) rethrow;
        continue;
      }
      if (_closed || _paused) return;
      final committed = await binding.local(() async {
        if (_closed || _paused) return true;
        final current = await binding.readLocal();
        final rebased = mergeJsonDocuments(
          base: local,
          local: current,
          remote: merged,
        );
        if (rebased.hasConflicts) {
          conflicts[binding.key] = rebased.conflicts
              .map((c) => c.path)
              .toList();
          return true;
        }
        binding.validate(rebased.document);
        if (!dataApiJsonEquivalent(current, rebased.document)) {
          await binding.writeLocal(rebased.document);
          pulledGeneration++;
        }
        // The baseline is the acknowledged remote value, not a newer local
        // edit. The latter remains a durable pending diff for the next push.
        await checkpoints!.write(binding.key, merged);
        return dataApiJsonEquivalent(rebased.document, merged);
      });
      if (committed) return;
    }
    throw StateError('Local data changed during sync; retry pending.');
  }

  Future<void> pause() async {
    _paused = true;
    _timer?.cancel();
    _timer = null;
    _debounce?.cancel();
    await _running;
    if (!_closed) {
      _phase = LocalFirstSyncPhase.disabled;
      notifyListeners();
    }
  }

  Future<void> setTransport({
    DataApiResourceClient? nextClient,
    SyncCheckpointStore? nextCheckpoints,
    Future<void> Function()? nextClose,
  }) async {
    await pause();
    if (_closed) {
      await nextClose?.call();
      return;
    }
    try {
      await closeTransport?.call();
    } on Object {
      await nextClose?.call();
      rethrow;
    }
    client = nextClient;
    checkpoints = nextCheckpoints;
    closeTransport = nextClose;
    enabledButUnavailable = false;
    conflicts.clear();
    _failureReason = null;
    lastSyncedAt = null;
    _paused = false;
    _phase = LocalFirstSyncPhase.idle;
    notifyListeners();
    start();
  }

  void markUnavailable() {
    _paused = true;
    enabledButUnavailable = true;
    _phase = LocalFirstSyncPhase.unavailable;
    _failureReason = LocalFirstSyncFailureReason.unavailable;
    if (!_closed) notifyListeners();
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    _debounce?.cancel();
    await _running;
    await closeTransport?.call();
  }

  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}

LocalFirstSyncFailureReason _failureReasonFor(Object error) {
  if (error is DataApiAuthenticationRequiredException ||
      error is DataApiRequestException &&
          error.statusCode == HttpStatus.unauthorized) {
    return LocalFirstSyncFailureReason.authenticationRequired;
  }
  return LocalFirstSyncFailureReason.unavailable;
}

final localFirstSyncProvider =
    ChangeNotifierProvider<LocalFirstSyncCoordinator?>((ref) => null);

final applyApiSyncConfigurationProvider = Provider<Future<void> Function()?>(
  (ref) => null,
);
