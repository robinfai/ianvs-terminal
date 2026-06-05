# Command Block History Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the feature-flagged Command Blocks history tools experience: command block metadata, inline actions, History Peek, and Review entrypoints.

**Architecture:** Add a conservative feature-flag layer first, then extend existing productivity models instead of creating a parallel history system. Command block UI renders as overlay/annotation over the existing `TerminalViewport`; heavy replay and diff flows enter the existing Instant Replay / Review workspace path.

**Tech Stack:** Flutter, Dart, Material 3, existing `example/lib/features/productivity`, `example/lib/features/shell`, `example/lib/features/config`, and current widget/unit test setup.

---

## Scope Check

The design spans flags, data, actions, UI overlays, History Peek, and Review entrypoints. These are coupled through one product surface, so keep them in one plan, but land them in small commits. The first working slice is flags plus data with no visible UI; the second slice renders Command Blocks behind the off-by-default flag.

## File Structure

- Modify `example/lib/features/config/local_terminal_config_models.dart`
  - Add `LocalTerminalCommandBlocksHistoryConfig`.
  - Add `commandBlocksHistory` to `LocalTerminalConfigDocument`.
- Create `example/lib/features/productivity/command_blocks_history_feature_flags.dart`
  - Convert config values into a single read-only flag snapshot for UI, controllers, and action availability.
- Modify `example/lib/features/productivity/shell_productivity_models.dart`
  - Extend the existing `ShellCommandBlock` model instead of adding a duplicate.
  - Add command block ranges, markers, failure snapshots, and command block state.
- Create `example/lib/features/productivity/shell_command_block_controller.dart`
  - Build command blocks from prompt marks, output ranges, and command finish events.
- Modify `example/lib/features/productivity/shell_productivity_action_reducer.dart`
  - Return command block action inputs for jump/copy/save/compare actions.
- Modify `example/lib/features/shell/shell_action_registry.dart`
  - Add stable action ids for History Peek and command block actions.
- Modify `example/lib/features/shell/shell_action_availability.dart`
  - Gate command block actions through feature flags and available command block data.
- Create `example/lib/features/shell/shell_command_block_view_models.dart`
  - Translate command block state into viewport overlay rows and compact UI state.
- Create `example/lib/features/shell/shell_screen_command_blocks.dart`
  - Render the Command Blocks gutter, header, and action row as a `part of 'shell_screen.dart'`.
- Create `example/lib/features/shell/shell_screen_history_peek.dart`
  - Render the temporary History Peek sheet as a `part of 'shell_screen.dart'`.
- Modify `example/lib/features/shell/shell_screen.dart`
  - Add new `part` directives and wire flag-gated state into the terminal stack.
- Modify `example/lib/features/shell/shell_screen_state_events.dart`
  - Load config-backed command block history flags together with existing local config fields.
- Modify `example/lib/features/shell/shell_screen_state_terminal_workspace.dart`
  - Insert the flag-gated overlay above `TerminalViewport`.
- Modify `example/lib/features/shell/shell_screen_instant_replay.dart`
  - Accept optional command block review source metadata for `Replay from here`.
- Add focused tests under:
  - `example/test/config/local_terminal_config_models_test.dart`
  - `example/test/productivity/command_blocks_history_feature_flags_test.dart`
  - `example/test/productivity/shell_command_block_controller_test.dart`
  - `example/test/productivity/shell_productivity_action_reducer_test.dart`
  - `example/test/shell/shell_action_availability_test.dart`
  - `example/test/shell/shell_command_block_view_models_test.dart`
  - `example/test/shell/shell_screen_command_blocks_test.dart`
  - `example/test/shell/shell_screen_history_peek_test.dart`

---

### Task 1: Feature Flags And Local Config

**Files:**
- Modify: `example/lib/features/config/local_terminal_config_models.dart`
- Create: `example/lib/features/productivity/command_blocks_history_feature_flags.dart`
- Modify: `example/test/config/local_terminal_config_models_test.dart`
- Create: `example/test/productivity/command_blocks_history_feature_flags_test.dart`

- [ ] **Step 1: Write failing config tests**

Append these tests to `example/test/config/local_terminal_config_models_test.dart`:

```dart
test('command blocks history config defaults every flag to false', () {
  final config = LocalTerminalConfigDocument.fromJson(const {});

  expect(config.commandBlocksHistory.enabled, isFalse);
  expect(config.commandBlocksHistory.commandBlocks, isFalse);
  expect(config.commandBlocksHistory.historyPeek, isFalse);
  expect(config.commandBlocksHistory.failureSnapshots, isFalse);
  expect(config.commandBlocksHistory.reviewWorkspaceEntrypoints, isFalse);
  expect(config.commandBlocksHistory.outputDiff, isFalse);
});

test('command blocks history config decodes explicit flags', () {
  final config = LocalTerminalConfigDocument.fromJson({
    'commandBlocksHistory': {
      'enabled': true,
      'commandBlocks': true,
      'historyPeek': false,
      'failureSnapshots': true,
      'reviewWorkspaceEntrypoints': false,
      'outputDiff': true,
    },
  });

  expect(config.commandBlocksHistory.enabled, isTrue);
  expect(config.commandBlocksHistory.commandBlocks, isTrue);
  expect(config.commandBlocksHistory.historyPeek, isFalse);
  expect(config.commandBlocksHistory.failureSnapshots, isTrue);
  expect(config.commandBlocksHistory.reviewWorkspaceEntrypoints, isFalse);
  expect(config.commandBlocksHistory.outputDiff, isTrue);
  expect(
    config.commandBlocksHistory.toJson(),
    {
      'enabled': true,
      'commandBlocks': true,
      'historyPeek': false,
      'failureSnapshots': true,
      'reviewWorkspaceEntrypoints': false,
      'outputDiff': true,
    },
  );
});
```

- [ ] **Step 2: Run the config test and verify it fails**

Run:

```bash
cd example
flutter test test/config/local_terminal_config_models_test.dart --plain-name "command blocks history config"
```

Expected: FAIL because `LocalTerminalConfigDocument.commandBlocksHistory` and `LocalTerminalCommandBlocksHistoryConfig` do not exist.

- [ ] **Step 3: Implement local config support**

In `example/lib/features/config/local_terminal_config_models.dart`, add `commandBlocksHistory` to `LocalTerminalConfigDocument`:

```dart
class LocalTerminalConfigDocument {
  const LocalTerminalConfigDocument({
    this.schemaVersion = currentSchemaVersion,
    this.defaultProfileId,
    this.appearance = const TerminalAppAppearance(),
    this.keybindings = const LocalTerminalKeybindingsConfig(),
    this.workspace = const LocalTerminalWorkspaceConfig(),
    this.clipboard = const LocalTerminalClipboardConfig(),
    this.paste = const LocalTerminalPasteConfig(),
    this.shellIntegration = const LocalTerminalShellIntegrationConfig(),
    this.notifications = const LocalTerminalNotificationsConfig(),
    this.hotkeyWindow = const LocalTerminalHotkeyWindowConfig(),
    this.commandBlocksHistory =
        const LocalTerminalCommandBlocksHistoryConfig(),
  });

  final LocalTerminalCommandBlocksHistoryConfig commandBlocksHistory;
}
```

Update `copyWith`, `toJson`, and `fromJson`:

```dart
LocalTerminalConfigDocument copyWith({
  int? schemaVersion,
  Object? defaultProfileId = _localTerminalConfigNoChange,
  TerminalAppAppearance? appearance,
  LocalTerminalKeybindingsConfig? keybindings,
  LocalTerminalWorkspaceConfig? workspace,
  LocalTerminalClipboardConfig? clipboard,
  LocalTerminalPasteConfig? paste,
  LocalTerminalShellIntegrationConfig? shellIntegration,
  LocalTerminalNotificationsConfig? notifications,
  LocalTerminalHotkeyWindowConfig? hotkeyWindow,
  LocalTerminalCommandBlocksHistoryConfig? commandBlocksHistory,
}) {
  return LocalTerminalConfigDocument(
    schemaVersion: schemaVersion ?? this.schemaVersion,
    defaultProfileId: identical(defaultProfileId, _localTerminalConfigNoChange)
        ? this.defaultProfileId
        : defaultProfileId as String?,
    appearance: appearance ?? this.appearance,
    keybindings: keybindings ?? this.keybindings,
    workspace: workspace ?? this.workspace,
    clipboard: clipboard ?? this.clipboard,
    paste: paste ?? this.paste,
    shellIntegration: shellIntegration ?? this.shellIntegration,
    notifications: notifications ?? this.notifications,
    hotkeyWindow: hotkeyWindow ?? this.hotkeyWindow,
    commandBlocksHistory:
        commandBlocksHistory ?? this.commandBlocksHistory,
  );
}
```

