import 'dart:async';
import 'dart:convert';

import 'package:app/features/ai/acp/acp_installation.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/ai_settings_dialog.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_ai_test.dart' show MemoryAiStore;

const found = AcpInstallation(
  command: '/stable/node',
  arguments: ['/local path/codex-acp/dist/index.js'],
  version: '2.1.1',
);

void main() {
  Future<MemoryAiStore> mount(
    WidgetTester tester,
    Future<AcpInstallation> Function() discover, {
    AiConfiguration? saved,
    Brightness brightness = Brightness.light,
  }) async {
    final store = MemoryAiStore(saved);
    final settings = AiSettingsController(store);
    await settings.loaded;
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildIanvsTerminalTheme(brightness),
        home: Scaffold(
          body: AiSettingsDialog(settings: settings, discoverAcp: discover),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  Future<void> select(WidgetTester tester, String label) async {
    final selector = find.byKey(const Key('ai-backend'));
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

  testWidgets(
    'approval preference is explicit, saved, and survives backend changes',
    (tester) async {
      final store = await mount(
        tester,
        () async => found,
        saved: const AiConfiguration.mock(),
      );
      final field = find.byKey(const Key('ai-approval-mode'));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Smart review').last);
      await tester.pumpAndSettle();
      await select(tester, 'Codex ACP');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-save-settings')));
      await tester.pumpAndSettle();
      expect(store.value!.approvalMode, AiApprovalMode.smart);
      expect(store.value!.backend, AiBackendKind.acp);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'first ACP selection fills launch settings without saving or connecting',
    (tester) async {
      var calls = 0;
      final store = await mount(tester, () async {
        calls++;
        return found;
      });
      await select(tester, 'Codex ACP');
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(text(tester, 'ai-agent-command'), found.command);
      expect(jsonDecode(text(tester, 'ai-agent-arguments')), found.arguments);
      expect(text(tester, 'ai-model'), 'gpt-5.6-sol');
      expect(find.byKey(const Key('ai-acp-discovery-notice')), findsOneWidget);
      expect(find.byKey(const Key('ai-connection-ok')), findsNothing);
      expect(store.value, isNull);
      await tester.tap(find.byKey(const Key('ai-save-settings')));
      await tester.pumpAndSettle();
      expect(store.value!.agentCommand, found.command);
      expect(store.value!.agentArguments, found.arguments);
    },
  );

  testWidgets('saved custom settings stay unchanged until explicit detection', (
    tester,
  ) async {
    var calls = 0;
    await mount(
      tester,
      () async {
        calls++;
        return found;
      },
      saved: const AiConfiguration.acp(
        agentCommand: '/custom/agent',
        agentArguments: ['--custom'],
        model: 'chosen-model',
      ),
    );
    expect(calls, 0);
    expect(text(tester, 'ai-agent-command'), '/custom/agent');
    await tester.tap(find.byKey(const Key('ai-detect-acp')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(text(tester, 'ai-agent-command'), found.command);
    expect(text(tester, 'ai-model'), 'chosen-model');
  });

  testWidgets('manual edit during detection is not overwritten', (
    tester,
  ) async {
    final pending = Completer<AcpInstallation>();
    await mount(tester, () => pending.future);
    await select(tester, 'Codex ACP');
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ai-save-settings')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('ai-agent-command')),
      '/my/node',
    );
    pending.complete(found);
    await tester.pumpAndSettle();
    expect(text(tester, 'ai-agent-command'), '/my/node');
    expect(text(tester, 'ai-agent-arguments'), '[]');
    expect(find.textContaining('Your edits were kept'), findsOneWidget);
  });

  testWidgets('switching connection type discards a pending result', (
    tester,
  ) async {
    final pending = Completer<AcpInstallation>();
    await mount(tester, () => pending.future);
    await select(tester, 'Codex ACP');
    // Open the dropdown without waiting for the intentionally pending progress.
    await tester.tap(find.byKey(const Key('ai-backend')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Model API').last);
    await tester.pump();
    pending.complete(found);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-endpoint')), findsOneWidget);
    expect(find.byKey(const Key('ai-acp-discovery-notice')), findsNothing);
    await select(tester, 'Codex ACP');
    await tester.pumpAndSettle();
    expect(text(tester, 'ai-agent-command'), isEmpty);
  });

  testWidgets('failure retains saved fields and detection can be retried', (
    tester,
  ) async {
    var succeed = false;
    await mount(tester, () async {
      if (!succeed) throw const AiFailure('acp_adapter_missing');
      return found;
    }, saved: const AiConfiguration.acp(agentCommand: '/custom/agent'));
    await tester.tap(find.byKey(const Key('ai-detect-acp')));
    await tester.pumpAndSettle();
    expect(text(tester, 'ai-agent-command'), '/custom/agent');
    expect(find.textContaining('Codex ACP was not found'), findsOneWidget);
    succeed = true;
    await tester.tap(find.byKey(const Key('ai-detect-acp')));
    await tester.pumpAndSettle();
    expect(text(tester, 'ai-agent-command'), found.command);
    expect(find.textContaining('Codex ACP was not found'), findsNothing);
  });

  testWidgets('closing while detection is pending is safe', (tester) async {
    final pending = Completer<AcpInstallation>();
    await mount(tester, () => pending.future);
    await select(tester, 'Codex ACP');
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(found);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeout returns to manual configuration', (tester) async {
    final pending = Completer<AcpInstallation>();
    await mount(tester, () => pending.future);
    await select(tester, 'Codex ACP');
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.textContaining('Detection could not finish'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('ai-detect-acp')))
          .onPressed,
      isNotNull,
    );
    pending.complete(found);
    await tester.pumpAndSettle();
    expect(text(tester, 'ai-agent-command'), isEmpty);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'compact $brightness discovery error scrolls without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(390, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mount(
          tester,
          () async => throw const AiFailure('acp_adapter_missing'),
          brightness: brightness,
        );
        await select(tester, 'Codex ACP');
        await tester.pumpAndSettle();
        final field = find.byKey(const Key('ai-agent-arguments'));
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        expect(field.hitTestable(), findsOneWidget);
        expect(
          find.byKey(const Key('ai-save-settings')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
