import 'dart:async';
import 'package:app/features/ai/ai_model_catalog.dart';
import 'package:app/features/ai/ai_model_picker.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/ai_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/pump_app.dart';
import 'terminal_ai_test.dart' show MemoryAiStore;

class _Catalog extends AiModelCatalog {
  final requests = <Completer<List<String>>>[];
  @override
  Future<List<String>> fetch(AiConfiguration configuration) {
    final request = Completer<List<String>>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  testWidgets(
    'new iPhone connection defaults to official service; custom remains available',
    (tester) async {
      final settings = AiSettingsController(MemoryAiStore(null));
      addTearDown(settings.dispose);
      await settings.loaded;
      await tester.pumpApp(
        AiSettingsDialog(settings: settings),
        platform: TargetPlatform.iOS,
      );
      await tester.pumpAndSettle();
      expect(find.text('Official AI service'), findsOneWidget);
      expect(find.byKey(const Key('ai-endpoint')), findsNothing);
      await tester.tap(find.byKey(const Key('ai-custom-connection')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-endpoint')), findsOneWidget);
      expect(find.byKey(const Key('ai-load-models')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-remove-settings')));
      await tester.pumpAndSettle();
      expect(find.text('Official AI service'), findsOneWidget);
      expect(find.byKey(const Key('ai-endpoint')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'custom catalog loads on request and selection returns exact model ID',
    (tester) async {
      final catalog = _Catalog();
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiModelPicker(
              configuration: const AiConfiguration(
                endpoint: 'https://api.example/v1',
                apiKey: 'key',
                model: '',
              ),
              selected: '',
              catalog: catalog,
              onSelected: (id) => selected = id,
            ),
          ),
        ),
      );
      expect(catalog.requests, isEmpty);
      await tester.tap(find.byKey(const Key('ai-load-models')));
      await tester.pump();
      catalog.requests.single.complete(['deepseek-flash', 'another-model']);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('another-model').last);
      await tester.pumpAndSettle();
      expect(selected, 'another-model');
    },
  );
  testWidgets('changing credentials discards stale model list responses', (
    tester,
  ) async {
    final catalog = _Catalog();
    Widget build(String key) => MaterialApp(
      home: Scaffold(
        body: AiModelPicker(
          configuration: AiConfiguration(
            endpoint: 'https://api.example/v1',
            apiKey: key,
            model: '',
          ),
          selected: '',
          catalog: catalog,
          autoLoad: true,
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(build('old'));
    await tester.pumpWidget(build('new'));
    catalog.requests[1].complete(['current-model']);
    await tester.pumpAndSettle();
    catalog.requests[0].complete(['stale-model']);
    await tester.pumpAndSettle();
    expect(find.text('stale-model'), findsNothing);
    await tester.tap(find.text('Choose model'));
    await tester.pumpAndSettle();
    expect(find.text('current-model'), findsWidgets);
    expect(find.text('stale-model'), findsNothing);
  });
}
