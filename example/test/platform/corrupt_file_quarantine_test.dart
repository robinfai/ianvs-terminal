import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/platform/corrupt_file_quarantine.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'ianvs_corrupt_file_quarantine_test_',
    );
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('quarantineCorruptFile keeps existing quarantine files', () async {
    final file = File('${directory.path}/state.json');
    final existing = File('${file.path}.corrupt.1000');
    await file.writeAsString('new corrupt payload');
    await existing.writeAsString('previous corrupt payload');

    final quarantined = await quarantineCorruptFile(
      file,
      now: () => DateTime.fromMillisecondsSinceEpoch(1000),
    );

    expect(await file.exists(), isFalse);
    expect(quarantined.path, '${file.path}.corrupt.1000-1');
    expect(await quarantined.readAsString(), 'new corrupt payload');
    expect(await existing.readAsString(), 'previous corrupt payload');
  });

  test(
    'quarantineCorruptFile skips colliding quarantine directories',
    () async {
      final file = File('${directory.path}/state.json');
      final existingDirectory = Directory('${file.path}.corrupt.1000');
      await file.writeAsString('new corrupt payload');
      await existingDirectory.create();

      final quarantined = await quarantineCorruptFile(
        file,
        now: () => DateTime.fromMillisecondsSinceEpoch(1000),
      );

      expect(await file.exists(), isFalse);
      expect(quarantined.path, '${file.path}.corrupt.1000-1');
      expect(await quarantined.readAsString(), 'new corrupt payload');
      expect(await existingDirectory.exists(), isTrue);
    },
  );
}