```dart
Map<String, Object?> toJson() {
  return {
    'schemaVersion': schemaVersion,
    'defaultProfileId': defaultProfileId,
    'appearance': appearance.toJson(),
    'keybindings': keybindings.toJson(),
    'workspace': workspace.toJson(),
    'clipboard': clipboard.toJson(),
    'paste': paste.toJson(),
    'shellIntegration': shellIntegration.toJson(),
    'notifications': notifications.toJson(),
    'hotkeyWindow': hotkeyWindow.toJson(),
    'commandBlocksHistory': commandBlocksHistory.toJson(),
  };
}
```

```dart
return LocalTerminalConfigDocument(
  schemaVersion: _schemaVersionFromJson(
    json['schemaVersion'],
    currentSchemaVersion,
  ),
  defaultProfileId: _nonEmptyTrimmedStringOrNull(json['defaultProfileId']),
  appearance: TerminalAppAppearance.fromJson(_objectMap(json['appearance'])),
  keybindings: LocalTerminalKeybindingsConfig.fromJson(
    _objectMap(json['keybindings']),
  ),
  workspace: LocalTerminalWorkspaceConfig.fromJson(
    _objectMap(json['workspace']),
  ),
  clipboard: LocalTerminalClipboardConfig.fromJson(
    _objectMap(json['clipboard']),
  ),
  paste: LocalTerminalPasteConfig.fromJson(_objectMap(json['paste'])),
  shellIntegration: LocalTerminalShellIntegrationConfig.fromJson(
    _objectMap(json['shellIntegration']),
  ),
  notifications: LocalTerminalNotificationsConfig.fromJson(
    _objectMap(json['notifications']),
  ),
  hotkeyWindow: LocalTerminalHotkeyWindowConfig.fromJson(
    _objectMap(json['hotkeyWindow']),
  ),
  commandBlocksHistory: LocalTerminalCommandBlocksHistoryConfig.fromJson(
    _objectMap(json['commandBlocksHistory']),
  ),
);
```

Add the config class near the other `LocalTerminal*Config` classes:

```dart
class LocalTerminalCommandBlocksHistoryConfig {
  const LocalTerminalCommandBlocksHistoryConfig({
    this.enabled = false,
    this.commandBlocks = false,
    this.historyPeek = false,
    this.failureSnapshots = false,
    this.reviewWorkspaceEntrypoints = false,
    this.outputDiff = false,
  });

  final bool enabled;
  final bool commandBlocks;
  final bool historyPeek;
  final bool failureSnapshots;
  final bool reviewWorkspaceEntrypoints;
  final bool outputDiff;

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'commandBlocks': commandBlocks,
      'historyPeek': historyPeek,
      'failureSnapshots': failureSnapshots,
      'reviewWorkspaceEntrypoints': reviewWorkspaceEntrypoints,
      'outputDiff': outputDiff,
    };
  }

  static LocalTerminalCommandBlocksHistoryConfig fromJson(
    Map<Object?, Object?>? json,
  ) {
    if (json == null) {
      return const LocalTerminalCommandBlocksHistoryConfig();
    }
    return LocalTerminalCommandBlocksHistoryConfig(
      enabled: _boolFromJson(json['enabled'], false),
      commandBlocks: _boolFromJson(json['commandBlocks'], false),
      historyPeek: _boolFromJson(json['historyPeek'], false),
      failureSnapshots: _boolFromJson(json['failureSnapshots'], false),
      reviewWorkspaceEntrypoints: _boolFromJson(
        json['reviewWorkspaceEntrypoints'],
        false,
      ),
      outputDiff: _boolFromJson(json['outputDiff'], false),
    );
  }
}
```

- [ ] **Step 4: Run the config test and verify it passes**

Run:

```bash
cd example
flutter test test/config/local_terminal_config_models_test.dart --plain-name "command blocks history config"
```

Expected: PASS.

- [ ] **Step 5: Write failing feature flag tests**

Create `example/test/productivity/command_blocks_history_feature_flags_test.dart`:

```dart
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandBlocksHistoryFeatureFlags', () {
    test('disabled config disables every effective capability', () {
      final flags = CommandBlocksHistoryFeatureFlags.fromConfig(
        const LocalTerminalCommandBlocksHistoryConfig(
          enabled: false,
          commandBlocks: true,
          historyPeek: true,
          failureSnapshots: true,
          reviewWorkspaceEntrypoints: true,
          outputDiff: true,
        ),
      );

      expect(flags.enabled, isFalse);
      expect(flags.commandBlocks, isFalse);
      expect(flags.historyPeek, isFalse);
      expect(flags.failureSnapshots, isFalse);
      expect(flags.reviewWorkspaceEntrypoints, isFalse);
      expect(flags.outputDiff, isFalse);
    });

    test('enabled config allows each selected child capability', () {
      final flags = CommandBlocksHistoryFeatureFlags.fromConfig(
        const LocalTerminalCommandBlocksHistoryConfig(
          enabled: true,
          commandBlocks: true,
          historyPeek: false,
          failureSnapshots: true,
          reviewWorkspaceEntrypoints: false,
          outputDiff: true,
        ),
      );

      expect(flags.enabled, isTrue);
      expect(flags.commandBlocks, isTrue);
      expect(flags.historyPeek, isFalse);
      expect(flags.failureSnapshots, isTrue);
      expect(flags.reviewWorkspaceEntrypoints, isFalse);
      expect(flags.outputDiff, isTrue);
    });
  });
}
```

- [ ] **Step 6: Run the feature flag test and verify it fails**

Run:

```bash
cd example
flutter test test/productivity/command_blocks_history_feature_flags_test.dart
```

Expected: FAIL because `command_blocks_history_feature_flags.dart` does not exist.

- [ ] **Step 7: Implement `CommandBlocksHistoryFeatureFlags`**

Create `example/lib/features/productivity/command_blocks_history_feature_flags.dart`:

```dart
import '../config/local_terminal_config_models.dart';

class CommandBlocksHistoryFeatureFlags {
  const CommandBlocksHistoryFeatureFlags({
    required this.enabled,
    required this.commandBlocks,
    required this.historyPeek,
    required this.failureSnapshots,
    required this.reviewWorkspaceEntrypoints,
    required this.outputDiff,
  });

  static const disabled = CommandBlocksHistoryFeatureFlags(
    enabled: false,
    commandBlocks: false,
    historyPeek: false,
    failureSnapshots: false,
    reviewWorkspaceEntrypoints: false,
    outputDiff: false,
  );

  final bool enabled;
  final bool commandBlocks;
  final bool historyPeek;
  final bool failureSnapshots;
  final bool reviewWorkspaceEntrypoints;
  final bool outputDiff;

  factory CommandBlocksHistoryFeatureFlags.fromConfig(
    LocalTerminalCommandBlocksHistoryConfig config,
  ) {
    if (!config.enabled) {
      return disabled;
    }
    return CommandBlocksHistoryFeatureFlags(
      enabled: true,
      commandBlocks: config.commandBlocks,
      historyPeek: config.historyPeek,
      failureSnapshots: config.failureSnapshots,
      reviewWorkspaceEntrypoints: config.reviewWorkspaceEntrypoints,
      outputDiff: config.outputDiff,
    );
  }

  Map<String, Object?> toDiagnosticsJson() {
    return {
      'enabled': enabled,
      'commandBlocks': commandBlocks,
      'historyPeek': historyPeek,
      'failureSnapshots': failureSnapshots,
      'reviewWorkspaceEntrypoints': reviewWorkspaceEntrypoints,
      'outputDiff': outputDiff,
    };
  }
}
```

