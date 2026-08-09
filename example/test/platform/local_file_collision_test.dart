import 'dart:io';

import 'package:app/platform/local_file_collision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'ianvs_local_file_collision_test_',
    );
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('nextAvailableFile inserts suffix before file extension', () async {
    final existing = File('${directory.path}/export.txt');
    await existing.writeAsString('previous');

    final next = await nextAvailableFile(existing);

    expect(next.path, '${directory.path}/export-1.txt');
  });

  test('nextAvailableDirectory skips colliding file system entries', () async {
    final existingDirectory = Directory('${directory.path}/bundle');
    final existingFile = File('${directory.path}/bundle-1');
    await existingDirectory.create();
    await existingFile.writeAsString('not a directory');

    final next = await nextAvailableDirectory(existingDirectory);

    expect(next.path, '${directory.path}/bundle-2');
  });
}
