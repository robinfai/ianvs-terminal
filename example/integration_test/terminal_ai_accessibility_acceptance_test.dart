import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/shell/window_bridge.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/ai/terminal_ai_recovery_test.dart' show RecoveringTerminal;
import '../test/ai/terminal_ai_tasks_test.dart' show source;
import '../test/ai/terminal_ai_test.dart'
    show FakeApi, MemoryAiStore, commandReply;
import '../test/support/macos_integration_test_lifecycle.dart';

// Optional dwell time is for a separately scoped OS screen-reader review.
// This fixture itself never enables VoiceOver or reads its global state.
const _evidence = String.fromEnvironment('TRAIL_ACCESSIBILITY_EVIDENCE');
const _reviewSeconds = int.fromEnvironment('TRAIL_ACCESSIBILITY_DWELL');
const _captureKey = Key('accessibility-fixture');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'isolated native accessibility states preserve input ownership',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      final title = 'Trail Accessibility Fixture · $pid';
      final settings = AiSettingsController(MemoryAiStore());
      await settings.loaded;
      final terminal = RecoveringTerminal();
      final api = FakeApi();
      final controller = TerminalAiController(
        settings: settings,
        terminal: terminal,
        api: api,
      );
      final semantics = tester.ensureSemantics();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        settings.dispose();
      });
      try {
        await WindowBridge.setTitle(title);
        controller.attachContext(source);
        api.respond = (_) async => commandReply(r'printf "fixture only\n"');
        await controller.ask(
          'Inspect fixture output without executing commands',
        );
        controller.attachContext(source);
        controller.setDraft('Retain this fixture draft');
        await tester.pumpWidget(
          MaterialApp(
            theme: buildIanvsTerminalTheme(
              Brightness.light,
              platform: TargetPlatform.macOS,
            ),
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) =>
                RepaintBoundary(key: _captureKey, child: child),
            home: Scaffold(
              body: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Accessibility fixture · memory only · no terminal or network',
                    ),
                  ),
                  Expanded(
                    child: TerminalAiWorkspace(
                      controller: controller,
                      onClose: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final stages = <Map<String, Object?>>[];
        Future<void> record(String stage) async {
          final status = find.byKey(const Key('ai-task-status'));
          final label = status.evaluate().isEmpty
              ? null
              : tester.getSemantics(status).label;
          final entry = <String, Object?>{
            'stage': stage,
            'pid': pid,
            'window_title': title,
            'fixture': 'memory-only; no PTY, credentials, or network',
            'phase': controller.phase.name,
            'semantic_status': label,
            'terminal_writes': terminal.writes.length,
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'speech_verified': false,
          };
          stages.add(entry);
          if (_evidence.isNotEmpty) {
            await Directory(_evidence).create(recursive: true);
            await File(
              '$_evidence/scope.json',
            ).writeAsString(jsonEncode(entry));
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(_captureKey),
            );
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$_evidence/$stage.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          }
          // A bounded interval leaves the real native window available for a
          // focused review without introducing any production control endpoint.
          final end = DateTime.now().add(
            Duration(seconds: _reviewSeconds.clamp(0, 20)),
          );
          while (DateTime.now().isBefore(end)) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }

        await record('proposal');
        final chip = find.byWidgetPredicate(
          (widget) => widget is InputChip && widget.onDeleted != null,
        );
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(find.text('Attached output snapshot'), findsOneWidget);
        await record('snapshot');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Attached output snapshot'), findsNothing);
        expect(controller.draft, 'Retain this fixture draft');
        expect(controller.attachments, [source]);
        expect(terminal.writes, isEmpty);

        controller.takeOver();
        AiTerminalContext running(String screen) => AiTerminalContext(
          sessionId: 'one',
          contextId: 'root',
          guard: 'fixture-running',
          screen: screen,
          cwd: '/tmp',
          runningCommand: 'fixture stream',
        );
        terminal.context = running('fixture line 1');
        api.respond = (_) async => AiReply(
          text: 'Observing fixture output',
          action: AiAction.fromToolCall({
            'id': 'fixture-observe',
            'function': {
              'name': 'read_screen',
              'arguments': jsonEncode({
                'reason': 'Observe fixture only',
                'wait_ms': 30000,
              }),
            },
          }),
        );
        final turn = controller.ask('Observe only');
        await tester.pump(const Duration(milliseconds: 150));
        expect(controller.phase, AiPhase.observing);
        final status = find.byKey(const Key('ai-task-status'));
        final initial = tester.getSemantics(status);
        final statusId = initial.id;
        expect(initial.label, 'AI is observing the terminal');
        expect(initial.getSemanticsData().flagsCollection.isLiveRegion, true);
        await record('observing');
        terminal.context = running('fixture line 1\nfixture line 2');
        await tester.pump(const Duration(milliseconds: 1300));
        final updated = tester.getSemantics(status);
        expect(updated.id, statusId);
        expect(updated.label, 'AI is observing the terminal');
        expect(controller.lastOutputAt, isNotNull);
        await record('output-updated');
        await tester.tap(find.byKey(const Key('ai-take-over')));
        await tester.pump(const Duration(milliseconds: 150));
        await turn;
        expect(
          tester.getSemantics(status).label,
          'AI paused · command is not interrupted',
        );
        expect(terminal.context.runningCommand, 'fixture stream');
        await record('paused');
        terminal.disconnected = true;
        await controller.refreshContext();
        await tester.pump();
        expect(
          tester.getSemantics(status).label,
          'Terminal unavailable · check its status',
        );
        await record('disconnected');
        expect(terminal.writes, isEmpty);
        if (_evidence.isNotEmpty) {
          await File('$_evidence/result.json').writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'stages': stages,
              'terminal_writes': terminal.writes.length,
              'fake_model_requests': api.requests.length,
              'speech_verified': false,
            }),
          );
        }
      } finally {
        semantics.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