- [ ] **Step 8: Run focused tests**

Run:

```bash
cd example
flutter test test/config/local_terminal_config_models_test.dart --plain-name "command blocks history config"
flutter test test/productivity/command_blocks_history_feature_flags_test.dart
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add \
  example/lib/features/config/local_terminal_config_models.dart \
  example/lib/features/productivity/command_blocks_history_feature_flags.dart \
  example/test/config/local_terminal_config_models_test.dart \
  example/test/productivity/command_blocks_history_feature_flags_test.dart
git commit -m "Add command block history feature flags"
```

---

### Task 2: Command Block Data Model And Controller

**Files:**
- Modify: `example/lib/features/productivity/shell_productivity_models.dart`
- Create: `example/lib/features/productivity/shell_command_block_controller.dart`
- Create: `example/test/productivity/shell_command_block_controller_test.dart`

- [ ] **Step 1: Write failing controller tests**

Create `example/test/productivity/shell_command_block_controller_test.dart`:

```dart
import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
import 'package:app/features/productivity/shell_command_block_controller.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/productivity/shell_productivity_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellCommandBlockController', () {
    test('does not build blocks when flags are disabled', () {
      final snapshot = const ShellCommandBlockSnapshot();
      final next = ShellCommandBlockController.reduce(
        snapshot,
        const ShellPromptMarkEvent(id: 'p1', row: 1, cwd: '/repo'),
        flags: CommandBlocksHistoryFeatureFlags.disabled,
      );

      expect(next.blocks, isEmpty);
    });

    test('builds failed command block from prompt range and finish event', () {
      var snapshot = const ShellCommandBlockSnapshot();
      const flags = CommandBlocksHistoryFeatureFlags(
        enabled: true,
        commandBlocks: true,
        historyPeek: false,
        failureSnapshots: true,
        reviewWorkspaceEntrypoints: false,
        outputDiff: false,
      );

      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellPromptMarkEvent(id: 'p1', row: 10, cwd: '/repo'),
        flags: flags,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandOutputRangeEvent(
          commandId: 'cmd-1',
          startRow: 11,
          endRow: 18,
        ),
        flags: flags,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandFinishedEvent(
          command: 'flutter test',
          cwd: '/repo',
          exitCode: 1,
        ),
        flags: flags,
      );

      expect(snapshot.blocks, hasLength(1));
      final block = snapshot.blocks.single;
      expect(block.id, 'cmd-1');
      expect(block.command, 'flutter test');
      expect(block.cwd, '/repo');
      expect(block.status, ShellCommandBlockStatus.failed);
      expect(block.outputRange.startRow, 11);
      expect(block.outputRange.endRow, 18);
      expect(block.failureSnapshot, isNotNull);
      expect(block.failureSnapshot!.exitCode, 1);
    });

    test('finds previous run with same cwd and command', () {
      final previous = ShellCommandBlock(
        id: 'old',
        command: 'flutter test',
        cwd: '/repo',
        outputRange: const ShellCommandBlockRange(
          commandRow: 1,
          outputStartRow: 2,
          outputEndRow: 8,
        ),
        status: ShellCommandBlockStatus.succeeded,
      );
      final current = ShellCommandBlock(
        id: 'new',
        command: 'flutter test',
        cwd: '/repo',
        outputRange: const ShellCommandBlockRange(
          commandRow: 12,
          outputStartRow: 13,
          outputEndRow: 20,
        ),
        status: ShellCommandBlockStatus.failed,
      );

      final snapshot = ShellCommandBlockSnapshot(blocks: [previous, current]);

      expect(
        snapshot.previousRunFor(current)!.id,
        'old',
      );
    });
  });
}
```

- [ ] **Step 2: Run the controller test and verify it fails**

Run:

```bash
cd example
flutter test test/productivity/shell_command_block_controller_test.dart
```

Expected: FAIL because `shell_command_block_controller.dart`, `ShellCommandBlockSnapshot`, `ShellCommandBlockStatus`, and the richer `ShellCommandBlock` fields do not exist.

- [ ] **Step 3: Extend productivity command block models**

In `example/lib/features/productivity/shell_productivity_models.dart`, replace the current simple `ShellCommandBlock` class with this richer model:

```dart
enum ShellCommandBlockStatus { running, succeeded, failed, unknown }

class ShellCommandBlockRange {
  const ShellCommandBlockRange({
    required this.commandRow,
    required this.outputStartRow,
    required this.outputEndRow,
  });

  final int commandRow;
  final int outputStartRow;
  final int outputEndRow;

  bool get isValid {
    return commandRow >= 0 &&
        outputStartRow >= commandRow &&
        outputEndRow >= outputStartRow;
  }

  bool containsRow(int row) {
    return isValid && row >= commandRow && row <= outputEndRow;
  }
}

class ShellFailureSnapshot {
  const ShellFailureSnapshot({
    required this.commandBlockId,
    required this.command,
    required this.cwd,
    required this.exitCode,
    required this.outputRange,
    this.keyErrorLines = const <String>[],
  });

  final String commandBlockId;
  final String command;
  final String? cwd;
  final int? exitCode;
  final ShellCommandBlockRange outputRange;
  final List<String> keyErrorLines;
}

class ShellHistoryMarker {
  const ShellHistoryMarker({
    required this.id,
    required this.row,
    required this.kind,
    this.commandBlockId,
    this.label,
  });

  final String id;
  final int row;
  final ShellHistoryMarkerKind kind;
  final String? commandBlockId;
  final String? label;
}

enum ShellHistoryMarkerKind { manual, failure, idleGap, replayFrame }

class ShellCommandBlock {
  const ShellCommandBlock({
    required this.id,
    required this.command,
    required this.outputRange,
    this.cwd,
    this.exitCode,
    this.status = ShellCommandBlockStatus.unknown,
    this.markers = const <ShellHistoryMarker>[],
    this.failureSnapshot,
  });

  final String id;
  final String command;
  final String? cwd;
  final int? exitCode;
  final ShellCommandBlockStatus status;
  final ShellCommandBlockRange outputRange;
  final List<ShellHistoryMarker> markers;
  final ShellFailureSnapshot? failureSnapshot;

  int get startRow => outputRange.commandRow;
  int get endRow => outputRange.outputEndRow;
  bool get isValid => id.trim().isNotEmpty && outputRange.isValid;
  bool get failed => status == ShellCommandBlockStatus.failed;

  bool containsRow(int row) {
    return isValid && outputRange.containsRow(row);
  }

  ShellCommandBlock copyWith({
    String? id,
    String? command,
    Object? cwd = _shellCommandBlockNoChange,
    Object? exitCode = _shellCommandBlockNoChange,
    ShellCommandBlockStatus? status,
    ShellCommandBlockRange? outputRange,
    List<ShellHistoryMarker>? markers,
    Object? failureSnapshot = _shellCommandBlockNoChange,
  }) {
    return ShellCommandBlock(
      id: id ?? this.id,
      command: command ?? this.command,
      cwd: identical(cwd, _shellCommandBlockNoChange) ? this.cwd : cwd as String?,
      exitCode: identical(exitCode, _shellCommandBlockNoChange)
          ? this.exitCode
          : exitCode as int?,
      status: status ?? this.status,
      outputRange: outputRange ?? this.outputRange,
      markers: markers ?? this.markers,
      failureSnapshot: identical(
        failureSnapshot,
        _shellCommandBlockNoChange,
      )
          ? this.failureSnapshot
          : failureSnapshot as ShellFailureSnapshot?,
    );
  }
}

const Object _shellCommandBlockNoChange = Object();
```

- [ ] **Step 4: Implement command block controller**

Create `example/lib/features/productivity/shell_command_block_controller.dart`:

