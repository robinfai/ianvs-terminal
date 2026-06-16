# Command Block Command Center Fusion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `ShellCommandBlockSnapshot` the command block source of truth for Command Center block actions, context chips, and review entrypoints.

**Architecture:** Add a small adapter that converts `ShellCommandBlock` objects into the existing Command Center compatible `CommandBlock` targets. Then replace `ShellScreen` block lookup paths so Action Search, context chips, copy/save/search/review, and selected block navigation all read from `_commandBlockSnapshotsBySession` instead of rebuilding ranges through `CommandCenterRuntime.blockRangeState(...)`.

**Tech Stack:** Flutter, Dart, Riverpod, `package:flutter_test`, existing `ShellCommandBlockSnapshot`, `CommandBlockActionReducer`, `ContextChipState`, and `CommandReviewEntrypointResolver`.

---

## File Structure

- Create: `example/lib/features/command_center/shell_command_block_command_center_adapter.dart`
  - Owns all conversion from `ShellCommandBlockSnapshot` to Command Center compatible targets.
  - Does not parse shell hooks, inspect terminal frames, write shell input, or persist data.
- Create: `example/test/command_center/shell_command_block_command_center_adapter_test.dart`
  - Covers selected block lookup, fallback to newest block, last failed block, range conversion, and context chips.
- Modify: `example/lib/features/shell/shell_screen.dart`
  - Imports the adapter and stores one adapter instance.
- Modify: `example/lib/features/shell/shell_screen_state_context_chips.dart`
  - Replaces context chip block lookup with adapter-backed `ShellCommandBlockSnapshot` lookup.
- Modify: `example/lib/features/shell/shell_screen_state_command_action_search.dart`
  - Replaces Action Search active block lookup with adapter-backed `ShellCommandBlockSnapshot` lookup.
- Modify: `example/test/widget_test.dart`
  - Adds a regression where Action Search can copy block output from `ShellCommandBlockSnapshot` even when the old prompt-mark range rebuild would not produce a `CommandBlockRangeState`.
- Optional documentation update after implementation:
  - `docs/superpowers/specs/2026-06-16-command-block-command-center-fusion-design.md`
  - Add a short implementation note only if the implementation chooses a different file placement or public API than planned.

---

### Task 1: Adapter Tests

**Files:**
- Create: `example/test/command_center/shell_command_block_command_center_adapter_test.dart`
- Read: `example/lib/features/productivity/shell_productivity_models.dart`
- Read: `example/lib/features/command_center/command_block_models.dart`

- [ ] **Step 1: Write failing adapter tests**

Create `example/test/command_center/shell_command_block_command_center_adapter_test.dart`:

```dart
import 'package:app/features/command_center/command_invocation_models.dart';
import 'package:app/features/command_center/context_chip_models.dart';
import 'package:app/features/command_center/shell_command_block_command_center_adapter.dart';
import 'package:app/features/productivity/shell_command_block_controller.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellCommandBlockCommandCenterAdapter', () {
    const adapter = ShellCommandBlockCommandCenterAdapter();

    test('uses selected block when it exists in the snapshot', () {
      final snapshot = ShellCommandBlockSnapshot.withBlocks(
        blocks: const [
          ShellCommandBlock(
            id: 'old',
            command: 'false',
            status: ShellCommandBlockStatus.failed,
            exitCode: 2,
            outputRange: ShellCommandBlockRange(
              commandRow: 10,
              outputStartRow: 11,
              outputEndRow: 12,
            ),
          ),
          ShellCommandBlock(
            id: 'new',
            command: 'echo ok',
            status: ShellCommandBlockStatus.succeeded,
            exitCode: 0,
            outputRange: ShellCommandBlockRange(
              commandRow: 20,
              outputStartRow: 21,
              outputEndRow: 22,
            ),
          ),
        ],
      );

      final block = adapter.activeCompatibleBlockFor(
        snapshot: snapshot,
        sessionId: 'session-a',
        selectedBlockId: 'old',
      );

      expect(block?.id, 'old');
      expect(block?.sessionId, 'session-a');
      expect(block?.status, CommandInvocationStatus.failed);
      expect(block?.inputRange?.startRow, 10);
      expect(block?.inputRange?.endRowExclusive, 11);
      expect(block?.outputRange?.startRow, 11);
      expect(block?.outputRange?.endRowExclusive, 13);
    });

    test('falls back to newest valid block when selected block is missing', () {
      final snapshot = ShellCommandBlockSnapshot.withBlocks(
        blocks: const [
          ShellCommandBlock(
            id: 'old',
            command: 'false',
            status: ShellCommandBlockStatus.failed,
            exitCode: 2,
            outputRange: ShellCommandBlockRange(
              commandRow: 10,
              outputStartRow: 11,
              outputEndRow: 11,
            ),
          ),
          ShellCommandBlock(
            id: 'new',
            command: 'echo ok',
            status: ShellCommandBlockStatus.succeeded,
            exitCode: 0,
            outputRange: ShellCommandBlockRange(
              commandRow: 20,
              outputStartRow: 21,
              outputEndRow: 21,
            ),
          ),
        ],
      );

      final block = adapter.activeCompatibleBlockFor(
        snapshot: snapshot,
        sessionId: 'session-a',
        selectedBlockId: 'missing',
      );

      expect(block?.id, 'new');
    });

    test('exposes last failed block and selected block chips from snapshot', () {
      final snapshot = ShellCommandBlockSnapshot.withBlocks(
        blocks: const [
          ShellCommandBlock(
            id: 'failed',
            command: 'flutter test',
            status: ShellCommandBlockStatus.failed,
            exitCode: 1,
            outputRange: ShellCommandBlockRange(
              commandRow: 30,
              outputStartRow: 31,
              outputEndRow: 33,
            ),
          ),
          ShellCommandBlock(
            id: 'newest',
            command: 'echo ok',
            status: ShellCommandBlockStatus.succeeded,
            exitCode: 0,
            outputRange: ShellCommandBlockRange(
              commandRow: 40,
              outputStartRow: 41,
              outputEndRow: 41,
            ),
          ),
        ],
      );

      final chips = adapter.contextChipsForSession(
        snapshot: snapshot,
        sessionId: 'session-a',
        cwd: '/repo',
        profileId: 'default',
        profileName: 'Default',
        selectedBlockId: 'failed',
      );

      expect(chips.byKind(ContextChipKind.lastExit)?.intent.blockId, 'failed');
      expect(
        chips.byKind(ContextChipKind.selectedBlock)?.intent.blockId,
        'failed',
      );
      expect(chips.byKind(ContextChipKind.cwd)?.value, '/repo');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd example
flutter test test/command_center/shell_command_block_command_center_adapter_test.dart
```

Expected: FAIL because `shell_command_block_command_center_adapter.dart` does not exist.

- [ ] **Step 3: Commit only if this is being executed as an isolated TDD checkpoint**

Do not commit the failing test on shared branches. Continue directly to Task 2 when executing inline.

---

### Task 2: Adapter Implementation

**Files:**
- Create: `example/lib/features/command_center/shell_command_block_command_center_adapter.dart`
- Test: `example/test/command_center/shell_command_block_command_center_adapter_test.dart`

- [ ] **Step 1: Implement the adapter**

Create `example/lib/features/command_center/shell_command_block_command_center_adapter.dart`:

