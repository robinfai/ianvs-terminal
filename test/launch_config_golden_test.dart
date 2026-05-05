import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_pty/flutterm_pty.dart';

import 'package:ianvs_terminal/main.dart';
import 'package:ianvs_terminal/src/clipboard_client.dart';
import 'package:ianvs_terminal/src/terminal_settings.dart';

void main() {
  testWidgets(
    'launch config modal compose and success states stay visually stable',
    (tester) async {
      if (!Platform.isMacOS) {
        return;
      }

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(960, 700);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final backend = _GoldenFakePtySessionBackend();
      final settingsStore = _goldenSettingsStore();
      final relativeSavePath =
          'docs/design_snapshots/warp_alignment/payments-prod.json';
      Directory(
        'docs/design_snapshots/warp_alignment',
      ).createSync(recursive: true);
      addTearDown(() {
        final file = File(relativeSavePath);
        if (file.existsSync()) {
          file.deleteSync();
        }
      });

      await tester.pumpWidget(
        IanvsTerminalApp(
          backendFactory: () => backend,
          clipboardClient: const _GoldenClipboardClient(),
          settingsStore: settingsStore,
        ),
      );
      await tester.pump();

      await _selectAddMenuAction(tester, 'new-window');
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

      await _selectAddMenuAction(tester, 'launch-config');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('terminal-launch-config-name-field')),
        'payments-prod',
      );
      await tester.ensureVisible(
        find.byKey(const Key('terminal-launch-config-advanced-toggle')),
      );
      await tester.tap(
        find.byKey(const Key('terminal-launch-config-advanced-toggle')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('terminal-launch-config-path-field')),
        relativeSavePath,
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const Key('terminal-launch-config-dialog')),
        matchesGoldenFile(
          '../docs/design_snapshots/warp_alignment/launch_config_compose.png',
        ),
      );
      _expectLaunchConfigPanelPixelContract(tester);
      _expectLaunchConfigComposePixelContract(tester);

      await tester.ensureVisible(
        find.byKey(const Key('terminal-launch-config-save-button')),
      );
      await tester.tap(
        find.byKey(const Key('terminal-launch-config-save-button')),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const Key('terminal-launch-config-dialog')),
        matchesGoldenFile(
          '../docs/design_snapshots/warp_alignment/launch_config_success.png',
        ),
      );
      _expectLaunchConfigPanelPixelContract(tester);
      _expectLaunchConfigSuccessPixelContract(tester);
    },
    skip: !Platform.isMacOS,
  );
}

void _expectLaunchConfigPanelPixelContract(WidgetTester tester) {
  const size = Size(960, 700);
  final panel = tester.getRect(
    find.byKey(const Key('terminal-launch-config-dialog')),
  );
  _expectRatioWithinFivePercent(
    'launch config panel center x',
    panel.center.dx / size.width,
    0.5,
  );
  _expectRatioWithinFivePercent(
    'launch config panel center y',
    panel.center.dy / size.height,
    0.5,
  );
  _expectRatioWithinFivePercent(
    'launch config panel width',
    panel.width / size.width,
    860 / 960,
  );
  _expectRatioWithinFivePercent(
    'launch config panel height',
    panel.height / size.height,
    650 / 700,
  );
}

