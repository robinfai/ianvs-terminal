import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/ai/terminal_ai_test.dart' show FakeTerminal, MemoryAiStore;
import '../test/helpers/pump_app.dart';
import '../test/support/macos_integration_test_lifecycle.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native UI receives SSE incrementally and gates tools on completion',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final responses = <HttpResponse>[];
      server.listen((request) async {
        final body = jsonDecode(await utf8.decodeStream(request)) as Map;
        expectSync(body['stream'], true);
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.bufferOutput = false;
        request.response.write(': connected\n\n');
        await request.response.flush();
        responses.add(request.response);
      });
      final settings = AiSettingsController(
        MemoryAiStore(
          AiConfiguration(
            endpoint: 'http://127.0.0.1:${server.port}/v1',
            apiKey: 'fixture',
            model: 'fixture',
          ),
        ),
      );
      await settings.loaded;
      final terminal = FakeTerminal();
      final controller = TerminalAiController(
        settings: settings,
        terminal: terminal,
      );
      await controller.refreshContext();
      addTearDown(() async {
        controller.dispose();
        settings.dispose();
        await server.close(force: true);
      });
      final key = GlobalKey();
      await tester.pumpApp(
        RepaintBoundary(
          key: key,
          child: TerminalAiWorkspace(
            compactMobile: true,
            controller: controller,
            onClose: () {},
          ),
        ),
        platform: TargetPlatform.iOS,
        locale: const Locale('zh'),
      );
      Future<void> until(bool Function() ready) async {
        final limit = DateTime.now().add(const Duration(seconds: 10));
        while (!ready()) {
          if (DateTime.now().isAfter(limit)) {
            fail('phase=${controller.phase}, error=${controller.error}');
          }
          await tester.pump(const Duration(milliseconds: 30));
        }
        await tester.pump();
      }

      Future<void> capture(String name) async {
        const path = String.fromEnvironment('STREAM_EVIDENCE');
        if (path.isEmpty) return;
        await tester.pump(const Duration(milliseconds: 200));
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final picture = await boundary.toImage(pixelRatio: 2);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        await Directory(path).create(recursive: true);
        await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      }

      Future<void> delta(Map<String, Object?> value, {String? finish}) async {
        responses.last.write(
          'data: ${jsonEncode({
            'id': 'native-fixture',
            'model': 'fixture',
            'choices': [
              {'index': 0, 'delta': value, 'finish_reason': finish},
            ],
          })}\n\n',
        );
        await responses.last.flush();
      }

      Future<void> done() async {
        responses.last.write('data: [DONE]\n\n');
        await responses.last.close();
      }

      Future<void> ask(String text) async {
        final count = responses.length;
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('ai-prompt')));
        // Let the native text client finish its focus handshake before the
        // test keyboard supplies a new editing value (also used by AI E2E).
        await tester.pump(const Duration(milliseconds: 150));
        await tester.enterText(find.byKey(const Key('ai-prompt')), text);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('ai-send')))
              .onPressed,
          isNotNull,
          reason:
              'lifecycle=${tester.binding.lifecycleState}; '
              'draft=${controller.draft}; terminal=${controller.terminalError}; '
              'targetChanged=${controller.targetChanged}; '
              'field=${tester.widget<TextField>(find.byKey(const Key('ai-prompt'))).controller!.value}',
        );
        await tester.tap(find.byKey(const Key('ai-send')));
        await until(
          () =>
              responses.length > count &&
              controller.phase == AiPhase.waitingForFirstToken,
        );
      }

      expect(
        tester.getSize(find.byKey(const Key('ai-mobile-composer'))).height,
        lessThanOrEqualTo(56),
      );
      await capture('01-compact');
      await ask('解释当前目录，并提出待审批命令');
      await capture('02-first-token');
      await delta({'content': '正在读取目录信息，'});
      await until(() => controller.transcript.last.text == '正在读取目录信息，');
      expect(controller.busy, true);
      expect(controller.pending, isNull);
      await capture('03-generating');
      await delta({
        'content': '请确认下面的命令。',
        'tool_calls': [
          {
            'index': 0,
            'id': 'native-call',
            'type': 'function',
            'function': {
              'name': 'run_command',
              'arguments': '{"command":"pwd"',
            },
          },
        ],
      });
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.canApprove, false);
      await delta({
        'tool_calls': [
          {
            'index': 0,
            'function': {'arguments': ',"reason":"查看目录"}'},
          },
        ],
      }, finish: 'tool_calls');
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.canApprove, false);
      await done();
      await until(() => controller.canApprove);
      expect(
        controller.transcript.where((e) => e.role == 'assistant'),
        hasLength(1),
      );
      await capture('04-approval');
      controller.reject();
      await ask('给出第二次解释');
      await delta({'content': '保留已收到的文字'});
      await until(() => controller.phase == AiPhase.generating);
      await tester.tap(find.byKey(const Key('ai-mobile-primary-pause')));
      await until(() => controller.generationCancelled);
      await capture('05-cancelled');
      controller.newTask();
      await tester.pump();
      await ask('完整的下一轮');
      await delta({'content': '新任务回复'}, finish: 'stop');
      await done();
      await until(() => controller.phase == AiPhase.idle);
      expect(controller.transcript.last.text, '新任务回复');
      await capture('06-completed');
      await ask('演示服务中断');
      await delta({'content': '未完成的回复'});
      await responses.last.close();
      await until(() => controller.phase == AiPhase.failed);
      expect(controller.error, 'response_incomplete');
      expect(controller.pending, isNull);
      expect(terminal.writes, isEmpty);
      await capture('07-failed');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !Platform.isMacOS,
  );
}
