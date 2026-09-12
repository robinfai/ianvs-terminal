import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/sessions/shell_capabilities_dialog.dart';
import 'package:app/features/sessions/shell_connection_chain.dart';
import 'package:app/features/sessions/shell_integration_capabilities.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

import '../helpers/pump_app.dart';

void main() {
  group(ShellCapabilitiesDialog, () {
    final captureEnabled =
        Platform.environment['IANVS_CAPABILITY_CAPTURE_DIR'] != null;
    setUpAll(() async {
      if (!captureEnabled) return;
      final flutterRoot =
          Platform.environment['FLUTTER_ROOT'] ??
          File(
            Platform.resolvedExecutable,
          ).parent.parent.parent.parent.parent.path;
      Future<ByteData> font(String path) async =>
          ByteData.sublistView(await File(path).readAsBytes());
      await Future.wait([
        (FontLoader(
          'CapabilityCaptureSans',
        )..addFont(font('/System/Library/Fonts/SFNS.ttf'))).load(),
        (FontLoader(
          'CapabilityCaptureCjk',
        )..addFont(font('/System/Library/Fonts/STHeiti Medium.ttc'))).load(),
        (FontLoader('MaterialIcons')..addFont(
              font(
                '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ),
            ))
            .load(),
      ]);
    });
    testWidgets('startup readiness distinguishes runtime observations', (
      tester,
    ) async {
      await tester.pumpApp(
        ShellCapabilitiesDialog(
          sessionTitle: 'SSH',
          capabilities: const ShellIntegrationCapabilities.pending()
              .applyRegistration({'current_directory': 'registered'}),
          bootstrapPhase: 'ready',
          bootstrapSource: 'reused',
          registrationChecks: const {'current_directory': 'registered'},
          onClose: () {},
        ),
      );
      expect(find.text('Shell integration is ready'), findsOneWidget);
      expect(
        find.text('Reused hooks already loaded in this shell'),
        findsOneWidget,
      );
      expect(find.text('1 of 13 capabilities active'), findsOneWidget);
      expect(find.text('Hook registration checked'), findsOneWidget);
      expect(
        find.text(
          'Initialization checks passed; ready to use, with no runtime event observed yet.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Confirmed by a matching event in this session.'),
        findsNothing,
      );
    });
    testWidgets('shows ordered SSH layers and follows a return to the parent', (
      tester,
    ) async {
      final chain = ValueNotifier<List<ShellConnectionHop>>(_sshChain);
      addTearDown(chain.dispose);
      await tester.pumpApp(
        ValueListenableBuilder(
          valueListenable: chain,
          builder: (context, value, _) => ShellCapabilitiesDialog(
            sessionTitle: 'SSH',
            connectionChain: value,
            capabilities: const ShellIntegrationCapabilities.pending(),
            onClose: () {},
          ),
        ),
      );
      expect(find.text('Connection chain'), findsOneWidget);
      expect(find.text('3 SSH hops'), findsOneWidget);
      expect(find.byIcon(Icons.dns_outlined), findsNWidgets(3));
      expect(find.byIcon(Icons.terminal_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
      expect(find.text('ProxyJump · forwarding only'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('ops@bastion.example:2222')).dy,
        lessThan(tester.getTopLeft(find.text('deploy@app.example:22')).dy),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('shell-connection-hop-3')),
          matching: find.text('Current shell'),
        ),
        findsOneWidget,
      );
      chain.value = chain.value.take(3).toList();
      await tester.pump();
      expect(find.text('root@db.example:22'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('shell-connection-hop-2')),
          matching: find.text('Current shell'),
        ),
        findsOneWidget,
      );
      expect(find.text('Current shell'), findsOneWidget);
      await tester.ensureVisible(find.text('Custom shell variables'));
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'updates activation while open, scrolls to extensions, and closes with Escape',
      (tester) async {
        final capabilities = ValueNotifier(
          const ShellIntegrationCapabilities.pending(),
        );
        addTearDown(capabilities.dispose);
        var closed = false;
        await tester.pumpApp(
          ValueListenableBuilder(
            valueListenable: capabilities,
            builder: (context, value, _) => ShellCapabilitiesDialog(
              sessionTitle: 'Local zsh',
              capabilities: value,
              onClose: () => closed = true,
            ),
          ),
        );
        expect(find.text('0 of 13 capabilities active'), findsOneWidget);
        capabilities.value = capabilities.value.observe(
          terminal.TerminalSessionShellHookEvent(
            'one',
            rawPayload: {'hook': 'precmd.pwd', 'pwd': '/tmp', 'shell': 'zsh'},
          ),
        );
        await tester.pump();
        expect(find.text('2 of 13 capabilities active'), findsOneWidget);
        final directory = find.byKey(
          const ValueKey('shell-capability-current_directory'),
        );
        expect(
          find.descendant(of: directory, matching: find.text('Active')),
          findsOneWidget,
        );
        final command = find.byKey(
          const ValueKey('shell-capability-command_text'),
        );
        expect(
          find.descendant(
            of: command,
            matching: find.text('Pending confirmation'),
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Custom shell variables'));
        await tester.pump();
        expect(
          find.text('Custom shell variables').hitTestable(),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(closed, isTrue);
      },
    );

    for (final brightness in Brightness.values) {
      testWidgets(
        'Chinese compact ${brightness.name} layout supports large text and scrolling',
        (tester) async {
          tester.view.physicalSize = const Size(390, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final captureKey = GlobalKey();
          final capabilities = const ShellIntegrationCapabilities.pending()
              .observe(
                terminal.TerminalSessionShellHookEvent(
                  'one',
                  rawPayload: {
                    'hook': 'precmd.pwd',
                    'pwd': '/tmp',
                    'shell': 'zsh',
                  },
                ),
              );
          await tester.pumpApp(
            RepaintBoundary(
              key: captureKey,
              child: ShellCapabilitiesDialog(
                sessionTitle: '本地 zsh',
                connectionChain: _sshChain,
                capabilities: capabilities,
                onClose: () {},
              ),
            ),
            brightness: brightness,
            locale: const Locale('zh'),
            textScale: 2,
            platform: TargetPlatform.iOS,
            fontFamily: captureEnabled ? 'CapabilityCaptureSans' : null,
            fontFamilyFallback: captureEnabled
                ? ['CapabilityCaptureCjk']
                : null,
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          await _capture(tester, captureKey, 'compact-${brightness.name}.png');
          await tester.ensureVisible(find.text('自定义 shell 变量'));
          await tester.pump();
          expect(find.text('自定义 shell 变量').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'disabled capabilities explain the gate instead of claiming activation',
      (tester) async {
        final capabilities = const ShellIntegrationCapabilities.pending()
            .withPolicy(enabled: false, supportedEmulation: true);
        await tester.pumpApp(
          ShellCapabilitiesDialog(
            sessionTitle: 'Disabled',
            capabilities: capabilities,
            onClose: () {},
          ),
        );
        expect(find.text('Disabled'), findsWidgets);
        expect(
          find.text('Shell integration is disabled for this session.'),
          findsNWidgets(13),
        );
        expect(find.text('Active'), findsNothing);
      },
    );
    testWidgets(
      'desktop capability list retains a visible close control while scrolling',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await tester.pumpApp(
          RepaintBoundary(
            key: key,
            child: ShellCapabilitiesDialog(
              sessionTitle: '生产环境',
              connectionChain: _sshChain,
              capabilities: const ShellIntegrationCapabilities.pending(),
              onClose: () {},
            ),
          ),
          locale: const Locale('zh'),
          fontFamily: captureEnabled ? 'CapabilityCaptureSans' : null,
          fontFamilyFallback: captureEnabled ? ['CapabilityCaptureCjk'] : null,
        );
        await tester.pump();
        await _capture(tester, key, 'desktop-light.png');
        await tester.ensureVisible(find.text('自定义 shell 变量'));
        await tester.pump();
        expect(find.byTooltip('关闭对话框').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'selected compact rail design keeps capability content visible',
      (tester) async {
        tester.view.physicalSize = const Size(1268, 1474);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        final capabilities = const ShellIntegrationCapabilities.pending()
            .observe(
              terminal.TerminalSessionShellHookEvent(
                'design',
                rawPayload: {'hook': 'precmd', 'pwd': '/root', 'shell': 'bash'},
              ),
            );
        await tester.pumpApp(
          RepaintBoundary(
            key: key,
            child: ShellCapabilitiesDialog(
              sessionTitle: 'root@21.91.218.17',
              connectionChain: const [
                ShellConnectionHop(
                  kind: ShellConnectionHopKind.localShell,
                  contextId: 'root',
                ),
                ShellConnectionHop(
                  kind: ShellConnectionHopKind.sshShell,
                  contextId: 'a',
                  host: '9.134.114.235',
                  user: 'root',
                  port: 36000,
                ),
                ShellConnectionHop(
                  kind: ShellConnectionHopKind.sshShell,
                  contextId: 'b',
                  host: '21.91.218.17',
                  user: 'root',
                  port: 36000,
                ),
              ],
              capabilities: capabilities,
              bootstrapPhase: 'ready',
              bootstrapSource: 'installed',
              registrationChecks: const {
                'current_directory': 'registered',
                'prompt_lifecycle': 'registered',
              },
              onClose: () {},
            ),
          ),
          locale: const Locale('zh'),
          fontFamily: captureEnabled ? 'CapabilityCaptureSans' : null,
          fontFamilyFallback: captureEnabled ? ['CapabilityCaptureCjk'] : null,
        );
        await tester.pump();
        expect(find.text('2 次 SSH 跳转'), findsOneWidget);
        expect(find.text('已激活 3 / 13 项能力'), findsOneWidget);
        expect(find.text('当前'), findsOneWidget);
        expect(find.text('提示符生命周期').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, key, 'selected-design.png', pixelRatio: 2);
      },
    );
  });
}

const _sshChain = [
  ShellConnectionHop(kind: ShellConnectionHopKind.localClient),
  ShellConnectionHop(
    kind: ShellConnectionHopKind.jump,
    host: 'bastion.example',
    user: 'ops',
    port: 2222,
  ),
  ShellConnectionHop(
    kind: ShellConnectionHopKind.sshShell,
    contextId: 'root',
    host: 'app.example',
    user: 'deploy',
    port: 22,
  ),
  ShellConnectionHop(
    kind: ShellConnectionHopKind.sshShell,
    contextId: 'child',
    host: 'db.example',
    user: 'root',
    port: 22,
  ),
];

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String name, {
  double pixelRatio = 1,
}) async {
  final directory = Platform.environment['IANVS_CAPABILITY_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(directory).create(recursive: true);
    await File('$directory/$name').writeAsBytes(bytes!.buffer.asUint8List());
  });
}
