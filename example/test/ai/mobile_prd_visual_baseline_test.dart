import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/ai/ai_api_client.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design/configuration_capture_binding.dart';
import '../design/visual_capture_fonts.dart';
import '../helpers/pump_app.dart';

const _outputDirectory = String.fromEnvironment('MOBILE_PRD_BASELINE_DIR');
const _capturePhase = String.fromEnvironment(
  'MOBILE_PRD_CAPTURE_PHASE',
  defaultValue: 'before',
);
const _captureKey = Key('mobile-prd-visual-baseline');

abstract final class _TestTag {
  static const golden = 'golden';
}

enum _Scene { multilineDraft, proposal, unknownSubmission }

/// Captures current production widgets, including the old one-line prompt and
/// icon-only action. These are before/after fixtures, not assertions that the
/// new PRD's expanded editor, four-line growth or action labels already exist.
///
/// PNGs and JSON sidecars are written only when MOBILE_PRD_BASELINE_DIR is set.
/// They are widget_golden artifacts on the host, never real iOS App captures.
void main() {
  ConfigurationCaptureBinding();

  group('$TerminalAiWorkspace mobile PRD visual baseline', () {
    late AiSettingsController settings;
    late _FixtureTerminal terminal;
    late _FixtureApi api;
    late TerminalAiController controller;
    late Map<String, Object?> environment;

    setUpAll(() async {
      if (_outputDirectory.isNotEmpty) {
        await loadVisualCaptureFonts();
        environment = await _captureEnvironment();
      }
    });

    setUp(() async {
      settings = AiSettingsController(_FixtureStore());
      await settings.loaded;
      terminal = _FixtureTerminal();
      api = _FixtureApi();
      controller = TerminalAiController(
        settings: settings,
        terminal: terminal,
        api: api,
      );
    });

    tearDown(() {
      controller.dispose();
      settings.dispose();
    });

    for (final size in [const Size(390, 844), const Size(320, 600)]) {
      for (final locale in [const Locale('en'), const Locale('zh')]) {
        for (final brightness in Brightness.values) {
          for (final scene in _Scene.values) {
            final fixtureId =
                '${size.width.toInt()}x${size.height.toInt()}-'
                '${locale.languageCode}-${brightness.name}-${scene.name}';
            testWidgets(
              'captures $fixtureId without sending the saved multiline draft',
              (tester) async {
                tester.view.devicePixelRatio = 1;
                tester.view.physicalSize = size;
                addTearDown(tester.view.reset);
                final chinese = locale.languageCode == 'zh';
                final draft = chinese
                    ? '分析部署失败的原因。\n保留原始日志，不要修改远端文件。\n解释这段路径：/srv/发布目录/应用 🧭'
                    : 'Explain why deployment failed.\nKeep the original logs; do not modify remote files.\nCheck this path: /srv/releases/application 🧭';
                final source = _source(chinese);
                api.reply = _proposal(chinese);
                // Controller preparation can await real risk-review work.
                // Keep it outside the widget binding's FakeAsync clock so a
                // timer/worker completion cannot stall the capture fixture.
                await tester.runAsync(() async {
                  await controller.refreshContext();
                  if (scene == _Scene.multilineDraft) {
                    controller.attachContext(source);
                  } else {
                    await controller.ask(
                      chinese
                          ? '检查部署日志，只读取状态。'
                          : 'Inspect the deployment log without changing files.',
                      block: source,
                    );
                    expect(controller.canApprove, isTrue);
                    if (scene == _Scene.unknownSubmission) {
                      terminal.failSubmission = true;
                      await controller.approve();
                      expect(controller.hasUnresolvedSubmission, isTrue);
                      expect(controller.canApprove, isFalse);
                    }
                    // A new attachment belongs to the unsent follow-up, not
                    // the frozen context that produced the proposal above.
                    controller.attachContext(source);
                  }
                });
                controller.setDraft(draft);

                try {
                  await tester.pumpApp(
                    Builder(
                      builder: (context) => Theme(
                        data: _outputDirectory.isEmpty
                            ? Theme.of(context)
                            : withVisualCaptureFonts(Theme.of(context)),
                        child: RepaintBoundary(
                          key: _captureKey,
                          child: TerminalAiWorkspace(
                            controller: controller,
                            targetLabel: 'ops@staging.example.test',
                            onClose: controller.takeOver,
                          ),
                        ),
                      ),
                    ),
                    brightness: brightness,
                    locale: locale,
                    platform: TargetPlatform.iOS,
                  );
                  await tester.pumpAndSettle();

                  expect(find.byType(TerminalAiWorkspace), findsOneWidget);
                  final prompt = tester.widget<TextField>(
                    find.byKey(const Key('ai-prompt')),
                  );
                  expect(prompt.controller!.text, draft);
                  expect(controller.draft, draft);
                  expect(
                    terminal.submissions,
                    scene == _Scene.unknownSubmission ? 1 : 0,
                  );
                  expect(api.requests, scene == _Scene.multilineDraft ? 0 : 1);
                  expect(tester.takeException(), isNull);

                  if (_outputDirectory.isNotEmpty) {
                    await _capture(
                      tester,
                      fixtureId: fixtureId,
                      size: size,
                      locale: locale,
                      brightness: brightness,
                      scene: scene,
                      controller: controller,
                      environment: environment,
                    );
                  }
                } finally {
                  // Dispose the workspace's polling timer before disposing its
                  // controller, including when a capture/assertion fails.
                  await tester.pumpWidget(const SizedBox.shrink());
                }
              },
              tags: _TestTag.golden,
              variant: const TargetPlatformVariant({TargetPlatform.iOS}),
            );
          }
        }
      }
    }
  });
}

