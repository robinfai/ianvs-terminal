import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/saved_commands.dart';

void main() {
  late Directory tempDir;
  late File savedCommandsFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'ianvs_terminal_saved_commands_',
    );
    savedCommandsFile = File('${tempDir.path}/saved_commands.json');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('store returns empty commands when file is missing', () {
    final store = SavedCommandsStore(file: savedCommandsFile);

    expect(store.load().commands, isEmpty);
  });

  test('store saves and reloads commands with versioned json', () {
    final store = SavedCommandsStore(file: savedCommandsFile);

    store.save(const SavedCommandsState(commands: <String>['echo one', 'pwd']));

    expect(store.load().commands, <String>['echo one', 'pwd']);
    expect(savedCommandsFile.readAsStringSync(), contains('"version": 1'));
  });

  test('store falls back to empty commands for malformed json', () {
    savedCommandsFile.parent.createSync(recursive: true);
    savedCommandsFile.writeAsStringSync('{ bad json');
    final store = SavedCommandsStore(file: savedCommandsFile);

    expect(store.load().commands, isEmpty);
  });

  test('controller trims ignores empty and dedupes commands by recency', () {
    final controller = SavedCommandsController(
      store: SavedCommandsStore(file: savedCommandsFile),
    );
    addTearDown(controller.dispose);

    expect(controller.addCommand('  echo one  '), isTrue);
    expect(controller.addCommand(''), isFalse);
    expect(controller.addCommand('pwd'), isTrue);
    expect(controller.addCommand('echo one'), isTrue);

    expect(controller.commands, <String>['echo one', 'pwd']);
    expect(
      SavedCommandsStore(file: savedCommandsFile).load().commands,
      <String>['echo one', 'pwd'],
    );
  });

  test('controller removes exact command without affecting others', () {
    final controller = SavedCommandsController(
      store: SavedCommandsStore(file: savedCommandsFile),
    );
    addTearDown(controller.dispose);

    controller
      ..addCommand('echo one')
      ..addCommand('echo two');

    expect(controller.removeCommand('echo one'), isTrue);
    expect(controller.commands, <String>['echo two']);
    expect(controller.removeCommand('missing'), isFalse);
    expect(controller.commands, <String>['echo two']);
  });
}
