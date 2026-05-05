import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_pty/flutterm_pty.dart';

import 'package:ianvs_terminal/main.dart';
import 'package:ianvs_terminal/src/clipboard_client.dart';
import 'package:ianvs_terminal/src/launch_config.dart';
import 'package:ianvs_terminal/src/saved_commands.dart';
import 'package:ianvs_terminal/src/terminal_blocks.dart';
import 'package:ianvs_terminal/src/terminal_settings.dart';

final _alignmentAnnotations = _WarpAlignmentAnnotations.load();
final _defaultDisplayAnnotation = _DefaultDisplayAnnotation.load();

void main() {
  testWidgets('default terminal layout stays visually stable', (tester) async {
    if (!Platform.isMacOS) {
      return;
    }
    final size = _defaultDisplayAnnotation.imageSize;
    _configureGoldenView(tester, size);

    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: _WarpAlignmentFakePtySessionBackend.defaultDisplay,
        clipboardClient: const _WarpAlignmentClipboardClient(),
        settingsStore: _goldenSettingsStore(),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'cd app',
    );
    await tester.pump();

    await expectLater(
      find.byType(IanvsTerminalShell),
      matchesGoldenFile(
        '../docs/design_snapshots/warp_alignment/default_terminal_layout.png',
      ),
    );

    _expectDefaultDisplayRegion(
      'top chrome',
      tester.getRect(find.byKey(const Key('terminal-header'))),
      'top_chrome',
    );
    _expectDefaultDisplayRegion(
      'terminal viewport',
      tester.getRect(
        find.byKey(const Key('terminal-default-viewport-visible')),
      ),
      'terminal_viewport',
    );
    _expectDefaultDisplayRegion(
      'input context',
      tester.getRect(find.byKey(const Key('terminal-input-context-strip'))),
      'input_context',
    );
    _expectDefaultDisplayRegion(
      'input editor',
      tester.getRect(find.byKey(const Key('terminal-modern-input-bar'))),
      'input_editor',
    );
  }, skip: !Platform.isMacOS);

  testWidgets('completion input layout stays visually stable', (tester) async {
    if (!Platform.isMacOS) {
      return;
    }
    _configureGoldenView(tester, const Size(1440, 900));

    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => _WarpAlignmentFakePtySessionBackend(),
        clipboardClient: const _WarpAlignmentClipboardClient(),
        settingsStore: _goldenSettingsStore(),
        initialBlocksForSession: _completionAlignmentBlocksForSession,
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'demo build --release',
    );
    await tester.pump();

    await expectLater(
      find.byType(IanvsTerminalShell),
      matchesGoldenFile(
        '../docs/design_snapshots/warp_alignment/completion_input_layout.png',
      ),
    );
  }, skip: !Platform.isMacOS);

  testWidgets('block actions hover layout stays visually stable', (
    tester,
  ) async {
    if (!Platform.isMacOS) {
      return;
    }
    _configureGoldenView(tester, const Size(1440, 900));

    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => _WarpAlignmentFakePtySessionBackend(),
        clipboardClient: const _WarpAlignmentClipboardClient(),
        settingsStore: _goldenSettingsStore(),
        initialBlocksForSession: _alignmentBlocksForSession,
      ),
    );
    await tester.pump();
    await _hoverInlineActiveBlock(tester);

    await expectLater(
      find.byType(IanvsTerminalShell),
      matchesGoldenFile(
        '../docs/design_snapshots/warp_alignment/block_actions_layout.png',
      ),
    );
  }, skip: !Platform.isMacOS);

  testWidgets('add menu layout stays visually stable', (tester) async {
    if (!Platform.isMacOS) {
      return;
    }
    _configureGoldenView(tester, const Size(1440, 900));

    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => _WarpAlignmentFakePtySessionBackend(),
        clipboardClient: const _WarpAlignmentClipboardClient(),
        settingsStore: _goldenSettingsStore(),
        launchConfigStore: _goldenLaunchConfigStore(),
        initialBlocksForSession: _alignmentBlocksForSession,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('terminal-add-menu-button')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Overlay).last,
      matchesGoldenFile(
        '../docs/design_snapshots/warp_alignment/add_menu_layout.png',
      ),
    );
  }, skip: !Platform.isMacOS);

  testWidgets('block rail and command palette stay visually stable', (
    tester,
  ) async {
    if (!Platform.isMacOS) {
      return;
    }
    _configureGoldenView(tester, const Size(1440, 900));

    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => _WarpAlignmentFakePtySessionBackend(),
        clipboardClient: const _WarpAlignmentClipboardClient(),
        settingsStore: _goldenSettingsStore(),
        savedCommandsStore: SavedCommandsStore.memory(
          const SavedCommandsState(
            entries: <SavedCommandEntry>[
              SavedCommandEntry(
                command: 'kubectl get pods -n payments',
                title: 'Payments pods',
                tags: <String>['k8s', 'prod'],
                cwdHint: '~/work/payments',
                targetKind: 'ssh',
                createdAt: '2026-05-04T09:00:00Z',
              ),
            ],
          ),
        ),
        launchConfigStore: _goldenLaunchConfigStore(),
        initialBlocksForSession: _alignmentBlocksForSession,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('terminal-command-history-button')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(IanvsTerminalShell),
      matchesGoldenFile(
        '../docs/design_snapshots/warp_alignment/blocks_command_palette.png',
      ),
    );
  }, skip: !Platform.isMacOS);

  testWidgets('split pane layout stays visually stable', (tester) async {
    if (!Platform.isMacOS) {
      return;
    }
    _configureGoldenView(tester, const Size(1440, 900));

    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => _WarpAlignmentFakePtySessionBackend(),
        clipboardClient: const _WarpAlignmentClipboardClient(),
        settingsStore: _goldenSettingsStore(),
        launchConfigStore: _goldenLaunchConfigStore(),
        initialBlocksForSession: _alignmentBlocksForSession,
      ),
    );
    await tester.pump();

    await _selectHeaderOverflowAction(tester, 'split-right');
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(IanvsTerminalShell),
      matchesGoldenFile(
        '../docs/design_snapshots/warp_alignment/split_pane_layout.png',
      ),
    );
  }, skip: !Platform.isMacOS);

  testWidgets('split pane and session palette stay visually stable', (
    tester,
  ) async {
    if (!Platform.isMacOS) {
      return;
    }
    _configureGoldenView(tester, const Size(1440, 900));

    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => _WarpAlignmentFakePtySessionBackend(),
        clipboardClient: const _WarpAlignmentClipboardClient(),
        settingsStore: _goldenSettingsStore(),
        launchConfigStore: _goldenLaunchConfigStore(),
        initialBlocksForSession: _alignmentBlocksForSession,
      ),
    );
    await tester.pump();

    await _selectHeaderOverflowAction(tester, 'split-right');
    await _selectAddMenuAction(tester, 'new-ssh');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('terminal-new-ssh-host-field')),
      'prod.example.internal',
    );
    await tester.enterText(
      find.byKey(const Key('terminal-new-ssh-project-field')),
      'payments-api',
    );
    await tester.tap(find.byKey(const Key('terminal-new-ssh-open-button')));
    await tester.pumpAndSettle();

    await _selectHeaderOverflowAction(tester, 'workspace-search');
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(IanvsTerminalShell),
      matchesGoldenFile(
        '../docs/design_snapshots/warp_alignment/split_session_palette.png',
      ),
    );
  }, skip: !Platform.isMacOS);

  testWidgets('saved config sidecar stays visually stable', (tester) async {
    if (!Platform.isMacOS) {
      return;
    }
    _configureGoldenView(tester, const Size(1440, 900));
    final dir = _freshGoldenTestDirectory('saved_config_sidecar_store');
    final store = TerminalLaunchConfigurationStore(directory: dir);

    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => _WarpAlignmentFakePtySessionBackend(),
        clipboardClient: const _WarpAlignmentClipboardClient(),
        settingsStore: _goldenSettingsStore(),
        launchConfigStore: store,
        initialBlocksForSession: _alignmentBlocksForSession,
      ),
    );
    await tester.pump();

    await _selectHeaderOverflowAction(tester, 'split-right');
    await _selectAddMenuAction(tester, 'save-tab-config');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    _freezeLaunchConfigModifiedTimes(dir);
    await _selectAddMenuAction(tester, 'saved-configs');
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('terminal-saved-launch-configs-dialog')),
      matchesGoldenFile(
        '../docs/design_snapshots/warp_alignment/saved_config_sidecar.png',
      ),
    );
  }, skip: !Platform.isMacOS);

  testWidgets('default layout matches the 1 percent pixel contract', (
    tester,
  ) async {
    if (!Platform.isMacOS) {
      return;
    }
    const size = Size(1440, 900);
    _configureGoldenView(tester, size);

    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => _WarpAlignmentFakePtySessionBackend(),
        clipboardClient: const _WarpAlignmentClipboardClient(),
        settingsStore: _goldenSettingsStore(),
        initialBlocksForSession: _alignmentBlocksForSession,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('terminal-block-panel')), findsNothing);
    expect(
      find.byKey(const Key('terminal-input-command-detection-strip')),
      findsNothing,
    );
    _expectRatioWithinOnePercent(
      'default header height',
      tester.getRect(find.byKey(const Key('terminal-header'))).height /
          size.height,
      70 / 1078,
    );
    final inputBar = tester.getRect(
      find.byKey(const Key('terminal-modern-input-bar')),
    );
    final blockRail = tester.getRect(
      find.byKey(const Key('terminal-inline-block-rail')),
    );
    final blockActions = tester.getRect(
      find.byKey(const Key('terminal-inline-block-actions-button')),
    );
    final blockBand = _rectAroundFinders(tester, const <Key>[
      Key('terminal-inline-block-rail'),
      Key('terminal-block-status-rail'),
    ]);
    final inputContext = tester.getRect(
      find.byKey(const Key('terminal-input-context-strip')),
    );
    _expectRatioWithinOnePercent(
      'default block rail left within terminal area',
      blockRail.left / size.width,
      (532 - 501) / (3456 - 501),
    );
    _expectRatioWithinOnePercent(
      'default block rail width within terminal area',
      blockRail.width / size.width,
      (3451 - 532) / (3456 - 501),
    );
    _expectRatioWithinOnePercent(
      'default block rail top',
      blockRail.top / size.height,
      449 / 1078,
    );
    _expectRatioWithinOnePercent(
      'default block output band height',
      blockBand.height / size.height,
      373 / 1078,
    );
    _expectRatioWithinOnePercent(
      'default block actions top offset',
      (blockActions.top - blockRail.top) / size.height,
      (486 - 449) / 1078,
    );
    _expectRatioWithinOnePercent(
      'default block actions right gap',
      (blockRail.right - blockActions.right) / blockRail.width,
      (3456 - 3343) / (3456 - 501),
    );
    _expectRatioWithinOnePercent(
      'default input context top',
      inputContext.top / size.height,
      873 / 1078,
    );
    _expectRatioWithinOnePercent(
      'default input context height',
      inputContext.height / size.height,
      41 / 1078,
    );
    _expectRatioWithinOnePercent(
      'default input top',
      inputBar.top / size.height,
      914 / 1078,
    );
    _expectRatioWithinOnePercent(
      'default input height',
      inputBar.height / size.height,
      164 / 1078,
    );
  }, skip: !Platform.isMacOS);

  testWidgets(
    'completion input matches the pane-local pixel contract',
    (tester) async {
      if (!Platform.isMacOS) {
        return;
      }
      _configureGoldenView(tester, const Size(1440, 900));

      await tester.pumpWidget(
        IanvsTerminalApp(
          backendFactory: () => _WarpAlignmentFakePtySessionBackend(),
          clipboardClient: const _WarpAlignmentClipboardClient(),
          settingsStore: _goldenSettingsStore(),
          initialBlocksForSession: _completionAlignmentBlocksForSession,
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('terminal-modern-input-field')),
        'demo build --release',
      );
      await tester.pump();

      final activePane = tester.getRect(
        find.byKey(const Key('terminal-pane-surface-1')),
      );
      final inputSystem = tester.getRect(
        find.byKey(const Key('terminal-modern-input-bar')),
      );
      final inputEditor = tester.getRect(
        find.byKey(const Key('terminal-modern-input-editor')),
      );
      final detectionStrip = tester.getRect(
        find.byKey(const Key('terminal-input-command-detection-strip')),
      );
      final blockBand = tester.getRect(
        find.byKey(const Key('terminal-inline-block-row')),
      );
      final commandOutputBody = tester.getRect(
        find.byKey(
          const Key('terminal-inline-active-block-command-output-body'),
        ),
      );
      final blockActions = tester.getRect(
        find.byKey(const Key('terminal-inline-block-actions-button')),
      );
      final outputBody = tester.getRect(
        find.byKey(const Key('terminal-inline-active-block-output-body')),
      );
      final mutedViewport = tester.widget<Opacity>(
        find.byKey(const Key('terminal-default-viewport-muted-for-completion')),
      );
      expect(mutedViewport.opacity, 0);
      expect(
        find.byKey(const Key('terminal-inline-menu-shell-completion')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('terminal-inline-block-context-strip')),
        findsNothing,
      );
      final blockBandTarget = _alignmentAnnotations
          .region('completion_input_layout', 'block_band')
          .requiredWarpRatio;
      final commandBodyTarget = _alignmentAnnotations
          .region('completion_input_layout', 'command_body')
          .requiredWarpRatio;
      final blockActionsTarget = _alignmentAnnotations
          .region('completion_input_layout', 'block_actions')
          .requiredWarpRatio;
      final detectionTarget = _alignmentAnnotations
          .region('completion_input_layout', 'detection_strip')
          .requiredWarpRatio;
      final inputEditorTarget = _alignmentAnnotations
          .region('completion_input_layout', 'input_editor')
          .requiredWarpRatio;
      _expectPaneLocalRatioWithinOnePercent(
        'completion block band left',
        _paneLocalLeft(activePane, blockBand),
        blockBandTarget.left,
      );
      _expectPaneLocalRatioWithinOnePercent(
        'completion block band top',
        _paneLocalTop(activePane, blockBand),
        blockBandTarget.top,
      );
      _expectPaneLocalRatioWithinOnePercent(
        'completion block band width',
        _paneLocalWidth(activePane, blockBand),
        blockBandTarget.width,
      );
      _expectPaneLocalRatioWithinOnePercent(
        'completion block band height',
        _paneLocalHeight(activePane, blockBand),
        blockBandTarget.height,
      );
      _expectPaneLocalRatioWithinOnePercent(
        'completion command output body left',
        _paneLocalLeft(activePane, commandOutputBody),
        commandBodyTarget.left,
      );
      _expectPaneLocalRatioWithinOnePercent(
        'completion command output body top',
        _paneLocalTop(activePane, commandOutputBody),
        commandBodyTarget.top,
      );
      _expectPaneLocalRatioWithinOnePercent(
        'completion command output body width',
        _paneLocalWidth(activePane, commandOutputBody),
        commandBodyTarget.width,
      );
      _expectPaneLocalRatioWithinOnePercent(
        'completion command output body height',
        _paneLocalHeight(activePane, commandOutputBody),
        commandBodyTarget.height,
      );
      _expectPaneLocalRatioWithinOnePercent(
        'completion block actions right gap',
        _paneLocalRightGap(activePane, blockActions),
        blockActionsTarget.rightGap,
      );
      _expectPaneLocalRatioWithinOnePercent(
        'completion block actions top',
        _paneLocalTop(activePane, blockActions),
        blockActionsTarget.top,
      );
      _expectPaneLocalRatioWithinOnePercent(
        'completion detection top',
        _paneLocalTop(activePane, detectionStrip),
        detectionTarget.top,
      );
      _expectPaneLocalRatioWithinOnePercent(
        'completion detection height',
        _paneLocalHeight(activePane, detectionStrip),
        detectionTarget.height,
      );
      _expectPaneLocalRatioWithinOnePercent(
        'completion input system top',
        _paneLocalTop(activePane, inputSystem),
        inputEditorTarget.top,
      );
      _expectPaneLocalRatioWithinOnePercent(
        'completion input system height',
        _paneLocalHeight(activePane, inputSystem),
        inputEditorTarget.height,
      );
      _expectPaneLocalRatioWithinOnePercent(
        'completion input editor top',
        _paneLocalTop(activePane, inputEditor),
        inputEditorTarget.top,
      );
      expect(
        outputBody.bottom,
        lessThanOrEqualTo(detectionStrip.top),
        reason: 'completion block output must not overlap detection strip',
      );
      expect(
        blockBand.bottom,
        lessThanOrEqualTo(detectionStrip.top + 1),
        reason:
            'completion block row should hand off directly to detection strip',
      );
    },
    skip: !Platform.isMacOS,
  );

  testWidgets(
    'command palette matches the 1 percent pixel contract',
    (tester) async {
      if (!Platform.isMacOS) {
        return;
      }
      const size = Size(1440, 900);
      _configureGoldenView(tester, size);

      await tester.pumpWidget(
        IanvsTerminalApp(
          backendFactory: () => _WarpAlignmentFakePtySessionBackend(),
          clipboardClient: const _WarpAlignmentClipboardClient(),
          settingsStore: _goldenSettingsStore(),
          savedCommandsStore: SavedCommandsStore.memory(
            const SavedCommandsState(
              entries: <SavedCommandEntry>[
                SavedCommandEntry(
                  command: 'kubectl get pods -n payments',
                  title: 'Payments pods',
                  tags: <String>['k8s', 'prod'],
                  cwdHint: '~/work/payments',
                  targetKind: 'ssh',
                  createdAt: '2026-05-04T09:00:00Z',
                ),
              ],
            ),
          ),
          launchConfigStore: _goldenLaunchConfigStore(),
          initialBlocksForSession: _alignmentBlocksForSession,
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('terminal-command-history-button')),
      );
      await tester.pumpAndSettle();

      final palette = tester.getRect(
        find.byKey(const Key('terminal-inline-menu-shell-command-palette')),
      );
      final sourceRail = tester.getRect(
        find.byKey(const Key('terminal-command-palette-source-rail')),
      );
      final resultsList = tester.getRect(
        find.byKey(const Key('terminal-command-palette-results-list')),
      );
      final paletteTarget = _alignmentAnnotations
          .region('blocks_command_palette', 'palette_shell')
          .requiredWarpRatio;
      final sourceRailTarget = _alignmentAnnotations
          .region('blocks_command_palette', 'source_rail')
          .requiredWarpRatio;
      final resultsTarget = _alignmentAnnotations
          .region('blocks_command_palette', 'results_list')
          .requiredWarpRatio;
      _expectRatioWithinOnePercent(
        'command palette left',
        palette.left / size.width,
        paletteTarget.left,
      );
      _expectRatioWithinOnePercent(
        'command palette top',
        palette.top / size.height,
        paletteTarget.top,
      );
      _expectRatioWithinOnePercent(
        'command palette width',
        palette.width / size.width,
        paletteTarget.width,
      );
      _expectRatioWithinOnePercent(
        'command palette height',
        palette.height / size.height,
        paletteTarget.height,
      );
      _expectRatioWithinOnePercent(
        'command palette source rail top',
        sourceRail.top / size.height,
        sourceRailTarget.top,
      );
      _expectRatioWithinOnePercent(
        'command palette source rail height',
        sourceRail.height / size.height,
        sourceRailTarget.height,
      );
      _expectRatioWithinOnePercent(
        'command palette results top',
        resultsList.top / size.height,
        resultsTarget.top,
      );
    },
    skip: !Platform.isMacOS,
  );

  testWidgets(
    'session palette matches the 1 percent pixel contract',
    (tester) async {
      if (!Platform.isMacOS) {
        return;
      }
      const size = Size(1440, 900);
      _configureGoldenView(tester, size);

      await tester.pumpWidget(
        IanvsTerminalApp(
          backendFactory: () => _WarpAlignmentFakePtySessionBackend(),
          clipboardClient: const _WarpAlignmentClipboardClient(),
          settingsStore: _goldenSettingsStore(),
          launchConfigStore: _goldenLaunchConfigStore(),
          initialBlocksForSession: _alignmentBlocksForSession,
        ),
      );
      await tester.pump();

      await _selectHeaderOverflowAction(tester, 'split-right');
      await _selectAddMenuAction(tester, 'new-ssh');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('terminal-new-ssh-host-field')),
        'prod.example.internal',
      );
      await tester.enterText(
        find.byKey(const Key('terminal-new-ssh-project-field')),
        'payments-api',
      );
      await tester.tap(find.byKey(const Key('terminal-new-ssh-open-button')));
      await tester.pumpAndSettle();

      await _selectHeaderOverflowAction(tester, 'workspace-search');
      await tester.pumpAndSettle();

      final palette = tester.getRect(
        find.byKey(const Key('terminal-inline-menu-shell-command-palette')),
      );
      final sourceRail = tester.getRect(
        find.byKey(const Key('terminal-command-palette-source-rail')),
      );
      final resultsList = tester.getRect(
        find.byKey(const Key('terminal-command-palette-results-list')),
      );
      final paletteTarget = _alignmentAnnotations
          .region('split_session_palette', 'palette_shell')
          .requiredWarpRatio;
      final sourceRailTarget = _alignmentAnnotations
          .region('split_session_palette', 'source_rail')
          .requiredWarpRatio;
      final resultsTarget = _alignmentAnnotations
          .region('split_session_palette', 'results_list')
          .requiredWarpRatio;
      _expectRatioWithinOnePercent(
        'session palette left',
        palette.left / size.width,
        paletteTarget.left,
      );
      _expectRatioWithinOnePercent(
        'session palette top',
        palette.top / size.height,
        paletteTarget.top,
      );
      _expectRatioWithinOnePercent(
        'session palette width',
        palette.width / size.width,
        paletteTarget.width,
      );
      _expectRatioWithinOnePercent(
        'session palette height',
        palette.height / size.height,
        paletteTarget.height,
      );
      _expectRatioWithinOnePercent(
        'session palette source rail top',
        sourceRail.top / size.height,
        sourceRailTarget.top,
      );
      _expectRatioWithinOnePercent(
        'session palette source rail height',
        sourceRail.height / size.height,
        sourceRailTarget.height,
      );
      _expectRatioWithinOnePercent(
        'session palette results top',
        resultsList.top / size.height,
        resultsTarget.top,
      );
    },
    skip: !Platform.isMacOS,
  );

  testWidgets('add menu matches the 1 percent pixel contract', (tester) async {
    if (!Platform.isMacOS) {
      return;
    }
    const size = Size(1440, 900);
    _configureGoldenView(tester, size);

    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => _WarpAlignmentFakePtySessionBackend(),
        clipboardClient: const _WarpAlignmentClipboardClient(),
        settingsStore: _goldenSettingsStore(),
        launchConfigStore: _goldenLaunchConfigStore(),
        initialBlocksForSession: _alignmentBlocksForSession,
      ),
    );
    await tester.pump();
    final addButton = tester.getRect(
      find.byKey(const Key('terminal-add-menu-button')),
    );
    await tester.tap(find.byKey(const Key('terminal-add-menu-button')));
    await tester.pumpAndSettle();

    final menuRect = _rectAroundFinders(tester, const <Key>[
      Key('terminal-add-menu-new-tab'),
      Key('terminal-add-menu-new-window'),
      Key('terminal-add-menu-new-ssh'),
      Key('terminal-add-menu-saved-configs'),
      Key('terminal-add-menu-launch-config'),
      Key('terminal-add-menu-save-tab-config'),
      Key('terminal-add-menu-save-app-config'),
      Key('terminal-add-menu-default-shell'),
      Key('terminal-add-menu-bash-shell'),
      Key('terminal-add-menu-fish-shell'),
    ]);
    _expectRatioWithinOnePercent(
      'add menu top is under the add button',
      (menuRect.top - addButton.bottom) / size.height,
      0,
    );
    _expectRatioWithinOnePercent(
      'add menu width',
      menuRect.width / size.width,
      600 / 1510,
    );
    _expectRatioWithinOnePercent(
      'add menu height',
      menuRect.height / size.height,
      564 / 1132,
    );
  }, skip: !Platform.isMacOS);

  testWidgets(
    'split pane layout matches the 1 percent pixel contract',
    (tester) async {
      if (!Platform.isMacOS) {
        return;
      }
      const size = Size(1440, 900);
      _configureGoldenView(tester, size);

      await tester.pumpWidget(
        IanvsTerminalApp(
          backendFactory: () => _WarpAlignmentFakePtySessionBackend(),
          clipboardClient: const _WarpAlignmentClipboardClient(),
          settingsStore: _goldenSettingsStore(),
          launchConfigStore: _goldenLaunchConfigStore(),
          initialBlocksForSession: _alignmentBlocksForSession,
        ),
      );
      await tester.pump();
      await _selectHeaderOverflowAction(tester, 'split-right');
      await tester.pumpAndSettle();

      final firstPane = tester.getRect(
        find.byKey(const Key('terminal-pane-1')),
      );
      final secondPane = tester.getRect(
        find.byKey(const Key('terminal-pane-2')),
      );
      final firstHeader = tester.getRect(
        find.byKey(const Key('terminal-pane-header-1')),
      );
      final secondHeader = tester.getRect(
        find.byKey(const Key('terminal-pane-header-2')),
      );
      final activeMarker = tester.getRect(
        find.byKey(const Key('terminal-pane-active-marker-2')),
      );
      final activeInputBar = tester.getRect(
        find.byKey(const Key('terminal-modern-input-bar')),
      );
      final inactiveInputBar = tester.getRect(
        find.byKey(const Key('terminal-inactive-modern-input-bar-1')),
      );
      final activeInputContext = tester.getRect(
        find.byKey(const Key('terminal-input-context-strip')),
      );
      final inactiveInputContext = tester.getRect(
        find.byKey(const Key('terminal-inactive-input-context-strip-1')),
      );
      _expectRatioWithinOnePercent(
        'split divider x',
        secondPane.left / size.width,
        (1978 - 501) / (3456 - 501),
      );
      _expectRatioWithinOnePercent(
        'split first pane width',
        firstPane.width / size.width,
        (1978 - 501) / (3456 - 501),
      );
      _expectRatioWithinOnePercent(
        'split second pane width',
        secondPane.width / size.width,
        (3456 - 1978) / (3456 - 501),
      );
      _expectRatioWithinOnePercent(
        'split first pane header top',
        firstHeader.top / size.height,
        72 / 1078,
      );
      _expectRatioWithinOnePercent(
        'split first pane header height',
        firstHeader.height / size.height,
        40 / 1078,
      );
      _expectRatioWithinOnePercent(
        'split second pane header top',
        secondHeader.top / size.height,
        72 / 1078,
      );
      _expectRatioWithinOnePercent(
        'split active marker height share',
        activeMarker.height / secondHeader.height,
        1,
      );
      _expectRatioWithinOnePercent(
        'split active input context top',
        activeInputContext.top / size.height,
        873 / 1078,
      );
      _expectRatioWithinOnePercent(
        'split inactive input context top',
        inactiveInputContext.top / size.height,
        873 / 1078,
      );
      _expectRatioWithinOnePercent(
        'split active input top',
        activeInputBar.top / size.height,
        914 / 1078,
      );
      _expectRatioWithinOnePercent(
        'split inactive input top',
        inactiveInputBar.top / size.height,
        914 / 1078,
      );
    },
    skip: !Platform.isMacOS,
  );

  testWidgets(
    'saved config sidecar matches the 1 percent pixel contract',
    (tester) async {
      if (!Platform.isMacOS) {
        return;
      }
      const size = Size(1440, 900);
      _configureGoldenView(tester, size);
      final dir = Directory.systemTemp.createTempSync(
        'ianvs_warp_alignment_launch_configs_',
      );
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final store = TerminalLaunchConfigurationStore(directory: dir);

      await tester.pumpWidget(
        IanvsTerminalApp(
          backendFactory: () => _WarpAlignmentFakePtySessionBackend(),
          clipboardClient: const _WarpAlignmentClipboardClient(),
          settingsStore: _goldenSettingsStore(),
          launchConfigStore: store,
          initialBlocksForSession: _alignmentBlocksForSession,
        ),
      );
      await tester.pump();
      await _selectHeaderOverflowAction(tester, 'split-right');
      await _selectAddMenuAction(tester, 'save-tab-config');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      _freezeLaunchConfigModifiedTimes(dir);
      await _selectAddMenuAction(tester, 'saved-configs');
      await tester.pumpAndSettle();

      final dialog = tester.getRect(
        find.byKey(const Key('terminal-saved-launch-configs-dialog')),
      );
      final sidecar = tester.getRect(
        find.byKey(const Key('terminal-saved-launch-config-sidecar')),
      );
      final dialogTarget = _alignmentAnnotations
          .region('saved_config_sidecar', 'dialog')
          .requiredIanvsRect;
      final sidecarTarget = _alignmentAnnotations
          .region('saved_config_sidecar', 'sidecar')
          .requiredIanvsRect;
      _expectRatioWithinOnePercent(
        'saved config dialog width',
        dialog.width / size.width,
        dialogTarget.width / size.width,
      );
      _expectRatioWithinOnePercent(
        'saved config dialog height',
        dialog.height / size.height,
        dialogTarget.height / size.height,
      );
      _expectRatioWithinOnePercent(
        'saved config sidecar width share',
        sidecar.width / dialog.width,
        sidecarTarget.width / dialogTarget.width,
      );
    },
    skip: !Platform.isMacOS,
  );

  testWidgets(
    'block actions hover matches the 1 percent pixel contract',
    (tester) async {
      if (!Platform.isMacOS) {
        return;
      }
      const size = Size(1440, 900);
      _configureGoldenView(tester, size);

      await tester.pumpWidget(
        IanvsTerminalApp(
          backendFactory: () => _WarpAlignmentFakePtySessionBackend(),
          clipboardClient: const _WarpAlignmentClipboardClient(),
          settingsStore: _goldenSettingsStore(),
          initialBlocksForSession: _alignmentBlocksForSession,
        ),
      );
      await tester.pump();

      final blockRailBefore = tester.getRect(
        find.byKey(const Key('terminal-inline-block-rail')),
      );
      final blockCardBefore = tester.getRect(
        find.byKey(const Key('terminal-inline-active-block-card')),
      );
      final inputContextBefore = tester.getRect(
        find.byKey(const Key('terminal-input-context-strip')),
      );
      final inputBarBefore = tester.getRect(
        find.byKey(const Key('terminal-modern-input-bar')),
      );

      await _hoverInlineActiveBlock(tester);

      final blockRail = tester.getRect(
        find.byKey(const Key('terminal-inline-block-rail')),
      );
      final blockCard = tester.getRect(
        find.byKey(const Key('terminal-inline-active-block-card')),
      );
      final blockActions = tester.getRect(
        find.byKey(const Key('terminal-inline-block-actions-button')),
      );
      final blockBand = _rectAroundFinders(tester, const <Key>[
        Key('terminal-inline-block-rail'),
        Key('terminal-block-status-rail'),
      ]);
      final inputContext = tester.getRect(
        find.byKey(const Key('terminal-input-context-strip')),
      );
      final inputBar = tester.getRect(
        find.byKey(const Key('terminal-modern-input-bar')),
      );

      expect(blockRail, blockRailBefore);
      expect(blockCard, blockCardBefore);
      expect(inputContext, inputContextBefore);
      expect(inputBar, inputBarBefore);
      _expectRatioWithinOnePercent(
        'block actions rail top',
        blockRail.top / size.height,
        449 / 1078,
      );
      _expectRatioWithinOnePercent(
        'block actions output band height',
        blockBand.height / size.height,
        373 / 1078,
      );
      _expectRatioWithinOnePercent(
        'block actions card top offset',
        (blockCard.top - blockRail.top) / size.height,
        10 / 1078,
      );
      _expectRatioWithinOnePercent(
        'block actions button top offset',
        (blockActions.top - blockRail.top) / size.height,
        (486 - 449) / 1078,
      );
      _expectRatioWithinOnePercent(
        'block actions button right gap',
        (blockRail.right - blockActions.right) / blockRail.width,
        (3456 - 3343) / (3456 - 501),
      );
      _expectRatioWithinOnePercent(
        'block actions input context top',
        inputContext.top / size.height,
        873 / 1078,
      );
      _expectRatioWithinOnePercent(
        'block actions input top',
        inputBar.top / size.height,
        914 / 1078,
      );
    },
    skip: !Platform.isMacOS,
  );
}

