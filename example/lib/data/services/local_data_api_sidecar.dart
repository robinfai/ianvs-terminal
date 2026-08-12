import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'data_api_local_access_token.dart';
import 'data_api_runtime.dart';

abstract interface class LocalDataApiSidecarHandle {
  Uri get baseUri;

  Future<void> close();
}

typedef LocalDataApiSidecarLauncher =
    Future<LocalDataApiSidecarHandle> Function({
      required File binary,
      required File database,
      required String localAccessToken,
    });

class LocalDataApiSidecar implements LocalDataApiSidecarHandle {
  LocalDataApiSidecar._({
    required this.baseUri,
    required LocalDataApiSidecarResourceCleanup resourceCleanup,
  }) : _resourceCleanup = resourceCleanup;

  static const _readyPrefix = 'IANVS_API_READY=';
  static const _defaultShutdownGracePeriod = Duration(seconds: 5);
  static const _defaultShutdownTerminateTimeout = Duration(seconds: 3);
  static const _defaultShutdownKillTimeout = Duration(seconds: 2);
  static const _minimumProcessEnvironment = <String, String>{
    'LANG': 'C',
    'PATH': '/usr/bin:/bin',
  };

  @override
  final Uri baseUri;
  final LocalDataApiSidecarResourceCleanup _resourceCleanup;
  Future<void>? _closeFuture;

  static Future<LocalDataApiSidecar> start({
    required File binary,
    required File database,
    required String localAccessToken,
    Duration startupTimeout = const Duration(seconds: 10),
    Duration shutdownGracePeriod = _defaultShutdownGracePeriod,
    Duration shutdownTerminateTimeout = _defaultShutdownTerminateTimeout,
    Duration shutdownKillTimeout = _defaultShutdownKillTimeout,
  }) async {
    if (!await binary.exists()) {
      throw StateError('The bundled local data API is missing: ${binary.path}');
    }
    await database.parent.create(recursive: true);
    final runtimeConfiguration =
        await LocalDataApiSidecarRuntimeConfiguration.create(
          parent: database.parent,
          database: database,
          localAccessToken: localAccessToken,
        );

    late final Process process;
    try {
      process = await Process.start(
        binary.path,
        <String>['serve', '--config', runtimeConfiguration.file.path],
        environment: _minimumProcessEnvironment,
        includeParentEnvironment: false,
        workingDirectory: binary.parent.path,
        runInShell: false,
      );
    } on Object {
      await runtimeConfiguration.delete();
      rethrow;
    }
    final processTerminator = LocalDataApiSidecarProcessTerminator(
      gracePeriod: shutdownGracePeriod,
      terminateTimeout: shutdownTerminateTimeout,
      killTimeout: shutdownKillTimeout,
    );
    final terminationProcess = _IoLocalDataApiSidecarProcess(process);

    final ready = Completer<Uri>();
    var startupPending = true;
    final stderrDone = Completer<void>();
    final stderrTail = _SanitizedStderrTail(
      secrets: <String>{
        localAccessToken,
        database.path,
        runtimeConfiguration.file.path,
      },
    );
    final stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (startupPending &&
              !ready.isCompleted &&
              line.startsWith(_readyPrefix)) {
            final uri = Uri.tryParse(line.substring(_readyPrefix.length));
            if (uri != null && uri.scheme == 'http' && uri.host.isNotEmpty) {
              ready.complete(uri);
            }
          }
        });
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          stderrTail.add,
          onError: (Object _, StackTrace _) {},
          onDone: stderrDone.complete,
        );
    final resourceCleanup = LocalDataApiSidecarResourceCleanup(
      process: terminationProcess,
      processTerminator: processTerminator,
      cancelSubscriptions: () => _cancelSubscriptionsAndRuntimeConfiguration(
        stdoutSubscription,
        stderrSubscription,
        runtimeConfiguration,
      ),
    );
    unawaited(
      process.exitCode.then((exitCode) async {
        if (startupPending && !ready.isCompleted) {
          await stderrDone.future;
          if (startupPending && !ready.isCompleted) {
            ready.completeError(
              StateError(
                'The local data API exited before startup (code $exitCode).',
              ),
            );
          }
        }
      }),
    );

    try {
      final baseUri = await ready.future.timeout(startupTimeout);
      // The backend loads the document before announcing READY. Remove the
      // token-bearing file immediately; later cleanup remains idempotent.
      await runtimeConfiguration.delete();
      startupPending = false;
      return LocalDataApiSidecar._(
        baseUri: baseUri,
        resourceCleanup: resourceCleanup,
      );
    } on Object catch (error, stackTrace) {
      startupPending = false;
      final terminationFailure = await resourceCleanup.terminateForStartup();
      try {
        await stderrDone.future.timeout(shutdownKillTimeout);
      } on Object {
        // Preserve bounded startup failure handling even if stderr never closes.
      }
      final startupFailure = LocalDataApiSidecarStartException(
        cause: error,
        sanitizedStderrTail: stderrTail.text,
        terminationFailure: terminationFailure,
      );
      await resourceCleanup.completeStartupFailure(startupFailure, stackTrace);
    }
  }

  @override
  Future<void> close() => _closeFuture ??= _resourceCleanup.close();
}

