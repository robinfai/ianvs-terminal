part of 'command_blocks_view.dart';

/// Searches one retained-output version in bounded pages. Only matching row
/// identities are retained; text, styling, filtering and user selection stay
/// owned by the native reader. A new query/version cancels an older scan.
class _ReaderFind extends ChangeNotifier {
  _ReaderFind(this.request);
  final CommandBlockRequest request;
  final editor = TextEditingController();
  List<({int ordinal, int index})> rows = const [];
  int active = -1;
  int? get activeRow => active < 0 ? null : rows.elementAtOrNull(active)?.index;
  bool busy = false;
  bool unavailable = false;
  int _generation = 0;

  Future<void> scan({
    required String id,
    required int count,
    required int? sourceBase,
    required CommandBlockFilter? filter,
    int? retainIndex,
  }) async {
    final generation = ++_generation;
    final query = editor.text.toLowerCase();
    rows = const [];
    active = -1;
    unavailable = false;
    busy = query.isNotEmpty;
    notifyListeners();
    if (!busy) return;
    final found = <({int ordinal, int index})>[];
    var offset = 0;
    while (offset < count) {
      // Yield between bounded replies; typing, scrolling and closing the
      // reader must remain responsive even for large retained transcripts.
      await Future<void>.delayed(Duration.zero);
      if (generation != _generation) return;
      final page = CommandBlock.fromJson(
        request({
          'id': id,
          'offset': offset,
          'limit': (count - offset).clamp(1, 128),
          ...?filter?.toJson(),
        })?['block'],
      );
      if (page == null ||
          page.lines.isEmpty ||
          page.offset != offset ||
          page.sourceLineBase != sourceBase) {
        unavailable = true;
        break;
      }
      for (var i = 0; i < page.lines.length && offset + i < count; i++) {
        final row = page.lines[i];
        if (row.text.toLowerCase().contains(query)) {
          found.add((ordinal: offset + i, index: row.index));
        }
      }
      offset += page.lines.length;
    }
    if (generation != _generation) return;
    rows = unavailable ? const [] : found;
    active = retainIndex == null
        ? -1
        : rows.indexWhere((r) => r.index == retainIndex);
    busy = false;
    notifyListeners();
  }

  void clear() {
    ++_generation;
    editor.clear();
    rows = const [];
    active = -1;
    busy = false;
    unavailable = false;
    notifyListeners();
  }

  @override
  void dispose() {
    ++_generation;
    editor.dispose();
    super.dispose();
  }
}

class _ReaderLineNumbers extends CustomPainter {
  const _ReaderLineNumbers({
    required this.rows,
    required this.lineNumberOffset,
    required this.rowHeight,
    required this.style,
    required this.scaler,
    required this.divider,
  });
  final List<TerminalRow> rows;
  final int lineNumberOffset;
  final double rowHeight;
  final TextStyle style;
  final TextScaler scaler;
  final Color divider;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = divider;
    canvas.drawLine(
      Offset(size.width - 8, 0),
      Offset(size.width - 8, size.height),
      paint,
    );
    final text = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    );
    for (var i = 0; i < rows.length; i++) {
      text.text = TextSpan(
        text: '${rows[i].index + 1 + lineNumberOffset}',
        style: style,
      );
      text.layout();
      text.paint(
        canvas,
        Offset(
          size.width - 16 - text.width,
          i * rowHeight + (rowHeight - text.height) / 2,
        ),
      );
    }
    text.dispose();
  }

  @override
  bool shouldRepaint(_ReaderLineNumbers old) =>
      rows != old.rows ||
      lineNumberOffset != old.lineNumberOffset ||
      rowHeight != old.rowHeight ||
      style != old.style ||
      scaler != old.scaler ||
      divider != old.divider;
}
