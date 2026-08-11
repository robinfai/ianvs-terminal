import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'data_api_runtime.dart';

class LocalDataApiSidecar {
  LocalDataApiSidecar._({
    required this.baseUri,
    required LocalDataApiSidecarResourceCleanup resourceCleanup,
  }) : _resourceCleanup = resourceCleanup;

  static const _readyPrefix = 'IANVS_API_READY=';
  static const _defaultShutdownGracePeriod = Duration(seconds: 5);
  static const _defaultShutdownTerminateTimeout = Duration(seconds: 3);
  static const _defaultShutdownKillTimeout = Duration(seconds: 2);

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

    final process = await Process.start(
      binary.path,
      const <String>['serve'],
      environment: <String, String>{
        ...Platform.environment,
        'IANVS_API_MODE': 'local',
        'IANVS_API_ADDR': '127.0.0.1:0',
        'IANVS_DB_DRIVER': 'sqlite',
        'IANVS_DB_DSN': database.path,
        'IANVS_ALLOW_REGISTRATION': 'false',
        'IANVS_LOCAL_ACCESS_TOKEN': localAccessToken,
        'IANVS_EXIT_ON_STDIN_CLOSE': 'true',
      },
      workingDirectory: binary.parent.path,
      runInShell: false,
    );
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
        ...Platform.environment.entries
            .where((entry) => _looksLikeSecretName(entry.key))
            .map((entry) => entry.value)
            .where((value) => value.length >= 4),
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
      cancelSubscriptions: () =>
          _cancelSubscriptions(stdoutSubscription, stderrSubscription),
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

  Future<void> close() => _closeFuture ??= _resourceCleanup.close();
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

bool _looksLikeSecretName(String name) {
  final normalized = name.toLowerCase();
  return normalized.contains('token') ||
      normalized.contains('secret') ||
      normalized.contains('password') ||
      normalized.contains('passwd') ||
      normalized.contains('credential') ||
      normalized.contains('api_key') ||
      normalized.contains('apikey') ||
      normalized.contains('private_key') ||
      normalized.contains('encryption_key');
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
