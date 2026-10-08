import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../design/configuration_capture_binding.dart';
import '../design/visual_capture_fonts.dart';
import '../helpers/pump_app.dart';

const _outputDirectory = String.fromEnvironment('MOBILE_PRD_BASELINE_DIR');
const _capturePhase = String.fromEnvironment(
  'MOBILE_PRD_CAPTURE_PHASE',
  defaultValue: 'before',
);
const _captureKey = Key('mobile-prd-composer-baseline');
const _draft = "printf '部署状态 ready\\n'\nls -l /srv/应用/config.yaml\npwd";

abstract final class _TestTag {
  static const golden = 'golden';
}

/// Canonical Composer and Block widgets with deterministic native-cell data.
/// Captures current behavior, including any old intent/unknown-status gaps;
/// no PRD redesign is assumed to have been implemented.
///
/// All three outcome blocks appear in each scene. These host widget_golden
/// PNGs are not App/device evidence and do not start a PTY or an AI request.
void main() {
  ConfigurationCaptureBinding();

  group(
    '$TerminalComposerView and $TerminalCommandBlocksView PRD baseline',
    () {
      late CommandBlockController blocks;
      late TerminalComposerController composer;
      late FocusNode focus;
      late ValueNotifier<bool> followTail;
      late int submissions;
      late int aiRequests;
      late Map<String, Object?> environment;

      setUpAll(() async {
        if (_outputDirectory.isNotEmpty) {
          await loadVisualCaptureFonts();
          environment = await _captureEnvironment();
        }
      });

      setUp(() {
        final source = _FixtureOutput();
        blocks = CommandBlockController(request: source.snapshot)..refresh();
        focus = FocusNode(debugLabel: 'PRD baseline Composer');
        followTail = ValueNotifier(false);
        submissions = 0;
        aiRequests = 0;
        composer =
            TerminalComposerController(
                targetId: 'composer-baseline',
                text: _draft,
                provider: (query, _) async => CompletionBatch(query, const []),
                submit: (_) async {
                  submissions++;
                  return ComposerSubmissionOutcome.accepted;
                },
              )
              ..updateShell(
                contextKey: 'ssh-staging',
                cwd: '/srv/应用',
                dialect: 'zsh',
                lease: 'fixture-ready-lease',
                ownership: ComposerOwnership.ready,
              )
              ..updateIntentContext(
                const InputIntentContext(
                  scope: 'ssh-staging',
                  commandNames: {'printf', 'ls', 'pwd'},
                ),
              );
      });

      tearDown(() {
        blocks.dispose();
        composer.dispose();
        focus.dispose();
        followTail.dispose();
      });

      for (final device in [
        (
          name: 'phone',
          size: const Size(390, 844),
          platform: TargetPlatform.iOS,
        ),
        (
          name: 'ipad',
          size: const Size(1024, 768),
          platform: TargetPlatform.iOS,
        ),
        (
          name: 'mac',
          size: const Size(1280, 900),
          platform: TargetPlatform.macOS,
        ),
      ]) {
        for (final brightness in Brightness.values) {
          for (final choice in InputIntentChoice.values) {
            final fixtureId =
                'composer-${device.name}-'
                '${device.size.width.toInt()}x${device.size.height.toInt()}-'
                '${brightness.name}-${choice.name}';
            testWidgets(
              'captures $fixtureId while preserving the unsent multiline draft',
              (tester) async {
                tester.view.devicePixelRatio = 1;
                tester.view.physicalSize = device.size;
                addTearDown(tester.view.reset);
                composer.chooseInputIntent(choice);
                final savedDraft = composer.editor.value;
                final resolvedIntent = composer.intentDecision.intent;

                try {
                  await tester.pumpApp(
                    Builder(
                      builder: (context) => Theme(
                        data: _outputDirectory.isEmpty
                            ? Theme.of(context)
                            : withVisualCaptureFonts(Theme.of(context)),
                        child: RepaintBoundary(
                          key: _captureKey,
                          child: ColoredBox(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            child: Column(
                              children: [
                                Expanded(
                                  child: TerminalCommandBlocksView(
                                    controller: blocks,
                                    followTail: followTail,
                                    font: TerminalFontConfig(
                                      family: _outputDirectory.isEmpty
                                          ? 'monospace'
                                          : visualCaptureMonoFont,
                                      fallback: _outputDirectory.isEmpty
                                          ? const TerminalFontConfig().fallback
                                          : visualCaptureFontFallback,
                                    ),
                                    onReinput: (value) {
                                      composer.editor.text = value;
                                      focus.requestFocus();
                                    },
                                    onReturnToInput: focus.requestFocus,
                                    onAskAi: (_) => aiRequests++,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    8,
                                    10,
                                    8,
                                  ),
                                  child: TerminalComposerView(
                                    controller: composer,
                                    focusNode: focus,
                                    targetLabel: 'ops@staging.example.test',
                                    onUseTerminal: () {},
                                    onAskAi: (_) => aiRequests++,
                                    onOpenAi: () => aiRequests++,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    brightness: brightness,
                    platform: device.platform,
                  );
                  await tester.pumpAndSettle();

                  expect(find.byType(TerminalComposerView), findsOneWidget);
                  for (final id in ['success', 'failed', 'unknown']) {
                    expect(
                      find.byKey(ValueKey('command-block-$id')),
                      findsOneWidget,
                    );
                  }
                  expect(composer.editor.value, savedDraft);
                  expect(composer.inputIntent.choice, choice);
                  expect(composer.intentDecision.intent, resolvedIntent);
                  expect(submissions, 0);
                  expect(aiRequests, 0);
                  expect(tester.takeException(), isNull);

                  if (_outputDirectory.isNotEmpty) {
                    await _capture(
                      tester,
                      fixtureId: fixtureId,
                      size: device.size,
                      platform: device.platform,
                      brightness: brightness,
                      composer: composer,
                      blocks: blocks,
                      environment: environment,
                    );
                  }
                } finally {
                  // Unmount listeners, focus attachments and any widget timers
                  // before the group disposes their controllers.
                  await tester.pumpWidget(const SizedBox.shrink());
                }
              },
              tags: _TestTag.golden,
              variant: TargetPlatformVariant({device.platform}),
            );
          }
        }
      }
    },
  );
}

class _FixtureOutput {
  final List<Map<String, Object?>> blocks = [
    _block(
      id: 'success',
      command: r"printf 'ready\n'",
      lines: ['ready'],
      exitCode: 0,
      sourceRow: 100,
    ),
    _block(
      id: 'failed',
      command: 'cat /srv/应用/config.yaml',
      lines: ['cat: config.yaml: Permission denied', '检查配置文件的读取权限'],
      exitCode: 1,
      sourceRow: 200,
    ),
    _block(
      id: 'unknown',
      command: 'sh /srv/releases/deploy.sh',
      lines: ['Checking deployment…'],
      exitCode: null,
      sourceRow: 300,
    ),
  ];

  Map<String, Object?> snapshot(Map<String, Object?> request) {
    if (request['id'] == null) return {'blocks': blocks};
    final block = blocks.firstWhere((b) => b['id'] == request['id']);
    final lines = block['lines']! as List<Map<String, Object?>>;
    final offset = (request['offset'] as int? ?? 0).clamp(0, lines.length);
    final end = (offset + (request['limit'] as int? ?? lines.length)).clamp(
      offset,
      lines.length,
    );
    return {
      'block': {
        ...block,
        'offset': offset,
        'nextOffset': end < lines.length ? end : null,
        'lines': lines.sublist(offset, end),
      },
    };
  }

  static Map<String, Object?> _block({
    required String id,
    required String command,
    required List<String> lines,
    required int? exitCode,
    required int sourceRow,
  }) => {
    'id': id,
    'command': command,
    'contextId': 'ssh-staging',
    'cwd': '/srv/应用',
    'exitCode': exitCode,
    // Missing exit status is deliberately not fabricated as running/success.
    'running': false,
    'columns': 80,
    'startedAt': 1000,
    'finishedAt': exitCode == null ? null : 1120,
    'totalLines': lines.length,
    'matchingLines': lines.length,
    'offset': 0,
    'lines': [
      for (var i = 0; i < lines.length; i++)
        <String, Object?>{
          'index': i,
          'source_row': sourceRow + i,
          'text': lines[i],
          'wrapped': false,
        },
    ],
  };
}

Future<Map<String, Object?>> _captureEnvironment() async {
  final commit = await Process.run('git', ['rev-parse', 'HEAD']);
  final status = await Process.run('git', ['status', '--porcelain']);
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final versionFile = File('$flutterRoot/bin/cache/flutter.version.json');
  return {
    'source_commit': commit.exitCode == 0
        ? commit.stdout.toString().trim()
        : null,
    'worktree_dirty': status.exitCode == 0
        ? status.stdout.toString().trim().isNotEmpty
        : null,
    'host_os': Platform.operatingSystem,
    'host_os_version': Platform.operatingSystemVersion,
    'dart_version': Platform.version,
    'flutter_version': versionFile.existsSync()
        ? jsonDecode(await versionFile.readAsString())
        : null,
    'font_source': {
      'sans': 'Flutter SDK material_fonts/Roboto',
      'cjk': 'example/test/design/fonts/NotoSansSC-Regular.otf',
      'mono':
          'native/vendor/par-term-emu-core-rust/src/screenshot/JetBrainsMono-Regular.ttf',
      'icons': 'Flutter SDK material_fonts/MaterialIcons-Regular.otf',
      'native_system_fonts': false,
    },
  };
}

Future<void> _capture(
  WidgetTester tester, {
  required String fixtureId,
  required Size size,
  required TargetPlatform platform,
  required Brightness brightness,
  required TerminalComposerController composer,
  required CommandBlockController blocks,
  required Map<String, Object?> environment,
}) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('PNG encoding returned no bytes.');
      final directory = await Directory(
        _outputDirectory,
      ).create(recursive: true);
      final basename = '${directory.path}/$_capturePhase-$fixtureId';
      await File('$basename.png').writeAsBytes(bytes.buffer.asUint8List());
      await File('$basename.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'evidence_type': 'widget_golden',
          'real_app_capture': false,
          'capture_phase': _capturePhase,
          'fixture_id': fixtureId,
          'test_file':
              'example/test/terminal_composer/mobile_prd_composer_baseline_test.dart',
          'capture_method': 'RenderRepaintBoundary.toImage',
          'comparison': 'Raw baseline capture; no image match asserted.',
          'logical_size': {'width': size.width, 'height': size.height},
          'png_size': {'width': image.width, 'height': image.height},
          'capture_pixel_ratio': 2,
          'view_device_pixel_ratio': tester.view.devicePixelRatio,
          'target_platform': '${platform.name} widget theme/test override',
          'locale': 'en',
          'fixture_text': 'English UI with Chinese paths/output and draft',
          'brightness': brightness.name,
          'text_scale': 1,
          'keyboard': 'hidden; no real IME',
          'system_chrome': 'not rendered by this widget fixture',
          'runtime': 'controlled native-cell data; no account or PTY',
          'composer_state': {
            'ownership': composer.ownership.name,
            'input_choice': composer.inputIntent.choice.name,
            'resolved_intent': composer.intentDecision.intent.name,
            'draft_line_count': composer.editor.text.split('\n').length,
          },
          'block_states': [
            for (final block in blocks.blocks)
              {
                'id': block.id,
                'exit_code': block.exitCode,
                'running': block.running,
                'line_count': block.lines.length,
              },
          ],
          'assertion_scope':
              'Current canonical widgets render all three outcome blocks and '
              'preserve the multiline draft and selected input intent without '
              'submitting. Fullscreen editing, one-to-four line growth, visible '
              'intent/action labels and unknown-state icons are not asserted '
              'as already implemented. Reuse for before/after comparison.',
          ...environment,
        }),
      );
    } finally {
      image.dispose();
    }
  });
}