Future<void> _selectAddMenuAction(WidgetTester tester, String action) async {
  final addMenu = find.byKey(const Key('terminal-add-menu-button'));
  tester.widget<PopupMenuButton<String>>(addMenu).onSelected!(action);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _selectHeaderOverflowAction(
  WidgetTester tester,
  String action,
) async {
  final overflowMenu = find.byKey(
    const Key('terminal-header-overflow-menu-button'),
  );
  tester.widget<PopupMenuButton<String>>(overflowMenu).onSelected!(action);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _hoverInlineActiveBlock(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(gesture.removePointer);
  await gesture.addPointer(
    location: tester.getCenter(
      find.byKey(const Key('terminal-inline-active-block-card')),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

void _expectRatioWithinOnePercent(
  String label,
  double actual,
  double expected,
) {
  _expectRatioWithinTolerance(label, actual, expected, 0.01);
}

void _expectPaneLocalRatioWithinOnePercent(
  String label,
  double actual,
  double expected,
) {
  _expectRatioWithinTolerance('$label pane-local', actual, expected, 0.01);
}

void _expectRatioWithinTolerance(
  String label,
  double actual,
  double expected,
  double tolerance,
) {
  final delta = (actual - expected).abs();
  expect(
    delta,
    lessThanOrEqualTo(tolerance),
    reason:
        '$label expected ${expected.toStringAsFixed(4)}, '
        'actual ${actual.toStringAsFixed(4)}, '
        'delta ${delta.toStringAsFixed(4)}',
  );
}

double _paneLocalLeft(Rect pane, Rect rect) =>
    (rect.left - pane.left) / pane.width;

double _paneLocalTop(Rect pane, Rect rect) =>
    (rect.top - pane.top) / pane.height;

double _paneLocalWidth(Rect pane, Rect rect) => rect.width / pane.width;

double _paneLocalHeight(Rect pane, Rect rect) => rect.height / pane.height;

double _paneLocalRightGap(Rect pane, Rect rect) =>
    (pane.right - rect.right) / pane.width;

void _expectDefaultDisplayRegion(String label, Rect actual, String regionKey) {
  final expected = _defaultDisplayAnnotation.region(regionKey);
  final size = _defaultDisplayAnnotation.imageSize;
  _expectRatioWithinTolerance(
    '$label left',
    actual.left / size.width,
    expected.left / size.width,
    0.01,
  );
  _expectRatioWithinTolerance(
    '$label top',
    actual.top / size.height,
    expected.top / size.height,
    0.01,
  );
  _expectRatioWithinTolerance(
    '$label width',
    actual.width / size.width,
    expected.width / size.width,
    0.01,
  );
  _expectRatioWithinTolerance(
    '$label height',
    actual.height / size.height,
    expected.height / size.height,
    0.01,
  );
}

Rect _rectAroundFinders(WidgetTester tester, List<Key> keys) {
  final rects = keys
      .map((key) => tester.getRect(find.byKey(key)))
      .toList(growable: false);
  return rects
      .skip(1)
      .fold<Rect>(rects.first, (bounds, rect) => bounds.expandToInclude(rect));
}

void _configureGoldenView(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  Directory('docs/design_snapshots/warp_alignment').createSync(recursive: true);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

TerminalSettingsStore _goldenSettingsStore() {
  final dir = Directory.systemTemp.createTempSync('ianvs_warp_alignment_');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return TerminalSettingsStore(
    file: File('${dir.path}/settings.json'),
    defaultShell: '/bin/zsh',
  );
}

Directory _freshGoldenTestDirectory(String name) {
  final dir = Directory('docs/design_snapshots/warp_alignment/$name');
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
  dir.createSync(recursive: true);
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

TerminalLaunchConfigurationStore _goldenLaunchConfigStore() {
  final dir = Directory(
    'docs/design_snapshots/warp_alignment/golden_launch_configs',
  );
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
  dir.createSync(recursive: true);
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  final store = TerminalLaunchConfigurationStore(directory: dir);
  store.save(
    File('${dir.path}/payments-stack.json'),
    const TerminalLaunchConfiguration(
      windows: <TerminalLaunchConfigurationWindow>[
        TerminalLaunchConfigurationWindow(
          fallbackTitle: 'Payments Window',
          tabs: <TerminalLaunchConfigurationTab>[
            TerminalLaunchConfigurationTab(
              fallbackTitle: 'Deploy',
              activePaneId: 1,
              rootPane: TerminalLaunchConfigurationPaneLeaf(
                id: 1,
                cwd: '/Users/ianvs/work/payments',
                startupCommand: 'kubectl get pods -n payments',
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return store;
}

void _freezeLaunchConfigModifiedTimes(Directory dir) {
  final modifiedAt = DateTime(2026, 5, 4, 17);
  if (!dir.existsSync()) {
    return;
  }
  for (final entity in dir.listSync()) {
    if (entity is File && entity.path.toLowerCase().endsWith('.json')) {
      entity.setLastModifiedSync(modifiedAt);
    }
  }
}

class _DefaultDisplayAnnotation {
  const _DefaultDisplayAnnotation({
    required this.imageSize,
    required this.regions,
  });

  final Size imageSize;
  final Map<String, Rect> regions;

  static _DefaultDisplayAnnotation load() {
    final file = File(
      'docs/design_snapshots/warp_alignment/analysis/'
      'default_display_view_annotation.json',
    );
    final root = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final rawSize = root['image_size']! as List<Object?>;
    final regions = <String, Rect>{};
    for (final regionValue in root['regions'] as List<Object?>? ?? const []) {
      final region = regionValue! as Map<String, Object?>;
      regions[region['key']! as String] = _rectFromList(
        region['rect']! as List<Object?>,
      );
    }
    return _DefaultDisplayAnnotation(
      imageSize: Size(
        (rawSize[0]! as num).toDouble(),
        (rawSize[1]! as num).toDouble(),
      ),
      regions: regions,
    );
  }

  Rect region(String key) {
    final rect = regions[key];
    if (rect == null) {
      fail('Missing default display annotation region "$key"');
    }
    return rect;
  }
}

Rect _rectFromList(List<Object?> value) {
  return Rect.fromLTWH(
    (value[0]! as num).toDouble(),
    (value[1]! as num).toDouble(),
    (value[2]! as num).toDouble(),
    (value[3]! as num).toDouble(),
  );
}

class _WarpAlignmentAnnotations {
  const _WarpAlignmentAnnotations(this._regionsByComparison);

  final Map<String, Map<String, _AlignmentRegion>> _regionsByComparison;

  static _WarpAlignmentAnnotations load() {
    final file = File(
      'docs/design_snapshots/warp_alignment/analysis/reannotated/'
      'alignment_regions.json',
    );
    final root = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final comparisons = root['comparisons'] as List<Object?>? ?? const [];
    final regionsByComparison = <String, Map<String, _AlignmentRegion>>{};
    for (final comparisonValue in comparisons) {
      final comparison = comparisonValue! as Map<String, Object?>;
      final key = comparison['key']! as String;
      final rawRegions = <String, Map<String, Object?>>{};
      for (final regionValue
          in comparison['regions'] as List<Object?>? ?? const []) {
        final region = regionValue! as Map<String, Object?>;
        rawRegions[region['key']! as String] = region;
      }
      final regions = <String, _AlignmentRegion>{};
      for (final rawRegion in rawRegions.entries) {
        regions[rawRegion.key] = _AlignmentRegion(
          warpRect: _rectFromJson(rawRegion.value['warp']),
          ianvsRect: _rectFromJson(rawRegion.value['ianvs']),
        );
      }
      for (final alignmentValue
          in comparison['alignment'] as List<Object?>? ?? const []) {
        final alignment = alignmentValue! as Map<String, Object?>;
        final regionKey = alignment['region']! as String;
        final existing = regions[regionKey];
        regions[regionKey] = _AlignmentRegion(
          warpRect: existing?.warpRect,
          ianvsRect: existing?.ianvsRect,
          warpRatio: _ratioFromJson(alignment['warp_ratio']),
          ianvsRatio: _ratioFromJson(alignment['ianvs_ratio']),
        );
      }
      regionsByComparison[key] = regions;
    }
    return _WarpAlignmentAnnotations(regionsByComparison);
  }

  _AlignmentRegion region(String comparisonKey, String regionKey) {
    final regions = _regionsByComparison[comparisonKey];
    if (regions == null) {
      fail('Missing alignment comparison "$comparisonKey"');
    }
    final region = regions[regionKey];
    if (region == null) {
      fail('Missing alignment region "$comparisonKey/$regionKey"');
    }
    return region;
  }

  static Rect? _rectFromJson(Object? value) {
    if (value is! List<Object?>) {
      return null;
    }
    return _rectFromList(value);
  }

  static List<double>? _ratioFromJson(Object? value) {
    if (value is! List<Object?>) {
      return null;
    }
    return value
        .map((entry) => (entry! as num).toDouble())
        .toList(growable: false);
  }
}

class _AlignmentRegion {
  const _AlignmentRegion({
    this.warpRect,
    this.ianvsRect,
    this.warpRatio,
    this.ianvsRatio,
  });

  final Rect? warpRect;
  final Rect? ianvsRect;
  final List<double>? warpRatio;
  final List<double>? ianvsRatio;

  Rect get requiredIanvsRect {
    final rect = ianvsRect;
    if (rect == null) {
      fail('Expected Ianvs rect in alignment annotation');
    }
    return rect;
  }

  List<double> get requiredWarpRatio {
    final ratio = warpRatio;
    if (ratio == null) {
      fail('Expected Warp ratio in alignment annotation');
    }
    return ratio;
  }
}

extension _RatioValues on List<double> {
  double get left => this[0];
  double get top => this[1];
  double get width => this[2];
  double get height => this[3];
  double get rightGap => 1 - left - width;
}

List<TerminalBlock> _alignmentBlocksForSession(String sessionId) {
  return <TerminalBlock>[
    TerminalBlock(
      id: '$sessionId-1',
      sessionId: sessionId,
      commandText: 'git status --short',
      outputText: ' M lib/main.dart\n M test/widget_test.dart\n',
      status: TerminalBlockStatus.succeeded,
      scrollbackOffset: 2,
      recordedAt: '2026-05-04T09:12:00Z',
    ),
    TerminalBlock(
      id: '$sessionId-2',
      sessionId: sessionId,
      commandText: 'flutter test test/command_palette_test.dart',
      outputText: '00:00 +2: All tests passed!\n',
      status: TerminalBlockStatus.succeeded,
      scrollbackOffset: 8,
      recordedAt: '2026-05-04T09:16:00Z',
    ),
    TerminalBlock(
      id: '$sessionId-3',
      sessionId: sessionId,
      commandText: 'ssh prod.example.internal',
      outputText: 'Permission denied (publickey).\n',
      status: TerminalBlockStatus.failed,
      scrollbackOffset: 15,
      targetEnvironment: 'prod',
      recordedAt: '2026-05-04T09:20:00Z',
    ),
  ];
}

List<TerminalBlock> _completionAlignmentBlocksForSession(String sessionId) {
  return <TerminalBlock>[
    ..._alignmentBlocksForSession(sessionId).take(2),
    TerminalBlock(
      id: '$sessionId-3',
      sessionId: sessionId,
      commandText:
          "pwd\nprintf 'ianvs-warp-block-smoke\\n'\nfor i in 1 2 3; do echo \"warp-line-\$i\"; done",
      outputText:
          '/Users/luobinghui/projects/flutter/flutterm\nianvs-warp-block-smoke\nwarp-line-1\nwarp-line-2\nwarp-line-3\n',
      status: TerminalBlockStatus.succeeded,
      scrollbackOffset: 15,
      recordedAt: '2026-05-04T09:20:00Z',
    ),
  ];
}

class _WarpAlignmentClipboardClient implements ClipboardClient {
  const _WarpAlignmentClipboardClient();

  @override
  Future<String> readText() async => '';

  @override
  Future<void> writeText(String text) async {}
}

class _WarpAlignmentFakePtySessionBackend implements PtySessionBackend {
  _WarpAlignmentFakePtySessionBackend({bool defaultDisplay = false})
    : _defaultDisplay = defaultDisplay,
      _viewportRows = defaultDisplay ? 78 : 24;

  factory _WarpAlignmentFakePtySessionBackend.defaultDisplay() {
    return _WarpAlignmentFakePtySessionBackend(defaultDisplay: true);
  }

  final bool _defaultDisplay;
  int _createCount = 0;
  int _viewportRows;
  int _viewportCols = 80;

  @override
  int ping() => 42;

  @override
  String createSession(String sessionConfigJson) => 'session-${++_createCount}';

  @override
  void closeSession(String sessionId) {}

  @override
  List<PtyEvent> pollEvents(String sessionId) => const <PtyEvent>[];

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
  }) {
    _viewportRows = rows;
    _viewportCols = cols;
  }

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}

  @override
  String? searchTextJson(String sessionId, String query) => '[]';

  @override
  String? selectionText(String sessionId, String requestJson) => '';

  @override
  String? takeFrameDiffJson(String sessionId) {
    if (_defaultDisplay) {
      return jsonEncode(_defaultDisplayFrameJson());
    }
    return '{"frame_kind":"snapshot","rows":[{"index":0,"text":"% ready","style_runs":[]}],"cursor":{"row":0,"col":7,"visible":true},"viewport_rows":24,"viewport_cols":80,"dirty_ranges":[{"start":0,"end":1}],"scrollback_offset":0,"scrollback_max_offset":0,"modes":{}}';
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {}

  Map<String, Object?> _defaultDisplayFrameJson() {
    final firstBlockStart = (_viewportRows - 14).clamp(0, _viewportRows - 1);
    final secondBlockStart = (_viewportRows - 6).clamp(0, _viewportRows - 1);
    final rows = <Map<String, Object?>>[
      <String, Object?>{
        'index': firstBlockStart,
        'text':
            '~/projects/flutter/flutterm git:(codex/hyper-first-shell)  1 file changed, 1 insertion(+), 1 deletion(-) (0.025s)',
        'style_runs': const <Object?>[],
      },
      <String, Object?>{
        'index': (firstBlockStart + 1).clamp(0, _viewportRows - 1),
        'text': 'ls',
        'style_runs': const <Object?>[],
      },
      <String, Object?>{
        'index': (firstBlockStart + 3).clamp(0, _viewportRows - 1),
        'text':
            'AGENTS.md        ARCHITECTURE.md README.md       app          docs          example       native',
        'style_runs': const <Object?>[],
      },
      <String, Object?>{
        'index': (firstBlockStart + 4).clamp(0, _viewportRows - 1),
        'text': '      packages        pubspec.lock    pubspec.yaml    tools',
        'style_runs': const <Object?>[],
      },
      <String, Object?>{
        'index': secondBlockStart,
        'text':
            '~/projects/flutter/flutterm git:(codex/hyper-first-shell)  1 file changed, 1 insertion(+), 1 deletion(-) (0.025s)',
        'style_runs': const <Object?>[],
      },
      <String, Object?>{
        'index': (secondBlockStart + 1).clamp(0, _viewportRows - 1),
        'text': 'pwd',
        'style_runs': const <Object?>[],
      },
      <String, Object?>{
        'index': (secondBlockStart + 3).clamp(0, _viewportRows - 1),
        'text': '/Users/luobinghui/projects/flutter/flutterm',
        'style_runs': const <Object?>[],
      },
    ];
    return <String, Object?>{
      'frame_kind': 'snapshot',
      'rows': rows,
      'cursor': <String, Object?>{
        'row': (_viewportRows - 1).clamp(0, _viewportRows - 1),
        'col': 0,
        'visible': false,
      },
      'viewport_rows': _viewportRows,
      'viewport_cols': _viewportCols,
      'dirty_ranges': <Object?>[
        <String, Object?>{'start': 0, 'end': _viewportRows},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'window_title': '/Users/luobinghui/projects/flutter/flutterm',
      'modes': const <String, Object?>{},
    };
  }
}