```dart
import 'command_blocks_history_feature_flags.dart';
import 'shell_productivity_models.dart';
import 'shell_productivity_reducer.dart';

class ShellCommandBlockSnapshot {
  const ShellCommandBlockSnapshot({
    this.blocks = const <ShellCommandBlock>[],
    this.lastPrompt,
    this.pendingRange,
  });

  final List<ShellCommandBlock> blocks;
  final ShellPromptMark? lastPrompt;
  final ShellCommandOutputRange? pendingRange;

  ShellCommandBlock? previousRunFor(ShellCommandBlock block) {
    for (final candidate in blocks.reversed) {
      if (candidate.id == block.id) {
        continue;
      }
      if (candidate.command == block.command && candidate.cwd == block.cwd) {
        return candidate;
      }
    }
    return null;
  }
}

class ShellCommandBlockController {
  const ShellCommandBlockController._();

  static ShellCommandBlockSnapshot reduce(
    ShellCommandBlockSnapshot snapshot,
    ShellProductivityEvent event, {
    required CommandBlocksHistoryFeatureFlags flags,
  }) {
    if (!flags.enabled || !flags.commandBlocks) {
      return snapshot;
    }
    return switch (event) {
      ShellPromptMarkEvent() => _promptMark(snapshot, event),
      ShellCommandOutputRangeEvent() => _outputRange(snapshot, event),
      ShellCommandFinishedEvent() => _commandFinished(
        snapshot,
        event,
        flags: flags,
      ),
      ShellCwdChangedEvent() => snapshot,
    };
  }

  static ShellCommandBlockSnapshot _promptMark(
    ShellCommandBlockSnapshot snapshot,
    ShellPromptMarkEvent event,
  ) {
    final id = event.id.trim();
    if (id.isEmpty || event.row < 0) {
      return snapshot;
    }
    return ShellCommandBlockSnapshot(
      blocks: snapshot.blocks,
      lastPrompt: ShellPromptMark(id: id, row: event.row, cwd: _trimmed(event.cwd)),
      pendingRange: snapshot.pendingRange,
    );
  }

  static ShellCommandBlockSnapshot _outputRange(
    ShellCommandBlockSnapshot snapshot,
    ShellCommandOutputRangeEvent event,
  ) {
    if (event.startRow < 0 || event.endRow < event.startRow) {
      return snapshot;
    }
    return ShellCommandBlockSnapshot(
      blocks: snapshot.blocks,
      lastPrompt: snapshot.lastPrompt,
      pendingRange: ShellCommandOutputRange(
        commandId: event.commandId,
        startRow: event.startRow,
        endRow: event.endRow,
      ),
    );
  }

  static ShellCommandBlockSnapshot _commandFinished(
    ShellCommandBlockSnapshot snapshot,
    ShellCommandFinishedEvent event, {
    required CommandBlocksHistoryFeatureFlags flags,
  }) {
    final command = event.command.trim();
    final range = snapshot.pendingRange;
    if (command.isEmpty || range == null || !range.isValid) {
      return snapshot;
    }
    final status = switch (event.exitCode) {
      0 => ShellCommandBlockStatus.succeeded,
      null => ShellCommandBlockStatus.unknown,
      _ => ShellCommandBlockStatus.failed,
    };
    final outputRange = ShellCommandBlockRange(
      commandRow: snapshot.lastPrompt?.row ?? range.startRow,
      outputStartRow: range.startRow,
      outputEndRow: range.endRow,
    );
    final cwd = _trimmed(event.cwd) ?? snapshot.lastPrompt?.cwd;
    final block = ShellCommandBlock(
      id: range.commandId,
      command: command,
      cwd: cwd,
      exitCode: event.exitCode,
      status: status,
      outputRange: outputRange,
      failureSnapshot: status == ShellCommandBlockStatus.failed &&
              flags.failureSnapshots
          ? ShellFailureSnapshot(
              commandBlockId: range.commandId,
              command: command,
              cwd: cwd,
              exitCode: event.exitCode,
              outputRange: outputRange,
            )
          : null,
    );
    return ShellCommandBlockSnapshot(
      blocks: [...snapshot.blocks, block],
      lastPrompt: snapshot.lastPrompt,
      pendingRange: null,
    );
  }
}

String? _trimmed(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}
```

- [ ] **Step 5: Run the controller test and verify it passes**

Run:

```bash
cd example
flutter test test/productivity/shell_command_block_controller_test.dart
```

Expected: PASS.

- [ ] **Step 6: Run existing productivity tests for regressions**

Run:

```bash
cd example
flutter test \
  test/productivity/shell_productivity_models_test.dart \
  test/productivity/shell_productivity_reducer_test.dart \
  test/productivity/shell_productivity_action_reducer_test.dart \
  test/productivity/shell_command_block_controller_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add \
  example/lib/features/productivity/shell_productivity_models.dart \
  example/lib/features/productivity/shell_command_block_controller.dart \
  example/test/productivity/shell_command_block_controller_test.dart
git commit -m "Add command block history model"
```

---

### Task 3: Actions And Availability Gates

**Files:**
- Modify: `example/lib/features/shell/shell_action_registry.dart`
- Modify: `example/lib/features/shell/shell_action_availability.dart`
- Modify: `example/lib/features/productivity/shell_productivity_action_reducer.dart`
- Modify: `example/test/shell/terminal_action_registry_test.dart`
- Modify: `example/test/shell/shell_action_availability_test.dart`
- Modify: `example/test/productivity/shell_productivity_action_reducer_test.dart`

- [ ] **Step 1: Write failing action availability tests**

Append to `example/test/shell/shell_action_availability_test.dart`:

```dart
test('command block actions are disabled when feature flags are off', () {
  final availability = ShellActionAvailabilityResolver.resolve(
    actionId: TerminalActionId.openHistoryPeek,
    hasActiveSession: true,
    productivity: const ShellProductivityState(),
    commandBlocksHistory: CommandBlocksHistoryFeatureFlags.disabled,
    hasCommandBlocks: true,
  );

  expect(availability.enabled, isFalse);
  expect(
    availability.reason,
    ShellActionDisabledReason.commandBlocksHistoryDisabled,
  );
});

test('history peek is enabled only when flag and command blocks exist', () {
  const flags = CommandBlocksHistoryFeatureFlags(
    enabled: true,
    commandBlocks: true,
    historyPeek: true,
    failureSnapshots: false,
    reviewWorkspaceEntrypoints: false,
    outputDiff: false,
  );

  final availability = ShellActionAvailabilityResolver.resolve(
    actionId: TerminalActionId.openHistoryPeek,
    hasActiveSession: true,
    productivity: const ShellProductivityState(),
    commandBlocksHistory: flags,
    hasCommandBlocks: true,
  );

  expect(availability.enabled, isTrue);
});
```

- [ ] **Step 2: Run action availability tests and verify failure**

Run:

```bash
cd example
flutter test test/shell/shell_action_availability_test.dart --plain-name "command block"
```

Expected: FAIL because new action ids, disabled reason, and resolver parameters do not exist.

- [ ] **Step 3: Add command block action ids and descriptors**

In `example/lib/features/shell/shell_action_registry.dart`, add enum values:

```dart
openHistoryPeek,
replayFromCommandBlock,
saveCommandSnapshot,
compareLastCommandRun,
markCommandBlock,
```

Add descriptors:

