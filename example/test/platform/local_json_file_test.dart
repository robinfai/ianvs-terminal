import 'dart:io';

import 'package:app/platform/local_json_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('local JSON decoding', () {
    test('decodes an object and rejects a non-object root', () {
      expect(
        decodeJsonObject('{"enabled":true}', documentName: 'Settings'),
        <String, Object?>{'enabled': true},
      );
      expect(
        () => decodeJsonObject('[]', documentName: 'Settings'),
        throwsA(isA<FormatException>()),
      );
    });

    test('decodes an array and rejects a non-array root', () {
      expect(decodeJsonArray('[1,2]', documentName: 'Items'), <Object?>[1, 2]);
      expect(
        () => decodeJsonArray('{}', documentName: 'Items'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('atomic local file writes', () {
    late Directory directory;
    late File target;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'ianvs-terminal-local-json-',
      );
      target = File('${directory.path}/settings.json');
    });

    tearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test(
      'replaces an existing file without leaving a temporary file',
      () async {
        await target.writeAsString('old');

        await writeStringAtomically(target, 'new');

        expect(await target.readAsString(), 'new');
        expect(await _temporaryFilesFor(target), isEmpty);
      },
    );

    test('preserves the existing file when the commit fails', () async {
      await target.writeAsString('old');

      await expectLater(
        writeStringAtomically(
          target,
          'new',
          replace: (temporaryFile, targetPath) async {
            expect(targetPath, target.path);
            expect(await temporaryFile.readAsString(), 'new');
            throw const FileSystemException('commit failed');
          },
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(await target.readAsString(), 'old');
      expect(await _temporaryFilesFor(target), isEmpty);
    });
  });
}

Future<List<FileSystemEntity>> _temporaryFilesFor(File target) async {
  final prefix = '${target.path}.tmp.';
  return target.parent
      .list()
      .where((entity) => entity.path.startsWith(prefix))
      .toList();
}