/// One process-private backend configuration document.
///
/// It deliberately lives outside the user-facing Data API configuration file
/// and owns the bearer token only for the lifetime of one local sidecar.
final class LocalDataApiSidecarRuntimeConfiguration {
  const LocalDataApiSidecarRuntimeConfiguration._({
    required this.directory,
    required this.file,
  });

  static const currentSchemaVersion = 1;

  final Directory directory;
  final File file;

  static Future<LocalDataApiSidecarRuntimeConfiguration> create({
    required Directory parent,
    required File database,
    required String localAccessToken,
  }) async {
    if (!isCanonicalDataApiLocalAccessToken(localAccessToken)) {
      throw const FormatException(
        'The local Data API access token must be a canonical unpadded '
        'base64url encoding of 32 random bytes.',
      );
    }
    final directory = await parent.createTemp('sidecar-runtime-');
    final file = File(
      '${directory.path}${Platform.pathSeparator}runtime-config.json',
    );
    RandomAccessFile? writer;
    var completed = false;
    try {
      _setPrivatePosixMode(directory.path, 0x1c0);
      // The parent directory was freshly created with a random name and 0700
      // permissions, so this path cannot pre-exist or be observed by peers.
      writer = await file.open(mode: FileMode.write);
      _setPrivatePosixMode(file.path, 0x180);
      final document = <String, Object?>{
        'schema_version': currentSchemaVersion,
        'mode': 'local',
        'address': '127.0.0.1:0',
        'database_driver': 'sqlite',
        'database_dsn': database.absolute.path,
        'local_access_token': localAccessToken,
        'exit_on_stdin_close': true,
        'auth_token_ttl_seconds': 3600,
        'allow_registration': false,
        'allow_insecure_sensitive_transport': false,
        'trust_proxy_headers': false,
      };
      await writer.writeFrom(utf8.encode('${jsonEncode(document)}\n'));
      await writer.flush();
      await writer.close();
      writer = null;
      completed = true;
      return LocalDataApiSidecarRuntimeConfiguration._(
        directory: directory,
        file: file,
      );
    } finally {
      await writer?.close();
      if (!completed && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  Future<void> delete() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

class LocalDataApiSidecarStartException
    implements DataApiRuntimeTerminationFailureCarrier {
  const LocalDataApiSidecarStartException({
    required this.cause,
    required this.sanitizedStderrTail,
    this.terminationFailure,
  });

  final Object cause;
  final String sanitizedStderrTail;
  @override
  final DataApiRuntimeTerminationUnknownFailure? terminationFailure;

  @override
  String toString() {
    final message = StringBuffer('The local data API failed to start: $cause');
    if (sanitizedStderrTail.isNotEmpty) {
      message
        ..writeln()
        ..writeln('Sanitized stderr tail:')
        ..write(sanitizedStderrTail);
    }
    if (terminationFailure case final failure?) {
      message
        ..writeln()
        ..write('Process termination could not be confirmed: $failure');
    }
    return message.toString();
  }
}

typedef LocalDataApiSidecarSubscriptionCancellation = Future<void> Function();

/// Owns the two independent cleanup resources of a running sidecar.
///
/// Process termination is always attempted before stream subscription
/// cancellation. If both fail, neither error is discarded.
final class LocalDataApiSidecarResourceCleanup {
  LocalDataApiSidecarResourceCleanup({
    required LocalDataApiSidecarProcess process,
    required LocalDataApiSidecarProcessTerminator processTerminator,
    required LocalDataApiSidecarSubscriptionCancellation cancelSubscriptions,
  }) : _process = process,
       _processTerminator = processTerminator,
       _cancelSubscriptions = cancelSubscriptions;

  final LocalDataApiSidecarProcess _process;
  final LocalDataApiSidecarProcessTerminator _processTerminator;
  final LocalDataApiSidecarSubscriptionCancellation _cancelSubscriptions;

  Future<void> close() async {
    Object? terminationError;
    StackTrace? terminationStackTrace;
    try {
      await _processTerminator.terminate(_process);
    } on Object catch (error, stackTrace) {
      terminationError = error;
      terminationStackTrace = stackTrace;
    }

    Object? cancellationError;
    StackTrace? cancellationStackTrace;
    try {
      await _cancelSubscriptions();
    } on Object catch (error, stackTrace) {
      cancellationError = error;
      cancellationStackTrace = stackTrace;
    }

    if (terminationError != null && cancellationError != null) {
      Error.throwWithStackTrace(
        LocalDataApiSidecarCleanupException(
          primaryError: terminationError,
          subscriptionCancellationError: cancellationError,
        ),
        terminationStackTrace!,
      );
    }
    if (terminationError != null) {
      Error.throwWithStackTrace(terminationError, terminationStackTrace!);
    }
    if (cancellationError != null) {
      Error.throwWithStackTrace(cancellationError, cancellationStackTrace!);
    }
  }

  Future<DataApiRuntimeTerminationUnknownFailure?> terminateForStartup() async {
    try {
      await _processTerminator.terminate(_process);
      return null;
    } on Object catch (error) {
      final terminationFailure = dataApiRuntimeTerminationFailureOf(error);
      if (terminationFailure != null) {
        return terminationFailure;
      }
      rethrow;
    }
  }

  Future<Never> completeStartupFailure(
    LocalDataApiSidecarStartException startupFailure,
    StackTrace startupStackTrace,
  ) async {
    try {
      await _cancelSubscriptions();
    } on Object catch (cancellationError) {
      Error.throwWithStackTrace(
        LocalDataApiSidecarCleanupException(
          primaryError: startupFailure,
          subscriptionCancellationError: cancellationError,
        ),
        startupStackTrace,
      );
    }
    Error.throwWithStackTrace(startupFailure, startupStackTrace);
  }
}

/// Preserves a primary startup/termination error when subscription cleanup
/// independently fails.
final class LocalDataApiSidecarCleanupException
    implements DataApiRuntimeTerminationFailureCarrier {
  const LocalDataApiSidecarCleanupException({
    required this.primaryError,
    required this.subscriptionCancellationError,
  });

  final Object primaryError;
  final Object subscriptionCancellationError;

  @override
  DataApiRuntimeTerminationUnknownFailure? get terminationFailure {
    return dataApiRuntimeTerminationFailureOf(primaryError) ??
        dataApiRuntimeTerminationFailureOf(subscriptionCancellationError);
  }

  @override
  String toString() {
    return 'Local data API cleanup failed ($primaryError), and subscription '
        'cancellation also failed ($subscriptionCancellationError).';
  }
}

/// The process operations required by the sidecar termination protocol.
///
/// Keeping this boundary smaller than [Process] makes the escalation policy
/// independently testable without starting or sleeping on a real process.
abstract interface class LocalDataApiSidecarProcess {
  Future<void> closeStdin();

  Future<int> get exitCode;

  bool kill(ProcessSignal signal);
}

typedef LocalDataApiSidecarExitWait =
    Future<bool> Function(LocalDataApiSidecarProcess process, Duration timeout);

/// Performs bounded stdin, SIGTERM, and SIGKILL sidecar shutdown escalation.
final class LocalDataApiSidecarProcessTerminator {
  LocalDataApiSidecarProcessTerminator({
    Duration gracePeriod = const Duration(seconds: 5),
    Duration terminateTimeout = const Duration(seconds: 3),
    Duration killTimeout = const Duration(seconds: 2),
    LocalDataApiSidecarExitWait? waitForExit,
  }) : _gracePeriod = gracePeriod,
       _terminateTimeout = terminateTimeout,
       _killTimeout = killTimeout,
       _waitForExit = waitForExit ?? _waitForSidecarExit;

  final Duration _gracePeriod;
  final Duration _terminateTimeout;
  final Duration _killTimeout;
  final LocalDataApiSidecarExitWait _waitForExit;

  Future<void> terminate(LocalDataApiSidecarProcess process) async {
    try {
      await process.closeStdin().timeout(_gracePeriod);
    } on Object {
      // Continue with bounded signal escalation.
    }
    if (await _wait(
      process,
      _gracePeriod,
      LocalDataApiSidecarTerminationOperation.waitAfterStdinClose,
    )) {
      return;
    }
    _sendSignal(
      process,
      ProcessSignal.sigterm,
      LocalDataApiSidecarTerminationOperation.sendTerminateSignal,
    );
    if (await _wait(
      process,
      _terminateTimeout,
      LocalDataApiSidecarTerminationOperation.waitAfterTerminateSignal,
    )) {
      return;
    }

    final killAccepted = _sendSignal(
      process,
      ProcessSignal.sigkill,
      LocalDataApiSidecarTerminationOperation.sendKillSignal,
    );
    final exitObserved = await _wait(
      process,
      _killTimeout,
      LocalDataApiSidecarTerminationOperation.waitAfterKillSignal,
    );
    if (!killAccepted || !exitObserved) {
      throw LocalDataApiSidecarTerminationUnknownException(
        killAccepted: killAccepted,
        exitObserved: exitObserved,
      );
    }
  }

  Future<bool> _wait(
    LocalDataApiSidecarProcess process,
    Duration timeout,
    LocalDataApiSidecarTerminationOperation operation,
  ) async {
    try {
      return await _waitForExit(process, timeout);
    } on DataApiRuntimeTerminationUnknownFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        LocalDataApiSidecarTerminationOperationException(
          operation: operation,
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  bool _sendSignal(
    LocalDataApiSidecarProcess process,
    ProcessSignal signal,
    LocalDataApiSidecarTerminationOperation operation,
  ) {
    try {
      return process.kill(signal);
    } on DataApiRuntimeTerminationUnknownFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        LocalDataApiSidecarTerminationOperationException(
          operation: operation,
          cause: error,
        ),
        stackTrace,
      );
    }
  }
}

enum LocalDataApiSidecarTerminationOperation {
  waitAfterStdinClose,
  sendTerminateSignal,
  waitAfterTerminateSignal,
  sendKillSignal,
  waitAfterKillSignal,
}

/// Wraps an I/O or injected-wait failure that prevents the caller from
/// establishing whether the sidecar exited.
final class LocalDataApiSidecarTerminationOperationException
    implements DataApiRuntimeTerminationUnknownFailure {
  const LocalDataApiSidecarTerminationOperationException({
    required this.operation,
    required this.cause,
  });

  final LocalDataApiSidecarTerminationOperation operation;
  final Object cause;

  @override
  String toString() {
    return 'The local data API process termination state is unknown because '
        '$operation failed: $cause';
  }
}

/// Reports that the final SIGKILL request or subsequent exit confirmation
/// failed, so the caller must assume the sidecar may still be running.
final class LocalDataApiSidecarTerminationUnknownException
    implements DataApiRuntimeTerminationUnknownFailure {
  const LocalDataApiSidecarTerminationUnknownException({
    required this.killAccepted,
    required this.exitObserved,
  });

  final bool killAccepted;
  final bool exitObserved;

  @override
  String toString() {
    return 'The local data API process termination state is unknown '
        '(SIGKILL accepted: $killAccepted, exit observed: $exitObserved).';
  }
}

final class _IoLocalDataApiSidecarProcess
    implements LocalDataApiSidecarProcess {
  const _IoLocalDataApiSidecarProcess(this._process);

  final Process _process;

  @override
  Future<void> closeStdin() async {
    await _process.stdin.close();
  }

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill(ProcessSignal signal) => _process.kill(signal);
}

class _SanitizedStderrTail {
  _SanitizedStderrTail({required Set<String> secrets})
    : _secrets = secrets.where((secret) => secret.isNotEmpty).toList()
        ..sort((left, right) => right.length.compareTo(left.length));

  static const _maximumLines = 24;
  static const _maximumCharacters = 4096;
  static const _redaction = '<redacted>';
  static final _credentialAssignment = RegExp(
    r'''\b(authorization|x-ianvs-encryption-key|ianvs[_-]local[_-]access[_-]token|ianvs[_-]encryption[_-]key|access[_-]?token|api[_-]?key|password|passwd|secret)\b(\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;&]+)''',
    caseSensitive: false,
  );
  static final _bearerCredential = RegExp(
    r'\bbearer\s+[^\s,;&]+',
    caseSensitive: false,
  );
  static final _uriCredential = RegExp(
    r'([a-z][a-z0-9+.-]*://[^:/\s]+:)[^@\s]+@',
    caseSensitive: false,
  );

  final List<String> _secrets;
  final List<String> _lines = <String>[];
  int _characterCount = 0;

  String get text => _lines.join('\n');

  void add(String rawLine) {
    var line = _sanitize(rawLine);
    if (line.length > _maximumCharacters) {
      const prefix = '<truncated>';
      line =
          '$prefix${line.substring(line.length - (_maximumCharacters - prefix.length))}';
    }
    _lines.add(line);
    _characterCount += line.length;
    while (_lines.length > _maximumLines ||
        _characterCount + _lines.length - 1 > _maximumCharacters) {
      _characterCount -= _lines.removeAt(0).length;
    }
  }

  String _sanitize(String rawLine) {
    var line = rawLine;
    for (final secret in _secrets) {
      line = line.replaceAll(secret, _redaction);
    }
    line = line.replaceAllMapped(
      _credentialAssignment,
      (match) => '${match.group(1)}${match.group(2)}$_redaction',
    );
    line = line.replaceAll(_bearerCredential, 'Bearer $_redaction');
    return line.replaceAllMapped(
      _uriCredential,
      (match) => '${match.group(1)}$_redaction@',
    );
  }
}

Future<bool> _waitForSidecarExit(
  LocalDataApiSidecarProcess process,
  Duration timeout,
) async {
  try {
    await process.exitCode.timeout(timeout);
    return true;
  } on TimeoutException {
    return false;
  }
}

Future<void> _cancelSubscriptions(
  StreamSubscription<String> stdoutSubscription,
  StreamSubscription<String> stderrSubscription,
) async {
  await Future.wait<void>([
    stdoutSubscription.cancel(),
    stderrSubscription.cancel(),
  ]).timeout(const Duration(seconds: 2), onTimeout: () => <void>[]);
}

Future<void> _cancelSubscriptionsAndRuntimeConfiguration(
  StreamSubscription<String> stdoutSubscription,
  StreamSubscription<String> stderrSubscription,
  LocalDataApiSidecarRuntimeConfiguration runtimeConfiguration,
) async {
  Object? cancellationError;
  StackTrace? cancellationStackTrace;
  try {
    await _cancelSubscriptions(stdoutSubscription, stderrSubscription);
  } on Object catch (error, stackTrace) {
    cancellationError = error;
    cancellationStackTrace = stackTrace;
  }
  try {
    await runtimeConfiguration.delete();
  } on Object catch (error, stackTrace) {
    cancellationError ??= error;
    cancellationStackTrace ??= stackTrace;
  }
  if (cancellationError != null) {
    Error.throwWithStackTrace(cancellationError, cancellationStackTrace!);
  }
}

int Function(ffi.Pointer<Utf8> path, int mode)? _chmod;

void _setPrivatePosixMode(String path, int mode) {
  if (Platform.isWindows) {
    return;
  }
  final chmod = _chmod ??= ffi.DynamicLibrary.process()
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<Utf8> path, ffi.Uint32 mode),
        int Function(ffi.Pointer<Utf8> path, int mode)
      >('chmod');
  final nativePath = path.toNativeUtf8();
  try {
    if (chmod(nativePath, mode) != 0) {
      throw FileSystemException(
        'Could not restrict local Data API runtime configuration permissions.',
        path,
      );
    }
  } finally {
    malloc.free(nativePath);
  }
}