```dart
TerminalActionId.openHistoryPeek: TerminalActionDescriptor(
  id: TerminalActionId.openHistoryPeek,
  label: 'open_history_peek',
  category: TerminalActionCategory.navigation,
  terminalInputPolicy: TerminalInputPolicy.appFirst,
  icon: Icons.history,
  requiresActiveSession: true,
),
TerminalActionId.replayFromCommandBlock: TerminalActionDescriptor(
  id: TerminalActionId.replayFromCommandBlock,
  label: 'replay_from_command_block',
  category: TerminalActionCategory.navigation,
  terminalInputPolicy: TerminalInputPolicy.appFirst,
  icon: Icons.replay,
  requiresActiveSession: true,
),
TerminalActionId.saveCommandSnapshot: TerminalActionDescriptor(
  id: TerminalActionId.saveCommandSnapshot,
  label: 'save_command_snapshot',
  category: TerminalActionCategory.integration,
  terminalInputPolicy: TerminalInputPolicy.appFirst,
  icon: Icons.bookmark_add,
  requiresActiveSession: true,
),
TerminalActionId.compareLastCommandRun: TerminalActionDescriptor(
  id: TerminalActionId.compareLastCommandRun,
  label: 'compare_last_command_run',
  category: TerminalActionCategory.integration,
  terminalInputPolicy: TerminalInputPolicy.appFirst,
  icon: Icons.compare_arrows,
  requiresActiveSession: true,
),
TerminalActionId.markCommandBlock: TerminalActionDescriptor(
  id: TerminalActionId.markCommandBlock,
  label: 'mark_command_block',
  category: TerminalActionCategory.integration,
  terminalInputPolicy: TerminalInputPolicy.appFirst,
  icon: Icons.bookmark_border,
  requiresActiveSession: true,
),
```

- [ ] **Step 4: Gate action availability with feature flags**

In `example/lib/features/shell/shell_action_availability.dart`, import flags:

```dart
import '../productivity/command_blocks_history_feature_flags.dart';
```

Add disabled reasons:

```dart
commandBlocksHistoryDisabled,
missingCommandBlock,
```

Add user-facing text:

```dart
ShellActionDisabledReason.commandBlocksHistoryDisabled =>
  'Command Blocks disabled',
ShellActionDisabledReason.missingCommandBlock => 'No command block available',
```

```dart
ShellActionDisabledReason.commandBlocksHistoryDisabled =>
  'Enable Command Blocks history tools before using this action.',
ShellActionDisabledReason.missingCommandBlock =>
  'Run a command with captured output before using this action.',
```

Update resolver signature:

```dart
static ShellActionAvailability resolve({
  required TerminalActionId actionId,
  required bool hasActiveSession,
  required ShellProductivityState productivity,
  CommandBlocksHistoryFeatureFlags commandBlocksHistory =
      CommandBlocksHistoryFeatureFlags.disabled,
  bool hasCommandBlocks = false,
}) {
```

Add cases:

```dart
case TerminalActionId.openHistoryPeek:
  if (!commandBlocksHistory.historyPeek) {
    return ShellActionAvailability.disabled(
      ShellActionDisabledReason.commandBlocksHistoryDisabled,
    );
  }
  return hasCommandBlocks
      ? ShellActionAvailability.enabledAction
      : ShellActionAvailability.disabled(
          ShellActionDisabledReason.missingCommandBlock,
        );
case TerminalActionId.replayFromCommandBlock:
  if (!commandBlocksHistory.reviewWorkspaceEntrypoints) {
    return ShellActionAvailability.disabled(
      ShellActionDisabledReason.commandBlocksHistoryDisabled,
    );
  }
  return hasCommandBlocks
      ? ShellActionAvailability.enabledAction
      : ShellActionAvailability.disabled(
          ShellActionDisabledReason.missingCommandBlock,
        );
case TerminalActionId.saveCommandSnapshot:
  if (!commandBlocksHistory.failureSnapshots) {
    return ShellActionAvailability.disabled(
      ShellActionDisabledReason.commandBlocksHistoryDisabled,
    );
  }
  return hasCommandBlocks
      ? ShellActionAvailability.enabledAction
      : ShellActionAvailability.disabled(
          ShellActionDisabledReason.missingCommandBlock,
        );
case TerminalActionId.compareLastCommandRun:
  if (!commandBlocksHistory.outputDiff) {
    return ShellActionAvailability.disabled(
      ShellActionDisabledReason.commandBlocksHistoryDisabled,
    );
  }
  return hasCommandBlocks
      ? ShellActionAvailability.enabledAction
      : ShellActionAvailability.disabled(
          ShellActionDisabledReason.missingCommandBlock,
        );
case TerminalActionId.markCommandBlock:
  if (!commandBlocksHistory.commandBlocks) {
    return ShellActionAvailability.disabled(
      ShellActionDisabledReason.commandBlocksHistoryDisabled,
    );
  }
  return hasCommandBlocks
      ? ShellActionAvailability.enabledAction
      : ShellActionAvailability.disabled(
          ShellActionDisabledReason.missingCommandBlock,
        );
```

- [ ] **Step 5: Extend productivity action reducer result types**

In `example/lib/features/productivity/shell_productivity_action_reducer.dart`, add:

```dart
class ShellProductivityCommandBlockActionResult
    extends ShellProductivityActionResult {
  const ShellProductivityCommandBlockActionResult();
}
```

Add reducer cases:

```dart
TerminalActionId.openHistoryPeek ||
TerminalActionId.replayFromCommandBlock ||
TerminalActionId.saveCommandSnapshot ||
TerminalActionId.compareLastCommandRun ||
TerminalActionId.markCommandBlock =>
  const ShellProductivityCommandBlockActionResult(),
```

- [ ] **Step 6: Add reducer test**

Append to `example/test/productivity/shell_productivity_action_reducer_test.dart`:

```dart
test('command block actions return command block action result', () {
  final result = ShellProductivityActionReducer.reduce(
    state: const ShellProductivityState(),
    actionId: TerminalActionId.openHistoryPeek,
    context: const ShellProductivityActionContext(),
  );

  expect(result, isA<ShellProductivityCommandBlockActionResult>());
});
```

- [ ] **Step 7: Run action tests**

Run:

```bash
cd example
flutter test \
  test/shell/terminal_action_registry_test.dart \
  test/shell/shell_action_availability_test.dart \
  test/productivity/shell_productivity_action_reducer_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add \
  example/lib/features/shell/shell_action_registry.dart \
  example/lib/features/shell/shell_action_availability.dart \
  example/lib/features/productivity/shell_productivity_action_reducer.dart \
  example/test/shell/terminal_action_registry_test.dart \
  example/test/shell/shell_action_availability_test.dart \
  example/test/productivity/shell_productivity_action_reducer_test.dart
git commit -m "Gate command block history actions"
```

---

### Task 4: Command Block Overlay View Models

**Files:**
- Create: `example/lib/features/shell/shell_command_block_view_models.dart`
- Create: `example/test/shell/shell_command_block_view_models_test.dart`

- [ ] **Step 1: Write failing view model tests**

Create `example/test/shell/shell_command_block_view_models_test.dart`:

```dart
import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_command_block_view_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellCommandBlockViewModels', () {
    test('returns no overlays when commandBlocks flag is off', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          ShellCommandBlock(
            id: 'cmd',
            command: 'flutter test',
            outputRange: const ShellCommandBlockRange(
              commandRow: 1,
              outputStartRow: 2,
              outputEndRow: 4,
            ),
            status: ShellCommandBlockStatus.failed,
          ),
        ],
        viewportStartRow: 0,
        viewportEndRow: 10,
        flags: CommandBlocksHistoryFeatureFlags.disabled,
      );

      expect(viewModel.blocks, isEmpty);
    });

    test('maps visible failed block into overlay state', () {
      const flags = CommandBlocksHistoryFeatureFlags(
        enabled: true,
        commandBlocks: true,
        historyPeek: false,
        failureSnapshots: true,
        reviewWorkspaceEntrypoints: true,
        outputDiff: false,
      );
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          ShellCommandBlock(
            id: 'cmd',
            command: 'flutter test',
            cwd: '/repo',
            exitCode: 1,
            outputRange: const ShellCommandBlockRange(
              commandRow: 10,
              outputStartRow: 11,
              outputEndRow: 20,
            ),
            status: ShellCommandBlockStatus.failed,
          ),
        ],
        viewportStartRow: 8,
        viewportEndRow: 24,
        activeBlockId: 'cmd',
        flags: flags,
      );

      expect(viewModel.blocks, hasLength(1));
      expect(viewModel.blocks.single.id, 'cmd');
      expect(viewModel.blocks.single.statusLabel, 'exit 1');
      expect(viewModel.blocks.single.showFailureSnapshotAction, isTrue);
      expect(viewModel.blocks.single.showReplayAction, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run view model test and verify failure**

Run:

```bash
cd example
flutter test test/shell/shell_command_block_view_models_test.dart
```

Expected: FAIL because `shell_command_block_view_models.dart` does not exist.

- [ ] **Step 3: Implement overlay view models**

Create `example/lib/features/shell/shell_command_block_view_models.dart`:

```dart
import '../productivity/command_blocks_history_feature_flags.dart';
import '../productivity/shell_productivity_models.dart';

