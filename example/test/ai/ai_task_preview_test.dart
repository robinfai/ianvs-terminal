import 'dart:convert';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/ai_task_preview.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_ai_test.dart' show FakeApi, FakeTerminal, MemoryAiStore;

void main() {
  test(
    'same-title summaries stay distinct without mutating persisted messages',
    () async {
      final settings = AiSettingsController(MemoryAiStore());
      await settings.loaded;
      final api = FakeApi();
      final controller = TerminalAiController(
        settings: settings,
        terminal: FakeTerminal(),
        api: api,
      );
      addTearDown(controller.dispose);
      addTearDown(settings.dispose);
      api.respond = (_) async => const AiReply(
        text: '**First result** [Example](https://example.com)',
      );
      await controller.ask('Same task title');
      controller.newTask();
      api.respond = (_) async => const AiReply(
        text: '| Fruit | Color |\n| --- | --- |\n| Lemon | Yellow |',
      );
      await controller.ask('Same task title');
      final before = jsonEncode(controller.exportHistory({}));
      final summaries = controller.tasks;
      expect(
        summaries.map((task) => task.title),
        everyElement('Same task title'),
      );
      expect(summaries.map((task) => task.preview), [
        'First result Example',
        'Fruit · Color Lemon · Yellow',
      ]);
      expect(jsonEncode(controller.exportHistory({})), before);
      expect(controller.transcript.last.text, contains('| Lemon | Yellow |'));
    },
  );

  test('table preview preserves cell boundaries without source delimiters', () {
    expect(
      aiTaskPreview('| Fruit | Color |\n| --- | --- |\n| Lemon | Yellow |'),
      'Fruit · Color Lemon · Yellow',
    );
  });
  test('links keep labels and inline formatting becomes readable text', () {
    expect(
      aiTaskPreview('# **Report**\n[Example](https://example.com) and `code`'),
      'Report Example and code',
    );
  });
  test('long preview keeps opening text with grapheme-safe ellipsis', () {
    final source =
        'Distinctive opening ${List.filled(180, '👨‍👩‍👧‍👦').join()}';
    final preview = aiTaskPreview(source);
    expect(preview, startsWith('Distinctive opening '));
    expect(preview, endsWith('…'));
    expect(preview.characters.length, 161);
    expect(preview, isNot(contains('[earlier content omitted]')));
  });
  test('existing internal marker is removed only from display projection', () {
    const source = '[earlier content omitted]\n**Retained answer**';
    expect(aiTaskPreview(source), 'Retained answer');
    expect(source, startsWith('[earlier content omitted]'));
  });
}
