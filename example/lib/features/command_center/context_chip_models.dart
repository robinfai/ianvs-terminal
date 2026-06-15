import 'command_block_models.dart';
import 'command_lifecycle_degraded_state.dart';

enum ContextChipKind {
  cwd,
  profile,
  shellHook,
  lastExit,
  selectedBlock,
  readOnly,
}

enum ContextChipTone { normal, success, warning, danger, disabled }

enum ContextChipIntentKind {
  none,
  revealCwd,
  openProfile,
  showShellHookDiagnostics,
  navigateToBlock,
  openBlockActions,
  toggleReadOnly,
}

class ContextChipClickIntent {
  const ContextChipClickIntent._({
    required this.kind,
    required this.chipKind,
    this.cwd,
    this.profileId,
    this.blockId,
    this.unavailableReason,
  });

  const ContextChipClickIntent.none(ContextChipKind chipKind)
    : this._(kind: ContextChipIntentKind.none, chipKind: chipKind);

  const ContextChipClickIntent.revealCwd(String cwd)
    : this._(
        kind: ContextChipIntentKind.revealCwd,
        chipKind: ContextChipKind.cwd,
        cwd: cwd,
      );

  const ContextChipClickIntent.openProfile(String profileId)
    : this._(
        kind: ContextChipIntentKind.openProfile,
        chipKind: ContextChipKind.profile,
        profileId: profileId,
      );

  const ContextChipClickIntent.showShellHookDiagnostics({
    CommandCenterUnavailableReason? unavailableReason,
  }) : this._(
         kind: ContextChipIntentKind.showShellHookDiagnostics,
         chipKind: ContextChipKind.shellHook,
         unavailableReason: unavailableReason,
       );

  const ContextChipClickIntent.navigateToBlock(String blockId)
    : this._(
        kind: ContextChipIntentKind.navigateToBlock,
        chipKind: ContextChipKind.lastExit,
        blockId: blockId,
      );

  const ContextChipClickIntent.openBlockActions(String blockId)
    : this._(
        kind: ContextChipIntentKind.openBlockActions,
        chipKind: ContextChipKind.selectedBlock,
        blockId: blockId,
      );

  const ContextChipClickIntent.toggleReadOnly()
    : this._(
        kind: ContextChipIntentKind.toggleReadOnly,
        chipKind: ContextChipKind.readOnly,
      );

  final ContextChipIntentKind kind;
  final ContextChipKind chipKind;
  final String? cwd;
  final String? profileId;
  final String? blockId;
  final CommandCenterUnavailableReason? unavailableReason;

  bool get writesToTerminal => false;
}

class ContextChipModel {
  const ContextChipModel({
    required this.kind,
    required this.label,
    required this.value,
    required this.semanticLabel,
    required this.tone,
    required this.intent,
    this.enabled = true,
    this.unavailableReason,
  });

  final ContextChipKind kind;
  final String label;
  final String value;
  final String semanticLabel;
  final ContextChipTone tone;
  final ContextChipClickIntent intent;
  final bool enabled;
  final CommandCenterUnavailableReason? unavailableReason;
}

class ContextChipState {
  const ContextChipState({required this.chips});

  factory ContextChipState.fromContext({
    required String? cwd,
    required String? profileId,
    required String? profileName,
    required CommandCenterCapabilityState shellHookState,
    CommandBlock? lastFailedBlock,
    CommandBlock? selectedBlock,
    bool readOnly = false,
  }) {
    final chips = <ContextChipModel>[
      _cwdChip(cwd),
      _profileChip(profileId: profileId, profileName: profileName),
      _shellHookChip(shellHookState),
      if (lastFailedBlock != null) _lastExitChip(lastFailedBlock),
      if (selectedBlock != null) _selectedBlockChip(selectedBlock),
      if (readOnly) _readOnlyChip(),
    ];
    return ContextChipState(chips: List<ContextChipModel>.unmodifiable(chips));
  }

  final List<ContextChipModel> chips;

  ContextChipModel? byKind(ContextChipKind kind) {
    for (final chip in chips) {
      if (chip.kind == kind) {
        return chip;
      }
    }
    return null;
  }
}

