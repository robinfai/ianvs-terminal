import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/ai/terminal_ai_message.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:app/ui/foundation/app_theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design/configuration_capture_binding.dart';
import '../design/visual_capture_fonts.dart';

void main() {
  ConfigurationCaptureBinding();
  const evidence = String.fromEnvironment('AI_MESSAGE_EVIDENCE_DIR');
  if (evidence.isNotEmpty) setUpAll(loadVisualCaptureFonts);
  for (final brightness in Brightness.values) {
    testWidgets('role marker contrast in $brightness', (tester) async {
      final theme = buildIanvsTerminalTheme(brightness);
      final palette = theme.extension<AppThemeTokens>()!;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Column(
              children: [
                TerminalAiMessageFrame(
                  entryId: 'user',
                  isUser: true,
                  child: Text('Question'),
                ),
                TerminalAiMessageFrame(
                  entryId: 'assistant',
                  isUser: false,
                  child: Text('Answer'),
                ),
              ],
            ),
          ),
        ),
      );
      for (final id in ['user', 'assistant']) {
        final marker = find.byKey(ValueKey('ai-message-role-$id'));
        final color = id == 'user'
            ? tester.widget<Text>(marker).style!.color!
            : tester.widget<Icon>(marker).color!;
        final foreground = color.computeLuminance();
        final background = (id == 'user' ? palette.chrome : palette.panel)
            .computeLuminance();
        final contrast = foreground > background
            ? (foreground + .05) / (background + .05)
            : (background + .05) / (foreground + .05);
        expect(contrast, greaterThanOrEqualTo(4.5), reason: '$id $brightness');
      }
    });
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'role surfaces share alignment and bounded reading width at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(1728, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildIanvsTerminalTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(
              body: Column(
                children: [
                  TerminalAiMessageFrame(
                    entryId: 'user',
                    isUser: true,
                    child: SelectableText(
                      'Inspect only',
                      key: Key('user-body'),
                    ),
                  ),
                  TerminalAiMessageFrame(
                    entryId: 'assistant',
                    isUser: false,
                    child: SelectableText(
                      'Read-only analysis',
                      key: Key('assistant-body'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final user = find.byKey(const ValueKey('ai-message-frame-user'));
        final assistant = find.byKey(
          const ValueKey('ai-message-frame-assistant'),
        );
        expect(tester.getSize(user).width, lessThanOrEqualTo(960));
        expect(tester.getSize(assistant).width, tester.getSize(user).width);
        expect(
          tester.getTopLeft(find.byKey(const Key('user-body'))).dx,
          tester.getTopLeft(find.byKey(const Key('assistant-body'))).dx,
        );
        expect(tester.widget<Container>(user).decoration, isNotNull);
        expect(tester.widget<Container>(assistant).decoration, isNull);
        expect(find.text('You'), findsOneWidget);
        expect(find.text('AI'), findsNothing);
        final icon = tester.widget<Icon>(
          find.byKey(const ValueKey('ai-message-role-assistant')),
        );
        expect(icon.icon, Icons.auto_awesome_outlined);
        expect(icon.semanticLabel, 'AI');
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final phone in [true, false]) {
    for (final dark in [false, true]) {
      testWidgets(
        'model markdown is readable and selectable (phone $phone, dark $dark)',
        (tester) async {
          tester.view.physicalSize = phone
              ? const Size(320, 568)
              : const Size(900, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          String? opened;
          final theme = buildIanvsTerminalTheme(
            dark ? Brightness.dark : Brightness.light,
            platform: phone ? TargetPlatform.iOS : TargetPlatform.macOS,
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('message-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: evidence.isEmpty ? theme : withVisualCaptureFonts(theme),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: TerminalAiMessage(
                        text:
                            '# Plan\n\nInspect **beta**; `enabled=false` does not prove health.\n\n'
                            '读取成功不代表服务恢复；健康状态**尚未检查**。\n\n'
                            '1. Read logs\n2. Explain evidence\n\n'
                            '```sh\nprintf "${'a' * 100}"\n```\n\n'
                            '[Reference](https://example.com/guide)\n\n'
                            '![Diagram](https://example.com/private.png)',
                        onOpenLink: (url) => opened = url,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (evidence.isNotEmpty) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const Key('message-capture')),
              );
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(evidence).create(recursive: true);
              await File(
                '$evidence/${phone ? 'phone' : 'desktop'}-${dark ? 'dark' : 'light'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          final texts = tester.widgetList<RichText>(find.byType(RichText));
          final plain = texts.map((t) => t.text.toPlainText()).join('\n');
          expect(find.byType(SelectionArea), findsOneWidget);
          expect(
            plain,
            contains('Inspect beta; enabled=false does not prove health.'),
          );
          expect(plain, isNot(contains('**')));
          expect(plain, isNot(contains('```')));
          expect(plain, contains('Diagram · https://example.com/private.png'));
          expect(find.byType(Image), findsNothing);
          expect(opened, isNull);
          final link = find.text('Reference', findRichText: true);
          await tester.ensureVisible(link);
          await tester.tap(link);
          expect(opened, 'https://example.com/guide');
          expect(
            tester
                .widgetList<Scrollable>(find.byType(Scrollable))
                .where(
                  (w) => axisDirectionToAxis(w.axisDirection) == Axis.vertical,
                ),
            hasLength(1),
          );
          expect(tester.testTextInput.hasAnyClients, false);
          String? copied;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          final region = tester.state<SelectableRegionState>(
            find.byType(SelectableRegion),
          );
          region.selectAll(SelectionChangedCause.keyboard);
          await tester.pump();
          region.contextMenuButtonItems
              .singleWhere((item) => item.type == ContextMenuButtonType.copy)
              .onPressed!();
          await tester.pump();
          expect(
            copied,
            contains('Inspect beta; enabled=false does not prove health.'),
          );
          expect(copied, contains('Read logs'));
          expect(copied, contains('Explain evidence'));
          expect(copied, contains('a' * 100));
          expect(copied, isNot(contains('**')));
          expect(copied, isNot(contains('```')));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
