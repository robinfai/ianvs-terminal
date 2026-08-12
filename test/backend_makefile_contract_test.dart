import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;
  late File fakeGo;
  late File capture;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ianvs-backend-makefile-contract-',
    );
    capture = File('${temporaryDirectory.path}/arguments.txt');
    fakeGo = File('${temporaryDirectory.path}/fake-go');
    await fakeGo.writeAsString(
      '#!/bin/sh\n'
      r': "${ARG_CAPTURE:?ARG_CAPTURE must be set}"'
      '\n'
      r'''printf '%s\n' "$@" > "$ARG_CAPTURE"'''
      '\n',
    );
    final chmod = await Process.run('chmod', <String>['700', fakeGo.path]);
    expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
  });

  tearDown(() async {
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('backend-run rejects a missing explicit configuration', () async {
    final result = await Process.run(
      'make',
      <String>['backend-run', 'GO=${fakeGo.path}'],
      environment: <String, String>{
        ...Platform.environment,
        'ARG_CAPTURE': capture.path,
      },
    );

    expect(result.exitCode, isNonZero);
    expect(result.stderr, contains('BACKEND_CONFIG is required'));
    expect(capture.existsSync(), isFalse);
  });

  test('backend-run passes only the strict JSON configuration argv', () async {
    final configuration = File('${temporaryDirectory.path}/runtime.json');
    await configuration.writeAsString('{}');

    final result = await Process.run(
      'make',
      <String>[
        'backend-run',
        'GO=${fakeGo.path}',
        'BACKEND_CONFIG=${configuration.path}',
      ],
      environment: <String, String>{
        ...Platform.environment,
        'ARG_CAPTURE': capture.path,
      },
    );

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(await capture.readAsLines(), <String>[
      'run',
      './cmd/ianvs-api',
      'serve',
      '--config',
      configuration.path,
    ]);
  });
}
