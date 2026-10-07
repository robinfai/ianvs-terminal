import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/app.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_message.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/macos_integration_test_lifecycle.dart';
import '../test/support/memory_local_terminal_config_repository.dart';
import '../test/support/memory_profile_repository.dart';
import '../test/support/no_io_local_session_recording_repository.dart';
import '../test/support/no_io_local_terminal_layout_repository.dart';
import 'terminal_ai_model_gateway.dart';

class _MemoryStore implements AiConfigurationStore {
  _MemoryStore(this.value);
  AiConfiguration? value;
  @override
  Future<AiConfiguration?> read() async => value;
  @override
  Future<void> write(AiConfiguration? configuration) async =>
      value = configuration;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const keyPath = String.fromEnvironment('TRAIL_PROXY_KEY_FILE');
  const evidencePath = String.fromEnvironment('TRAIL_MODEL_SCENE_EVIDENCE');
  const model = String.fromEnvironment(
    'TRAIL_MODEL_SCENE_MODEL',
    defaultValue: 'gpt-6-luna',
  );
  testWidgets(
    'real model clarifies, reviews and distinguishes evidence from success',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      final key = (await File(keyPath).readAsString()).trim();
      final gateway = await ModelScenarioGateway.start(key);
      final settings = AiSettingsController(
        _MemoryStore(
          AiConfiguration(
            endpoint: 'http://127.0.0.1:${gateway.server.port}/v1',
            apiKey: key,
            model: model,
          ),
        ),
      );
      final home = await Directory(
        '/private/tmp',
      ).createTemp('trail-model-scenes-');
      await File(
        '${home.path}/.zshrc',
      ).writeAsString("PROMPT='trail-scenes> '\nRPROMPT=''\n");
      for (final service in ['alpha', 'beta']) {
        await Directory('${home.path}/$service').create();
        await File('${home.path}/$service/status.txt').writeAsString(
          'service=$service\nenabled=false\nhealth=not_checked\n',
        );
      }
      await File('${home.path}/beta/check.sh').writeAsString(
        "printf 'beta: connection refused by db.internal:5432\\n'\nprintf 'beta: startup check failed; cause unverified\\n'\nexit 7\n",
      );
      await File('${home.path}/beta/many.sh').writeAsString(r'''
awk 'BEGIN {
  print "EARLY_FAILURE: job-1 failed"
  for (i=2; i<=599; i++) printf "ROW_%04d %0110d\n",i,0
  print "TAIL_ONLY: status is unverified"
}'
''');
      final initialFiles = {
        for (final name in [
          'alpha/status.txt',
          'beta/status.txt',
          'beta/check.sh',
          'beta/many.sh',
        ])
          name: await File('${home.path}/$name').readAsString(),
      };
      final profile = TerminalProfile(
        id: 'model-scenes',
        name: 'AI scenario review',
        shell: '/bin/zsh',
        cwd: home.path,
        env: {
          'HOME': home.path,
          'ZDOTDIR': home.path,
          'XDG_CONFIG_HOME': home.path,
          'XDG_DATA_HOME': home.path,
          'LANG': 'en_US.UTF-8',
          'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
        },
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(NativePtyBackend.load()),
          aiSettingsProvider.overrideWithValue(settings),
          profileRepositoryProvider.overrideWithValue(
            MemoryProfileRepository(
              TerminalProfilesDocument(profiles: [profile]),
            ),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            MemoryLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                defaultProfileId: 'model-scenes',
                appearance: TerminalAppAppearance(
                  preferredTerminalMode: TerminalViewMode.blocks,
                ),
              ),
            ),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            noIoLocalTerminalLayoutRepository(),
          ),
          localSessionRecordingRepositoryProvider.overrideWithValue(
            noIoLocalSessionRecordingRepository(),
          ),
          shellAnimationsEnabledProvider.overrideWithValue(false),
          shellNotificationSenderProvider.overrideWithValue(
            ({required title, body, identifier, expiresAfterMs}) async {},
          ),
        ],
      );
      final captureKey = GlobalKey();
      final result = <String, Object?>{
        'requested_model': model,
        'fixture':
            'Real model; isolated synthetic service files and actual local PTY',
        'passed': false,
      };
      addTearDown(() async {
        if (evidencePath.isNotEmpty) {
          await Directory(evidencePath).create(recursive: true);
          await File(
            '$evidencePath/model-traffic.json',
          ).writeAsString(jsonEncode(gateway.calls));
          await File(
            '$evidencePath/result.json',
          ).writeAsString(jsonEncode(result));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        for (final tab in container.read(sessionControllerProvider).tabs) {
          for (final pane in tab.effectivePanes) {
            await container
                .read(sessionControllerProvider.notifier)
                .closeSession(pane.sessionId);
          }
        }
        container.dispose();
        settings.dispose();
        await gateway.close();
        await home.delete(recursive: true);
      });
      Future<void> waitFor(bool Function() ready, String label) async {
        final deadline = DateTime.now().add(const Duration(seconds: 100));
        while (!ready()) {
          if (DateTime.now().isAfter(deadline)) fail('Timed out: $label');
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      Future<void> click(Key target) async {
        await waitFor(
          () => find.byKey(target).evaluate().isNotEmpty,
          'control $target',
        );
        await tester.ensureVisible(find.byKey(target));
        await tester.tap(find.byKey(target));
        await tester.pump(const Duration(milliseconds: 150));
      }

      Future<void> capture(String name) async {
        if (evidencePath.isEmpty) return;
        await tester.pump();
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(evidencePath).create(recursive: true);
        await File(
          '$evidencePath/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: captureKey,
            child: const IanvsTerminalApp(),
          ),
        ),
      );
      await waitFor(
        () => container.read(sessionControllerProvider).activeSessionId != null,
        'local session',
      );
      final id = container.read(sessionControllerProvider).activeSessionId!;
      gateway.bindFixture(sessionId: id, cwd: home.path);
      final runtime = container.read(terminalRuntimeControllerProvider);
      Map<String, Object?>? shell() =>
          runtime.composerRequest(id, 'composer.state', const {});
      List<Map<String, Object?>> blocks() =>
          (runtime.commandBlocks(id)!['blocks']! as List)
              .cast<Map<String, Object?>>();
      await waitFor(() => shell()?['state'] == 'ready', 'negotiated shell');
      await click(Key('terminal-ai-open-$id'));
      final task = tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .controller;
      await waitFor(() => task.context != null, 'AI context');
      final initialBlockCount = blocks().length;
      Future<void> ask(String prompt) async {
        final requestsBefore = gateway.calls.length;
        await click(const Key('ai-prompt'));
        await tester.enterText(find.byKey(const Key('ai-prompt')), prompt);
        await tester.pump();
        expect(task.draft, prompt);
        await click(const Key('ai-send'));
        await waitFor(
          () => gateway.calls.length > requestsBefore,
          'new model request',
        );
        await waitFor(() => !task.busy, 'model response');
        expect(task.error, isNull);
      }

      List<String> answers() => [
        for (final e in task.transcript)
          if (e.role == 'assistant') e.text,
      ];

      const goal =
          '这里有 alpha 和 beta 两个服务。我只想定位其中一个服务启动失败的原因，但还没决定检查哪个。只分析，不修改文件；先等我选择目标再做检查。';
      await ask(goal);
      final taskId = task.taskId;
      expect(task.canApprove, false);
      expect(blocks(), hasLength(initialBlockCount));
      result['clarification'] = answers().last;
      await capture('D02-real-model-clarification');
      await ask(
        '我选 beta。先给出基于证据的排查计划，继续只分析、不修改文件，也先不要提出运行命令。现在还没有日志或健康检查结果，不能把计划里的步骤标成已完成。',
      );
      expect(task.taskId, taskId);
      expect(task.canApprove, false);
      expect(blocks(), hasLength(initialBlockCount));
      expect(jsonEncode(gateway.calls.last['request']), contains(goal));
      result['plan'] = answers().last;
      await capture('D02-real-model-plan');

      const readCommand = 'cat beta/status.txt';
      await ask(
        '现在允许这一次只读检查。请提出且仅提出命令 cat beta/status.txt，等我确认执行；读到结果后解释它能否证明 beta 已经恢复正常，不要修改文件或接着提出其他命令。',
      );
      expect(task.pending?.kind, AiActionKind.runCommand);
      expect(task.pending?.command?.trim(), readCommand);
      expect(blocks(), hasLength(initialBlockCount));
      final commandStyle = tester
          .widget<SelectableText>(find.byKey(const Key('ai-action-preview')))
          .style!;
      double textWidth(String text) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: commandStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }

      // Native font resolution matters: the generic family previously fell
      // back to a proportional font despite passing font-loaded widget tests.
      expect(textWidth('WWW'), closeTo(textWidth('iii'), .1));
      await capture('D03-real-model-read-only-proposal');
      await click(const Key('ai-approve'));
      await waitFor(
        () => !task.busy && shell()?['state'] == 'ready',
        'approved read completed',
      );
      expect(task.error, isNull);
      expect(task.canApprove, false);
      final readBlock = blocks().singleWhere(
        (b) => b['command'] == readCommand,
      );
      expect(readBlock['exitCode'], 0);
      expect(task.context!.lastBlock!.output, contains('health=not_checked'));
      expect(answers().last, contains('[block:'));
      result['exit_zero_summary'] = answers().last;
      result['read_block'] = readBlock;
      await capture('D05-real-model-zero-exit-incomplete-health');

      await click(const Key('ai-close'));
      const failedCommand = '/bin/sh beta/check.sh';
      runtime.composerRequest(id, 'composer.submit', {
        'lease': shell()!['lease'],
        'submissionId': 'model-scenes-failure',
        'text': failedCommand,
      });
      await waitFor(
        () => blocks().any(
          (b) => b['command'] == failedCommand && b['exitCode'] == 7,
        ),
        'real failure block',
      );
      final failure = blocks().singleWhere(
        (b) => b['command'] == failedCommand,
      );
      final failedId = failure['id']! as String;
      final failedRoot = find.byKey(ValueKey('command-block-$failedId'));
      await waitFor(() => failedRoot.evaluate().isNotEmpty, 'failure visible');
      final requestsBeforeAttach = gateway.calls.length;
      await tester.ensureVisible(failedRoot);
      await tester.tap(
        find
            .descendant(
              of: failedRoot,
              matching: find.byType(PopupMenuButton<String>),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is PopupMenuItem<String> && w.value == 'ai',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      expect(gateway.calls, hasLength(requestsBeforeAttach));
      expect(task.attachments.single.id, failedId);
      await capture('D01-real-model-pending-context');
      final answersBeforeDiagnosis = answers().length;
      await ask(
        '仅依据附加的原始失败输出解释能确定什么、不能确定什么。继续只分析，不修改文件。可以提出下一条有依据的只读诊断，但不得假设数据库已经修复，也不要盲目重试原命令。',
      );
      expect(task.taskId, taskId);
      expect(blocks(), hasLength(initialBlockCount + 2));
      expect(blocks().singleWhere((b) => b['id'] == failedId)['exitCode'], 7);
      final diagnosis = answers().skip(answersBeforeDiagnosis).toList();
      expect(diagnosis, isNotEmpty);
      result['failure_diagnosis'] = diagnosis;
      result['failure_proposal'] = task.pending?.preview;
      result['failure_block'] = failure;
      await capture('D06-real-model-failure-evidence');
      if (task.canApprove) await click(const Key('ai-reject'));
      for (final file in initialFiles.entries) {
        expect(
          await File('${home.path}/${file.key}').readAsString(),
          file.value,
        );
      }
      expect(blocks(), hasLength(initialBlockCount + 2));
      expect(task.taskId, taskId);

      // Use fresh tasks so earlier service-analysis constraints cannot supply
      // the missing evidence. These commands run through the actual PTY.
      for (final command in ['true', '/bin/sh beta/many.sh']) {
        await click(const Key('ai-close'));
        final before = blocks().length;
        runtime.composerRequest(id, 'composer.submit', {
          'lease': shell()!['lease'],
          'submissionId': 'model-evidence-$before',
          'text': command,
        });
        await waitFor(
          () =>
              blocks().length == before + 1 &&
              blocks().last['exitCode'] == 0 &&
              shell()?['state'] == 'ready',
          'evidence fixture command',
        );
        await click(Key('terminal-ai-open-$id'));
        await click(const Key('ai-new-task'));
        final empty = command == 'true';
        final callsBefore = gateway.calls.length;
        await ask(
          empty
              ? '最后一条命令执行了什么？它的结果能证明什么？只根据当前证据解释，不要运行命令或追加读取。'
              : '总结最后一条命令的结果。这些信息足以证明所有任务都成功了吗？只根据当前已提供的证据解释，不要运行命令或追加读取。',
        );
        expect(task.canApprove, false);
        expect(blocks(), hasLength(before + 1));
        expect(gateway.calls.length, callsBefore + 1);
        final context = task.context!.lastBlock!;
        final json = context.toJson();
        final summary = answers().last;
        result[empty ? 'empty_output' : 'truncated_output'] = {
          'context': json,
          'summary': summary,
          'task_id': task.taskId,
          'command_count_unchanged_after_summary': true,
        };
        if (empty) {
          expect(context.output, isEmpty);
          expect(context.totalLines, 0);
          expect(
            tester
                .widgetList<TerminalAiMessage>(find.byType(TerminalAiMessage))
                .map((w) => w.text)
                .join('\n'),
            isNot(contains('[block:')),
          );
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith(
                    'ai-evidence-${context.id}-',
                  ),
            ),
            findsNothing,
          );
          await capture('D05-real-model-empty-output');
        } else {
          expect(context.totalLines, 600);
          expect(context.outputStartLine, 440);
          expect(json['output_start_line']! as int, greaterThan(440));
          expect(json['output_end_line'], 600);
          expect(json['output_truncated'], true);
          expect(json['output']! as String, isNot(contains('EARLY_FAILURE')));
          expect(
            jsonEncode(gateway.calls.last['request']),
            isNot(contains('EARLY_FAILURE')),
          );
          final citations = RegExp(
            r'\[block:([^:\]\s]+):(\d+)-(\d+)\]',
          ).allMatches(summary).toList();
          expect(citations, isNotEmpty);
          for (final citation in citations) {
            expect(citation[1], context.id);
            expect(
              int.parse(citation[2]!),
              greaterThan(json['output_start_line']! as int),
            );
            expect(int.parse(citation[3]!), lessThanOrEqualTo(600));
          }
          await capture('D05-real-model-truncated-output');
          final start = int.parse(citations.first[2]!) - 1;
          await click(ValueKey('ai-evidence-${context.id}-$start'));
          await waitFor(
            () => find
                .byKey(const Key('block-reader-scroll'))
                .evaluate()
                .isNotEmpty,
            'truncated evidence opens original reader',
          );
          await tester.pumpAndSettle();
          final readerViewport = tester.widget<TerminalViewport>(
            find
                .descendant(
                  of: find.byKey(const Key('block-reader')),
                  matching: find.byType(TerminalViewport),
                )
                .first,
          );
          final readerScroll = tester
              .widget<ListView>(find.byKey(const Key('block-reader-scroll')))
              .controller!;
          final visibleRow =
              (readerScroll.offset - 8) /
              readerViewport.controller.measuredCellSize!.height;
          expect(visibleRow, closeTo(start, .5));
          result['citation_reader_requested_row'] = start;
          result['citation_reader_visible_row'] = visibleRow;
          final pages = tester
              .widgetList<CommandBlockTerminal>(
                find.descendant(
                  of: find.byKey(const Key('block-reader')),
                  matching: find.byType(CommandBlockTerminal),
                ),
              )
              .map((widget) => widget.block)
              .toList();
          expect(pages, isNotEmpty);
          expect(
            pages.expand((page) => page.lines).any((row) => row.index == start),
            true,
          );
          for (final page in pages) {
            // Reader pages have presentation IDs. Verify their actual rows
            // against the retained native block instead of confusing page ID
            // with command ID or accidentally selecting a background block.
            expect(page.id, startsWith('${context.id}-reader-'));
            final original = CommandBlock.fromJson(
              runtime.commandBlocks(id, {
                'id': context.id,
                'offset': page.lines.first.index,
                'limit': page.lines.length,
              })!['block'],
            )!;
            expect(
              page.lines.map((r) => (r.index, r.sourceRow, r.text)),
              original.lines.map((r) => (r.index, r.sourceRow, r.text)),
            );
          }
          expect(blocks(), hasLength(before + 1));
          await capture('D05-truncated-evidence-original-reader');
          await click(const Key('block-reader-close'));
          result['truncated_citation_opened_original_block'] = true;
        }
      }
      for (final file in initialFiles.entries) {
        expect(
          await File('${home.path}/${file.key}').readAsString(),
          file.value,
        );
      }
      final reported = [
        for (final call in gateway.calls) (call['response'] as Map?)?['model'],
      ];
      expect(reported, everyElement(model));
      result.addAll({
        'passed': true,
        'reported_models': reported,
        'request_count': gateway.calls.length,
        'task_id': taskId,
        'native_command_count': blocks().length - initialBlockCount,
        'clarification_and_plan_did_not_execute': true,
        'files_unchanged': true,
        'diagnosis_did_not_retry_or_execute': true,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      });
    },
    skip: keyPath.isEmpty,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
