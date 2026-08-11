import 'dart:async';
import 'dart:io';

import 'package:app/data/services/data_api_runtime.dart';
import 'package:app/data/services/local_data_api_sidecar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(LocalDataApiSidecar, () {
    late Directory temporaryDirectory;

    setUp(() {
      temporaryDirectory = Directory.systemTemp.createTempSync(
        'ianvs-data-api-sidecar-test-',
      );
    });

    tearDown(() {
      if (temporaryDirectory.existsSync()) {
        temporaryDirectory.deleteSync(recursive: true);
      }
    });

    test(
      'reports only a bounded and redacted stderr tail when startup exits',
      () async {
        const accessToken = 'local-access-token-that-must-not-leak';
        final noise = List<String>.generate(
          40,
          (index) => "printf '%s\\n' 'noise-$index-${'x' * 180}' >&2",
        ).join('\n');
        final binary = await _writeExecutable(
          temporaryDirectory,
          // The shebang must be the first byte of the executable test fixture.
          // ignore: leading_newlines_in_multiline_strings
          '''#!/bin/sh
$noise
printf '%s\\n' 'Authorization: Bearer $accessToken' >&2
printf '%s\\n' 'password=hunter2' >&2
printf '%s\\n' 'mysql://user:database-secret@localhost/ianvs' >&2
printf '%s\\n' 'final diagnostic line' >&2
exit 23
''',
        );

        Object? failure;
        try {
          await LocalDataApiSidecar.start(
            binary: binary,
            database: File('${temporaryDirectory.path}/data.db'),
            localAccessToken: accessToken,
          );
        } on Object catch (error) {
          failure = error;
        }

        expect(failure, isA<LocalDataApiSidecarStartException>());
        final exception = failure! as LocalDataApiSidecarStartException;
        expect(exception.cause.toString(), contains('code 23'));
        expect(exception.sanitizedStderrTail.length, lessThanOrEqualTo(4096));
        expect(
          exception.sanitizedStderrTail,
          contains('final diagnostic line'),
        );
        expect(exception.sanitizedStderrTail, contains('<redacted>'));
        expect(exception.sanitizedStderrTail, isNot(contains(accessToken)));
        expect(exception.sanitizedStderrTail, isNot(contains('hunter2')));
        expect(
          exception.sanitizedStderrTail,
          isNot(contains('database-secret')),
        );
      },
      skip: Platform.isWindows
          ? 'The bundled sidecar is a POSIX executable on supported hosts.'
          : false,
    );

    test(
      'uses bounded signal escalation when startup times out',
      () async {
        const accessToken = 'timeout-token-that-must-not-leak';
        final binary = await _writeExecutable(
          temporaryDirectory,
          // The shebang must be the first byte of the executable test fixture.
          // ignore: leading_newlines_in_multiline_strings
          '''#!/bin/sh
trap '' TERM
printf '%s\\n' 'access_token=$accessToken' >&2
while :; do :; done
''',
        );
        final stopwatch = Stopwatch()..start();

        Object? failure;
        try {
          await LocalDataApiSidecar.start(
            binary: binary,
            database: File('${temporaryDirectory.path}/data.db'),
            localAccessToken: accessToken,
            // Leave enough time for the child to emit stderr even when the
            // test runner is compiling and executing other suites in parallel.
            startupTimeout: const Duration(milliseconds: 500),
            shutdownGracePeriod: const Duration(milliseconds: 50),
            shutdownTerminateTimeout: const Duration(milliseconds: 50),
            shutdownKillTimeout: const Duration(milliseconds: 200),
          );
        } on Object catch (error) {
          failure = error;
        } finally {
          stopwatch.stop();
        }

        expect(failure, isA<LocalDataApiSidecarStartException>());
        final exception = failure! as LocalDataApiSidecarStartException;
        expect(exception.cause, isA<TimeoutException>());
        expect(exception.sanitizedStderrTail, contains('<redacted>'));
        expect(exception.sanitizedStderrTail, isNot(contains(accessToken)));
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      },
      skip: Platform.isWindows
          ? 'The bundled sidecar is a POSIX executable on supported hosts.'
          : false,
    );

    group(LocalDataApiSidecarProcessTerminator, () {
      test('startup failure exposes a neutral termination carrier', () {
        const terminationFailure =
            LocalDataApiSidecarTerminationUnknownException(
              killAccepted: true,
              exitObserved: false,
            );
        const failure = LocalDataApiSidecarStartException(
          cause: 'startup failed',
          sanitizedStderrTail: '',
          terminationFailure: terminationFailure,
        );

        expect(failure, isA<DataApiRuntimeTerminationFailureCarrier>());
        expect(failure.terminationFailure, same(terminationFailure));
        expect(failure.cause, 'startup failed');
      });

      test('reports unknown termination when final kill is rejected', () async {
        final process = _FakeSidecarProcess(
          killResults: <ProcessSignal, bool>{
            ProcessSignal.sigterm: true,
            ProcessSignal.sigkill: false,
          },
        );
        final waits = _FakeExitWait(<bool>[false, false, true]);
        final terminator = LocalDataApiSidecarProcessTerminator(
          waitForExit: waits.call,
        );

        await expectLater(
          terminator.terminate(process),
          throwsA(
            isA<LocalDataApiSidecarTerminationUnknownException>()
                .having(
                  (failure) => failure,
                  'runtime termination marker',
                  isA<DataApiRuntimeTerminationUnknownFailure>(),
                )
                .having(
                  (failure) => failure.killAccepted,
                  'killAccepted',
                  isFalse,
                )
                .having(
                  (failure) => failure.exitObserved,
                  'exitObserved',
                  isTrue,
                ),
          ),
        );

        expect(process.killSignals, <ProcessSignal>[
          ProcessSignal.sigterm,
          ProcessSignal.sigkill,
        ]);
        expect(waits.callCount, 3);
      });

      test(
        'reports unknown termination when final exit is not observed',
        () async {
          final process = _FakeSidecarProcess(
            killResults: <ProcessSignal, bool>{
              ProcessSignal.sigterm: true,
              ProcessSignal.sigkill: true,
            },
          );
          final waits = _FakeExitWait(<bool>[false, false, false]);
          final terminator = LocalDataApiSidecarProcessTerminator(
            waitForExit: waits.call,
          );

          await expectLater(
            terminator.terminate(process),
            throwsA(
              isA<LocalDataApiSidecarTerminationUnknownException>()
                  .having(
                    (failure) => failure.killAccepted,
                    'killAccepted',
                    isTrue,
                  )
                  .having(
                    (failure) => failure.exitObserved,
                    'exitObserved',
                    isFalse,
                  ),
            ),
          );

          expect(process.killSignals, <ProcessSignal>[
            ProcessSignal.sigterm,
            ProcessSignal.sigkill,
          ]);
          expect(waits.callCount, 3);
        },
      );

      test('completes only after final exit is observed', () async {
        final process = _FakeSidecarProcess(
          killResults: <ProcessSignal, bool>{
            ProcessSignal.sigterm: true,
            ProcessSignal.sigkill: true,
          },
        );
        final waits = _FakeExitWait(<bool>[false, false, true]);
        final terminator = LocalDataApiSidecarProcessTerminator(
          waitForExit: waits.call,
        );

        await terminator.terminate(process);

        expect(process.closeStdinCalls, 1);
        expect(process.killSignals, <ProcessSignal>[
          ProcessSignal.sigterm,
          ProcessSignal.sigkill,
        ]);
        expect(waits.callCount, 3);
      });

      test('wraps an exception thrown by the final kill request', () async {
        final killError = StateError('kill transport failed');
        final process = _FakeSidecarProcess(
          killResults: <ProcessSignal, bool>{ProcessSignal.sigterm: true},
          killErrors: <ProcessSignal, Object>{ProcessSignal.sigkill: killError},
        );
        final waits = _FakeExitWait(<bool>[false, false]);
        final terminator = LocalDataApiSidecarProcessTerminator(
          waitForExit: waits.call,
        );

        await expectLater(
          terminator.terminate(process),
          throwsA(
            isA<LocalDataApiSidecarTerminationOperationException>()
                .having(
                  (failure) => failure.operation,
                  'operation',
                  LocalDataApiSidecarTerminationOperation.sendKillSignal,
                )
                .having((failure) => failure.cause, 'cause', same(killError))
                .having(
                  (failure) => failure,
                  'runtime termination marker',
                  isA<DataApiRuntimeTerminationUnknownFailure>(),
                ),
          ),
        );
      });

      test('wraps an exception from the process exit-code future', () async {
        final exitError = StateError('exit code unavailable');
        final exitCode = Completer<int>();
        final process = _FakeSidecarProcess(
          killResults: const <ProcessSignal, bool>{},
          exitCode: exitCode.future,
        );
        final terminator = LocalDataApiSidecarProcessTerminator();

        final expectation = expectLater(
          terminator.terminate(process),
          throwsA(
            isA<LocalDataApiSidecarTerminationOperationException>()
                .having(
                  (failure) => failure.operation,
                  'operation',
                  LocalDataApiSidecarTerminationOperation.waitAfterStdinClose,
                )
                .having((failure) => failure.cause, 'cause', same(exitError)),
          ),
        );
        await process.exitCodeRequested;
        exitCode.completeError(exitError);
        await expectation;

        expect(process.killSignals, isEmpty);
      });

      test('wraps an exception from the injected exit wait', () async {
        final waitError = StateError('wait seam failed');
        final process = _FakeSidecarProcess(
          killResults: const <ProcessSignal, bool>{},
        );
        final terminator = LocalDataApiSidecarProcessTerminator(
          waitForExit: (_, _) => Future<bool>.error(waitError),
        );

        await expectLater(
          terminator.terminate(process),
          throwsA(
            isA<LocalDataApiSidecarTerminationOperationException>()
                .having(
                  (failure) => failure.operation,
                  'operation',
                  LocalDataApiSidecarTerminationOperation.waitAfterStdinClose,
                )
                .having((failure) => failure.cause, 'cause', same(waitError)),
          ),
        );
      });

      test(
        'close aggregates cancellation without hiding unknown termination',
        () async {
          final cancellationError = StateError('cancel failed');
          final process = _FakeSidecarProcess(
            killResults: <ProcessSignal, bool>{
              ProcessSignal.sigterm: true,
              ProcessSignal.sigkill: true,
            },
          );
          final waits = _FakeExitWait(<bool>[false, false, false]);
          final cleanup = LocalDataApiSidecarResourceCleanup(
            process: process,
            processTerminator: LocalDataApiSidecarProcessTerminator(
              waitForExit: waits.call,
            ),
            cancelSubscriptions: () => Future<void>.error(cancellationError),
          );

          await expectLater(
            cleanup.close(),
            throwsA(
              isA<LocalDataApiSidecarCleanupException>()
                  .having(
                    (failure) => failure.terminationFailure,
                    'terminationFailure',
                    isA<LocalDataApiSidecarTerminationUnknownException>(),
                  )
                  .having(
                    (failure) => failure.subscriptionCancellationError,
                    'subscriptionCancellationError',
                    same(cancellationError),
                  ),
            ),
          );
        },
      );

      test(
        'startup failure is built before cancellation errors are aggregated',
        () async {
          final cancellationError = StateError('cancel failed');
          final process = _FakeSidecarProcess(
            killResults: <ProcessSignal, bool>{
              ProcessSignal.sigterm: true,
              ProcessSignal.sigkill: true,
            },
          );
          final waits = _FakeExitWait(<bool>[false, false, false]);
          final cleanup = LocalDataApiSidecarResourceCleanup(
            process: process,
            processTerminator: LocalDataApiSidecarProcessTerminator(
              waitForExit: waits.call,
            ),
            cancelSubscriptions: () => Future<void>.error(cancellationError),
          );
          final terminationFailure = await cleanup.terminateForStartup();
          final startupFailure = LocalDataApiSidecarStartException(
            cause: StateError('startup failed'),
            sanitizedStderrTail: 'diagnostic',
            terminationFailure: terminationFailure,
          );

          await expectLater(
            cleanup.completeStartupFailure(startupFailure, StackTrace.current),
            throwsA(
              isA<LocalDataApiSidecarCleanupException>()
                  .having(
                    (failure) => failure.primaryError,
                    'primaryError',
                    same(startupFailure),
                  )
                  .having(
                    (failure) => failure.terminationFailure,
                    'terminationFailure',
                    same(terminationFailure),
                  )
                  .having(
                    (failure) => failure.subscriptionCancellationError,
                    'subscriptionCancellationError',
                    same(cancellationError),
                  ),
            ),
          );
        },
      );
    });
  });
}

