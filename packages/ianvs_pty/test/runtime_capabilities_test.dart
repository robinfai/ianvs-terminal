import 'dart:convert';

import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:test/test.dart';

void main() {
  test('decodes Runtime Capabilities v1 and retains unknown features', () {
    final capabilities = PtyRuntimeCapabilities.fromJson(<String, Object?>{
      'schema_version': 1,
      'runtime_contract': 'ianvs-runtime-contract-v1',
      'frame_schema_versions': <Object?>['terminal-frame-diff-v1'],
      'recording_schema_versions': <Object?>[1],
      'features': <Object?>['frame.json.v1', 'future.feature.v1'],
      'future_metadata': <String, Object?>{'ignored': true},
    });

    expect(capabilities.schemaVersion, 1);
    expect(capabilities.runtimeContract, 'ianvs-runtime-contract-v1');
    expect(capabilities.frameSchemaVersions, <String>[
      'terminal-frame-diff-v1',
    ]);
    expect(capabilities.recordingSchemaVersions, <int>[1]);
    expect(capabilities.supports('frame.json.v1'), isTrue);
    expect(capabilities.supports('future.feature.v1'), isTrue);
    expect(capabilities.supports('missing.feature.v1'), isFalse);
  });

  test('exposes the stable SFTP directory-listing capability identifier', () {
    final capabilities = PtyRuntimeCapabilities.fromJson(<String, Object?>{
      'schema_version': 1,
      'runtime_contract': 'ianvs-runtime-contract-v1',
      'frame_schema_versions': <Object?>['terminal-frame-diff-v1'],
      'recording_schema_versions': <Object?>[1],
      'features': <Object?>[
        ptyRuntimeFeatureSftpDirectoryListingV1,
        ptyRuntimeFeatureSftpFileOperationsV1,
      ],
    });

    expect(
      capabilities.supports(ptyRuntimeFeatureSftpDirectoryListingV1),
      isTrue,
    );
    expect(
      capabilities.supports(ptyRuntimeFeatureSftpFileOperationsV1),
      isTrue,
    );
  });

  test('reports unsupported schema versions with a typed error', () {
    expect(
      () => PtyRuntimeCapabilities.fromJson(<String, Object?>{
        'schema_version': 2,
        'runtime_contract': 'ianvs-runtime-contract-v2',
        'frame_schema_versions': <Object?>['terminal-frame-diff-v1'],
        'recording_schema_versions': <Object?>[1],
        'features': <Object?>[],
      }),
      throwsA(
        isA<UnsupportedPtyRuntimeCapabilitiesSchemaVersion>().having(
          (error) => error.schemaVersion,
          'schemaVersion',
          2,
        ),
      ),
    );
  });

  test('rejects malformed, duplicate and oversized capability fields', () {
    Map<String, Object?> valid() => <String, Object?>{
      'schema_version': 1,
      'runtime_contract': 'ianvs-runtime-contract-v1',
      'frame_schema_versions': <Object?>['terminal-frame-diff-v1'],
      'recording_schema_versions': <Object?>[1],
      'features': <Object?>['frame.json.v1'],
    };

    expect(
      () => PtyRuntimeCapabilities.fromJson(<String, Object?>{
        ...valid(),
        'schema_version': 1.0,
      }),
      throwsFormatException,
    );
    expect(
      () => PtyRuntimeCapabilities.fromJson(<String, Object?>{
        ...valid(),
        'runtime_contract': 'different-contract-v1',
      }),
      throwsFormatException,
    );
    expect(
      () => PtyRuntimeCapabilities.fromJson(<String, Object?>{
        ...valid(),
        'features': <Object?>['frame.json.v1', 'frame.json.v1'],
      }),
      throwsFormatException,
    );
    expect(
      () => PtyRuntimeCapabilities.fromJson(<String, Object?>{
        ...valid(),
        'features': List<Object?>.generate(65, (index) => 'feature.$index'),
      }),
      throwsFormatException,
    );
    expect(
      () => PtyRuntimeCapabilities.fromJsonString(
        jsonEncode(<String, Object?>{
          ...valid(),
          'padding': 'x' * PtyRuntimeCapabilities.maxEncodedBytes,
        }),
      ),
      throwsFormatException,
    );
  });

  test('decoded collections are immutable', () {
    final capabilities = PtyRuntimeCapabilities.fromJson(<String, Object?>{
      'schema_version': 1,
      'runtime_contract': 'ianvs-runtime-contract-v1',
      'frame_schema_versions': <Object?>['terminal-frame-diff-v1'],
      'recording_schema_versions': <Object?>[1],
      'features': <Object?>['frame.json.v1'],
    });

    expect(
      () => capabilities.features.add('mutated.feature.v1'),
      throwsUnsupportedError,
    );
  });
}