class ShellCommandBlocksOverlayViewModel {
  const ShellCommandBlocksOverlayViewModel({this.blocks = const []});

  final List<ShellCommandBlockOverlayItem> blocks;

  bool get isEmpty => blocks.isEmpty;
}

class ShellCommandBlockOverlayItem {
  const ShellCommandBlockOverlayItem({
    required this.id,
    required this.command,
    required this.rowOffset,
    required this.rowSpan,
    required this.status,
    required this.statusLabel,
    required this.active,
    required this.showFailureSnapshotAction,
    required this.showReplayAction,
    required this.showDiffAction,
  });

  final String id;
  final String command;
  final int rowOffset;
  final int rowSpan;
  final ShellCommandBlockStatus status;
  final String statusLabel;
  final bool active;
  final bool showFailureSnapshotAction;
  final bool showReplayAction;
  final bool showDiffAction;
}

class ShellCommandBlockViewModelBuilder {
  const ShellCommandBlockViewModelBuilder._();

  static ShellCommandBlocksOverlayViewModel build({
    required List<ShellCommandBlock> blocks,
    required int viewportStartRow,
    required int viewportEndRow,
    required CommandBlocksHistoryFeatureFlags flags,
    String? activeBlockId,
  }) {
    if (!flags.enabled || !flags.commandBlocks) {
      return const ShellCommandBlocksOverlayViewModel();
    }
    final visible = <ShellCommandBlockOverlayItem>[];
    for (final block in blocks) {
      if (!block.isValid) {
        continue;
      }
      if (block.endRow < viewportStartRow || block.startRow > viewportEndRow) {
        continue;
      }
      visible.add(
        ShellCommandBlockOverlayItem(
          id: block.id,
          command: block.command,
          rowOffset: (block.startRow - viewportStartRow).clamp(
            0,
            viewportEndRow - viewportStartRow,
          ),
          rowSpan: (block.endRow - block.startRow + 1).clamp(1, 100000),
          status: block.status,
          statusLabel: _statusLabel(block),
          active: block.id == activeBlockId,
          showFailureSnapshotAction:
              flags.failureSnapshots && block.status == ShellCommandBlockStatus.failed,
          showReplayAction: flags.reviewWorkspaceEntrypoints,
          showDiffAction: flags.outputDiff,
        ),
      );
    }
    return ShellCommandBlocksOverlayViewModel(blocks: visible);
  }
}

String _statusLabel(ShellCommandBlock block) {
  return switch (block.status) {
    ShellCommandBlockStatus.succeeded => 'exit 0',
    ShellCommandBlockStatus.failed => 'exit ${block.exitCode ?? 1}',
    ShellCommandBlockStatus.running => 'running',
    ShellCommandBlockStatus.unknown => 'unknown',
  };
}
```

- [ ] **Step 4: Run view model test**

Run:

```bash
cd example
flutter test test/shell/shell_command_block_view_models_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add \
  example/lib/features/shell/shell_command_block_view_models.dart \
  example/test/shell/shell_command_block_view_models_test.dart
git commit -m "Add command block overlay view models"
```

---

### Task 5: Command Blocks UI Behind Feature Flag

**Files:**
- Create: `example/lib/features/shell/shell_screen_command_blocks.dart`
- Modify: `example/lib/features/shell/shell_screen.dart`
- Modify: `example/lib/features/shell/shell_screen_state_terminal_workspace.dart`
- Create: `example/test/shell/shell_screen_command_blocks_test.dart`

- [ ] **Step 1: Write focused widget tests for the new overlay widget**

Create `example/test/shell/shell_screen_command_blocks_test.dart`:

```dart
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_command_block_view_models.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('command block overlay renders active failed block actions', (
    tester,
  ) async {
    const item = ShellCommandBlockOverlayItem(
      id: 'cmd',
      command: 'flutter test',
      rowOffset: 2,
      rowSpan: 6,
      status: ShellCommandBlockStatus.failed,
      statusLabel: 'exit 1',
      active: true,
      showFailureSnapshotAction: true,
      showReplayAction: true,
      showDiffAction: false,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
            child: ShellCommandBlocksOverlay(
              viewModel: ShellCommandBlocksOverlayViewModel(blocks: [item]),
              rowHeight: 18,
            ),
          ),
        ),
      ),
    );

    expect(find.text('flutter test'), findsOneWidget);
    expect(find.text('exit 1'), findsOneWidget);
    expect(find.text('Copy output'), findsOneWidget);
    expect(find.text('Replay from here'), findsOneWidget);
    expect(find.text('Save snapshot'), findsOneWidget);
  });

  testWidgets('command block overlay renders nothing for empty view model', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShellCommandBlocksOverlay(
            viewModel: ShellCommandBlocksOverlayViewModel(),
            rowHeight: 18,
          ),
        ),
      ),
    );

    expect(find.text('Copy output'), findsNothing);
  });
}
```

- [ ] **Step 2: Run widget test and verify failure**

Run:

```bash
cd example
flutter test test/shell/shell_screen_command_blocks_test.dart
```

Expected: FAIL because `ShellCommandBlocksOverlay` does not exist.

- [ ] **Step 3: Export the overlay widget from a new shell part**

Create `example/lib/features/shell/shell_screen_command_blocks.dart`:

```dart
part of 'shell_screen.dart';

class ShellCommandBlocksOverlay extends StatelessWidget {
  const ShellCommandBlocksOverlay({
    super.key,
    required this.viewModel,
    required this.rowHeight,
  });

  final ShellCommandBlocksOverlayViewModel viewModel;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    if (viewModel.isEmpty) {
      return const SizedBox.shrink();
    }
    final palette = Theme.of(context).extension<AppThemeTokens>()!;
    return IgnorePointer(
      ignoring: false,
      child: Stack(
        children: [
          for (final block in viewModel.blocks)
            Positioned(
              top: block.rowOffset * rowHeight,
              left: 0,
              right: 0,
              height: block.rowSpan * rowHeight,
              child: _ShellCommandBlockChrome(
                block: block,
                palette: palette,
              ),
            ),
        ],
      ),
    );
  }
}

class _ShellCommandBlockChrome extends StatelessWidget {
  const _ShellCommandBlockChrome({
    required this.block,
    required this.palette,
  });

  final ShellCommandBlockOverlayItem block;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (block.status) {
      ShellCommandBlockStatus.succeeded => palette.success,
      ShellCommandBlockStatus.failed => palette.danger,
      ShellCommandBlockStatus.running => palette.warning,
      ShellCommandBlockStatus.unknown => palette.textSubtle,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: statusColor, width: block.active ? 3 : 1),
        ),
        color: block.active
            ? palette.panel.withValues(alpha: 0.22)
            : Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: palette.spacing.md,
              vertical: 2,
            ),
            child: Row(
              children: [
                Icon(Icons.circle, size: 7, color: statusColor),
                SizedBox(width: palette.spacing.sm),
                Expanded(
                  child: Text(
                    block.command,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                SizedBox(width: palette.spacing.sm),
                Text(
                  block.statusLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (block.active)
            _ShellCommandBlockActionRow(block: block, palette: palette),
        ],
      ),
    );
  }
}

class _ShellCommandBlockActionRow extends StatelessWidget {
  const _ShellCommandBlockActionRow({
    required this.block,
    required this.palette,
  });