```dart
import '../productivity/shell_command_block_controller.dart';
import '../productivity/shell_productivity_models.dart';
import 'command_block_models.dart';
import 'command_invocation_models.dart';
import 'command_lifecycle_degraded_state.dart';
import 'context_chip_models.dart';

class ShellCommandBlockCommandCenterAdapter {
  const ShellCommandBlockCommandCenterAdapter();

  CommandBlock? activeCompatibleBlockFor({
    required ShellCommandBlockSnapshot snapshot,
    required String sessionId,
    String? selectedBlockId,
  }) {
    final selected = compatibleBlockById(
      snapshot: snapshot,
      sessionId: sessionId,
      blockId: selectedBlockId,
    );
    if (selected != null) {
      return selected;
    }
    for (final block in snapshot.blocks.reversed) {
      if (block.isValid) {
        return compatibleBlockFor(sessionId: sessionId, block: block);
      }
    }
    return null;
  }

  CommandBlock? compatibleBlockById({
    required ShellCommandBlockSnapshot snapshot,
    required String sessionId,
    required String? blockId,
  }) {
    final targetId = blockId?.trim();
    if (targetId == null || targetId.isEmpty) {
      return null;
    }
    for (final block in snapshot.blocks) {
      if (block.id == targetId && block.isValid) {
        return compatibleBlockFor(sessionId: sessionId, block: block);
      }
    }
    return null;
  }

  CommandBlock? lastFailedCompatibleBlockFor({
    required ShellCommandBlockSnapshot snapshot,
    required String sessionId,
  }) {
    for (final block in snapshot.blocks.reversed) {
      if (block.isValid && block.status == ShellCommandBlockStatus.failed) {
        return compatibleBlockFor(sessionId: sessionId, block: block);
      }
    }
    return null;
  }

  List<CommandBlock> compatibleBlocksFor({
    required ShellCommandBlockSnapshot snapshot,
    required String sessionId,
  }) {
    return List<CommandBlock>.unmodifiable(
      snapshot.blocks
          .where((block) => block.isValid)
          .map((block) => compatibleBlockFor(sessionId: sessionId, block: block))
          .whereType<CommandBlock>(),
    );
  }

  ContextChipState contextChipsForSession({
    required ShellCommandBlockSnapshot snapshot,
    required String sessionId,
    required String? cwd,
    required String? profileId,
    required String? profileName,
    String? selectedBlockId,
    bool readOnly = false,
    bool shellIntegrationEnabled = true,
  }) {
    final trimmedCwd = _trimmedOrNull(cwd);
    final selectedBlock = compatibleBlockById(
      snapshot: snapshot,
      sessionId: sessionId,
      blockId: selectedBlockId,
    );
    return ContextChipState.fromContext(
      cwd: trimmedCwd,
      profileId: profileId,
      profileName: profileName,
      shellHookState: _shellHookState(
        cwd: trimmedCwd,
        shellIntegrationEnabled: shellIntegrationEnabled,
      ),
      readOnly: readOnly,
      lastFailedBlock: lastFailedCompatibleBlockFor(
        snapshot: snapshot,
        sessionId: sessionId,
      ),
      selectedBlock: selectedBlock,
    );
  }

  CommandBlock? compatibleBlockFor({
    required String sessionId,
    required ShellCommandBlock block,
  }) {
    if (!block.isValid) {
      return null;
    }
    final range = block.outputRange;
    return CommandBlock(
      id: block.id,
      sessionId: sessionId,
      command: block.command,
      cwd: block.cwd,
      startedAt: _syntheticStartedAtFor(block),
      finishedAt: block.status == ShellCommandBlockStatus.running
          ? null
          : _syntheticStartedAtFor(block),
      exitCode: block.exitCode,
      status: _statusFor(block.status),
      inputRange: CommandBlockRowRange(
        startRow: range.commandRow,
        endRowExclusive: range.commandRow + 1,
      ),
      outputRange: CommandBlockRowRange(
        startRow: range.outputStartRow,
        endRowExclusive: range.outputEndRow + 1,
      ),
    );
  }
}

CommandCenterCapabilityState _shellHookState({
  required String? cwd,
  required bool shellIntegrationEnabled,
}) {
  if (!shellIntegrationEnabled) {
    return const CommandCenterCapabilityState.unavailable(
      CommandCenterUnavailableReason.shellIntegrationDisabled,
    );
  }
  if (cwd == null) {
    return const CommandCenterCapabilityState.limited(
      CommandCenterUnavailableReason.missingCwd,
    );
  }
  return const CommandCenterCapabilityState.enabled();
}

CommandInvocationStatus _statusFor(ShellCommandBlockStatus status) {
  return switch (status) {
    ShellCommandBlockStatus.running => CommandInvocationStatus.running,
    ShellCommandBlockStatus.succeeded => CommandInvocationStatus.succeeded,
    ShellCommandBlockStatus.failed => CommandInvocationStatus.failed,
    ShellCommandBlockStatus.unknown => CommandInvocationStatus.unknown,
  };
}

DateTime _syntheticStartedAtFor(ShellCommandBlock block) {
  final row = block.startRow < 0 ? 0 : block.startRow;
  return DateTime.fromMicrosecondsSinceEpoch(row, isUtc: true);
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
```

- [ ] **Step 2: Run adapter test**

Run:

```bash
cd example
flutter test test/command_center/shell_command_block_command_center_adapter_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run analyzer for import/type issues**

Run:

```bash
cd example
flutter analyze
```

Expected: no errors.

---

### Task 3: Wire Context Chips to Command Block Snapshot

**Files:**
- Modify: `example/lib/features/shell/shell_screen.dart`
- Modify: `example/lib/features/shell/shell_screen_state_context_chips.dart`
- Test: `example/test/widget_test.dart`

- [ ] **Step 1: Import and instantiate the adapter**

In `example/lib/features/shell/shell_screen.dart`, add the import near the other command center imports:

```dart
import '../command_center/shell_command_block_command_center_adapter.dart';
```

Add a field near `_commandCenterContextWiring`:

```dart
  final ShellCommandBlockCommandCenterAdapter
  _commandBlockCommandCenterAdapter =
      const ShellCommandBlockCommandCenterAdapter();
