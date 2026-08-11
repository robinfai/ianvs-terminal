import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LocalDataApiSidecar {
  LocalDataApiSidecar._({
    required Process process,
    required this.baseUri,
    required StreamSubscription<String> stdoutSubscription,
    required StreamSubscription<String> stderrSubscription,
    required Duration shutdownGracePeriod,
    required Duration shutdownTerminateTimeout,
    required Duration shutdownKillTimeout,
  }) : _process = process,
       _stdoutSubscription = stdoutSubscription,
       _stderrSubscription = stderrSubscription,
       _shutdownGracePeriod = shutdownGracePeriod,
       _shutdownTerminateTimeout = shutdownTerminateTimeout,
       _shutdownKillTimeout = shutdownKillTimeout;

  static const _readyPrefix = 'IANVS_API_READY=';
  static const _defaultShutdownGracePeriod = Duration(seconds: 5);
  static const _defaultShutdownTerminateTimeout = Duration(seconds: 3);
  static const _defaultShutdownKillTimeout = Duration(seconds: 2);

  final Process _process;
  final Uri baseUri;
  final StreamSubscription<String> _stdoutSubscription;
  final StreamSubscription<String> _stderrSubscription;
  final Duration _shutdownGracePeriod;
  final Duration _shutdownTerminateTimeout;
  final Duration _shutdownKillTimeout;
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
        process: process,
        baseUri: baseUri,
        stdoutSubscription: stdoutSubscription,
        stderrSubscription: stderrSubscription,
        shutdownGracePeriod: shutdownGracePeriod,
        shutdownTerminateTimeout: shutdownTerminateTimeout,
        shutdownKillTimeout: shutdownKillTimeout,
      );
    } on Object catch (error, stackTrace) {
      startupPending = false;
      await _terminateProcess(
        process,
        gracePeriod: shutdownGracePeriod,
        terminateTimeout: shutdownTerminateTimeout,
        killTimeout: shutdownKillTimeout,
      );
      try {
        await stderrDone.future.timeout(shutdownKillTimeout);
      } on Object {
        // Preserve bounded startup failure handling even if stderr never closes.
      }
      await _cancelSubscriptions(stdoutSubscription, stderrSubscription);
      Error.throwWithStackTrace(
        LocalDataApiSidecarStartException(
          cause: error,
          sanitizedStderrTail: stderrTail.text,
        ),
        stackTrace,
      );
    }
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    try {
      await _terminateProcess(
        _process,
        gracePeriod: _shutdownGracePeriod,
        terminateTimeout: _shutdownTerminateTimeout,
        killTimeout: _shutdownKillTimeout,
      );
    } finally {
      await _cancelSubscriptions(_stdoutSubscription, _stderrSubscription);
    }
  }
}

class LocalDataApiSidecarStartException implements Exception {
  const LocalDataApiSidecarStartException({
    required this.cause,
    required this.sanitizedStderrTail,
  });

  final Object cause;
  final String sanitizedStderrTail;

  @override
  String toString() {
    final message = StringBuffer('The local data API failed to start: $cause');
    if (sanitizedStderrTail.isNotEmpty) {
      message
        ..writeln()
        ..writeln('Sanitized stderr tail:')
        ..write(sanitizedStderrTail);
    }
    return message.toString();
  }
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

Future<void> _terminateProcess(
  Process process, {
  required Duration gracePeriod,
  required Duration terminateTimeout,
  required Duration killTimeout,
}) async {
  try {
    await process.stdin.close().timeout(gracePeriod);
  } on Object {
    // Continue with bounded signal escalation.
  }
  if (await _waitForExit(process, gracePeriod)) {
    return;
  }
  process.kill(ProcessSignal.sigterm);
  if (await _waitForExit(process, terminateTimeout)) {
    return;
  }
  process.kill(ProcessSignal.sigkill);
  await _waitForExit(process, killTimeout);
}

Future<bool> _waitForExit(Process process, Duration timeout) async {
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
