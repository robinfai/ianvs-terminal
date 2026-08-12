import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/src/contracts/terminal_frame_normalization_policy.dart';
import 'package:ianvs_terminal_core/src/terminal/terminal_models.dart';

void main() {
  group(TerminalFrameNormalizationPolicy, () {
    test('normalizes bounded font and mode wire values', () {
      expect(
        TerminalFrameNormalizationPolicy.fontFamily('  Courier Prime  '),
        'Courier Prime',
      );
      expect(
        TerminalFrameNormalizationPolicy.fontFamily('bad\u0085font'),
        isNull,
      );
      expect(TerminalFrameNormalizationPolicy.fontFamily('x' * 257), isNull);
      expect(
        TerminalFrameNormalizationPolicy.mouseMode(' ANY_EVENT '),
        'any_event',
      );
      expect(
        TerminalFrameNormalizationPolicy.mouseEncoding('sgr-pixels'),
        'sgr_pixels',
      );
    });

    test('clips rows without retaining half of a wide grapheme', () {
      const row = TerminalRow(
        index: 0,
        text: 'A界B',
        styleRuns: <TerminalStyleRun>[TerminalStyleRun(start: 0, end: 1)],
      );

      final clipped = row.boundedToViewportColumns(2);
      final empty = row.boundedToViewportColumns(0);

      expect(clipped.text, 'A');
      expect(clipped.styleRuns, hasLength(1));
      expect(empty.text, isEmpty);
      expect(empty.styleRuns, isEmpty);
    });

    test('deduplicates, bounds, and orders rows in one shared rule', () {
      final rows = TerminalFrameNormalizationPolicy.normalizedRows(
        values: const <TerminalRow>[
          TerminalRow(index: 2, text: 'old'),
          TerminalRow(index: 0, text: 'zero'),
          TerminalRow(index: 2, text: 'new'),
          TerminalRow(index: 4, text: 'outside'),
        ],
        viewportRows: 3,
        viewportCols: 2,
        rawIndexOf: (row) => row.index,
        decode: (row) => row,
        indexOf: (row) => row.index,
        boundToColumns: (row, columns) => row.boundedToViewportColumns(columns),
      );

      expect(rows.map((row) => (row.index, row.text)), <(int, String)>[
        (0, 'ze'),
        (2, 'ne'),
      ]);
    });

    test('clamps and merges dirty ranges in one shared rule', () {
      final normalized = TerminalFrameNormalizationPolicy.normalizeDirtyRanges(
        ranges: const <_Range>[
          _Range(4, 9),
          _Range(-2, 2),
          _Range(2, 4),
          _Range(5, 5),
        ],
        viewportRows: 6,
        startOf: (range) => range.start,
        endOf: (range) => range.end,
        create: _Range.new,
      );

      expect(normalized, const <_Range>[_Range(0, 6)]);
    });

    test('filters invalid graphics and applies stable visual order', () {
      const validA = _Graphic(row: 1, col: 2, zIndex: 1);
      const validB = _Graphic(row: 0, col: 3, zIndex: 0);
      const invalidAsset = _Graphic(row: 0, col: 0, zIndex: 0, assetId: 0);

      final normalized = TerminalFrameNormalizationPolicy.normalizeGraphics(
        graphics: const <_Graphic?>[validA, invalidAsset, null, validB],
        viewportRows: 2,
        viewportCols: 4,
        rowOf: (graphic) => graphic.row,
        colOf: (graphic) => graphic.col,
        widthPxOf: (graphic) => graphic.widthPx,
        heightPxOf: (graphic) => graphic.heightPx,
        widthCellsOf: (graphic) => graphic.widthCells,
        heightCellsOf: (graphic) => graphic.heightCells,
        sourceXOffsetPxOf: (graphic) => graphic.sourceXOffsetPx,
        visibleWidthPxOf: (graphic) => graphic.visibleWidthPx,
        sourceYOffsetPxOf: (graphic) => graphic.sourceYOffsetPx,
        visibleHeightPxOf: (graphic) => graphic.visibleHeightPx,
        assetIdOf: (graphic) => graphic.assetId,
        assetVersionOf: (graphic) => graphic.assetVersion,
        zIndexOf: (graphic) => graphic.zIndex,
      );

      expect(normalized, const <_Graphic>[validB, validA]);
    });
  });
}

final class _Range {
  const _Range(this.start, this.end);

  final int start;
  final int end;

  @override
  bool operator ==(Object other) {
    return other is _Range && other.start == start && other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);
}

final class _Graphic {
  const _Graphic({
    required this.row,
    required this.col,
    required this.zIndex,
    this.assetId = 1,
  });

  final int row;
  final int col;
  final int zIndex;
  int get widthPx => 10;
  int get heightPx => 10;
  int get widthCells => 1;
  int get heightCells => 1;
  int get sourceXOffsetPx => 0;
  int get visibleWidthPx => 10;
  int get sourceYOffsetPx => 0;
  int get visibleHeightPx => 10;
  final int assetId;
  int get assetVersion => 1;
}
