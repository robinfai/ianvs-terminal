import 'package:app/features/ai/ai_composer_model_menu.dart';
import 'package:app/features/ai/ai_model_catalog.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_ai_test.dart' show MemoryAiStore;

class _Catalog extends AiModelCatalog {
  _Catalog(this.models);
  final List<AiModelOption> models;
  bool fail = false;
  int calls = 0;
  @override
  Future<List<AiModelOption>> choices(AiConfiguration configuration) async {
    calls++;
    if (fail) throw const AiFailure('models_unavailable');
    return models;
  }
}

Future<void> _pump(
  WidgetTester tester,
  AiSettingsController settings,
  _Catalog catalog, {
  bool enabled = true,
  bool Function()? canSelect,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(866, 468);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildIanvsTerminalTheme(
        Brightness.light,
        platform: TargetPlatform.macOS,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomLeft,
          child: SizedBox(
            width: 180,
            child: AiComposerModelMenu(
              settings: settings,
              enabled: enabled,
              catalog: catalog,
              onConfigure: () {},
              canSelect: canSelect ?? () => true,
              onSelect: (id, expected) =>
                  settings.selectModel(id, expected: expected),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final backend in AiBackendKind.values) {
    for (final count in [10, 11]) {
      testWidgets(
        '$backend $count models: threshold, selection and persistence',
        (tester) async {
          final config = backend == AiBackendKind.acp
              ? const AiConfiguration.acp(
                  agentCommand: '/fixture/agent',
                  model: 'model-0',
                )
              : const AiConfiguration(
                  endpoint: 'https://fixture.test/v1',
                  apiKey: 'fixture',
                  model: 'model-0',
                  approvalMode: AiApprovalMode.smart,
                );
          final store = MemoryAiStore(config);
          final settings = AiSettingsController(store);
          await settings.loaded;
          addTearDown(settings.dispose);
          final catalog = _Catalog([
            for (var i = 0; i < count; i++)
              AiModelOption('model-$i', name: 'Model $i'),
          ]);
          await _pump(tester, settings, catalog);
          await tester.tap(find.byKey(const Key('ai-composer-model')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('ai-model-search')),
            count > 10 ? findsOneWidget : findsNothing,
          );
          if (count > 10) {
            await tester.enterText(
              find.byKey(const Key('ai-model-search')),
              'MODEL 10',
            );
            await tester.pump();
            expect(
              find.byKey(const Key('ai-model-choice-model-0')),
              findsNothing,
            );
          }
          final chosen = count > 10 ? 'model-10' : 'model-1';
          await tester.tap(find.byKey(Key('ai-model-choice-$chosen')));
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(settings.configuration!.model, chosen);
          expect(store.value!.backend, backend);
          expect(store.value!.approvalMode, config.approvalMode);
          final restored = AiSettingsController(store);
          await restored.loaded;
          expect(restored.configuration!.model, chosen);
          restored.dispose();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('catalog error retries, Escape preserves selection', (
    tester,
  ) async {
    final settings = AiSettingsController(
      MemoryAiStore(const AiConfiguration.mock()),
    );
    await settings.loaded;
    addTearDown(settings.dispose);
    final catalog = _Catalog([const AiModelOption('next')])..fail = true;
    await _pump(tester, settings, catalog);
    await tester.tap(find.byKey(const Key('ai-composer-model')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-model-search')), findsNothing);
    expect(find.byKey(const Key('ai-model-choice-trail-mock')), findsOneWidget);
    catalog.fail = false;
    await tester.tap(find.byKey(const Key('ai-model-refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-model-choice-next')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(settings.configuration!.model, 'trail-mock');
    expect(catalog.calls, 2);
  });

  testWidgets(
    'stale connection and lost task ownership cannot apply a selection',
    (tester) async {
      final settings = AiSettingsController(
        MemoryAiStore(const AiConfiguration.mock()),
      );
      await settings.loaded;
      addTearDown(settings.dispose);
      var allowed = true;
      await _pump(
        tester,
        settings,
        _Catalog([const AiModelOption('next')]),
        canSelect: () => allowed,
      );
      await tester.tap(find.byKey(const Key('ai-composer-model')));
      await tester.pumpAndSettle();
      allowed = false;
      await tester.tap(find.byKey(const Key('ai-model-choice-next')));
      await tester.pumpAndSettle();
      expect(settings.configuration!.model, 'trail-mock');
      allowed = true;
      await settings.save(
        const AiConfiguration(
          endpoint: 'https://different.test',
          apiKey: 'different',
          model: 'different',
        ),
      );
      await tester.tap(find.byKey(const Key('ai-model-choice-next')));
      await tester.pumpAndSettle();
      expect(settings.configuration!.model, 'different');
    },
  );

  test(
    'official model preference never persists the gateway credential',
    () async {
      final store = MemoryAiStore(null);
      final settings = AiSettingsController(
        store,
        gatewayConfiguration: const AiConfiguration(
          endpoint: 'https://gateway.test',
          apiKey: 'ephemeral',
          model: 'default',
        ),
      );
      await settings.loaded;
      expect(
        await settings.selectModel('next', expected: settings.configuration!),
        isTrue,
      );
      expect(store.value!.officialService, isTrue);
      expect(store.value!.apiKey, isEmpty);
      expect(settings.configuration!.apiKey, 'ephemeral');
      settings.dispose();
    },
  );
}
