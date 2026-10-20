import 'dart:io';

import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

/// Uses real PTY output; marker files only pace the disposable shell process.
Future<Map<String, Object?>> verifyStreamingTimeline(
  WidgetTester tester, {
  required TerminalAiController task,
  required TerminalRuntimeController runtime,
  required String sessionId,
  required Directory home,
  required void Function(String, Map<String, Object?>) propose,
  required Future<void> Function(String) ask,
  required Future<void> Function(Key) click,
  required Future<void> Function(bool Function(), String) waitFor,
  required Future<void> Function(String) capture,
}) async {
  const command =
      r'''printf x >> stream-once.txt; for phase in 1 2 3; do for row in {1..80}; do printf 'STREAM_%s_%03d\n' "$phase" "$row"; done; touch "stream-phase-$phase"; while [[ ! -e "stream-next-$phase" ]]; do sleep 0.05; done; done; printf 'STREAM_DONE\n' ''';
  final proof = File('${home.path}/stream-once.txt');
  Map<String, Object?>? block() =>
      (runtime.commandBlocks(sessionId)!['blocks']! as List)
          .cast<Map<String, Object?>>()
          .where((value) => value['command'] == command.trim())
          .firstOrNull;
  Future<void> phase(int number) => waitFor(
    () => File('${home.path}/stream-phase-$number').existsSync(),
    'stream output phase $number',
  );
  Future<void> release(int number) =>
      File('${home.path}/stream-next-$number').writeAsString('continue');
  propose('run_command', {
    'command': command.trim(),
    'reason': 'Observe three batches from one command without losing history',
  });
  await ask('Read the live output while preserving my place in this task.');
  propose('read_screen', {
    'wait_ms': 30000,
    'reason': 'Observe the same command until it exits',
  });
  await click(const Key('ai-approve'));
  await phase(1);
  await waitFor(() => task.phase == AiPhase.observing, 'stream observation');
  await tester.pump(const Duration(milliseconds: 300));
  final nativeId = block()!['id']! as String;
  final workspace = find.byType(TerminalAiWorkspace);
  final blocks = find.descendant(
    of: workspace,
    matching: find.byType(TerminalCommandBlocksView),
  );
  final blocksView = tester.widget<TerminalCommandBlocksView>(blocks);
  final scroll =
      blocksView.scrollController! as CommandTimelineScrollController;
  final timeline = find.descendant(
    of: workspace,
    matching: find.byType(CommandTimelineView),
  );
  final firstRows = block()!['totalLines']! as int;
  expect(firstRows, greaterThanOrEqualTo(80));
  expect(proof.readAsStringSync(), 'x');
  expect(task.followingOutput, true);
  expect(scroll.position.extentAfter, lessThan(1));
  final root = find.descendant(
    of: workspace,
    matching: find.byKey(ValueKey('command-block-$nativeId')),
  );
  final initialHeight = tester.getSize(root).height;
  final availableHeight = tester.getSize(blocks).height;
  expect(initialHeight, lessThanOrEqualTo(availableHeight / 3 + 1));
  await capture('D04-streaming-one-native-block');

  // Wheel input in the timeline gutter reaches the outer reading surface.
  final bounds = tester.getRect(timeline);
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: Offset(bounds.left + 4, bounds.top + 40),
      scrollDelta: const Offset(0, -420),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  expect(task.followingOutput, false);
  expect(scroll.position.extentAfter, greaterThan(100));
  final anchor = scroll.readingAnchor!;
  final offset = scroll.offset;
  void expectAnchor() {
    expect(scroll.readingAnchor!.itemId, anchor.itemId);
    expect(scroll.readingAnchor!.offset, closeTo(anchor.offset, .5));
    expect(task.followingOutput, false);
  }

  Future<void> returnToReading() async {
    await click(const Key('ai-return-reading'));
    await waitFor(
      () =>
          scroll.readingAnchor?.itemId == anchor.itemId &&
          (scroll.readingAnchor!.offset - anchor.offset).abs() < .5,
      'explicit return restores the original timeline item and offset',
    );
    expectAnchor();
  }

  await capture('D13-stream-history-before-next-batch');
  await release(1);
  await phase(2);
  await tester.pump(const Duration(milliseconds: 350));
  final secondRows = block()!['totalLines']! as int;
  expect(secondRows, greaterThanOrEqualTo(firstRows + 80));
  expectAnchor();
  await capture('D13-stream-history-after-next-batch');

  await click(const Key('ai-show-latest'));
  expect(task.followingOutput, true);
  expect(scroll.position.extentAfter, lessThan(1));
  await release(2);
  await phase(3);
  await tester.pump(const Duration(milliseconds: 350));
  expect(scroll.position.extentAfter, lessThan(1));
  final thirdHeight = tester.getSize(root).height;
  // The native cell measurement may replace the initial font estimate.
  // Both layouts must honor the whole-block budget, not an identical pixel size.
  expect(thirdHeight, lessThanOrEqualTo(tester.getSize(blocks).height / 3 + 1));
  await capture('D04-stream-latest-third-batch');
  await returnToReading();

  // Let the command return to the shell before offering the next action. A
  // proposal made against the running command must be revoked when its guard
  // changes; that is not a navigation failure.
  await release(3);
  await waitFor(
    () =>
        block()?['exitCode'] == 0 &&
        task.phase == AiPhase.idle &&
        task.context?.canRunCommand == true,
    'stream exited and shell is ready',
  );
  // A new, unapproved action arrives while the reader is still in history.
  propose('run_command', {
    'command': 'printf NEVER >> stream-must-not-run.txt',
    'reason': 'Requires its own explicit approval',
  });
  final proposal = task.ask('Propose the next check and wait for my approval.');
  await waitFor(() => task.canApprove, 'next proposal after stream exit');
  await proposal;
  await tester.pump(const Duration(milliseconds: 350));
  expectAnchor();
  expect(block()!['exitCode'], 0);
  expect(proof.readAsStringSync(), 'x');
  expect(File('${home.path}/stream-must-not-run.txt').existsSync(), false);
  final finalRows = block()!['totalLines']! as int;
  expect(finalRows, greaterThanOrEqualTo(241));
  expect(
    task.transcript.where((entry) => entry.blockId == nativeId),
    hasLength(1),
  );
  await capture('D13-stream-completed-proposal-keeps-history');
  await click(const Key('ai-show-latest'));
  await capture('D13-stream-proposal-first-frame');
  await tester.pump(const Duration(milliseconds: 350));
  await capture('D13-stream-proposal-after-layout');
  expect(find.byKey(const Key('ai-approve')).hitTestable(), findsOneWidget);
  await capture('D13-stream-explicit-proposal-location');
  await returnToReading();
  final returnedOffset = scroll.offset;
  await click(const Key('ai-show-latest'));
  await capture('D13-stream-second-explicit-proposal-location');
  expect(
    task.canApprove,
    true,
    reason:
        'A navigation does not change the proposal: ${task.phase}, ${task.error}',
  );
  await click(const Key('ai-reject'));
  expect(File('${home.path}/stream-must-not-run.txt').existsSync(), false);
  expect(tester.takeException(), isNull);
  return {
    'block_id': nativeId,
    'output_rows_by_phase': [firstRows, secondRows, finalRows],
    'whole_block_height': initialHeight,
    'whole_block_height_after_updates': thirdHeight,
    'available_timeline_height': availableHeight,
    'reading_anchor_id': anchor.itemId,
    'reading_anchor_offset': anchor.offset,
    'scroll_offset_before': offset,
    'scroll_offset_after_return': returnedOffset,
    'execution_proof': proof.readAsStringSync(),
    'new_proposal_not_executed': true,
    'wheel_paused_follow_and_updates_kept_anchor': true,
    'explicit_latest_and_return_preserved_anchor': true,
  };
}
