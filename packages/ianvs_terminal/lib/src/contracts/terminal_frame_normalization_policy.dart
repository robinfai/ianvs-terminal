import 'dart:convert';

import 'terminal_frame_validation_limits.dart';

enum TerminalWireCursorShape { block, underline, beam }

/// Read-only terminal-column projection used by wire-neutral text clipping.
abstract interface class TerminalTextColumnView {
  int get cellCount;

  int clampColumn(int value);

  bool isContinuationAt(int index);

  int columnAt(int index);

  int columnSpanAt(int index);

  String sliceColumns(int start, int end);
}

typedef TerminalRowWithText<T> =
    T Function(T row, String text, {required bool preserveStyleRuns});

/// Pure normalization shared by JSON/domain and protobuf wire adapters.
///
/// Generic accessors keep this policy independent from generated transports
/// and concrete terminal domain models.
abstract final class TerminalFrameNormalizationPolicy {
  static const int maxTerminalFontFamilyBytes = 256;

  static int clampNativeDimension(int value) {
    return value.clamp(0, TerminalFrameValidationLimits.maxNativeDimension);
  }

  static int? optionalNonNegativeScalar(int? value) {
    return value == null || value < 0 ? null : value;
  }

  static String? fontFamily(Object? value) {
    final family = value is String ? value.trim() : null;
    if (family == null ||
        family.isEmpty ||
        utf8.encode(family).length > maxTerminalFontFamilyBytes ||
        family.runes.any(
          (rune) => rune <= 0x1f || (rune >= 0x7f && rune <= 0x9f),
        )) {
      return null;
    }
    return family;
  }

  static TerminalWireCursorShape? cursorShape(Object? value) {
    return switch (value) {
      'block' => TerminalWireCursorShape.block,
      'underline' => TerminalWireCursorShape.underline,
      'beam' => TerminalWireCursorShape.beam,
      _ => null,
    };
  }

  static String mouseMode(Object? value) {
    final normalized = value is String ? value.trim().toLowerCase() : null;
    return switch (normalized) {
      'x10' => 'x10',
      'normal' => 'normal',
      'button_event' => 'button_event',
      'any_event' => 'any_event',
      _ => 'off',
    };
  }

  static String mouseEncoding(Object? value) {
    final normalized = value is String ? value.trim().toLowerCase() : null;
    return switch (normalized) {
      'sgr' => 'sgr',
      'sgr_pixels' || 'sgr-pixels' || 'sgrpixels' => 'sgr_pixels',
      'urxvt' => 'urxvt',
      'utf8' => 'utf8',
      _ => 'default',
    };
  }

  static List<TOutput> normalizedRows<TInput, TOutput>({
    required Iterable<TInput> values,
    required int viewportRows,
    required int viewportCols,
    required int? Function(TInput value) rawIndexOf,
    required TOutput? Function(TInput value) decode,
    required int Function(TOutput row) indexOf,
    required TOutput Function(TOutput row, int viewportCols) boundToColumns,
  }) {
    if (viewportRows <= 0) {
      return <TOutput>[];
    }
    final maxEntries = TerminalFrameValidationLimits.maxViewportBoundedEntries(
      viewportRows,
    );
    final scanLimit = TerminalFrameValidationLimits.maxEntriesToScan(
      maxEntries,
    );
    final rowsByIndex = <int, TOutput>{};
    var entriesScanned = 0;
    for (final value in values) {
      if (entriesScanned >= scanLimit) {
        break;
      }
      entriesScanned += 1;
      final rawIndex = rawIndexOf(value);
      if (rawIndex == null || rawIndex < 0 || rawIndex >= viewportRows) {
        continue;
      }
      final replacesExisting = rowsByIndex.containsKey(rawIndex);
      if (!replacesExisting && rowsByIndex.length >= maxEntries) {
        continue;
      }
      final row = decode(value);
      if (row == null) {
        continue;
      }
      final index = indexOf(row);
      if (index != rawIndex) {
        continue;
      }
      rowsByIndex[index] = boundToColumns(row, viewportCols);
    }
    final sortedIndexes = rowsByIndex.keys.toList(growable: false)..sort();
    return <TOutput>[for (final index in sortedIndexes) rowsByIndex[index]!];
  }

  static T rowBoundedToViewportColumns<T>({
    required T row,
    required String text,
    required int viewportCols,
    required TerminalTextColumnView Function(String text) columnsOf,
    required TerminalRowWithText<T> withText,
  }) {
    if (viewportCols <= 0) {
      return withText(row, '', preserveStyleRuns: false);
    }
    final columns = columnsOf(text);
    if (columns.cellCount <= viewportCols) {
      return row;
    }
    return withText(
      row,
      clipTextToCompleteColumns(columns, viewportCols),
      preserveStyleRuns: true,
    );
  }

  static String clipTextToCompleteColumns(
    TerminalTextColumnView columns,
    int endColumn,
  ) {
    final clampedEnd = columns.clampColumn(endColumn);
    if (clampedEnd <= 0) {
      return '';
    }

    var lastIndex = clampedEnd - 1;
    while (lastIndex > 0 && columns.isContinuationAt(lastIndex)) {
      lastIndex -= 1;
    }
    final lastColumn = columns.columnAt(lastIndex);
    if (lastColumn + columns.columnSpanAt(lastIndex) > clampedEnd) {
      return columns.sliceColumns(0, lastColumn);
    }
    return columns.sliceColumns(0, clampedEnd);
  }