AiBlockContext _source(bool chinese) => AiBlockContext(
  id: 'deployment-log',
  command: 'tail -n 40 /srv/releases/application/deploy.log',
  output: chinese
      ? '部署检查失败：配置文件不可读\n检查 /srv/发布目录/应用/config.yaml 的权限'
      : 'Deployment check failed: configuration is not readable\nInspect permissions for /srv/releases/application/config.yaml',
  exitCode: 1,
  cwd: '/srv/releases/application',
  sourceSessionId: 'mobile-prd-fixture',
  sourceContextId: 'ssh-staging',
  sourceLineBase: 100,
  outputStartLine: 38,
  outputEndLine: 40,
  totalLines: 40,
);

AiReply _proposal(bool chinese) => AiReply(
  text: chinese
      ? '日志说明配置文件不可读。可以先检查文件属性；这不会修改服务器。'
      : 'The log reports an unreadable configuration. Inspect its metadata first; this does not modify the server.',
  action: AiAction.fromToolCall({
    'id': 'inspect-deployment-config',
    'type': 'function',
    'function': {
      'name': 'run_command',
      'arguments': jsonEncode({
        'command':
            'ls -ld /srv/releases/application\n'
            'ls -l /srv/releases/application/config.yaml',
        'reason': chinese
            ? '只读检查部署目录与配置文件权限'
            : 'Read deployment directory and configuration permissions',
      }),
    },
  }),
);

class _FixtureStore implements AiConfigurationStore {
  @override
  Future<AiConfiguration?> read() async => const AiConfiguration.mock();

  @override
  Future<void> write(AiConfiguration? configuration) async {}
}

class _FixtureApi implements AiApi {
  late AiReply reply;
  int requests = 0;

  @override
  Future<AiReply> complete(
    AiConfiguration configuration,
    List<Map<String, Object?>> messages,
    AiCancellation cancellation,
  ) async {
    cancellation.check();
    requests++;
    return reply;
  }
}

class _FixtureTerminal implements AiTerminalPort, AiSubmissionInspector {
  static const _context = AiTerminalContext(
    sessionId: 'mobile-prd-fixture',
    contextId: 'ssh-staging',
    guard: 'fixture-context-1',
    screen: r'ops@staging:~$ ',
    cwd: '/srv/releases/application',
    targetLabel: 'ops@staging.example.test',
    canRunCommand: true,
    readyLease: 'fixture-ready-lease',
    commandNames: {'ls', 'tail'},
  );

  final _inputs = StreamController<void>.broadcast(sync: true);
  bool failSubmission = false;
  int submissions = 0;

  @override
  Stream<void> get userInput => _inputs.stream;

  @override
  Future<AiTerminalContext> readContext() async => _context;

  @override
  Future<Map<String, Object?>> execute(
    AiAction action,
    AiTerminalContext expected,
    AiCancellation cancellation,
  ) async {
    cancellation.check();
    if (expected.guard != _context.guard) {
      throw const AiFailure('stale_context');
    }
    submissions++;
    if (failSubmission) throw const AiFailure('submission_unknown');
    throw StateError('Only the unknown-receipt fixture may submit an action.');
  }

  @override
  String? submissionFor(String actionId) => 'original-fixture-submission';

  @override
  Future<Map<String, Object?>> inspectSubmission(String id) async => {
    'outcome': 'unknown',
  };

  @override
  void dispose() => unawaited(_inputs.close());
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
      'native_ios_system_font': false,
    },
  };
}

Future<void> _capture(
  WidgetTester tester, {
  required String fixtureId,
  required Size size,
  required Locale locale,
  required Brightness brightness,
  required _Scene scene,
  required TerminalAiController controller,
  required Map<String, Object?> environment,
}) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final capturedAt = DateTime.now().toUtc().toIso8601String();
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
          'captured_at': capturedAt,
          'fixture_id': fixtureId,
          'fixture_state': scene.name,
          'test_file': 'example/test/ai/mobile_prd_visual_baseline_test.dart',
          'capture_method': 'RenderRepaintBoundary.toImage',
          'comparison': 'Raw baseline capture; no image match asserted.',
          'logical_size': {'width': size.width, 'height': size.height},
          'png_size': {'width': image.width, 'height': image.height},
          'capture_pixel_ratio': 2,
          'view_device_pixel_ratio': tester.view.devicePixelRatio,
          'target_platform': 'iOS widget theme/test override; no device',
          'locale': locale.toLanguageTag(),
          'brightness': brightness.name,
          'text_scale': 1,
          'keyboard': 'hidden; no real IME',
          'system_chrome': 'not rendered by this widget fixture',
          'runtime': 'controlled AI and terminal ports; no account or PTY',
          'task_state': {
            'phase': controller.phase.name,
            'can_approve': controller.canApprove,
            'unresolved_submission': controller.hasUnresolvedSubmission,
            'draft_line_count': controller.draft.split('\n').length,
          },
          'assertion_scope':
              'Current widgets render and preserve the multiline draft. '
              'Expanded editing, four-line growth and visible action labels '
              'are intentionally not asserted as already implemented. '
              'Reuse this fixture for before/after comparison.',
          ...environment,
        }),
      );
    } finally {
      image.dispose();
    }
  });
}
