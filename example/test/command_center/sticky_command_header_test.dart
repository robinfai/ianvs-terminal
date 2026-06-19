import 'package:app/features/command_center/command_block_models.dart';
import 'package:app/features/command_center/command_invocation_models.dart';
import 'package:app/features/command_center/sticky_command_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StickyCommandHeaderResolver', () {
    test('selects the command block at the visible viewport start', () {
      const scope = CommandBlockScope('session-a');
      final resolver = StickyCommandHeaderResolver();
      final visibleRange = const CommandBlockRowRange(
        startRow: 92,
        endRowExclusive: 120,
      );

      final result = resolver.resolve(
        blocks: [
          _block(
            id: 'setup',
            command: 'flutter pub get',
            scope: scope,
            inputStart: 0,
            outputStart: 1,
            outputEnd: 80,
          ),
          _block(
            id: 'long-test',
            command: 'flutter test --coverage',
            scope: scope,
            inputStart: 80,
            outputStart: 81,
            outputEnd: 180,
          ),
        ],
        viewport: StickyCommandHeaderViewport(
          scope: scope,
          visibleRange: visibleRange,
        ),
      );

      expect(result.header?.blockId, 'long-test');
      expect(result.header?.command, 'flutter test --coverage');
      expect(result.header?.blockEndRowExclusive, 180);
      expect(result.visibleRange, visibleRange);
      expect(result.scrollbackRowsInspected, 0);
      expect(result.writesToScrollback, isFalse);
    });

    test('hides for alt buffer, fullscreen app, and pager states', () {
      const scope = CommandBlockScope('session-a');
      final resolver = StickyCommandHeaderResolver();
      final blocks = [
        _block(
          id: 'less',
          command: 'less CHANGELOG.md',
          scope: scope,
          inputStart: 0,
          outputStart: 1,
          outputEnd: 80,
        ),
      ];

      final altBuffer = resolver.resolve(
        blocks: blocks,
        viewport: const StickyCommandHeaderViewport(
          scope: scope,
          visibleRange: CommandBlockRowRange(startRow: 4, endRowExclusive: 20),
          altBufferActive: true,
        ),
      );
      final fullscreen = resolver.resolve(
        blocks: blocks,
        viewport: const StickyCommandHeaderViewport(
          scope: scope,
          visibleRange: CommandBlockRowRange(startRow: 4, endRowExclusive: 20),
          fullscreenAppActive: true,
        ),
      );
      final pager = resolver.resolve(
        blocks: blocks,
        viewport: const StickyCommandHeaderViewport(
          scope: scope,
          visibleRange: CommandBlockRowRange(startRow: 4, endRowExclusive: 20),
          pagerActive: true,
        ),
      );

      expect(altBuffer.header, isNull);
      expect(
        altBuffer.disabledReason,
        StickyCommandHeaderDisabledReason.altBufferActive,
      );
      expect(
        fullscreen.disabledReason,
        StickyCommandHeaderDisabledReason.fullscreenAppActive,
      );
      expect(
        pager.disabledReason,
        StickyCommandHeaderDisabledReason.pagerActive,
      );
    });

    test('failed header includes exit code, cwd, and duration text', () {
      const scope = CommandBlockScope('session-a');
      final resolver = StickyCommandHeaderResolver();

      final result = resolver.resolve(
        blocks: [
          _block(
            id: 'failed',
            command: 'dart test',
            scope: scope,
            inputStart: 10,
            outputStart: 11,
            outputEnd: 70,
            cwd: '/repo',
            exitCode: 2,
            duration: const Duration(seconds: 3),
          ),
        ],
        viewport: const StickyCommandHeaderViewport(
          scope: scope,
          visibleRange: CommandBlockRowRange(startRow: 20, endRowExclusive: 40),
        ),
      );

      final header = result.header;
      expect(header, isNotNull);
      expect(header!.statusLabel, 'Failed exit 2');
      expect(header.cwdLabel, '/repo');
      expect(header.durationLabel, '3s');
      expect(header.semanticLabel, contains('Failed exit 2'));
      expect(header.semanticLabel, contains('/repo'));
      expect(header.tone, StickyCommandHeaderTone.danger);
    });
  });

  group('StickyCommandHeaderOverlay', () {
    testWidgets('renders header as overlay outside scrollback content', (
      tester,
    ) async {
      const scope = CommandBlockScope('session-a');
      final resolver = StickyCommandHeaderResolver();
      final rows = ['\$ dart test', 'failing output'];
      final resolution = resolver.resolve(
        blocks: [
          _block(
            id: 'failed',
            command: 'dart test',
            scope: scope,
            inputStart: 0,
            outputStart: 1,
            outputEnd: 80,
            cwd: '/repo',
            exitCode: 1,
            duration: const Duration(seconds: 1),
          ),
        ],
        viewport: const StickyCommandHeaderViewport(
          scope: scope,
          visibleRange: CommandBlockRowRange(startRow: 20, endRowExclusive: 40),
        ),
      );

      await tester.pumpWidget(
        _app(
          StickyCommandHeaderOverlay(
            resolution: resolution,
            child: Column(
              key: const Key('terminal-scrollback'),
              children: [for (final row in rows) Text(row)],
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('sticky-command-header')), findsOneWidget);
      expect(find.text('dart test'), findsOneWidget);
      expect(find.text('Failed exit 1'), findsOneWidget);
      expect(resolution.writesToScrollback, isFalse);
      expect(
        find.descendant(
          of: find.byKey(const Key('terminal-scrollback')),
          matching: find.text('Failed exit 1'),
        ),
        findsNothing,
      );
    });

    testWidgets('can expose a jump to bottom action for the header', (
      tester,
    ) async {
      const scope = CommandBlockScope('session-a');
      final resolver = StickyCommandHeaderResolver();
      var jumpCount = 0;
      final resolution = resolver.resolve(
        blocks: [
          _block(
            id: 'long',
            command: 'seq 1 1000',
            scope: scope,
            inputStart: 0,
            outputStart: 1,
            outputEnd: 120,
          ),
        ],
        viewport: const StickyCommandHeaderViewport(
          scope: scope,
          visibleRange: CommandBlockRowRange(startRow: 40, endRowExclusive: 70),
        ),
      );

      await tester.pumpWidget(
        _app(
          StickyCommandHeaderOverlay(
            resolution: resolution,
            onJumpToBlockEnd: () => jumpCount += 1,
            child: const SizedBox(key: Key('terminal-surface')),
          ),
        ),
      );

      expect(find.byTooltip('Jump to bottom of block'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('sticky-command-header-jump-bottom')),
      );
      await tester.pump();

      expect(jumpCount, 1);
      expect(resolution.header?.blockEndRowExclusive, 120);
    });

    testWidgets('does not render when resolver disables the header', (
      tester,
    ) async {
      const resolution = StickyCommandHeaderResolution.disabled(
        visibleRange: CommandBlockRowRange(startRow: 0, endRowExclusive: 10),
        disabledReason: StickyCommandHeaderDisabledReason.altBufferActive,
      );

      await tester.pumpWidget(
        _app(
          StickyCommandHeaderOverlay(
            resolution: resolution,
            child: const SizedBox(key: Key('terminal-surface')),
          ),
        ),
      );

      expect(find.byKey(const Key('sticky-command-header')), findsNothing);
      expect(find.byKey(const Key('terminal-surface')), findsOneWidget);
    });
  });
}

Widget _app(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    ),
    home: Scaffold(
      body: Center(child: SizedBox(width: 480, child: child)),
    ),
  );
}

CommandBlock _block({
  required String id,
  required String command,
  required CommandBlockScope scope,
  required int inputStart,
  required int outputStart,
  required int outputEnd,
  String? cwd,
  int exitCode = 0,
  Duration duration = const Duration(seconds: 2),
}) {
  final startedAt = DateTime.utc(2026, 6, 15, 10);
  final finishedAt = startedAt.add(duration);
  return CommandBlock(
    id: id,
    sessionId: scope.sessionId,
    paneId: scope.paneId,
    command: command,
    cwd: cwd,
    startedAt: startedAt,
    finishedAt: finishedAt,
    exitCode: exitCode,
    status: exitCode == 0
        ? CommandInvocationStatus.succeeded
        : CommandInvocationStatus.failed,
    inputRange: CommandBlockRowRange(
      startRow: inputStart,
      endRowExclusive: inputStart + 1,
    ),
    outputRange: CommandBlockRowRange(
      startRow: outputStart,
      endRowExclusive: outputEnd,
    ),
  );
}