  static List<T> normalizeDirtyRanges<T>({
    required Iterable<T> ranges,
    required int viewportRows,
    required int Function(T range) startOf,
    required int Function(T range) endOf,
    required T Function(int start, int end) create,
  }) {
    if (viewportRows <= 0) {
      return <T>[];
    }

    final maxEntries = TerminalFrameValidationLimits.maxViewportBoundedEntries(
      viewportRows,
    );
    final scanLimit = TerminalFrameValidationLimits.maxEntriesToScan(
      maxEntries,
    );
    final normalized = <(int, int)>[];
    var entriesScanned = 0;
    for (final range in ranges) {
      if (entriesScanned >= scanLimit || normalized.length >= maxEntries) {
        break;
      }
      entriesScanned += 1;
      final start = startOf(range).clamp(0, viewportRows);
      final end = endOf(range).clamp(start, viewportRows);
      if (start < end) {
        normalized.add((start, end));
      }
    }
    if (normalized.length < 2) {
      return <T>[for (final (start, end) in normalized) create(start, end)];
    }

    normalized.sort((left, right) {
      final byStart = left.$1.compareTo(right.$1);
      return byStart == 0 ? left.$2.compareTo(right.$2) : byStart;
    });
    final merged = <T>[];
    var (currentStart, currentEnd) = normalized.first;
    for (final (start, end) in normalized.skip(1)) {
      if (start <= currentEnd) {
        if (end > currentEnd) {
          currentEnd = end;
        }
        continue;
      }
      merged.add(create(currentStart, currentEnd));
      currentStart = start;
      currentEnd = end;
    }
    merged.add(create(currentStart, currentEnd));
    return merged;
  }

  static List<T> normalizeGraphics<T>({
    required Iterable<T?> graphics,
    required int viewportRows,
    required int viewportCols,
    required int Function(T graphic) rowOf,
    required int Function(T graphic) colOf,
    required int Function(T graphic) widthPxOf,
    required int Function(T graphic) heightPxOf,
    required int Function(T graphic) widthCellsOf,
    required int Function(T graphic) heightCellsOf,
    required int Function(T graphic) sourceXOffsetPxOf,
    required int Function(T graphic) visibleWidthPxOf,
    required int Function(T graphic) sourceYOffsetPxOf,
    required int Function(T graphic) visibleHeightPxOf,
    required int Function(T graphic) assetIdOf,
    required int Function(T graphic) assetVersionOf,
    required int Function(T graphic) zIndexOf,
  }) {
    final normalized = <T>[];
    for (final graphic in graphics) {
      if (graphic == null ||
          !isGraphicPlacementValid(
            row: rowOf(graphic),
            col: colOf(graphic),
            widthPx: widthPxOf(graphic),
            heightPx: heightPxOf(graphic),
            widthCells: widthCellsOf(graphic),
            heightCells: heightCellsOf(graphic),
            sourceXOffsetPx: sourceXOffsetPxOf(graphic),
            visibleWidthPx: visibleWidthPxOf(graphic),
            sourceYOffsetPx: sourceYOffsetPxOf(graphic),
            visibleHeightPx: visibleHeightPxOf(graphic),
            assetId: assetIdOf(graphic),
            assetVersion: assetVersionOf(graphic),
            viewportRows: viewportRows,
            viewportCols: viewportCols,
          )) {
        continue;
      }
      normalized.add(graphic);
    }
    normalized.sort((left, right) {
      final byZ = zIndexOf(left).compareTo(zIndexOf(right));
      if (byZ != 0) {
        return byZ;
      }
      final byRow = rowOf(left).compareTo(rowOf(right));
      if (byRow != 0) {
        return byRow;
      }
      return colOf(left).compareTo(colOf(right));
    });
    return List<T>.unmodifiable(normalized);
  }

  static bool isGraphicPlacementValid({
    required int row,
    required int col,
    required int widthPx,
    required int heightPx,
    required int widthCells,
    required int heightCells,
    required int sourceXOffsetPx,
    required int visibleWidthPx,
    required int sourceYOffsetPx,
    required int visibleHeightPx,
    required int assetId,
    required int assetVersion,
    int? viewportRows,
    int? viewportCols,
  }) {
    return row >= 0 &&
        (viewportRows == null || row < viewportRows) &&
        col >= 0 &&
        (viewportCols == null || col < viewportCols) &&
        widthPx > 0 &&
        heightPx > 0 &&
        widthCells > 0 &&
        heightCells > 0 &&
        sourceXOffsetPx >= 0 &&
        sourceXOffsetPx < widthPx &&
        visibleWidthPx > 0 &&
        visibleWidthPx <= widthPx - sourceXOffsetPx &&
        sourceYOffsetPx >= 0 &&
        sourceYOffsetPx < heightPx &&
        visibleHeightPx > 0 &&
        visibleHeightPx <= heightPx - sourceYOffsetPx &&
        assetId > 0 &&
        assetVersion > 0;
  }
}
