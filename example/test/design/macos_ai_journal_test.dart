import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:app/ui/components/app_prompt_surface.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../ai/terminal_ai_test.dart'
    show FakeApi, FakeTerminal, MemoryAiStore, commandReply;
import 'configuration_capture_binding.dart';
import 'visual_capture_fonts.dart';

const evidence = String.fromEnvironment('AI_JOURNAL_EVIDENCE_DIR');
const output = [
  'Filesystem      Size  Used Avail Use% Mounted on',
  'tmpfs           395M  9.7M  385M   3% /run',
  '/dev/vda1        79G   45G   31G  60% /',
  'tmpfs           2.0G   24K  2.0G   1% /dev/shm',
  'tmpfs           5.0M     0  5.0M   0% /run/lock',
  'tmpfs           2.0G     0  2.0G   0% /sys/fs/cgroup',
  'tmpfs           395M     0  395M   0% /run/user/1000',
];

void main() {
  ConfigurationCaptureBinding();
  setUpAll(loadVisualCaptureFonts);
  for (final scene in [
    (name: 'light', size: const Size(1248, 950), dark: false, scale: 1.0),
    (name: 'dark', size: const Size(1248, 950), dark: true, scale: 1.0),
    (
      name: 'narrow-scaled',
      size: const Size(600, 800),
      dark: false,
      scale: 2.0,
    ),
    (name: 'short', size: const Size(700, 340), dark: true, scale: 1.0),
  ]) {
    testWidgets('macOS journal native output and actions ${scene.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scene.size;
      addTearDown(tester.view.reset);
      final settings = AiSettingsController(MemoryAiStore());
      await settings.loaded;
      final terminal = FakeTerminal()
        ..execution = Completer()
        ..context = const AiTerminalContext(
          sessionId: 'one',
          contextId: 'root',
          guard: 'disk-fixture',
          cwd: '/home/lighthouse',
          screen: '',
          canRunCommand: true,
          readyLease: 'fixture',
        );
      final api = FakeApi()
        ..respond = (_) async =>
            AiReply(text: '', action: commandReply('df -h').action);
      final task = TerminalAiController(
        settings: settings,
        terminal: terminal,
        api: api,
      );
      final block = <String, Object?>{
        'id': 'disk',
        'command': 'df -h',
        'cwd': '/home/lighthouse',
        'contextId': 'root',
        'running': false,
        'exitCode': 0,
        'columns': 80,
        'totalLines': output.length,
        'matchingLines': output.length,
        'lines': [
          for (final (i, line) in output.indexed)
            {'index': i, 'text': line, 'source_row': i},
        ],
      };
      final blocks = CommandBlockController(
        request: (args) => args['id'] == null
            ? {
                'blocks': [block],
              }
            : {'block': block},
      )..refresh();
      addTearDown(task.dispose);
      addTearDown(settings.dispose);
      addTearDown(blocks.dispose);
      await task.ask('看看磁盘空间');
      final turn = task.approve();
      api.respond = (_) async =>
          const AiReply(text: '根目录已使用 **60%**，可用 **31 GB**。');
      terminal.execution!.complete({
        'status': 'input_sent',
        'submission_id': 'disk-submission',
        'block_id': 'disk',
      });
      await turn;
      task.setDraft('帮我看看哪个目录占用最多');
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: withVisualCaptureFonts(
              buildIanvsTerminalTheme(
                scene.dark ? Brightness.dark : Brightness.light,
                platform: TargetPlatform.macOS,
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scene.scale)),
              child: child!,
            ),
            home: Scaffold(
              body: TerminalAiWorkspace(
                controller: task,
                onClose: () {},
                targetLabel: 'lighthouse',
                timelineBuilder: (items, scroll, follow) =>
                    TerminalCommandBlocksView(
                      controller: blocks,
                      onReinput: task.setDraft,
                      onAttachBlocks: (selected) {},
                      chinese: true,
                      font: const TerminalFontConfig(
                        family: visualCaptureMonoFont,
                      ),
                      timeline: items,
                      scrollController: scroll,
                      followTail: follow,
                      showToolbar: false,
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CommandBlockTerminal), findsOneWidget);
      final timeline = tester.getRect(find.byType(CommandTimelineView));
      final composer = tester.getRect(find.byType(AppPromptSurface));
      expect(timeline.left, closeTo(composer.left, .1));
      expect(timeline.right, closeTo(composer.right, .1));
      expect(terminal.writes, hasLength(1));
      if (evidence.isNotEmpty) {
        await tester.runAsync(() async {
          await Directory(evidence).create(recursive: true);
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$evidence/${scene.name}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      if (scene.name == 'light') {
        await tester.tap(find.text('df -h').last);
        await tester.pumpAndSettle();
        expect(blocks.selected, contains('disk'));
        await tester.tap(find.byTooltip('折叠输出'));
        await tester.pumpAndSettle();
        expect(blocks.collapsed, contains('disk'));
        await tester.tap(find.byTooltip('展开输出'));
        await tester.pumpAndSettle();
        expect(blocks.collapsed, isEmpty);
        await tester.tap(find.byTooltip('命令块操作'));
        await tester.pumpAndSettle();
        expect(find.text('复制输出'), findsOneWidget);
        expect(task.draft, '帮我看看哪个目录占用最多');
        expect(terminal.writes, hasLength(1));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