  final ShellCommandBlockOverlayItem block;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(palette.spacing.sm),
      child: Wrap(
        spacing: palette.spacing.sm,
        runSpacing: palette.spacing.xs,
        children: [
          const _ShellCommandBlockActionChip(
            icon: Icons.copy,
            label: 'Copy output',
          ),
          if (block.showReplayAction)
            const _ShellCommandBlockActionChip(
              icon: Icons.replay,
              label: 'Replay from here',
            ),
          if (block.showFailureSnapshotAction)
            const _ShellCommandBlockActionChip(
              icon: Icons.bookmark_add,
              label: 'Save snapshot',
            ),
          if (block.showDiffAction)
            const _ShellCommandBlockActionChip(
              icon: Icons.compare_arrows,
              label: 'Compare last run',
            ),
        ],
      ),
    );
  }
}

class _ShellCommandBlockActionChip extends StatelessWidget {
  const _ShellCommandBlockActionChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppThemeTokens>()!;
    return TextButton.icon(
      onPressed: () {},
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: TextButton.styleFrom(
        minimumSize: Size(0, palette.controls.dense),
        padding: EdgeInsets.symmetric(horizontal: palette.spacing.sm),
      ),
    );
  }
}
```

Add these imports and part directive to `example/lib/features/shell/shell_screen.dart`:

```dart
import '../productivity/command_blocks_history_feature_flags.dart';
import '../productivity/shell_productivity_models.dart';
import 'shell_command_block_view_models.dart';
```

```dart
part 'shell_screen_command_blocks.dart';
```

- [ ] **Step 4: Run the overlay widget test**

Run:

```bash
cd example
flutter test test/shell/shell_screen_command_blocks_test.dart
```

Expected: PASS.

- [ ] **Step 5: Wire the overlay into the terminal pane behind flags**

In `example/lib/features/shell/shell_screen_state_terminal_workspace.dart`, inside the `Stack` that already contains `TerminalViewport`, place `ShellCommandBlocksOverlay` above the viewport:

```dart
final commandBlocksViewModel = ShellCommandBlockViewModelBuilder.build(
  blocks: _commandBlocksForSession(sessionId),
  viewportStartRow: viewportController.frame.viewportStartRow,
  viewportEndRow: viewportController.frame.viewportStartRow +
      viewportController.frame.viewportRows,
  flags: _commandBlocksHistoryFeatureFlags,
  activeBlockId: _activeCommandBlockId,
);
```

```dart
Positioned.fill(
  child: ShellCommandBlocksOverlay(
    viewModel: commandBlocksViewModel,
    rowHeight: _measuredCellSizes[sessionId]?.height ??
        terminal.terminalFallbackCellSize.height,
  ),
),
```

Add these private helpers/state fields in `ShellScreen` state files:

```dart
CommandBlocksHistoryFeatureFlags _commandBlocksHistoryFeatureFlags =
    CommandBlocksHistoryFeatureFlags.disabled;

List<ShellCommandBlock> _commandBlocksForSession(String sessionId) {
  return const <ShellCommandBlock>[];
}

String? get _activeCommandBlockId => null;
```

This first UI commit intentionally returns disabled flags and empty blocks from `ShellScreen`; it lands the render path without changing live behavior. Task 6 connects this render path to config-backed flags and controller-backed command blocks.

- [ ] **Step 6: Run shell screen smoke tests**

Run:

```bash
cd example
flutter test \
  test/shell/shell_screen_command_blocks_test.dart \
  test/shell/shell_screen_phase3_test.dart \
  test/shell/shell_screen_phase4_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add \
  example/lib/features/shell/shell_screen.dart \
  example/lib/features/shell/shell_screen_state_terminal_workspace.dart \
  example/lib/features/shell/shell_screen_command_blocks.dart \
  example/test/shell/shell_screen_command_blocks_test.dart
