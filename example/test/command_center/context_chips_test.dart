import 'package:app/features/command_center/command_block_models.dart';
import 'package:app/features/command_center/command_invocation_models.dart';
import 'package:app/features/command_center/command_lifecycle_degraded_state.dart';
import 'package:app/features/command_center/context_chip_models.dart';
import 'package:app/features/command_center/context_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContextChipState', () {
    test('derives cwd, profile, shell hook and read-only chips', () {
      final state = ContextChipState.fromContext(
        cwd: '/repo/example',
        profileId: 'default',
        profileName: 'Default',
        shellHookState: const CommandCenterCapabilityState.enabled(),
        readOnly: true,
      );

      expect(state.byKind(ContextChipKind.cwd)!.value, '/repo/example');
      expect(state.byKind(ContextChipKind.profile)!.value, 'Default');
      expect(
        state.byKind(ContextChipKind.shellHook)!.tone,
        ContextChipTone.success,
      );
      expect(state.byKind(ContextChipKind.readOnly)!.value, 'Input blocked');
      expect(
        state.byKind(ContextChipKind.readOnly)!.semanticLabel,
        contains('Read-only'),
      );
    });

    test('shows unavailable cwd and limited shell hook reason', () {
      final state = ContextChipState.fromContext(
        cwd: null,
        profileId: null,
        profileName: null,
        shellHookState: const CommandCenterCapabilityState.limited(
          CommandCenterUnavailableReason.missingCwd,
        ),
      );

      final cwd = state.byKind(ContextChipKind.cwd)!;
      final shellHook = state.byKind(ContextChipKind.shellHook)!;

      expect(cwd.enabled, isFalse);
      expect(cwd.value, 'CWD unavailable');
      expect(shellHook.value, 'Shell hooks limited');
      expect(
        shellHook.unavailableReason,
        CommandCenterUnavailableReason.missingCwd,
      );
      expect(shellHook.tone, ContextChipTone.warning);
    });

    test('creates safe intents for failed and selected blocks', () {
      final failed = _block(id: 'cmd-fail', command: 'false', exitCode: 2);
      final selected = _block(id: 'cmd-selected', command: 'flutter test');
      final state = ContextChipState.fromContext(
        cwd: '/repo',
        profileId: 'default',
        profileName: 'Default',
        shellHookState: const CommandCenterCapabilityState.enabled(),
        lastFailedBlock: failed,
        selectedBlock: selected,
      );

      final lastExit = state.byKind(ContextChipKind.lastExit)!;
      final selectedBlock = state.byKind(ContextChipKind.selectedBlock)!;

      expect(lastExit.value, 'Exit 2');
      expect(lastExit.intent.kind, ContextChipIntentKind.navigateToBlock);
      expect(lastExit.intent.blockId, 'cmd-fail');
      expect(selectedBlock.intent.kind, ContextChipIntentKind.openBlockActions);
      expect(selectedBlock.intent.blockId, 'cmd-selected');
      expect(
        state.chips.every((chip) => !chip.intent.writesToTerminal),
        isTrue,
      );
    });
  });

  group('ContextChips', () {
    testWidgets('renders chips and dispatches safe click intents', (
      tester,
    ) async {
      final intents = <ContextChipClickIntent>[];
      final state = ContextChipState.fromContext(
        cwd: '/repo',
        profileId: 'default',
        profileName: 'Default',
        shellHookState: const CommandCenterCapabilityState.enabled(),
        selectedBlock: _block(id: 'cmd-1', command: 'flutter test'),
        readOnly: true,
      );

      await tester.pumpWidget(
        _app(
          ContextChips(
            chips: state.chips,
            onIntent: (intent, _) => intents.add(intent),
          ),
        ),
      );

      expect(find.byKey(const Key('context-chip-cwd')), findsOneWidget);
      expect(find.text('CWD /repo'), findsOneWidget);
      expect(find.text('Read-only Input blocked'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('context-chip-readOnly')),
          matching: find.byIcon(Icons.lock),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('context-chip-selectedBlock')));
      await tester.pump();

      expect(intents.single.kind, ContextChipIntentKind.openBlockActions);
      expect(intents.single.blockId, 'cmd-1');
      expect(intents.single.writesToTerminal, isFalse);
    });
  });
}

final _startedAt = DateTime.utc(2026, 6, 15, 10);

CommandBlock _block({
  required String id,
  required String command,
  int? exitCode,
}) {
  return CommandBlock(
    id: id,
    sessionId: 'session-a',
    paneId: 'pane-a',
    command: command,
    startedAt: _startedAt,
    status: exitCode == null
        ? CommandInvocationStatus.running
        : exitCode == 0
        ? CommandInvocationStatus.succeeded
        : CommandInvocationStatus.failed,
    exitCode: exitCode,
    inputRange: const CommandBlockRowRange(startRow: 4, endRowExclusive: 5),
    outputRange: const CommandBlockRowRange(startRow: 5, endRowExclusive: 8),
  );
}

Widget _app(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    ),
    home: Scaffold(body: Center(child: child)),
  );
}
