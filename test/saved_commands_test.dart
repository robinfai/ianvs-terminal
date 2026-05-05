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

    store.save(
      const SavedCommandsState(
        entries: <SavedCommandEntry>[
          SavedCommandEntry(command: 'echo one'),
          SavedCommandEntry(command: 'pwd'),
        ],
      ),
    );

    expect(store.load().commands, <String>['echo one', 'pwd']);
    expect(savedCommandsFile.readAsStringSync(), contains('"version": 2'));
  });

  test('store migrates legacy commands list into entry schema', () {
    savedCommandsFile.parent.createSync(recursive: true);
    savedCommandsFile.writeAsStringSync(
      '{"commands":[" echo one ","pwd","echo one",""]}',
    );
    final state = SavedCommandsStore(file: savedCommandsFile).load();

    expect(state.version, 2);
    expect(state.commands, <String>['echo one', 'pwd']);
    expect(state.entries, hasLength(2));
    expect(state.entries.first.command, 'echo one');
    expect(state.entries.first.createdAt, isNotEmpty);
  });

  test('store preserves saved command entry metadata', () {
    savedCommandsFile.parent.createSync(recursive: true);
    savedCommandsFile.writeAsStringSync('''
{
  "version": 2,
  "entries": [
    {
      "command": "kubectl get pods",
      "title": "Pods",
      "tags": ["k8s", "prod", "k8s"],
      "cwdHint": "~/work/payments",
      "targetKind": "ssh",
      "createdAt": "2026-05-04T09:00:00Z"
    }
  ]
}
''');
    final state = SavedCommandsStore(file: savedCommandsFile).load();

    expect(state.commands, <String>['kubectl get pods']);
    expect(state.entries.single.title, 'Pods');
    expect(state.entries.single.tags, <String>['k8s', 'prod']);
    expect(state.entries.single.cwdHint, '~/work/payments');
    expect(state.entries.single.targetKind, 'ssh');
    expect(state.entries.single.createdAt, '2026-05-04T09:00:00Z');
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
