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

  test('repository verify reaches clean actual native ABI comparison', () {
    final repository = Directory.current.absolute;
    final makefile = File('${repository.path}/Makefile').readAsStringSync();
    final repositoryVerifier = File(
      '${repository.path}/tools/verify_flutter_terminal.sh',
    ).readAsStringSync();
    final generatedVerifier = File(
      '${repository.path}/tools/verify_generated_contracts.sh',
    ).readAsStringSync();
    final binaryVerifier = File(
      '${repository.path}/tools/verify_native_binary_contract.sh',
    ).readAsStringSync();

    expect(
      _nativeAbiVerificationViolations(
        makefile: makefile,
        repositoryVerifier: repositoryVerifier,
        generatedVerifier: generatedVerifier,
        binaryVerifier: binaryVerifier,
      ),
      isEmpty,
    );

    for (final mutation
        in <
          ({
            String makefile,
            String repositoryVerifier,
            String generatedVerifier,
            String binaryVerifier,
          })
        >[
          (
            makefile: makefile.replaceFirst(
              'tools/verify_flutter_terminal.sh',
              'tools/verify_flutter_terminal_compat.sh',
            ),
            repositoryVerifier: repositoryVerifier,
            generatedVerifier: generatedVerifier,
            binaryVerifier: binaryVerifier,
          ),
          (
            makefile: makefile,
            repositoryVerifier: repositoryVerifier.replaceFirst(
              'tools/verify_generated_contracts.sh',
              'tools/verify_generated_contracts_compat.sh',
            ),
            generatedVerifier: generatedVerifier,
            binaryVerifier: binaryVerifier,
          ),
          (
            makefile: makefile,
            repositoryVerifier: repositoryVerifier,
            generatedVerifier: generatedVerifier.replaceFirst(
              'tools/verify_native_binary_contract.sh',
              'tools/verify_native_binary_contract_compat.sh',
            ),
            binaryVerifier: binaryVerifier,
          ),
          (
            makefile: makefile,
            repositoryVerifier: repositoryVerifier,
            generatedVerifier: generatedVerifier,
            binaryVerifier: binaryVerifier.replaceFirst(
              r'--library "$library"',
              r'--header "$library"',
            ),
          ),
        ]) {
      expect(
        _nativeAbiVerificationViolations(
          makefile: mutation.makefile,
          repositoryVerifier: mutation.repositoryVerifier,
          generatedVerifier: mutation.generatedVerifier,
          binaryVerifier: mutation.binaryVerifier,
        ),
        isNotEmpty,
      );
    }
  });
}

List<String> _nativeAbiVerificationViolations({
  required String makefile,
  required String repositoryVerifier,
  required String generatedVerifier,
  required String binaryVerifier,
}) {
  final violations = <String>[];
  for (final contract in <({String source, String required})>[
    (source: makefile, required: 'tools/verify_flutter_terminal.sh'),
    (
      source: repositoryVerifier,
      required: 'tools/verify_generated_contracts.sh',
    ),
    (
      source: generatedVerifier,
      required: 'tools/verify_native_binary_contract.sh',
    ),
    (source: binaryVerifier, required: 'native/core'),
    (
      source: binaryVerifier,
      required: 'packages/ianvs_terminal_core/native/core',
    ),
    (source: binaryVerifier, required: r'CARGO_TARGET_DIR="$target_dir"'),
    (source: binaryVerifier, required: r'--library "$library"'),
  ]) {
    if (!contract.source.contains(contract.required)) {
      violations.add('missing native ABI gate: ${contract.required}');
    }
  }
  return violations;
}
