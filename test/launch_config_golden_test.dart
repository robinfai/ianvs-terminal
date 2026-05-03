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

      await tester.tap(find.byKey(const Key('terminal-new-window-button')));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('terminal-new-ssh-session-button')),
      );
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

      await tester.tap(find.byKey(const Key('terminal-launch-config-button')));
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
        find.byKey(const Key('terminal-launch-config-panel')),
        matchesGoldenFile(
          '../docs/design_snapshots/warp_alignment/launch_config_compose.png',
        ),
      );

      await tester.ensureVisible(
        find.byKey(const Key('terminal-launch-config-save-button')),
      );
      await tester.tap(
        find.byKey(const Key('terminal-launch-config-save-button')),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const Key('terminal-launch-config-panel')),
        matchesGoldenFile(
          '../docs/design_snapshots/warp_alignment/launch_config_success.png',
        ),
      );
    },
    skip: !Platform.isMacOS,
  );
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