void _expectLaunchConfigComposePixelContract(WidgetTester tester) {
  final panel = tester.getRect(
    find.byKey(const Key('terminal-launch-config-dialog')),
  );
  final nameField = tester.getRect(
    find.byKey(const Key('terminal-launch-config-name-field')),
  );
  final scopeExplainer = tester.getRect(
    find.byKey(const Key('terminal-launch-config-scope-explainer')),
  );
  final pathPreview = tester.getRect(
    find.byKey(const Key('terminal-launch-config-path-preview')),
  );
  final advancedToggle = tester.getRect(
    find.byKey(const Key('terminal-launch-config-advanced-toggle')),
  );
  final pathField = tester.getRect(
    find.byKey(const Key('terminal-launch-config-path-field')),
  );

  _expectRatioWithinFivePercent(
    'launch config compose name top',
    (nameField.top - panel.top) / panel.height,
    185 / 650,
  );
  _expectRatioWithinFivePercent(
    'launch config compose name width',
    nameField.width / panel.width,
    776 / 860,
  );
  _expectRatioWithinFivePercent(
    'launch config compose path preview top',
    (pathPreview.top - panel.top) / panel.height,
    298 / 650,
  );
  _expectRatioWithinFivePercent(
    'launch config compose scope top',
    (scopeExplainer.top - panel.top) / panel.height,
    71 / 650,
  );
  _expectRatioWithinFivePercent(
    'launch config compose scope height',
    scopeExplainer.height / panel.height,
    106 / 650,
  );
  _expectRatioWithinFivePercent(
    'launch config compose advanced toggle top',
    (advancedToggle.top - panel.top) / panel.height,
    340 / 650,
  );
  _expectRatioWithinFivePercent(
    'launch config compose path field top',
    (pathField.top - panel.top) / panel.height,
    391 / 650,
  );
}

void _expectLaunchConfigSuccessPixelContract(WidgetTester tester) {
  final panel = tester.getRect(
    find.byKey(const Key('terminal-launch-config-dialog')),
  );
  final successState = tester.getRect(
    find.byKey(const Key('terminal-launch-config-success-state')),
  );
  final successPath = tester.getRect(
    find.byKey(const Key('terminal-launch-config-success-path')),
  );
  final applyButton = tester.getRect(
    find.byKey(const Key('terminal-launch-config-success-apply-button')),
  );
  final doneButton = tester.getRect(
    find.byKey(const Key('terminal-launch-config-done-button')),
  );

  _expectRatioWithinFivePercent(
    'launch config success state top',
    (successState.top - panel.top) / panel.height,
    147 / 650,
  );
  _expectRatioWithinFivePercent(
    'launch config success state width',
    successState.width / panel.width,
    812 / 860,
  );
  _expectRatioWithinFivePercent(
    'launch config success path top',
    (successPath.top - panel.top) / panel.height,
    392 / 650,
  );
  _expectRatioWithinFivePercent(
    'launch config success actions top',
    (doneButton.top - panel.top) / panel.height,
    548 / 650,
  );
  _expectRatioWithinFivePercent(
    'launch config success primary action gap',
    (doneButton.left - applyButton.right) / panel.width,
    8 / 860,
  );
}

void _expectRatioWithinFivePercent(
  String label,
  double actual,
  double expected,
) {
  final delta = (actual - expected).abs();
  expect(
    delta,
    lessThanOrEqualTo(0.05),
    reason:
        '$label expected ${expected.toStringAsFixed(4)}, '
        'actual ${actual.toStringAsFixed(4)}, '
        'delta ${delta.toStringAsFixed(4)}',
  );
}

Future<void> _selectAddMenuAction(WidgetTester tester, String action) async {
  final addMenu = find.byKey(const Key('terminal-add-menu-button'));
  tester.widget<PopupMenuButton<String>>(addMenu).onSelected!(action);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

TerminalSettingsStore _goldenSettingsStore() {
  final dir = Directory.systemTemp.createTempSync('ianvs_launch_golden_');
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

class _GoldenClipboardClient implements ClipboardClient {
  const _GoldenClipboardClient();

  @override
  Future<String> readText() async => '';

  @override
  Future<void> writeText(String text) async {}
}

class _GoldenFakePtySessionBackend implements PtySessionBackend {
  int _createCount = 0;

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
  }) {}

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
    return '{"frame_kind":"snapshot","rows":[{"index":0,"text":"ready","style_runs":[]}],"cursor":{"row":0,"col":0,"visible":true},"viewport_rows":1,"viewport_cols":80,"dirty_ranges":[{"start":0,"end":1}],"scrollback_offset":0,"scrollback_max_offset":0,"modes":{}}';
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {}
}
