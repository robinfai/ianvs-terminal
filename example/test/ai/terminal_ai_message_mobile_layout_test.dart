import 'package:app/features/ai/terminal_ai_message.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_agent_chat/ianvs_agent_chat.dart'
    show ChatMessageBody, ChatMessageFrame;

void main() {
  Future<void> mountFrame(
    WidgetTester tester, {
    required double width,
    TargetPlatform platform = TargetPlatform.iOS,
    Brightness brightness = Brightness.dark,
    bool isUser = false,
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(1728, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildIanvsTerminalTheme(brightness, platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              // Match the timeline's unbounded vertical reading constraints.
              child: SingleChildScrollView(
                child: TerminalAiMessageFrame(
                  entryId: 'reading',
                  isUser: isUser,
                  child: const SizedBox(
                    key: Key('reading-body'),
                    height: 60,
                    child: Text('Keep the original command and its evidence.'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Geometry is theme-independent; exercise both phone width boundaries.
  for (final width in [320.0, 430.0]) {
    for (final isUser in [false, true]) {
      testWidgets('mobile $width user=$isUser uses W-32 body width', (
        tester,
      ) async {
        await mountFrame(tester, width: width, isUser: isUser);
        final body = find.byKey(const Key('reading-body'));
        final role = find.byKey(const ValueKey('ai-message-role-reading'));
        expect(tester.getSize(body).width, closeTo(width - 32, .01));
        expect(tester.getTopLeft(body).dx, closeTo(16, .01));
        expect(tester.getTopLeft(role).dx, closeTo(16, .01));
        expect(
          tester.getBottomLeft(role).dy,
          lessThan(tester.getTopLeft(body).dy),
          reason: 'The role must not reserve a column beside the prose.',
        );
        expect(find.byType(ChatMessageFrame), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final width in [390.0, 900.0, 1728.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'desktop $width at $scale uses bounded shared reading layout',
        (tester) async {
          await mountFrame(
            tester,
            width: width,
            platform: TargetPlatform.macOS,
            scale: scale,
          );
          final body = find.byKey(const Key('reading-body'));
          final role = find.byKey(const ValueKey('ai-message-role-reading'));
          expect(tester.getSize(body).width, lessThanOrEqualTo(800));
          expect(tester.getSize(body).width, greaterThan(200));
          if (width < 600) {
            expect(
              tester.getBottomLeft(role).dy,
              lessThan(tester.getTopLeft(body).dy),
            );
          } else {
            expect(tester.getTopLeft(body).dy, tester.getTopLeft(role).dy);
            expect(
              tester.getTopLeft(body).dx,
              greaterThan(tester.getTopRight(role).dx),
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('wide tablet uses shared side-by-side layout', (tester) async {
    await mountFrame(tester, width: 700);
    final body = find.byKey(const Key('reading-body'));
    final role = find.byKey(const ValueKey('ai-message-role-reading'));
    expect(tester.getSize(body).width, greaterThan(400));
    expect(tester.getTopLeft(body).dy, tester.getTopLeft(role).dy);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android narrow surface uses the same presentation rule', (
    tester,
  ) async {
    await mountFrame(tester, width: 390, platform: TargetPlatform.android);
    expect(
      tester.getSize(find.byKey(const Key('reading-body'))).width,
      closeTo(358, .01),
    );
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets('Markdown spacing and exact copy on $platform', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const path = '/home/lighthouse/项目/带 空格/logs/service-2026-10-10.log';
      const command = "printf '%s\\n' '$path'";
      const markdown =
          '## 整理建议\n\n'
          '先检查目录，只提供建议，不移动文件。\n\n'
          '1. 配置文件：`.bashrc`、`.profile`。\n'
          '2. 项目路径：`$path`。\n\n'
          '```sh\n$command\n```\n\n'
          '![Diagram](https://example.com/private.png)';
      final theme = buildIanvsTerminalTheme(
        Brightness.dark,
        platform: platform,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: TerminalAiMessageFrame(
                entryId: 'markdown',
                isUser: false,
                child: TerminalAiMessage(text: markdown),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rendered = tester.widget<ChatMessageBody>(
        find.byType(ChatMessageBody),
      );
      expect(rendered.text, markdown);
      expect(rendered.resourcePolicy.imageBuilder, isNull);
      expect(rendered.diagramBuilder, isNull);
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.testTextInput.hasAnyClients, false);
      expect(
        tester
            .stateList<ScrollableState>(find.byType(Scrollable))
            .where(
              (widget) =>
                  axisDirectionToAxis(widget.widget.axisDirection) ==
                      Axis.vertical &&
                  widget.position.maxScrollExtent > 0,
            ),
        hasLength(lessThanOrEqualTo(1)),
      );
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
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final selectionContext = tester.element(find.byType(SelectionArea));
      Actions.invoke(
        selectionContext,
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pump();
      Actions.invoke(selectionContext, CopySelectionTextIntent.copy);
      await tester.pumpAndSettle();
      expect(copied, contains(path));
      expect(copied, contains(command));
      expect(copied, contains('.bashrc'));
      expect(copied, contains('.profile'));
      expect(copied, isNot(contains('\u200b')));
      expect(copied, contains('```'));
      expect(tester.takeException(), isNull);
    });
  }
}
