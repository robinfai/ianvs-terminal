import 'dart:async';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_connections.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_retained_timeline.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'terminal_ai_test.dart'
    show FakeApi, FakeTerminal, MemoryAiStore, contextFor;

class _Output {
  int base = 1000;
  int? baseDuringPage;
  final requests = <Map<String, Object?>>[];
  Map<String, Object?> request(Map<String, Object?> args) {
    requests.add(Map.of(args));
    if (baseDuringPage != null && (args['limit'] as int? ?? 0) > 1) {
      base = baseDuringPage!;
      baseDuringPage = null;
    }
    final count = 1600 - base;
    final offset = args['offset'] as int? ?? 0;
    final limit = args['limit'] as int? ?? 6;
    final indices = [
      for (var i = 0; i < count; i++)
        if (args['query'] != 'filtered' || i == 5) i,
    ];
    final block = {
      'id': 'log',
      'command': 'cat log',
      'exitCode': 0,
      'totalLines': count,
      'matchingLines': indices.length,
      'columns': 80,
      'offset': offset,
      'evicted': base > 1000,
      'nextOffset': offset + limit < indices.length ? offset + limit : null,
      'lines': [
        for (final i in indices.skip(offset).take(limit))
          {'index': i, 'source_row': base + i, 'text': 'source ${base + i}'},
      ],
    };
    return args['id'] == null
        ? {
            'blocks': [block],
          }
        : {'block': block};
  }
}

