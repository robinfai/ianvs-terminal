import 'dart:convert';
import 'dart:io';

import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/ai/terminal_ai_test.dart'
    show FakeApi, FakeTerminal, MemoryAiStore;
import '../test/helpers/pump_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    testWidgets(
      'iOS retained draft collapses to 56 points ${brightness.name}',
      (tester) async {
        final settings = AiSettingsController(MemoryAiStore());
        await settings.loaded;
        final terminal = FakeTerminal();
        final api = FakeApi();
        final controller = TerminalAiController(
          settings: settings,
          terminal: terminal,
          api: api,
        );
        await controller.refreshContext();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          settings.dispose();
        });
        await tester.pumpApp(
          TerminalAiWorkspace(
            compactMobile: true,
            controller: controller,
            onClose: () {},
          ),
          platform: TargetPlatform.iOS,
          brightness: brightness,
          locale: const Locale('zh'),
        );
        await tester.pumpAndSettle();
        final prompt = find.byKey(const Key('ai-prompt'));
        await tester.tap(prompt);
        await tester.pump(const Duration(milliseconds: 150));
        await tester.enterText(prompt, '中文\n第二行\n第三行\n第四行\n第五行\n第六行 🧭');
        final input = tester.widget<TextField>(prompt).controller!;
        input.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
        final value = input.value;
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(prompt).maxLines, 5);
        await tester.tap(find.byKey(const Key('ai-dismiss-keyboard')));
        await tester.pumpAndSettle();
        final composer = find.byKey(const Key('ai-mobile-composer'));
        final height = tester.getSize(composer).height;
        expect(height, lessThanOrEqualTo(56));
        expect(tester.widget<TextField>(prompt).maxLines, 1);
        expect(tester.widget<TextField>(prompt).focusNode!.hasFocus, isFalse);
        expect(tester.widget<TextField>(prompt).controller, same(input));
        expect(input.value, value);
        expect(find.byKey(const Key('ai-expand-draft')), findsOneWidget);
        expect(api.requests, isEmpty);
        expect(terminal.writes, isEmpty);
        final view = View.of(tester.element(composer));
        debugPrint(
          'compact-mobile-measurement: ${jsonEncode({'theme': brightness.name, 'height_logical': height, 'physical_width': view.physicalSize.width, 'physical_height': view.physicalSize.height, 'dpr': view.devicePixelRatio, 'os': Platform.operatingSystemVersion, 'draft_and_selection_retained': input.value == value, 'requests': api.requests.length, 'writes': terminal.writes.length, 'test_input': 'synthetic; native iOS render/layout'})}',
        );
        await tester.tap(prompt);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(prompt).maxLines, 5);
        expect(input.text, value.text);
        expect(tester.takeException(), isNull);
      },
      skip: !Platform.isIOS,
    );
  }
}
