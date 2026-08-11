import 'dart:async';
import 'dart:io';

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
  });
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