void main() {
  late AiSettingsController settings;
  late TerminalAiController ai;
  late FakeTerminal terminal;
  late FakeApi api;
  late CommandBlockController blocks;
  late _Output output;
  late TerminalAiConnections connections;
  late List<String> sourceReads;
  setUp(() async {
    output = _Output();
    blocks = CommandBlockController(request: output.request)..refresh();
    terminal = FakeTerminal()
      ..context = contextFor(
        lastBlock: const AiBlockContext(
          id: 'log',
          command: 'cat log',
          exitCode: 0,
          output: 'source 1130\nsource 1131',
          cwd: '/tmp',
          sourceSessionId: 'one',
          sourceLineBase: 1000,
          totalLines: 600,
          outputStartLine: 130,
          outputEndLine: 132,
        ),
      );
    settings = AiSettingsController(MemoryAiStore());
    await settings.loaded;
    api = FakeApi()
      ..respond = (_) async =>
          const AiReply(text: 'Evidence [block:log:131-132]');
    sourceReads = [];
    connections = TerminalAiConnections(
      sessionId: 'one',
      terminal: terminal,
      requestBlocks: (session, request) {
        if (request['id'] != null) sourceReads.add(session);
        return session == 'one'
            ? output.request(request)
            : _Output().request(request);
      },
    );
    ai = TerminalAiController(
      settings: settings,
      terminal: connections,
      api: api,
    );
    await ai.ask('Explain this output');
  });
  tearDown(() {
    ai.dispose();
    settings.dispose();
    blocks.dispose();
  });
  Future<void> mount(
    WidgetTester tester, {
    bool retained = false,
    bool phone = false,
    bool dark = false,
    Size? size,
    double safeTop = 0,
    double textScale = 1,
  }) async {
    tester.view.physicalSize =
        size ?? (phone ? const Size(320, 568) : const Size(900, 640));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: EdgeInsets.only(top: safeTop),
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        theme: buildIanvsTerminalTheme(
          dark ? Brightness.dark : Brightness.light,
          platform: phone ? TargetPlatform.iOS : TargetPlatform.macOS,
        ),
        home: Builder(
          builder: (context) => TerminalAiWorkspace(
            controller: ai,
            onClose: () {},
            onShowEvidence: (reference) => unawaited(
              retained
                  ? showRetainedAiEvidence(
                      context,
                      controller: ai,
                      reference: reference,
                      font: const TerminalFontConfig(),
                    )
                  : showAiEvidenceReader(
                      context,
                      controller: blocks,
                      reference: reference,
                      sourceSessionId: 'one',
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('ai-evidence-log-130-132')));
    await tester.pumpAndSettle();
  }

  double row(WidgetTester tester) {
    final scroll = tester
        .widget<ListView>(find.byKey(const Key('block-reader-scroll')))
        .controller!;
    final cell = tester
        .widget<TerminalViewport>(find.byType(TerminalViewport).first)
        .controller
        .measuredCellSize!;
    return (scroll.offset - 8) / cell.height;
  }

  for (final dark in [false, true]) {
    for (final phone in [false, true]) {
      testWidgets('evidence returns to its task outside window chrome '
          '(dark $dark, phone $phone)', (tester) async {
        await mount(
          tester,
          phone: phone,
          dark: dark,
          size: phone ? const Size(320, 568) : const Size(640, 400),
        );
        final task = ai.taskId;
        final requests = api.requests.length;
        for (var visit = 0; visit < 2; visit++) {
          await open(tester);
          final back = find.byKey(const Key('block-reader-close'));
          expect(
            tester.getRect(back).top,
            greaterThanOrEqualTo(phone ? 0 : 44),
            reason:
                'macOS owns the entire top 44 points for window controls and dragging',
          );
          if (phone) {
            expect(
              tester.getRect(back).top,
              lessThan(44),
              reason: 'The desktop title bar must not consume phone height',
            );
          }
          await tester.tap(back);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('block-reader')), findsNothing);
          expect(
            find.byKey(const Key('ai-evidence-log-130-132')),
            findsOneWidget,
          );
          expect(ai.taskId, task);
          expect(api.requests, hasLength(requests));
          expect(terminal.writes, isEmpty);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('reader respects a larger system inset without doubling chrome', (
    tester,
  ) async {
    await mount(
      tester,
      size: const Size(640, 400),
      safeTop: 60,
      textScale: 1.5,
    );
    await open(tester);
    final back = find.byKey(const Key('block-reader-close'));
    expect(tester.getRect(back).top, greaterThanOrEqualTo(60));
    expect(tester.getRect(back).top, lessThan(104));
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('block-reader')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final phone in [false, true]) {
    testWidgets(
      'citation retains source row and bypasses saved filter (phone $phone)',
      (tester) async {
        output.base = 1100;
        blocks.refresh();
        blocks.filter('log', const CommandBlockFilter(query: 'filtered'));
        await mount(tester, phone: phone);
        await open(tester);
        expect(row(tester), closeTo(30, .5));
        expect(blocks.appliedFilter('log')?.query, 'filtered');
        expect(blocks.filtering, contains('log'));
        final shown = tester
            .widgetList<CommandBlockTerminal>(find.byType(CommandBlockTerminal))
            .expand((w) => w.block.lines);
        expect(
          shown.any((r) => r.index == 30 && r.text == 'source 1130'),
          true,
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('block-reader-range'))).data,
          startsWith('Lines 130–'),
          reason:
              'The partially visible preceding row keeps the cited snapshot numbering',
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
        tester
            .widget<CommandBlockTerminal>(
              find.byType(CommandBlockTerminal).first,
            )
            .selectionController!
            .setSelection(
              const TerminalSelection(
                startRow: 30,
                startCol: 0,
                endRow: 31,
                endCol: 11,
              ),
            );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('block-reader-actions')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('block-reader-copy-selection')));
        await tester.pumpAndSettle();
        expect(copied, 'source 1130\nsource 1131');
        expect(
          ai.transcript.last.suppliedEvidence!.single.sourceLineBase,
          1000,
        );
        expect(terminal.writes, isEmpty);
        output.base = 1200;
        blocks.refresh();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('block-reader-evidence-unavailable')),
          findsOneWidget,
        );
        expect(find.byType(CommandBlockTerminal), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final stage in [
    'before click',
    'partial range',
    'keyboard dismissal',
    'native page',
  ]) {
    testWidgets('citation cannot drift when source is evicted during $stage', (
      tester,
    ) async {
      await mount(tester);
      if (stage == 'before click') output.base = 1200;
      if (stage == 'partial range') output.base = 1131;
      if (stage == 'native page') output.baseDuringPage = 1200;
      if (stage == 'keyboard dismissal') {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.textInput,
          (call) async {
            if (call.method == 'TextInput.hide') output.base = 1200;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.textInput,
            null,
          ),
        );
      }
      await open(tester);
      expect(find.byType(CommandBlockTerminal), findsNothing);
      expect(find.textContaining('no longer available'), findsWidgets);
      expect(terminal.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'overlapping citations from different retained versions remain ambiguous',
    (tester) async {
      terminal.context = contextFor(
        lastBlock: const AiBlockContext(
          id: 'log',
          command: 'cat log',
          exitCode: 0,
          output: 'different source',
          cwd: '/tmp',
          sourceSessionId: 'one',
          sourceLineBase: 1200,
          totalLines: 400,
          outputStartLine: 130,
          outputEndLine: 132,
        ),
      );
      await tester.runAsync(() => ai.ask('Explain the updated output'));
      await mount(tester);
      await tester.tap(find.byKey(const Key('ai-evidence-log-130-132')).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-evidence-ambiguous')), findsOneWidget);
      expect(find.byKey(const Key('block-reader')), findsNothing);
      expect(terminal.writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'retained citation recovers its target after a page changes version',
    (tester) async {
      await mount(tester);
      output.baseDuringPage = 1100;
      await open(tester);
      expect(find.byType(CommandBlockTerminal), findsNothing);
      blocks.refresh();
      await tester.pumpAndSettle();
      expect(row(tester), closeTo(30, .5));
      expect(
        tester
            .widgetList<CommandBlockTerminal>(find.byType(CommandBlockTerminal))
            .expand((w) => w.block.lines)
            .any((r) => r.index == 30 && r.text == 'source 1130'),
        true,
      );
      expect(terminal.writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'reconnected sessions with equal native IDs open the quoted source',
    (tester) async {
      output.base = 1100;
      connections.reconnect(
        sessionId: 'two',
        terminal: FakeTerminal()
          ..context = const AiTerminalContext(
            sessionId: 'two',
            contextId: 'root',
            guard: 'two',
            screen: 'new shell',
            cwd: '/tmp',
          ),
      );
      await tester.runAsync(ai.refreshContext);
      await mount(tester, retained: true);
      sourceReads.clear();
      await open(tester);
      expect(row(tester), closeTo(30, .5));
      expect(sourceReads, isNotEmpty);
      expect(sourceReads.toSet(), {'one'});
      expect(find.byKey(const Key('ai-evidence-ambiguous')), findsNothing);
      expect(terminal.writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
