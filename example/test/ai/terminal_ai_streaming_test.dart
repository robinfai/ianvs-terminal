import 'dart:async';

import 'package:app/features/ai/ai_api_client.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_response_activity.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';
import 'terminal_ai_test.dart' show FakeApi, FakeTerminal, MemoryAiStore, commandReply;

class _StreamingApi extends FakeApi implements AiStreamingApi {
  final started = Completer<void>();
  final result = Completer<AiReply>();
  late AiStreamListener update;
  @override
  Future<AiReply> completeStreaming(AiConfiguration configuration,
      List<Map<String, Object?>> messages, AiCancellation cancellation,
      {required AiStreamListener onUpdate}) {
    requests.add(messages);
    cancellations.add(cancellation);
    update = onUpdate;
    started.complete();
    return result.future;
  }
}

void main() {
  late AiSettingsController settings;
  late TerminalAiController controller;
  late FakeTerminal terminal;
  late _StreamingApi api;
  setUp(() async {
    settings = AiSettingsController(MemoryAiStore());
    await settings.loaded;
    terminal = FakeTerminal();
    api = _StreamingApi();
    controller = TerminalAiController(settings:settings, terminal:terminal, api:api);
  });
  tearDown(() { controller.dispose(); settings.dispose(); });

  test('partial text is visible before completion; complete tool still needs approval', () async {
    final turn = controller.ask('Inspect the current directory');
    await api.started.future;
    expect(controller.responseProgress?.stage, AiResponseStage.connecting);
    api.update(const AiStreamUpdate(AiStreamStage.waiting));
    api.update(const AiStreamUpdate(AiStreamStage.receivingText, textDelta:'Checking'));
    expect(controller.transcript.last.text, 'Checking');
    expect(controller.transcript.last.state, AiEntryState.streaming);
    final id = controller.transcript.last.id;
    expect(controller.pending,isNull);
    expect(terminal.writes,isEmpty);
    api.update(const AiStreamUpdate(AiStreamStage.receivingText, textDelta:' files'));
    api.update(const AiStreamUpdate(AiStreamStage.receivingTool));
    expect(controller.pending,isNull);
    api.result.complete(AiReply(text:'Checking files', action:commandReply('pwd').action));
    await turn;
    final messages = controller.transcript.where((e)=>e.role=='assistant').toList();
    expect(messages,hasLength(1));
    expect(messages.single.id,id);
    expect(messages.single.text,'Checking files');
    expect(messages.single.state,AiEntryState.message);
    expect(controller.phase,AiPhase.awaitingApproval);
    expect(controller.pending?.command,'pwd');
    expect(terminal.writes,isEmpty);
    expect(controller.responseProgress?.active,isFalse);
  });

  test('stopping retains partial text and ignores delayed old-task chunks', () async {
    final oldId = controller.taskId;
    final turn = controller.ask('Explain output');
    await api.started.future;
    api.update(const AiStreamUpdate(AiStreamStage.receivingText,textDelta:'Keep this'));
    controller.takeOver();
    expect(controller.responseProgress?.stage,AiResponseStage.cancelled);
    expect(controller.transcript.last.state,AiEntryState.partial);
    controller.newTask();
    final replacement = controller.taskId;
    api.update(const AiStreamUpdate(AiStreamStage.receivingText,textDelta:' wrong task'));
    api.result.complete(const AiReply(text:'Keep this wrong task'));
    await turn;
    expect(controller.taskId,replacement);
    expect(controller.transcript,isEmpty);
    controller.selectTask(oldId);
    expect(controller.transcript.last.text,'Keep this');
    expect(controller.transcript.last.state,AiEntryState.partial);
    expect(terminal.writes,isEmpty);
  });

  test('transport truncation retains partial text and creates no proposal', () async {
    final turn = controller.ask('Explain');
    await api.started.future;
    api.update(const AiStreamUpdate(AiStreamStage.receivingText,textDelta:'Incomplete'));
    api.result.completeError(const AiFailure('stream_incomplete'));
    await turn;
    expect(controller.phase,AiPhase.failed);
    expect(controller.error,'stream_incomplete');
    expect(controller.transcript.last.state,AiEntryState.partial);
    expect(controller.transcript.last.text,'Incomplete');
    expect(controller.pending,isNull);
    expect(terminal.writes,isEmpty);
  });

  testWidgets('request waiting, first text, completion and partial status use actual states', (tester) async {
    await tester.pumpApp(Builder(builder:(context)=>MediaQuery(
      data:MediaQuery.of(context).copyWith(disableAnimations:true),
      child:TerminalAiWorkspace(controller:controller,onClose:(){},compactMobile:true),
    )),platform:TargetPlatform.iOS,locale:const Locale('zh'));
    final turn = controller.ask('Explain');
    await tester.pump();
    await api.started.future;
    await tester.pump();
    expect(find.byKey(const Key('ai-request-activity')),findsOneWidget);
    expect(find.text('正在发送请求…'),findsWidgets);
    api.update(const AiStreamUpdate(AiStreamStage.waiting));
    await tester.pump();
    expect(find.text('等待模型回复…'),findsWidgets);
    api.update(const AiStreamUpdate(AiStreamStage.receivingText,textDelta:'先到的回复'));
    await tester.pump();
    expect(find.text('正在生成回复…'),findsWidgets);
    expect(controller.transcript.last.text,'先到的回复');
    controller.takeOver();
    api.result.completeError(const AiFailure('cancelled'));
    await turn;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-request-activity')),findsNothing);
    expect(find.text('生成已停止 · 内容不完整'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('loading animation respects reduced motion', (tester) async {
    await tester.pumpApp(const AiResponseActivity(label:'Waiting',animate:true));
    await tester.pump(const Duration(milliseconds:150));
    expect(find.byType(CircularProgressIndicator),findsOneWidget);
    await tester.pumpApp(Builder(builder:(context)=>MediaQuery(
      data:MediaQuery.of(context).copyWith(disableAnimations:true),
      child:const AiResponseActivity(label:'Waiting',animate:true),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator),findsNothing);
  });

  testWidgets('missing-runtime fallback always exposes a readable route out', (tester) async {
    var back=0;
    var reconnect=0;
    await tester.pumpApp(TerminalUnavailablePaneNotice(
        onBack:()=>back++,onReconnect:()=>reconnect++),
        platform:TargetPlatform.iOS,locale:const Locale('zh'));
    expect(find.text('终端会话不可用'),findsOneWidget);
    await tester.tap(find.byKey(const Key('terminal-unavailable-back')));
    await tester.tap(find.byKey(const Key('terminal-unavailable-reconnect')));
    expect(back,1);
    expect(reconnect,1);
    expect(tester.takeException(),isNull);
  });
}