```

- [ ] **Step 2: Replace `_contextChipsForPane`**

In `example/lib/features/shell/shell_screen_state_context_chips.dart`, replace `_contextChipsForPane(...)` with:

```dart
  ContextChipState _contextChipsForPane({
    required SessionState sessionState,
    required TerminalPane pane,
    required TerminalProfile? profile,
  }) {
    final cwd =
        _commandCenterRuntime.cwdForSession(pane.sessionId) ??
        pane.shellIntegration.currentDirectory;
    return _commandBlockCommandCenterAdapter.contextChipsForSession(
      snapshot:
          _commandBlockSnapshotsBySession[pane.sessionId] ??
          const ShellCommandBlockSnapshot(),
      sessionId: pane.sessionId,
      cwd: cwd,
      profileId: profile?.id ?? pane.profileId,
      profileName: profile?.name,
      readOnly: _isSessionReadOnly(pane.sessionId),
      selectedBlockId: _selectedCommandBlockIdsBySession[pane.sessionId],
      shellIntegrationEnabled: _commandBlocksHistoryFeatureFlags.enabled,
    );
  }
```

- [ ] **Step 3: Replace context chip block lookup**

In `example/lib/features/shell/shell_screen_state_context_chips.dart`, replace `_navigateToContextChipBlock(...)` block lookup with adapter lookup:

```dart
    final block = _commandBlockCommandCenterAdapter.compatibleBlockById(
      snapshot:
          _commandBlockSnapshotsBySession[sessionId] ??
          const ShellCommandBlockSnapshot(),
      sessionId: sessionId,
      blockId: blockId,
    );
    final inputRange = block?.inputRange;
```

Replace `_contextChipBlockFor(...)` with:

```dart
  CommandBlock? _contextChipBlockFor({
    required SessionState sessionState,
    required String sessionId,
    required String? blockId,
  }) {
    return _commandBlockCommandCenterAdapter.compatibleBlockById(
      snapshot:
          _commandBlockSnapshotsBySession[sessionId] ??
          const ShellCommandBlockSnapshot(),
      sessionId: sessionId,
      blockId: blockId,
    );
  }
```

- [ ] **Step 4: Run context chip regression tests**

Run:

```bash
cd example
flutter test test/widget_test.dart --plain-name "context chip navigates to the last failed command block"
flutter test test/widget_test.dart --plain-name "selected block chip opens block actions without shell write"
```

Expected: both PASS.

---

### Task 4: Wire Action Search Block Actions to Command Block Snapshot

**Files:**
- Modify: `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- Test: `example/test/widget_test.dart`

- [ ] **Step 1: Replace active block lookup**

In `example/lib/features/shell/shell_screen_state_command_action_search.dart`, replace `_activeCommandActionSearchBlock(...)` with:

```dart
  CommandBlock? _activeCommandActionSearchBlock(
    SessionState sessionState,
    String sessionId,
  ) {
    return _commandBlockCommandCenterAdapter.activeCompatibleBlockFor(
      snapshot:
          _commandBlockSnapshotsBySession[sessionId] ??
          const ShellCommandBlockSnapshot(),
      sessionId: sessionId,
      selectedBlockId: _selectedCommandBlockIdsBySession[sessionId],
    );
  }
```

Leave `_commandBlockRangesForSession(...)` in place for now if analyzer still sees references from legacy code. The completion criterion for this task is that Action Search no longer calls it when selecting the current command block.

- [ ] **Step 2: Add a widget regression that would fail with the old range rebuild**

Add this test near the existing Action Search command block tests in `example/test/widget_test.dart`:

```dart
  testWidgets(
    'action search copies block output from command block snapshot without prompt range rebuild',
    (tester) async {
      final fakeBindings = FakePtyBackend();
      String? copiedText;

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': copiedText};
          }
          if (methodCall.method == 'Clipboard.setData') {
            copiedText = (methodCall.arguments as Map)['text'] as String?;
            return null;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _pumpShellScreen(
        tester,
        bindings: fakeBindings,
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      fakeBindings.setFrame(1, {
        'rows': [
          {'index': 10, 'text': r'$ false', 'style_runs': const []},
          {'index': 11, 'text': 'failed output', 'style_runs': const []},
          {'index': 12, 'text': 'still failed', 'style_runs': const []},
        ],
        'cursor': {'row': 12, 'col': 12, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 10, 'end': 13},
        ],
        'viewport_start_row': 10,
        'scrollback_offset': 0,
        'scrollback_max_offset': 20,
      });
      fakeBindings.enqueueEvent(
        1,
        PtyEvent(
          kind: 'shell_hook',
          sessionId: '1',
          payload: const <String, Object?>{
            'hook': 'preexec',
            'command': 'false',
            'prompt_scrollback_offset': 10,
            'pwd': '/tmp/project',
          },
        ),
      );
      fakeBindings.enqueueEvent(
        1,
        PtyEvent(
          kind: 'shell_hook',
          sessionId: '1',
          payload: const <String, Object?>{
            'hook': 'command_finished',
            'command': 'false',
            'pwd': '/tmp/project',
            'exit_code': 1,
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      await _openCommandMenu(tester);
      await tester.enterText(
        find.byKey(const Key('shell-command-search-field')),
        'action search',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('command-action-search-overlay-field')),
        'copy block output',
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(copiedText, 'failed output\nstill failed');
      expect(fakeBindings.writes, isEmpty);
    },
  );
```