ContextChipModel _cwdChip(String? cwd) {
  final trimmed = cwd?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return const ContextChipModel(
      kind: ContextChipKind.cwd,
      label: 'CWD',
      value: 'CWD unavailable',
      semanticLabel: 'Current working directory unavailable',
      tone: ContextChipTone.disabled,
      enabled: false,
      unavailableReason: CommandCenterUnavailableReason.missingCwd,
      intent: ContextChipClickIntent.none(ContextChipKind.cwd),
    );
  }
  return ContextChipModel(
    kind: ContextChipKind.cwd,
    label: 'CWD',
    value: trimmed,
    semanticLabel: 'Current working directory $trimmed',
    tone: ContextChipTone.normal,
    intent: ContextChipClickIntent.revealCwd(trimmed),
  );
}

ContextChipModel _profileChip({
  required String? profileId,
  required String? profileName,
}) {
  final trimmedName = profileName?.trim();
  final trimmedId = profileId?.trim();
  if (trimmedName == null ||
      trimmedName.isEmpty ||
      trimmedId == null ||
      trimmedId.isEmpty) {
    return const ContextChipModel(
      kind: ContextChipKind.profile,
      label: 'Profile',
      value: 'Profile unavailable',
      semanticLabel: 'Local profile unavailable',
      tone: ContextChipTone.disabled,
      enabled: false,
      intent: ContextChipClickIntent.none(ContextChipKind.profile),
    );
  }
  return ContextChipModel(
    kind: ContextChipKind.profile,
    label: 'Profile',
    value: trimmedName,
    semanticLabel: 'Local profile $trimmedName',
    tone: ContextChipTone.normal,
    intent: ContextChipClickIntent.openProfile(trimmedId),
  );
}

ContextChipModel _shellHookChip(CommandCenterCapabilityState state) {
  if (state.unavailable) {
    return ContextChipModel(
      kind: ContextChipKind.shellHook,
      label: 'Shell',
      value: 'Shell hooks unavailable',
      semanticLabel: 'Shell integration unavailable',
      tone: ContextChipTone.disabled,
      unavailableReason: state.reason,
      intent: ContextChipClickIntent.showShellHookDiagnostics(
        unavailableReason: state.reason,
      ),
    );
  }
  if (state.limited) {
    return ContextChipModel(
      kind: ContextChipKind.shellHook,
      label: 'Shell',
      value: 'Shell hooks limited',
      semanticLabel: 'Shell integration limited',
      tone: ContextChipTone.warning,
      unavailableReason: state.reason,
      intent: ContextChipClickIntent.showShellHookDiagnostics(
        unavailableReason: state.reason,
      ),
    );
  }
  return const ContextChipModel(
    kind: ContextChipKind.shellHook,
    label: 'Shell',
    value: 'Shell hooks on',
    semanticLabel: 'Shell integration enabled',
    tone: ContextChipTone.success,
    intent: ContextChipClickIntent.showShellHookDiagnostics(),
  );
}

ContextChipModel _lastExitChip(CommandBlock block) {
  final exitCode = block.exitCode;
  final value = exitCode == null ? 'Exit unknown' : 'Exit $exitCode';
  return ContextChipModel(
    kind: ContextChipKind.lastExit,
    label: 'Last exit',
    value: value,
    semanticLabel: 'Most recent failed command $value',
    tone: ContextChipTone.danger,
    intent: ContextChipClickIntent.navigateToBlock(block.id),
  );
}

ContextChipModel _selectedBlockChip(CommandBlock block) {
  return ContextChipModel(
    kind: ContextChipKind.selectedBlock,
    label: 'Block',
    value: block.command,
    semanticLabel: 'Selected command block ${block.command}',
    tone: ContextChipTone.normal,
    intent: ContextChipClickIntent.openBlockActions(block.id),
  );
}

ContextChipModel _readOnlyChip() {
  return const ContextChipModel(
    kind: ContextChipKind.readOnly,
    label: 'Read-only',
    value: 'Input blocked',
    semanticLabel: 'Read-only mode. Input blocked.',
    tone: ContextChipTone.warning,
    intent: ContextChipClickIntent.toggleReadOnly(),
  );
}
