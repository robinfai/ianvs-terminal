import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_retained_timeline.dart';
import 'package:app/features/ai/terminal_ai_runtime.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:integration_test/integration_test.dart';

import '../test/ai/terminal_ai_test.dart'
    show FakeApi, FakeTerminal, MemoryAiStore;
import '../test/support/macos_integration_test_lifecycle.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const evidence = String.fromEnvironment('TRAIL_EVIDENCE_EVICTION');
  testWidgets(
    'native eviction keeps an AI citation on its original source rows',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      final home = await Directory.systemTemp.createTemp(
        'trail-evidence-eviction-',
      );
      await File(
        '${home.path}/.zshrc',
      ).writeAsString("PROMPT='evidence> '\nRPROMPT=''\n");
      final runtime = TerminalRuntimeController(
        backend: NativePtyBackend.load(),
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
      );
      final id = runtime.createSession(
        TerminalSessionConfig(
          launch: TerminalLaunchConfig(
            program: '/bin/zsh',
            cwd: home.path,
            env: {
              'HOME': home.path,
              'ZDOTDIR': home.path,
              'LANG': 'en_US.UTF-8',
              'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
            },
          ),
          scrollbackLines: 600,
        ),
      );
      final blocks = CommandBlockController(
        request: (args) => runtime.commandBlocks(id, args),
      );
      final settings = AiSettingsController(MemoryAiStore());
      TerminalAiController? ai;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        ai?.dispose();
        settings.dispose();
        blocks.dispose();
        runtime.dispose();
        await home.delete(recursive: true);
      });
      Future<void> waitFor(bool Function() ready, String label) async {
        final end = DateTime.now().add(const Duration(seconds: 20));
        while (!ready()) {
          if (DateTime.now().isAfter(end)) {
            if (evidence.isNotEmpty) {
              await Directory(evidence).create(recursive: true);
              await File('$evidence/failure.json').writeAsString(
                jsonEncode({
                  'stage': label,
                  'state': runtime.composerRequest(
                    id,
                    'composer.state',
                    const {},
                  ),
                  'blocks': runtime.commandBlocks(id),
                  'screen': runtime.liveScreen(id),
                }),
              );
            }
            fail('Timed out: $label');
          }
          runtime.refreshSession(id);
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      Map<String, Object?>? state() =>
          runtime.composerRequest(id, 'composer.state', const {});
      var submission = 0;
      Future<CommandBlock> run(String command) async {
        await waitFor(() => state()?['state'] == 'ready', 'shell ready');
        final receipt = 'evidence-${submission++}';
        runtime.composerRequest(id, 'composer.submit', {
          'lease': state()!['lease'],
          'submissionId': receipt,
          'text': command,
        });
        await waitFor(() {
          // The standalone fixture has no Composer widget polling its private
          // preparation/commit handshake. Inspect it just as production does.
          final receiptState = state();
          if (receiptState?['submissionId'] == receipt) {
            expect(
              receiptState?['outcome'],
              isNot(anyOf('unknown', 'rejected')),
            );
          }
          blocks.refresh();
          return blocks.blocks.any(
            (b) => b.submissionId == receipt && b.exitCode == 0,
          );
        }, command);
        return blocks.blocks.singleWhere((b) => b.submissionId == receipt);
      }

      final first = await run('/usr/bin/seq 1 600');
      CommandBlock? readOriginal(int offset, int limit) =>
          CommandBlock.fromJson(
            runtime.commandBlocks(id, {
              'id': first.id,
              'offset': offset,
              'limit': limit,
            })?['block'],
          );
      final snapshot = readOriginal(410, 3)!;
      expect(snapshot.lines.map((r) => r.text), ['411', '412', '413']);
      final frozen = TerminalAiRuntime.contextFromSnapshot(
        snapshot,
        sessionId: id,
      );
      final port = FakeTerminal()
        ..context = AiTerminalContext(
          sessionId: id,
          contextId: 'root',
          guard: 'fixture-read-only',
          screen: '',
          cwd: home.path,
          lastBlock: frozen,
        );
      final api = FakeApi()
        ..respond = (_) async => AiReply(
          text:
              'These are the supplied native rows. [block:${first.id}:411-413]',
        );
      ai = TerminalAiController(settings: settings, terminal: port, api: api);
      await ai.ask('Explain these retained rows');
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildIanvsTerminalTheme(
              Brightness.light,
              platform: TargetPlatform.macOS,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TerminalAiWorkspace(
                  controller: ai!,
                  onClose: () {},
                  onShowEvidence: (reference) => unawaited(
                    showAiEvidenceReader(
                      context,
                      controller: blocks,
                      reference: reference,
                      sourceSessionId: id,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await run('/usr/bin/seq 1 200');
      final retained = readOriginal(0, 1)!;
      expect(retained.evicted, true);
      expect(retained.sourceLineBase, greaterThan(frozen.sourceLineBase!));
      final expectedRow =
          frozen.sourceLineBase! + 410 - retained.sourceLineBase!;
      expect(expectedRow, greaterThan(0));
      await tester.tap(find.byKey(ValueKey('ai-evidence-${first.id}-410')));
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<ListView>(find.byKey(const Key('block-reader-scroll')))
          .controller!;
      final cell = tester
          .widget<TerminalViewport>(find.byType(TerminalViewport).first)
          .controller
          .measuredCellSize!;
      final actualRow = (scroll.offset - 8) / cell.height;
      expect(actualRow, closeTo(expectedRow, .5));
      final visible = tester
          .widgetList<CommandBlockTerminal>(find.byType(CommandBlockTerminal))
          .expand((w) => w.block.lines);
      expect(
        visible.any((r) => r.index == expectedRow && r.text == '411'),
        true,
      );
      Future<void> capture(String name) async {
        if (evidence.isEmpty) return;
        await Directory(evidence).create(recursive: true);
        await tester.pump();
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$evidence/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      }

      await capture('D05-retained-native-source');
      await tester.tap(find.byKey(const Key('block-reader-close')));
      await tester.pumpAndSettle();
      await run('/usr/bin/seq 1 800');
      await tester.tap(find.byKey(ValueKey('ai-evidence-${first.id}-410')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('block-reader-evidence-unavailable')),
        findsOneWidget,
      );
      expect(find.byType(CommandBlockTerminal), findsNothing);
      expect(find.text('Output unavailable'), findsOneWidget);
      expect(port.writes, isEmpty);
      expect(api.requests, hasLength(1));
      expect(submission, 3);
      await capture('D05-released-native-source');
      if (evidence.isNotEmpty) {
        await File('$evidence/result.json').writeAsString(
          jsonEncode({
            'fixture':
                'actual native zsh PTY eviction; deterministic model reply, read-only AI port',
            'passed': true,
            'block_id': first.id,
            'native_initial_base': frozen.sourceLineBase,
            'native_retained_base': retained.sourceLineBase,
            'quoted_lines': [411, 413],
            'expected_current_row': expectedRow,
            'actual_current_row': actualRow,
            'original_text_at_target': '411',
            'unavailable_after_eviction': true,
            'setup_native_submissions': submission,
            'ai_writes': port.writes.length,
            'model_requests': api.requests.length,
          }),
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
