import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/runtime/terminal_resize_coordinator.dart';

void main() {
  group('TerminalResizeCoordinator', () {
    test('plans viewport resizes and suppresses committed duplicates', () {
      final coordinator = TerminalResizeCoordinator();
      const sessionId = 'session-1';

      final first = coordinator.planViewportResize(
        sessionId,
        viewportSize: const Size(189, 162),
        devicePixelRatio: 2,
        cellSize: const Size(9, 18),
      );

      expect(first, isNotNull);
      expect(first!.isDuplicate, isFalse);
      expect(first.metric, _resizeMetric(cols: 21, rows: 9, dpr: 2));
      expect(first.viewportSize, const Size(189, 162));

      coordinator.commit(sessionId, first.metric);

      final duplicate = coordinator.planViewportResize(
        sessionId,
        viewportSize: const Size(189, 162),
        devicePixelRatio: 2,
        cellSize: const Size(9, 18),
      );

      expect(duplicate, isNotNull);
      expect(duplicate!.isDuplicate, isTrue);
      expect(duplicate.metric, first.metric);
    });

    test('logical cell changes survive identical rounded native pixels', () {
      final coordinator = TerminalResizeCoordinator();
      const sessionId = 'session-1';
      final first = coordinator.planCellResize(
        sessionId,
        cols: 80,
        rows: 24,
        cellSize: const Size(8.1, 17.1),
      );
      coordinator.commit(sessionId, first.metric);

      final changed = coordinator.planCellResize(
        sessionId,
        cols: 80,
        rows: 24,
        cellSize: const Size(8.4, 17.4),
      );
      expect(changed.metric.cellWidth, first.metric.cellWidth);
      expect(changed.metric.cellHeight, first.metric.cellHeight);
      expect(changed.isDuplicate, isFalse);
      expect(changed.metric.logicalCellWidth, 8.4);
      expect(changed.metric.logicalCellHeight, 17.4);
    });

    test('returns null for invalid viewport resize inputs', () {
      final coordinator = TerminalResizeCoordinator();

      expect(
        coordinator.planViewportResize(
          'session-1',
          viewportSize: const Size(double.infinity, 162),
          devicePixelRatio: 1,
          cellSize: const Size(9, 18),
        ),
        isNull,
      );
      expect(
        coordinator.planViewportResize(
          'session-1',
          viewportSize: const Size(189, 162),
          devicePixelRatio: double.nan,
          cellSize: const Size(9, 18),
        ),
        isNull,
      );
      expect(
        coordinator.planViewportResize(
          'session-1',
          viewportSize: const Size(189, 162),
          devicePixelRatio: 1,
          cellSize: Size.zero,
        ),
        isNull,
      );
    });

    test('plans explicit cell resizes with bounded dimensions', () {
      const maxDimension = 1000;
      final coordinator = TerminalResizeCoordinator(maxDimension: maxDimension);

      final plan = coordinator.planCellResize(
        'session-1',
        cols: maxDimension + 10,
        rows: maxDimension + 20,
        devicePixelRatio: 1.5,
        cellSize: const Size(10, 20),
      );

      expect(plan.isDuplicate, isFalse);
      expect(plan.metric.cols, maxDimension);
      expect(plan.metric.rows, maxDimension);
      expect(plan.metric.pixelWidth, maxDimension);
      expect(plan.metric.pixelHeight, maxDimension);
      expect(plan.metric.cellWidth, 15);
      expect(plan.metric.cellHeight, 30);
      expect(
        plan.viewportSize,
        const Size(maxDimension * 10, maxDimension * 20),
      );
    });

    test('plans native resize events from the last committed metric', () {
      final coordinator = TerminalResizeCoordinator();
      const sessionId = 'session-1';
      final initial = coordinator.planViewportResize(
        sessionId,
        viewportSize: const Size(180, 144),
        devicePixelRatio: 1,
        cellSize: const Size(9, 18),
      )!;
      coordinator.commit(sessionId, initial.metric);

      final plan = coordinator.planNativeResizeEvent(
        sessionId,
        cols: 21,
        rows: 9,
        cellSize: const Size(9, 18),
      );

      expect(plan, isNotNull);
      expect(plan!.metric, _resizeMetric(cols: 21, rows: 9));
      expect(plan.viewportSize, const Size(189, 162));
      expect(plan.widthDelta, 9);
      expect(plan.heightDelta, 18);
    });

    test('remove clears committed resize state', () {
      final coordinator = TerminalResizeCoordinator();
      const sessionId = 'session-1';
      final first = coordinator.planCellResize(
        sessionId,
        cols: 80,
        rows: 24,
        cellSize: const Size(9, 18),
      );
      coordinator.commit(sessionId, first.metric);
      expect(
        coordinator
            .planCellResize(
              sessionId,
              cols: 80,
              rows: 24,
              cellSize: const Size(9, 18),
            )
            .isDuplicate,
        isTrue,
      );

      coordinator.remove(sessionId);

      expect(
        coordinator
            .planCellResize(
              sessionId,
              cols: 80,
              rows: 24,
              cellSize: const Size(9, 18),
            )
            .isDuplicate,
        isFalse,
      );
    });
  });
}

TerminalResizeMetric _resizeMetric({
  required int cols,
  required int rows,
  double dpr = 1,
}) {
  return TerminalResizeMetric(
    cols: cols,
    rows: rows,
    pixelWidth: (cols * 9 * dpr).round(),
    pixelHeight: (rows * 18 * dpr).round(),
    cellWidth: (9 * dpr).round(),
    cellHeight: (18 * dpr).round(),
    logicalWidth: cols * 9,
    logicalHeight: rows * 18,
    logicalCellWidth: 9,
    logicalCellHeight: 18,
    devicePixelRatio: dpr,
  );
}
