abstract final class TerminalFrameValidationLimits {
  static const int maxNativeDimension = 0xffff;
  static const int maxStyleRunsPerRow = 1024;
  static const int maxHyperlinksPerFrame = 4096;
  static const int maxInlineImagesPerFrame = 32;
  static const int maxInlineImageDecodedBytes = 4 * 1024 * 1024;
  static const int malformedCollectionSlack = 64;
  static const int malformedCollectionScanMultiplier = 4;

  static int maxViewportBoundedEntries(int viewportRows) {
    if (viewportRows <= 0) {
      return malformedCollectionSlack;
    }
    return (viewportRows + malformedCollectionSlack)
        .clamp(0, maxNativeDimension)
        .toInt();
  }

  static int maxEntriesToScan(int maxEntries) {
    return (maxEntries * malformedCollectionScanMultiplier)
        .clamp(0, maxNativeDimension)
        .toInt();
  }

  static T? decodeViewportBounded<T>({
    required int row,
    required int col,
    required int widthCells,
    required int heightCells,
    required int viewportRows,
    required int viewportCols,
    required T? Function({required int widthCells, required int heightCells})
    decode,
  }) {
    if (viewportRows <= 0 ||
        viewportCols <= 0 ||
        row < 0 ||
        row >= viewportRows ||
        col < 0 ||
        col >= viewportCols ||
        widthCells <= 0 ||
        heightCells <= 0) {
      return null;
    }
    final boundedWidthCells = widthCells.clamp(1, viewportCols - col).toInt();
    final boundedHeightCells = heightCells.clamp(1, viewportRows - row).toInt();
    return decode(
      widthCells: boundedWidthCells,
      heightCells: boundedHeightCells,
    );
  }
}
