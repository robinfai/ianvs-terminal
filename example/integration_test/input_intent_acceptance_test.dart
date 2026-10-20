import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/app.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
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

class _FixtureStore implements AiConfigurationStore {
  _FixtureStore(this.value);
  AiConfiguration? value;
  @override
  Future<AiConfiguration?> read() async => value;
  @override
  Future<void> write(AiConfiguration? configuration) async =>
      value = configuration;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const evidencePath = String.fromEnvironment('TRAIL_INTENT_EVIDENCE');
  const nativeEvidenceClick = bool.fromEnvironment(
    'TRAIL_EVIDENCE_NATIVE_CLICK',
  );
  if (nativeEvidenceClick) {
    // Establish the OS accessibility handle before WidgetTester records its
    // baseline. A CUA accessibility query during the test must not look like a
    // leaked app-owned SemanticsHandle at teardown.
    binding.platformDispatcher.semanticsEnabledTestValue = true;
    tearDownAll(binding.platformDispatcher.clearSemanticsEnabledTestValue);
  }
  for (final smartApproval in [false, true]) {
    testWidgets(
      smartApproval
          ? 'Smart review approves once and escalates sensitive commands'
          : 'Automatic intent routes both input surfaces through the existing PTY',
      (tester) async {
        ensureMacosIntegrationTestFramesEnabled(tester.binding);
        final fixture = await _ResponseFixture.start();
        addTearDown(fixture.close);
        final configuration = AiConfiguration(
          endpoint: 'http://127.0.0.1:${fixture.server.port}/v1',
          apiKey: 'isolated-test-fixture',
          model: 'fixture',
          approvalMode: smartApproval
              ? AiApprovalMode.smart
              : AiApprovalMode.manual,
        );
        final settings = AiSettingsController(_FixtureStore(configuration));
        final home = await Directory.systemTemp.createTemp('trail-fusion-ui-');
        await File(
          '${home.path}/.zshrc',
        ).writeAsString("PROMPT='trail-proxy> '\nRPROMPT=''\n");
        final profile = TerminalProfile(
          id: 'proxy-ui',
          name: 'Block AI acceptance',
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
            ptySessionBackendProvider.overrideWithValue(
              NativePtyBackend.load(),
            ),
            aiSettingsProvider.overrideWithValue(settings),
            profileRepositoryProvider.overrideWithValue(
              MemoryProfileRepository(
                TerminalProfilesDocument(profiles: [profile]),
              ),
            ),
            localTerminalConfigRepositoryProvider.overrideWithValue(
              MemoryLocalTerminalConfigRepository(
                const LocalTerminalConfigDocument(
                  defaultProfileId: 'proxy-ui',
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
        addTearDown(() async {
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
          await home.delete(recursive: true);
        });
        Future<void> waitFor(
          bool Function() ready,
          String label, {
          Duration timeout = const Duration(seconds: 25),
        }) async {
          final deadline = DateTime.now().add(timeout);
          while (!ready()) {
            if (DateTime.now().isAfter(deadline)) fail('Timed out: $label');
            await tester.pump(const Duration(milliseconds: 50));
          }
        }

        Future<void> click(Key key) async {
          await waitFor(
            () => find.byKey(key).evaluate().isNotEmpty,
            'UI control $key',
          );
          await tester.ensureVisible(find.byKey(key));
          await tester.tap(find.byKey(key));
          await tester.pump(const Duration(milliseconds: 150));
        }

        Future<void> capture(String name) async {
          if (evidencePath.isEmpty) return;
          await tester.pump();
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(evidencePath).create(recursive: true);
          await File(
            '$evidencePath/$name.png',
          ).writeAsBytes(data!.buffer.asUint8List());
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
          () =>
              container.read(sessionControllerProvider).activeSessionId != null,
          'local session',
        );
        final id = container.read(sessionControllerProvider).activeSessionId!;
        final runtime = container.read(terminalRuntimeControllerProvider);
        Map<String, Object?>? shell() =>
            runtime.composerRequest(id, 'composer.state', const {});
        await waitFor(() => shell()?['state'] == 'ready', 'negotiated shell');
        await tester.pump(const Duration(seconds: 1));
        final initialPane = container
            .read(sessionControllerProvider)
            .tabs
            .first
            .activePane;
        expect(
          container.read(sessionControllerProvider).preferredTerminalMode,
          TerminalViewMode.blocks,
        );
        expect(initialPane.terminalMode.mode, TerminalViewMode.blocks);
        expect(initialPane.profileId, 'proxy-ui');
        await capture('D01-initial-mode');
        await waitFor(
          () => find.byType(TerminalCommandBlocksView).evaluate().isNotEmpty,
          'visible Command Block view',
        );
        final composer = tester
            .widget<TerminalComposerView>(find.byType(TerminalComposerView))
            .controller;

        if (smartApproval) {
          const command = r"printf 'SMART_REVIEW_OK\n'";
          fixture.propose('run_command', {
            'command': command,
            'reason': 'Print the requested marker',
          });
          await tester.enterText(
            find.byKey(const Key('composer-editor')),
            '输出 SMART_REVIEW_OK',
          );
          await tester.pump();
          await click(const Key('composer-primary-action'));
          await waitFor(
            () => fixture.reviewStarted.isCompleted,
            'independent review request',
          );
          final ai = tester
              .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
              .controller;
          expect(ai.phase, AiPhase.reviewing);
          expect(runtime.commandBlocks(id)!['blocks'], isEmpty);
          await capture('smart-reviewing');
          fixture.reviewRelease.complete();
          await waitFor(
            () =>
                ai.phase == AiPhase.idle &&
                ai.transcript.any((e) => e.state == AiEntryState.accepted),
            'automatic command receipt',
          );
          final written =
              (runtime.commandBlocks(id)!['blocks']! as List<Object?>)
                  .map(CommandBlock.fromJson)
                  .whereType<CommandBlock>()
                  .toList();
          expect(written.where((b) => b.command == command), hasLength(1));
          expect(
            ai.transcript
                .singleWhere((e) => e.action != null)
                .approvalReview!
                .automatic,
            isTrue,
          );
          expect(fixture.reviews, 1);
          expect(ai.canApprove, isFalse);
          await capture('smart-approved');
          final taskBeforeEvidence = ai.taskId;
          final requestsBeforeEvidence = fixture.requests;
          final evidenceKey = Key('ai-evidence-${written.single.id}-0');
          for (var visit = 0; visit < 2; visit++) {
            await click(evidenceKey);
            await waitFor(
              () => find.byKey(const Key('block-reader')).evaluate().isNotEmpty,
              'evidence reader',
            );
            await tester.pumpAndSettle();
            final back = find.byKey(const Key('block-reader-close'));
            expect(tester.getRect(back).top, greaterThanOrEqualTo(44));
            await capture('evidence-reader-$visit');
            if (nativeEvidenceClick && visit == 0) {
              // CUA sends an OS mouse click here; WidgetTester.tap alone cannot
              // reveal NSWindow intercepting clicks as native window drags.
              final previous =
                  tester.binding.shouldPropagateDevicePointerEvents;
              tester.binding.shouldPropagateDevicePointerEvents = true;
              try {
                debugPrint('EVIDENCE_READY_FOR_NATIVE_BACK_CLICK');
                await waitFor(
                  () =>
                      find.byKey(const Key('block-reader')).evaluate().isEmpty,
                  'native Back click',
                  timeout: const Duration(minutes: 3),
                );
              } finally {
                tester.binding.shouldPropagateDevicePointerEvents = previous;
              }
            } else {
              await click(const Key('block-reader-close'));
            }
            await tester.pumpAndSettle();
            expect(find.byKey(const Key('block-reader')), findsNothing);
            expect(find.byKey(evidenceKey), findsOneWidget);
            expect(ai.taskId, taskBeforeEvidence);
            expect(fixture.requests, requestsBeforeEvidence);
            expect(runtime.commandBlocks(id)!['blocks'], hasLength(1));
          }
          await capture('evidence-returned-to-task');
          fixture.propose('run_command', {
            'command': 'rm -rf /srv/shared',
            'reason': 'Sensitive proposal that must never execute in this test',
          });
          await tester.enterText(find.byKey(const Key('ai-prompt')), '清理共享目录');
          await tester.pump();
          await click(const Key('ai-send'));
          await waitFor(() => ai.canApprove, 'sensitive command confirmation');
          expect(ai.transcript.last.approvalReview!.source, 'sensitive');
          expect(runtime.commandBlocks(id)!['blocks'], hasLength(1));
          expect(fixture.reviews, 1);
          await capture('smart-needs-confirmation');
          ai.reject();
          expect(tester.takeException(), isNull);
          if (evidencePath.isNotEmpty) {
            await File('$evidencePath/smart-result.json').writeAsString(
              jsonEncode({
                'passed': true,
                'automaticExecutions': 1,
                'independentReviews': fixture.reviews,
                'sensitiveExecuted': false,
                'sameSession': true,
                'evidenceReturnVisits': 2,
                'nativeEvidenceClick': nativeEvidenceClick,
              }),
            );
          }
          return;
        }

        for (final input in [
          '写首诗',
          'good morning',
          'translate bonjour',
          '物語を話して',
          'unknown-tool --version',
        ]) {
          await tester.enterText(
            find.byKey(const Key('composer-editor')),
            input,
          );
          await tester.pump();
          expect(composer.intentDecision.intent, InputIntent.ai, reason: input);
        }
        expect(shell()?['commandNames'], contains('printf'));
        final promptsBefore = fixture.requests;
        await tester.enterText(
          find.byKey(const Key('composer-editor')),
          '讲个故事',
        );
        await tester.pump();
        expect(composer.intentDecision.intent, InputIntent.ai);
        expect(runtime.commandBlocks(id)!['blocks'], isEmpty);
        fixture.propose('run_command', {
          'command': 'printf proposal-only',
          'reason': 'A proposal requiring approval',
        });
        await capture('intent-composer-ai');
        await click(const Key('composer-primary-action'));
        await waitFor(
          () => find.byType(TerminalAiWorkspace).evaluate().isNotEmpty,
          'AI workspace',
        );
        final ai = tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .controller;
        await waitFor(() => ai.canApprove, 'AI proposal');
        expect(fixture.requests, promptsBefore + 1);
        expect(runtime.commandBlocks(id)!['blocks'], isEmpty);
        ai.reject();
        await tester.pump();
        final requestsBeforeCommand = fixture.requests;
        for (final input in [
          '随便聊聊',
          'invent a bedtime story',
          'unknown-tool --version',
        ]) {
          await tester.enterText(find.byKey(const Key('ai-prompt')), input);
          await tester.pump();
          expect(
            ai.inputIntentDecision().intent,
            InputIntent.ai,
            reason: input,
          );
        }
        final proof = File('${home.path}/human-once.txt');
        final command =
            "printf x >> '${proof.path}'; printf 'INTENT_PTY_OK\\n'";
        await tester.enterText(find.byKey(const Key('ai-prompt')), command);
        await waitFor(() => ai.canRunUserCommand, 'ready original PTY');
        await tester.pump();
        expect(ai.inputIntentDecision().intent, InputIntent.command);
        await capture('intent-ai-command');
        await click(const Key('ai-send'));
        await waitFor(
          () => !ai.busy && ai.draft.isEmpty,
          'human command receipt',
        );
        await waitFor(proof.existsSync, 'command proof');
        expect(await proof.readAsString(), 'x');
        expect(fixture.requests, requestsBeforeCommand);
        final blocks = (runtime.commandBlocks(id)!['blocks']! as List<Object?>)
            .map(CommandBlock.fromJson)
            .whereType<CommandBlock>()
            .toList();
        expect(blocks.where((block) => block.command == command), hasLength(1));
        final block = blocks.singleWhere((block) => block.command == command);
        expect(block.visibleOutput, contains('INTENT_PTY_OK'));
        final receipt = ai.transcript.singleWhere(
          (entry) => entry.blockId == block.id,
        );
        expect(receipt.state, AiEntryState.accepted);
        expect(receipt.target!.sessionId, id);
        await capture('intent-command-result');
        // A manual override remains on this entry, including further edits.
        await tester.enterText(
          find.byKey(const Key('ai-prompt')),
          'git status',
        );
        await click(const Key('ai-input-intent'));
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is CheckedPopupMenuItem<String> && w.value == 'ai',
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(find.byKey(const Key('ai-prompt')), 'pwd');
        await tester.pump();
        expect(ai.inputIntentDecision().intent, InputIntent.ai);
        expect(fixture.requests, requestsBeforeCommand);
        await tester.enterText(find.byKey(const Key('ai-prompt')), '');
        await tester.pump();
        expect(ai.inputIntentChoice, InputIntentChoice.automatic);
        expect(tester.takeException(), isNull);
        if (evidencePath.isNotEmpty) {
          await File('$evidencePath/result.json').writeAsString(
            jsonEncode({
              'passed': true,
              'modelRequests': fixture.requests,
              'manualCommandExecutions': await proof.readAsString(),
              'sameSession': receipt.target!.sessionId == id,
              'receipt': receipt.state.name,
            }),
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}

class _ResponseFixture {
  _ResponseFixture(this.server);
  final HttpServer server;
  Map<String, Object?>? next;
  int requests = 0;
  int reviews = 0;
  final reviewStarted = Completer<void>();
  final reviewRelease = Completer<void>();
  int? nextStatus;
  bool disconnectNext = false;
  final payloads = <Map<String, Object?>>[];
  static Future<_ResponseFixture> start() async {
    final fixture = _ResponseFixture(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fixture.server.listen((request) async {
      final data =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, Object?>;
      fixture.payloads.add(data);
      fixture.requests++;
      if (fixture.disconnectNext) {
        fixture.disconnectNext = false;
        (await request.response.detachSocket(writeHeaders: false)).destroy();
        return;
      }
      if (fixture.nextStatus case final int status) {
        fixture.nextStatus = null;
        request.response.statusCode = status;
        await request.response.close();
        return;
      }
      Map<String, Object?>? message;
      if (data['tools'] == null) {
        fixture.reviews++;
        final messages = data['messages']! as List;
        final review =
            jsonDecode((messages.last as Map)['content'] as String) as Map;
        if (!fixture.reviewStarted.isCompleted) {
          fixture.reviewStarted.complete();
        }
        await fixture.reviewRelease.future;
        message = {
          'role': 'assistant',
          'content': jsonEncode({
            'action_id': review['action_id'],
            'decision': 'allow',
            'risk': 'low',
            'within_scope': true,
            'needs_confirmation': false,
            'effect': 'read_only',
            'reason': '仅输出用户要求的标记，不修改文件。',
          }),
        };
      } else {
        message = fixture.next;
        fixture.next = null;
      }
      if (message == null) {
        final messages = data['messages']! as List;
        final results = messages.where((m) => (m as Map)['role'] == 'tool');
        String? blockId;
        if (results.isNotEmpty) {
          final result =
              jsonDecode((results.last as Map)['content'] as String) as Map;
          blockId = result['block_id'] as String?;
        }
        message = {
          'role': 'assistant',
          'content': blockId == null
              ? 'The current screen has been inspected.'
              : 'The command receipt is linked to its original output. [block:$blockId:1-1]',
        };
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': 'fixture-${fixture.requests}',
          'model': 'fixture',
          'choices': [
            {'message': message},
          ],
        }),
      );
      await request.response.close();
    });
    return fixture;
  }

  void propose(String name, Map<String, Object?> arguments) {
    next = {
      'role': 'assistant',
      'content': 'Review this action on the current target.',
      'tool_calls': [
        {
          'id': 'fixture-action-${requests + 1}',
          'type': 'function',
          'function': {'name': name, 'arguments': jsonEncode(arguments)},
        },
      ],
    };
  }

  Future<void> close() async {
    if (!reviewRelease.isCompleted) reviewRelease.complete();
    await server.close(force: true);
  }
}