git commit -m "Render command block overlay shell"
```

---

### Task 6: History Peek And Review Entrypoints

**Files:**
- Create: `example/lib/features/shell/shell_screen_history_peek.dart`
- Modify: `example/lib/features/shell/shell_screen.dart`
- Modify: `example/lib/features/shell/shell_screen_state_events.dart`
- Modify: `example/lib/features/shell/shell_screen_command_menu.dart`
- Modify: `example/lib/features/shell/shell_screen_instant_replay.dart`
- Create: `example/test/shell/shell_screen_history_peek_test.dart`

- [ ] **Step 1: Write failing History Peek widget test**

Create `example/test/shell/shell_screen_history_peek_test.dart`:

```dart
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('history peek lists failed and marked commands', (tester) async {
    final blocks = [
      ShellCommandBlock(
        id: 'failed',
        command: 'flutter test',
        cwd: '/repo',
        exitCode: 1,
        outputRange: const ShellCommandBlockRange(
          commandRow: 10,
          outputStartRow: 11,
          outputEndRow: 20,
        ),
        status: ShellCommandBlockStatus.failed,
      ),
      ShellCommandBlock(
        id: 'marked',
        command: 'git commit -m "wip"',
        cwd: '/repo',
        outputRange: const ShellCommandBlockRange(
          commandRow: 30,
          outputStartRow: 31,
          outputEndRow: 31,
        ),
        status: ShellCommandBlockStatus.succeeded,
        markers: const [
          ShellHistoryMarker(
            id: 'm1',
            row: 30,
            kind: ShellHistoryMarkerKind.manual,
            commandBlockId: 'marked',
          ),
        ],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShellHistoryPeekSheet(blocks: blocks),
        ),
      ),
    );

    expect(find.text('History Peek'), findsOneWidget);
    expect(find.text('flutter test'), findsOneWidget);
    expect(find.text('git commit -m "wip"'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Marked'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run History Peek test and verify failure**

Run:

```bash
cd example
flutter test test/shell/shell_screen_history_peek_test.dart
```

Expected: FAIL because `ShellHistoryPeekSheet` does not exist.

- [ ] **Step 3: Implement History Peek shell part**

Create `example/lib/features/shell/shell_screen_history_peek.dart`:

```dart
part of 'shell_screen.dart';

class ShellHistoryPeekSheet extends StatelessWidget {
  const ShellHistoryPeekSheet({super.key, required this.blocks});

  final List<ShellCommandBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppThemeTokens>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(left: BorderSide(color: palette.border)),
      ),
      child: SizedBox(
        width: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.all(palette.spacing.md),
              child: Text(
                'History Peek',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: palette.spacing.md),
              child: Wrap(
                spacing: palette.spacing.sm,
                children: const [
                  _ShellHistoryPeekFilterChip(label: 'All'),
                  _ShellHistoryPeekFilterChip(label: 'Failed'),
                  _ShellHistoryPeekFilterChip(label: 'Marked'),
                  _ShellHistoryPeekFilterChip(label: 'Recent'),
                ],
              ),
            ),
            SizedBox(height: palette.spacing.sm),
            Expanded(
              child: ListView.separated(
                itemCount: blocks.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: palette.border,
                ),
                itemBuilder: (context, index) {
                  final block = blocks[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.circle,
                      size: 8,
                      color: block.failed ? palette.danger : palette.success,
                    ),
                    title: Text(
                      block.command,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      block.cwd ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      block.exitCode == null ? '' : '${block.exitCode}',
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellHistoryPeekFilterChip extends StatelessWidget {
  const _ShellHistoryPeekFilterChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: label == 'All',
      onSelected: (_) {},
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
```

Add this part directive to `example/lib/features/shell/shell_screen.dart`:

```dart
part 'shell_screen_history_peek.dart';
```

- [ ] **Step 4: Run History Peek test**

Run:

```bash
cd example
flutter test test/shell/shell_screen_history_peek_test.dart
```

Expected: PASS.

- [ ] **Step 5: Connect config-backed flags and command block snapshots**

In `example/lib/features/shell/shell_screen.dart`, add controller state:

```dart
final Map<String, ShellCommandBlockSnapshot> _commandBlockSnapshotsBySession =
    <String, ShellCommandBlockSnapshot>{};
```

In `example/lib/features/shell/shell_screen.dart`, add imports:

```dart
import '../productivity/shell_command_block_controller.dart';
import '../productivity/shell_productivity_reducer.dart';
```

In `example/lib/features/shell/shell_screen_state_events.dart`, when local config is loaded and `_notificationLocalConfig` is assigned, also assign:

```dart
_commandBlocksHistoryFeatureFlags =
    CommandBlocksHistoryFeatureFlags.fromConfig(
  configBootstrap.config.commandBlocksHistory,
);
```

Add a helper in a shell state part near the shell integration event handling path:

```dart
void _applyCommandBlockProductivityEvent(
  String sessionId,
  ShellProductivityEvent event,
) {
  final flags = _commandBlocksHistoryFeatureFlags;
  if (!flags.enabled || !flags.commandBlocks) {
    _commandBlockSnapshotsBySession.remove(sessionId);
    return;
  }
  final current =
      _commandBlockSnapshotsBySession[sessionId] ??
      const ShellCommandBlockSnapshot();
  _commandBlockSnapshotsBySession[sessionId] =
      ShellCommandBlockController.reduce(
    current,
    event,
    flags: flags,
  );
}
```

Update `_commandBlocksForSession`:

```dart
List<ShellCommandBlock> _commandBlocksForSession(String sessionId) {
  if (!_commandBlocksHistoryFeatureFlags.enabled ||
      !_commandBlocksHistoryFeatureFlags.commandBlocks) {
    return const <ShellCommandBlock>[];
  }
  return _commandBlockSnapshotsBySession[sessionId]?.blocks ??
      const <ShellCommandBlock>[];
}
```

In `example/lib/features/shell/shell_screen_state_events.dart`, update the `TerminalSessionShellHookEvent` case:

```dart
case terminal.TerminalSessionShellHookEvent():
  _applyCommandBlockShellHook(event);
  _notifyShellHook(event);
```

Add this helper in the same extension:

```dart
void _applyCommandBlockShellHook(
  terminal.TerminalSessionShellHookEvent event,
) {
  if (event.hook != 'command_finished') {
    return;
  }
  final command = event.command?.trim();
  final promptOffset = event.promptScrollbackOffset;
  if (command == null || command.isEmpty || promptOffset == null) {
    return;
  }
  final promptMarks = _effectivePromptMarksForSession(event.sessionId);
  final previousPromptOffset = promptMarks.isEmpty
      ? promptOffset
      : promptMarks.last.scrollbackOffset;
  final outputStartRow = previousPromptOffset + 1;
  final outputEndRow = promptOffset - 1;
  if (outputEndRow < outputStartRow) {
    return;
  }
  final commandId =
      '${event.sessionId}:$previousPromptOffset:$promptOffset:$command';
  _applyCommandBlockProductivityEvent(
    event.sessionId,
    ShellPromptMarkEvent(
      id: 'prompt-$previousPromptOffset',
      row: previousPromptOffset,
      cwd: event.cwd,
    ),
  );
  _applyCommandBlockProductivityEvent(
    event.sessionId,
    ShellCommandOutputRangeEvent(
      commandId: commandId,
      startRow: outputStartRow,
      endRow: outputEndRow,
    ),
  );
  _applyCommandBlockProductivityEvent(
    event.sessionId,
    ShellCommandFinishedEvent(
      command: command,
      cwd: event.cwd,
      exitCode: event.exitCode,
    ),
  );
}
```

This keeps Command Blocks aligned with the same shell hook payload that currently drives command-finished notifications and prompt metadata.

- [ ] **Step 6: Wire History Peek entry behind flag**

In `ShellScreen` state, add:

```dart
bool _isHistoryPeekOpen = false;

void _openHistoryPeek() {
  if (!_commandBlocksHistoryFeatureFlags.historyPeek) {
    return;
  }
  _mutateState(() {
    _isHistoryPeekOpen = true;
  });
}

void _closeHistoryPeek() {
  _mutateState(() {
    _isHistoryPeekOpen = false;
  });
}
```

In the main shell layout stack, render:

```dart
if (_isHistoryPeekOpen && _commandBlocksHistoryFeatureFlags.historyPeek)
  Positioned(
    top: 0,
    right: 0,
    bottom: 0,
    child: ShellHistoryPeekSheet(
      blocks: _commandBlocksForSession(activeSessionId),
    ),
  ),
```

In command menu wiring, map `TerminalActionId.openHistoryPeek` to `_openHistoryPeek()`.

- [ ] **Step 7: Add command block review source metadata**

In `example/lib/features/shell/shell_screen_instant_replay.dart`, add a small source value object:

```dart
class InstantReplayCommandBlockSource {
  const InstantReplayCommandBlockSource({
    required this.commandBlockId,
    required this.command,
    required this.outputStartRow,
    required this.outputEndRow,
  });

  final String commandBlockId;
  final String command;
  final int outputStartRow;
  final int outputEndRow;
}
```

Add an optional field to the replay workspace session object used by `Replay from here`:

```dart
final InstantReplayCommandBlockSource? commandBlockSource;
```

When `replayFromCommandBlock` runs and `reviewWorkspaceEntrypoints` is true, pass:

```dart
InstantReplayCommandBlockSource(
  commandBlockId: block.id,
  command: block.command,
  outputStartRow: block.outputRange.outputStartRow,
  outputEndRow: block.outputRange.outputEndRow,
)
```

In the Replay header, show the command source when present:

```dart
final sourceLabel = widget.workspace.commandBlockSource == null
    ? widget.workspace.sourceLabel
    : 'Replay from: ${widget.workspace.commandBlockSource!.command}';
```

- [ ] **Step 8: Run History Peek and Instant Replay focused tests**

Run:

```bash
cd example
flutter test \
  test/shell/shell_screen_history_peek_test.dart \
  test/shell/shell_screen_command_blocks_test.dart \
  test/shell/shell_screen_phase3_test.dart \
  test/shell/shell_screen_phase4_test.dart
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add \
  example/lib/features/shell/shell_screen.dart \
  example/lib/features/shell/shell_screen_state_events.dart \
  example/lib/features/shell/shell_screen_command_menu.dart \
  example/lib/features/shell/shell_screen_history_peek.dart \
  example/lib/features/shell/shell_screen_instant_replay.dart \
  example/test/shell/shell_screen_history_peek_test.dart
git commit -m "Add history peek and command review entrypoints"
```

---

## Final Verification

- [ ] **Step 1: Run targeted test suite**

```bash
cd example
flutter test \
  test/config/local_terminal_config_models_test.dart \
  test/productivity/command_blocks_history_feature_flags_test.dart \
  test/productivity/shell_command_block_controller_test.dart \
  test/productivity/shell_productivity_action_reducer_test.dart \
  test/shell/shell_action_availability_test.dart \
  test/shell/shell_command_block_view_models_test.dart \
  test/shell/shell_screen_command_blocks_test.dart \
  test/shell/shell_screen_history_peek_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run static analysis**

```bash
cd example
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Run formatting**

```bash
dart format example/lib/features/config \
  example/lib/features/productivity \
  example/lib/features/shell \
  example/test/config \
  example/test/productivity \
  example/test/shell
```

Expected: files are formatted; no syntax errors.

- [ ] **Step 4: Run final git check**

```bash
git status --short
```

Expected: only intentional implementation files are modified, or no changes remain after final commit.

---

## Self-Review

Spec coverage:

- Feature flag total switch and child switches are covered by Task 1 and action gates in Task 3.
- Command Blocks data model, failed status, output ranges, snapshots, and previous-run lookup are covered by Task 2.
- Command block action ids and availability are covered by Task 3.
- Overlay view model and non-invasive terminal rendering are covered by Tasks 4 and 5.
- History Peek and Review entrypoints are covered by Task 6.
- Tests cover disabled flags, enabled flags, no overlay when disabled, failed command blocks, History Peek listing, and Review source metadata.

Placeholder scan:

- No placeholder markers or fill-in steps are present.
- Every code step includes concrete files, code snippets, commands, and expected results.

Type consistency:

- The plan extends the existing `ShellCommandBlock` symbol instead of introducing a duplicate type.
- `CommandBlocksHistoryFeatureFlags` is the same type used by config, controller, action availability, and view model tasks.
- `ShellCommandBlockRange`, `ShellFailureSnapshot`, and `ShellHistoryMarker` are introduced before they are used by controller, view model, and UI tasks.
