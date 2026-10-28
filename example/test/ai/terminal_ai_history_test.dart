import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_connections.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_history_binding.dart';
import 'package:app/features/ai/terminal_ai_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_ai_test.dart'
    show FakeApi, FakeTerminal, MemoryAiStore, commandReply;

void main() {
  test(
    'two restored sessions merge view changes without stale flush overwrite',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'trail-shared-history-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = LocalTerminalAiHistoryRepository(
        directory: () async => directory,
      );
      await repository.save('saved-task', {
        'schema': 1,
        'id': 'saved-task',
        'title': 'Task',
        'draft': '',
        'transcript': [
          {
            'id': 'message',
            'role': 'assistant',
            'text': 'Saved',
            'state': 'message',
          },
        ],
        'sources': {
          'saved-source': [
            {
              'id': 'block',
              'command': 'pwd',
              'totalLines': 0,
              'lines': <Object?>[],
            },
          ],
        },
      });
      final settings = AiSettingsController(MemoryAiStore());
      await settings.loaded;
      TerminalAiController makeController() => TerminalAiController(
        settings: settings,
        terminal: TerminalAiConnections(
          sessionId: 'live',
          terminal: FakeTerminal(),
          requestBlocks: (_, _) => {'blocks': <Object?>[]},
        ),
        api: FakeApi(),
      );
      final a = makeController();
      final b = makeController();
      final writerA = TerminalAiHistoryBinding(a, repository);
      final writerB = TerminalAiHistoryBinding(b, repository);
      await Future.wait([writerA.loaded, writerB.loaded]);
      a.readingAnchor = (id: 'message', offset: 31);
      await writerA.flush(requireSaved: true);
      final file = File('${directory.path}/ai-history/saved-task.json');
      final afterA = await file.readAsString();
      await writerB.flush(requireSaved: true);
      expect(
        await file.readAsString(),
        afterA,
        reason: 'Untouched restored view must not write',
      );
      (b.terminal as TerminalAiConnections).evidence.collapsed.add(
        'saved-source/block',
      );
      await writerB.flush(requireSaved: true);
      writerA.dispose();
      a.dispose();
      await writerA.flush(requireSaved: true);
      final result = jsonDecode(await file.readAsString()) as Map;
      expect((result['readingAnchor'] as Map)['offset'], 31);
      expect(
        (result['nativeView'] as Map)['collapsed'],
        contains('saved-source/block'),
      );
      writerB.dispose();
      await writerB.flush(requireSaved: true);
      b.dispose();
      settings.dispose();
    },
  );

  test(
    'startup selects recently saved valid documents before applying its limit',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'trail-recent-history-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = LocalTerminalAiHistoryRepository(
        directory: () async => directory,
      );
      for (var i = 0; i < 66; i++) {
        await repository.save('saved-$i', {'schema': 1, 'id': 'saved-$i'});
        await File(
          '${directory.path}/ai-history/saved-$i.json',
        ).setLastModified(DateTime(2020, 1, 1).add(Duration(seconds: i)));
      }
      await repository.save('saved-0', {
        'schema': 1,
        'id': 'saved-0',
        'draft': 'updated',
      });
      await File(
        '${directory.path}/ai-history/corrupt.json',
      ).writeAsString('{');
      await File(
        '${directory.path}/ai-history/unknown.json',
      ).writeAsString('{"schema":99}');
      final restored = await LocalTerminalAiHistoryRepository(
        directory: () async => directory,
      ).load();
      expect(restored, hasLength(64));
      expect(restored.first['id'], 'saved-0');
      expect(restored.first['draft'], 'updated');
    },
  );

  test(
    'closed session save remains awaitable and failed save can retry',
    () async {
      final settings = AiSettingsController(MemoryAiStore());
      await settings.loaded;
      final controller = TerminalAiController(
        settings: settings,
        terminal: FakeTerminal(),
        api: FakeApi(),
      );
      final repository = _ControlledHistoryRepository();
      final binding = TerminalAiHistoryBinding(controller, repository);
      await binding.loaded;
      await controller.ask('Preserve this task');
      repository.fail = true;
      await expectLater(binding.flush(requireSaved: true), throwsStateError);
      expect(controller.historyError, 'history_save_failed');
      repository.fail = false;
      repository.gate = Completer<void>();
      binding.dispose();
      controller.dispose();
      var settled = false;
      final closedSave = binding.flush(requireSaved: true).then((_) {
        settled = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      repository.gate!.complete();
      await closedSave;
      expect(repository.documents, hasLength(1));
      expect(settled, isTrue);
      settings.dispose();
    },
  );

  test('successful flush does not hide a history load failure', () async {
    final settings = AiSettingsController(MemoryAiStore());
    await settings.loaded;
    final controller = TerminalAiController(
      settings: settings,
      terminal: FakeTerminal(),
      api: FakeApi(),
    );
    final repository = _ControlledHistoryRepository()..loadFails = true;
    final binding = TerminalAiHistoryBinding(controller, repository);
    await binding.loaded;
    await binding.flush();
    expect(controller.historyError, 'history_load_failed');
    binding.dispose();
    await binding.flush();
    controller.dispose();
    settings.dispose();
  });

  test(
    'restart restores content and draft but never revives approval or PTY identity',
    () async {
      final settings = AiSettingsController(MemoryAiStore());
      await settings.loaded;
      final original = TerminalAiController(
        settings: settings,
        terminal: FakeTerminal(),
        api: FakeApi()..respond = (_) async => commandReply('pwd'),
      );
      await original.ask('Inspect');
      expect(original.canApprove, isTrue);
      original.setDraft('Keep this draft');
      original.readingOffset = 42;
      original.readingAnchor = (id: original.transcript.first.id, offset: 3);
      final serialized =
          jsonDecode(jsonEncode(original.exportHistory({}))) as List;
      original.dispose();
      final port = FakeTerminal();
      final restored = TerminalAiController(
        settings: settings,
        terminal: port,
        api: FakeApi(),
      );
      restored.restoreHistory(
        serialized.map((d) => Map<String, Object?>.from(d as Map)),
      );
      expect(restored.restoredHistory, isTrue);
      expect(restored.followUpEnded, isTrue);
      expect(restored.canApprove, isFalse);
      expect(restored.pending, isNull);
      expect(restored.transcript.last.state, AiEntryState.revoked);
      expect(restored.transcript.last.target!.sessionId, startsWith('saved-'));
      expect(restored.draft, 'Keep this draft');
      expect(restored.readingOffset, 42);
      expect(restored.readingAnchor!.offset, 3);
      await restored.approve();
      expect(port.writes, isEmpty);
      restored.newTask();
      expect(restored.restoredHistory, isFalse);
      expect(restored.transcript, isEmpty);
      restored.dispose();
      settings.dispose();
    },
  );

  test(
    'fresh host restores native snapshot and reading anchor without touching replacement PTY',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'trail-restart-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final settings = AiSettingsController(MemoryAiStore());
      await settings.loaded;
      TerminalAiConnections connection(FakeTerminal port, String text) =>
          TerminalAiConnections(
            sessionId: 'one',
            terminal: port,
            requestBlocks: (_, query) {
              final block = {
                'id': 'block',
                'command': 'pwd',
                'exitCode': 0,
                'totalLines': 1,
                'lines': [
                  {'index': 0, 'source_row': 5, 'text': text},
                ],
              };
              return query['id'] == null
                  ? {
                      'blocks': [block],
                    }
                  : {'block': block};
            },
          );
      final original = TerminalAiController(
        settings: settings,
        terminal: connection(FakeTerminal(), 'old output'),
        api: FakeApi(),
      );
      final writer = TerminalAiHistoryBinding(
        original,
        LocalTerminalAiHistoryRepository(directory: () async => directory),
      );
      await writer.loaded;
      await original.ask('Inspect');
      original.readingAnchor = (id: 'native-one-block', offset: 7);
      await writer.flush(requireSaved: true);
      writer.dispose();
      original.dispose();
      final live = FakeTerminal();
      final port = connection(live, 'new output');
      final restored = TerminalAiController(
        settings: settings,
        terminal: port,
        api: FakeApi(),
      );
      final reader = TerminalAiHistoryBinding(
        restored,
        LocalTerminalAiHistoryRepository(directory: () async => directory),
      );
      await reader.loaded;
      expect(restored.restoredHistory, isTrue);
      final source = restored.restoredSourceIds.single;
      expect(source, startsWith('saved-'));
      expect(restored.readingAnchor!.id, 'native-$source/block');
      expect(await port.evidence.outputText('$source/block'), 'old output');
      expect(live.writes, isEmpty);
      expect(restored.canApprove, isFalse);
      await restored.refreshContext();
      expect(restored.canApprove, isFalse);
      reader.dispose();
      restored.dispose();
      settings.dispose();
    },
  );

  test(
    'atomic file history is readable by a fresh repository and ignores bad documents',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'trail-history-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final writer = LocalTerminalAiHistoryRepository(
        directory: () async => directory,
      );
      await writer.save('saved-test', {
        'schema': 1,
        'id': 'saved-test',
        'text': 'literal\r\n```',
      });
      await File('${directory.path}/ai-history/broken.json').writeAsString('{');
      final reader = LocalTerminalAiHistoryRepository(
        directory: () async => directory,
      );
      final documents = await reader.load();
      expect(documents, hasLength(1));
      expect(documents.single['text'], 'literal\r\n```');
      expect(
        await File('${directory.path}/ai-history/broken.json').readAsString(),
        '{',
      );
      await expectLater(writer.save('../escape', {}), throwsArgumentError);
      expect(
        await directory
            .list(recursive: true)
            .where((file) => file.path.contains('.tmp.'))
            .isEmpty,
        isTrue,
      );
    },
  );
}

class _ControlledHistoryRepository implements TerminalAiHistoryRepository {
  bool fail = false;
  bool loadFails = false;
  Completer<void>? gate;
  final documents = <String, Map<String, Object?>>{};
  @override
  Future<List<Map<String, Object?>>> load() async {
    if (loadFails) throw StateError('unavailable');
    return [];
  }

  @override
  Future<void> save(
    String id,
    Map<String, Object?> document, {
    Map<String, Object?>? previous,
  }) async {
    if (fail) throw StateError('disk full');
    await gate?.future;
    documents[id] = document;
  }
}