final class _FakeSidecarProcess implements LocalDataApiSidecarProcess {
  _FakeSidecarProcess({
    required this.killResults,
    this.killErrors = const <ProcessSignal, Object>{},
    Future<int>? exitCode,
  }) : _exitCode = exitCode ?? Completer<int>().future;

  final Map<ProcessSignal, bool> killResults;
  final Map<ProcessSignal, Object> killErrors;
  final List<ProcessSignal> killSignals = <ProcessSignal>[];
  final Future<int> _exitCode;
  final Completer<void> _exitCodeRequested = Completer<void>();
  int closeStdinCalls = 0;

  Future<void> get exitCodeRequested => _exitCodeRequested.future;

  @override
  Future<void> closeStdin() async {
    closeStdinCalls += 1;
  }

  @override
  Future<int> get exitCode {
    if (!_exitCodeRequested.isCompleted) {
      _exitCodeRequested.complete();
    }
    return _exitCode;
  }

  @override
  bool kill(ProcessSignal signal) {
    killSignals.add(signal);
    final error = killErrors[signal];
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return killResults[signal] ?? false;
  }
}

final class _FakeExitWait {
  _FakeExitWait(List<bool> outcomes) : _outcomes = List<bool>.of(outcomes);

  final List<bool> _outcomes;
  int callCount = 0;

  Future<bool> call(
    LocalDataApiSidecarProcess process,
    Duration timeout,
  ) async {
    callCount += 1;
    if (_outcomes.isEmpty) {
      throw StateError('No fake exit outcome remains.');
    }
    return _outcomes.removeAt(0);
  }
}

Future<File> _writeExecutable(Directory directory, String contents) async {
  final binary = File('${directory.path}/fake-sidecar');
  await binary.writeAsString(contents);
  final chmod = await Process.run('chmod', <String>['+x', binary.path]);
  if (chmod.exitCode != 0) {
    throw StateError('chmod failed: ${chmod.stderr}');
  }
  return binary;
}
