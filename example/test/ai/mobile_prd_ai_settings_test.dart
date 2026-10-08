import 'dart:async';

import 'package:app/features/ai/acp/acp_installation.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/ai_settings_dialog.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';
import 'terminal_ai_test.dart' show FakeApi, FakeTerminal, MemoryAiStore;

class _RecordingAiStore extends MemoryAiStore {
  _RecordingAiStore() : super(null);
  int saves = 0;

  @override
  Future<void> write(AiConfiguration? configuration) async {
    saves++;
    await super.write(configuration);
  }
}

class _SettingsFixture {
  final store = _RecordingAiStore();
  final terminal = FakeTerminal();
  final api = FakeApi();
  late final settings = AiSettingsController(store);
  late final controller = TerminalAiController(
    settings: settings,
    terminal: terminal,
    api: api,
  );
  int discoveries = 0;

  Future<void> mount(
    WidgetTester tester, {
    required TargetPlatform platform,
    AiConfiguration? saved,
  }) async {
    store.value = saved;
    await settings.loaded;
    controller.setDraft('Keep this unsent task draft');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = platform == TargetPlatform.macOS
        ? const Size(960, 800)
        : const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () {
            unawaited(
              showDialog<bool>(
                context: context,
                builder: (_) => AiSettingsDialog(
                  settings: settings,
                  discoverAcp: () async {
                    discoveries++;
                    return const AcpInstallation(
                      command: '/fixture/node',
                      arguments: ['/fixture/codex-acp.js'],
                      version: 'fixture',
                    );
                  },
                ),
              ),
            );
          },
          child: const Text('Configure AI'),
        ),
      ),
      platform: platform,
    );
    await tester.tap(find.text('Configure AI'));
    await tester.pumpAndSettle();
  }

  void expectNoTaskSent() {
    expect(api.requests, isEmpty);
    expect(terminal.writes, isEmpty);
    expect(controller.transcript, isEmpty);
    expect(controller.draft, 'Keep this unsent task draft');
  }

  void dispose() {
    controller.dispose();
    settings.dispose();
  }
}

void main() {
  group('$AiSettingsDialog mobile PRD backend availability', () {
    const savedAcp = AiConfiguration.acp(
      agentCommand: '/existing/codex-acp',
      agentArguments: ['--existing'],
      model: 'existing-desktop-model',
    );
    late _SettingsFixture fixture;

    setUp(() => fixture = _SettingsFixture());
    tearDown(() => fixture.dispose());

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets('$platform offers only Model API without agent discovery', (
        tester,
      ) async {
        await fixture.mount(tester, platform: platform);

        expect(find.text('Model API'), findsOneWidget);
        expect(find.text('Codex ACP'), findsNothing);
        expect(find.byKey(const Key('ai-agent-command')), findsNothing);
        expect(find.byKey(const Key('ai-detect-acp')), findsNothing);
        expect(find.byKey(const Key('ai-endpoint')), findsOneWidget);
        expect(fixture.discoveries, 0);
        expect(fixture.store.saves, 0);
        fixture.expectNoTaskSent();

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(fixture.store.value, isNull);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        '$platform explains saved ACP and cancellation preserves it',
        (tester) async {
          await fixture.mount(tester, platform: platform, saved: savedAcp);

          expect(
            find.byKey(const Key('ai-acp-unavailable-on-mobile')),
            findsOneWidget,
          );
          expect(
            find.textContaining('saving does not send a task'),
            findsOneWidget,
          );
          expect(find.text('Codex ACP'), findsNothing);
          expect(find.byKey(const Key('ai-agent-command')), findsNothing);
          expect(
            tester
                .widget<TextField>(find.byKey(const Key('ai-model')))
                .controller!
                .text,
            isEmpty,
          );
          expect(fixture.store.value, same(savedAcp));
          expect(fixture.store.saves, 0);
          expect(fixture.discoveries, 0);
          fixture.expectNoTaskSent();

          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(fixture.store.value, same(savedAcp));
          expect(fixture.settings.configuration, same(savedAcp));
          expect(fixture.store.saves, 0);
          fixture.expectNoTaskSent();
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        '$platform saves an explicit API replacement without sending',
        (tester) async {
          await fixture.mount(tester, platform: platform, saved: savedAcp);
          for (final field in {
            'ai-endpoint': 'https://fixture.example.invalid/v1',
            'ai-api-key': 'public-test-key',
            'ai-model': 'fixture-api-model',
          }.entries) {
            final input = find.byKey(Key(field.key));
            await tester.ensureVisible(input);
            await tester.enterText(input, field.value);
          }
          expect(fixture.store.value, same(savedAcp));
          final save = find.byKey(const Key('ai-save-settings'));
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('ai-settings-dialog')), findsNothing);
          expect(fixture.store.saves, 1);
          expect(fixture.store.value!.backend, AiBackendKind.llm);
          expect(fixture.store.value!.model, 'fixture-api-model');
          expect(fixture.store.value!.agentCommand, isEmpty);
          expect(fixture.discoveries, 0);
          fixture.expectNoTaskSent();
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('desktop retains the saved ACP controls and model', (
      tester,
    ) async {
      await fixture.mount(
        tester,
        platform: TargetPlatform.macOS,
        saved: savedAcp,
      );

      expect(find.text('Codex ACP'), findsOneWidget);
      expect(find.byKey(const Key('ai-agent-command')), findsOneWidget);
      expect(find.byKey(const Key('ai-detect-acp')), findsOneWidget);
      expect(find.byKey(const Key('ai-endpoint')), findsNothing);
      expect(
        find.byKey(const Key('ai-acp-unavailable-on-mobile')),
        findsNothing,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('ai-model')))
            .controller!
            .text,
        savedAcp.model,
      );
      expect(fixture.discoveries, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fixture.store.value, same(savedAcp));
      expect(fixture.store.saves, 0);
      fixture.expectNoTaskSent();
      expect(tester.takeException(), isNull);
    });

    testWidgets('desktop can still select, discover and save local ACP', (
      tester,
    ) async {
      await fixture.mount(tester, platform: TargetPlatform.macOS);
      await tester.tap(find.byKey(const Key('ai-backend')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Codex ACP').last);
      await tester.pumpAndSettle();

      expect(fixture.discoveries, 1);
      expect(find.byKey(const Key('ai-agent-command')), findsOneWidget);
      expect(fixture.store.saves, 0);
      final save = find.byKey(const Key('ai-save-settings'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(fixture.store.saves, 1);
      expect(fixture.store.value!.backend, AiBackendKind.acp);
      expect(fixture.store.value!.agentCommand, '/fixture/node');
      expect(fixture.store.value!.agentArguments, ['/fixture/codex-acp.js']);
      fixture.expectNoTaskSent();
      expect(tester.takeException(), isNull);
    });
  });
}