- [ ] **Step 3: Run the new widget test**

Run:

```bash
cd example
flutter test test/widget_test.dart --plain-name "action search copies block output from command block snapshot without prompt range rebuild"
```

Expected: PASS after Step 1; FAIL before Step 1 with "No command block is selected" or empty copied text.

- [ ] **Step 4: Run existing selected-block Action Search test**

Run:

```bash
cd example
flutter test test/widget_test.dart --plain-name "action search prefers selected block over newest block without shell write"
```

Expected: PASS.

---

### Task 5: Cleanup and Guardrails

**Files:**
- Modify only if needed: `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- Modify only if needed: `example/lib/features/shell/shell_screen_state_context_chips.dart`
- Modify only if needed: `docs/superpowers/specs/2026-06-16-command-block-command-center-fusion-design.md`

- [ ] **Step 1: Check for remaining active block lookup through `blockRangeState`**

Run:

```bash
rg -n "blockRangeState|_commandBlockRangesForSession|CommandBlockRangeState" example/lib/features/shell example/lib/features/command_center
```

Expected:

- `CommandCenterRuntime.blockRangeState(...)` may still exist as a legacy API.
- Tests for legacy Command Center block models may still exist.
- `_activeCommandActionSearchBlock(...)`, `_contextChipBlockFor(...)`, and `_contextChipsForPane(...)` must not call `blockRangeState(...)`.

- [ ] **Step 2: Remove unused imports or fields**

If `_commandCenterContextWiring` becomes unused in `ShellScreen`, remove:

```dart
import '../command_center/command_center_context_wiring.dart';
```

and remove the field:

```dart
  final CommandCenterContextWiring _commandCenterContextWiring =
      const CommandCenterContextWiring();
```

Only remove them after `flutter analyze` proves they are unused.

- [ ] **Step 3: Run focused tests**

Run:

```bash
cd example
flutter test test/command_center/shell_command_block_command_center_adapter_test.dart
flutter test test/widget_test.dart --plain-name "action search copies block output from command block snapshot without prompt range rebuild"
flutter test test/widget_test.dart --plain-name "action search prefers selected block over newest block without shell write"
flutter test test/widget_test.dart --plain-name "context chip navigates to the last failed command block"
flutter test test/widget_test.dart --plain-name "selected block chip opens block actions without shell write"
```

Expected: all PASS.

- [ ] **Step 4: Run example analyzer**

Run:

```bash
cd example
flutter analyze
```

Expected: no issues.

- [ ] **Step 5: Commit implementation**

Run:

```bash
git add example/lib/features/command_center/shell_command_block_command_center_adapter.dart \
  example/test/command_center/shell_command_block_command_center_adapter_test.dart \
  example/lib/features/shell/shell_screen.dart \
  example/lib/features/shell/shell_screen_state_context_chips.dart \
  example/lib/features/shell/shell_screen_state_command_action_search.dart \
  example/test/widget_test.dart
git commit -m "Use command block snapshot for command center block actions"
```

Expected: commit succeeds.

---

## Self-Review

- Spec coverage:
  - Command Blocks as source of truth: covered by Tasks 1, 2, 3, and 4.
  - Command Center consumes via adapter: covered by Task 2.
  - Action Search block actions use the same block id/range as overlay and History Peek: covered by Task 4 widget regression.
  - Context chips use Command Blocks state: covered by Task 3.
  - First batch keeps legacy reducer compatible instead of deleting all models: covered by Task 2 and Task 5.
- Placeholder scan:
  - No placeholder markers or unspecified "add tests" instructions.
- Type consistency:
  - Adapter returns existing `CommandBlock` compatibility targets.
  - Row conversion is inclusive `ShellCommandBlockRange.outputEndRow` to exclusive `CommandBlockRowRange.endRowExclusive`.
  - Status conversion maps `ShellCommandBlockStatus` to `CommandInvocationStatus`.
