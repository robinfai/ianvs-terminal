import 'command_occurrence.dart';
import 'terminal_models.dart';

/// Immutable provenance captured when a command produced its output.
/// Shell-reported hostnames are hints, never transport authorization.
class TerminalSemanticContext {
  const TerminalSemanticContext({
    required this.occurrenceId,
    required this.sessionId,
    required this.sessionEpoch,
    required this.cwd,
    this.contextId,
    this.shellHostname,
    this.sftpContextId,
    this.frameRevision,
    this.viewportRow,
  });

  factory TerminalSemanticContext.fromOccurrence(
    CommandOccurrence occurrence, {
    String? frameRevision,
    int? viewportRow,
  }) => TerminalSemanticContext(
    occurrenceId: occurrence.id,
    sessionId: occurrence.scope.sessionId,
    sessionEpoch: occurrence.scope.sessionEpoch,
    cwd: occurrence.cwd,
    contextId: occurrence.contextId,
    shellHostname: occurrence.shellHostname,
    sftpContextId: occurrence.sftpContextId,
    frameRevision: frameRevision,
    viewportRow: viewportRow,
  );

  final String occurrenceId;
  final String sessionId;
  final int sessionEpoch;
  final String cwd;
  final String? contextId;
  final String? shellHostname;
  final String? sftpContextId;

  /// Raw viewport ownership evidence. Both values must be revalidated before
  /// acting after a menu, confirmation, or delayed click. Block snapshots omit
  /// them and retain their existing command occurrence provenance.
  final String? frameRevision;
  final int? viewportRow;
}

class TerminalSemanticFileTarget {
  const TerminalSemanticFileTarget({
    required this.path,
    required this.context,
    this.line,
    this.column,
  });

  /// An unquoted path. The host resolves it using [context], never live cwd.
  final String path;
  final int? line;
  final int? column;
  final TerminalSemanticContext context;
}

class TerminalSemanticTarget {
  const TerminalSemanticTarget({required this.text, this.fileTarget});
  final String text;
  final TerminalSemanticFileTarget? fileTarget;
}

typedef TerminalSemanticContextResolver =
    TerminalSemanticContext? Function(TerminalRow row);

final _url = RegExp(r'''(?:https?|file)://[^\s<>"']+''');
final _token = RegExp(
  r'''"[^"\r\n]+"(?::[0-9]+){0,2}|'[^'\r\n]+'(?::[0-9]+){0,2}|(?:\\ |[^\s<>"'()])+''',
);
final _location = RegExp(r':([1-9][0-9]*)(?::([1-9][0-9]*))?$');
final _filename = RegExp(r'^[^/\\:]+\.[A-Za-z0-9_+-]+$');

/// Detects only within a bounded, contiguous logical line. Callers must prefer
/// explicit OSC 8 hyperlinks before this heuristic. Missing provenance disables
/// file detection; URL detection does not require a working directory.
TerminalSemanticTarget? terminalSemanticTargetAt({
  required List<TerminalRow> rows,
  required int row,
  required int column,
  TerminalSemanticContextResolver? contextForRow,
}) {
  final selected = rows.indexWhere((candidate) => candidate.index == row);
  if (selected < 0 || column < 0) return null;
  bool contiguous(TerminalRow a, TerminalRow b) =>
      a.index + 1 == b.index &&
      (a.sourceRow == null && b.sourceRow == null ||
          a.sourceRow != null &&
              b.sourceRow == (a.sourceEndRow ?? a.sourceRow)! + 1);
  var first = selected;
  var last = selected;
  while (first > 0 &&
      selected - first < 32 &&
      contiguous(rows[first - 1], rows[first]) &&
      rows[first - 1].wrapped) {
    first--;
  }
  while (last + 1 < rows.length &&
      last - first < 32 &&
      rows[last].wrapped &&
      contiguous(rows[last], rows[last + 1])) {
    last++;
  }
  final leftTruncated = first == 0
      ? (rows[first].sourceRow ?? rows[first].index) > 0
      : rows[first - 1].wrapped;
  final rightTruncated = rows[last].wrapped;
  final parts = rows.sublist(first, last + 1);
  if (parts.any((r) => r.text.length > 32768) ||
      parts.fold<int>(0, (n, r) => n + r.text.length) > 32768) {
    return null;
  }
  final selectedText = rows[selected].text;
  final cells = TerminalTextCells.fromText(selectedText);
  final codeUnit = cells.codeUnitForColumn(column);
  if (codeUnit >= selectedText.length) return null;
  var hit = codeUnit;
  for (var i = first; i < selected; i++) {
    hit += rows[i].text.length;
  }
  final text = parts.map((part) => part.text).join();
  bool truncated(Match match) =>
      match.start == 0 && leftTruncated ||
      match.end == text.length && rightTruncated;
  TerminalSemanticContext? fileContext() {
    final context = contextForRow?.call(rows[selected]);
    if (context == null ||
        context.cwd.isEmpty ||
        context.occurrenceId.isEmpty) {
      return null;
    }
    // File URIs and ordinary paths have identical ownership requirements:
    // joining fragments from separate commands would invent a file candidate.
    for (final part in parts) {
      final other = contextForRow?.call(part);
      if (other == null ||
          other.occurrenceId != context.occurrenceId ||
          other.sessionId != context.sessionId ||
          other.sessionEpoch != context.sessionEpoch ||
          other.contextId != context.contextId ||
          other.cwd != context.cwd ||
          other.frameRevision != context.frameRevision ||
          other.sftpContextId != context.sftpContextId) {
        return null;
      }
    }
    return context;
  }

  for (final match in _url.allMatches(text)) {
    if (truncated(match)) continue;
    var value = match.group(0)!;
    while (value.isNotEmpty) {
      final end = value[value.length - 1];
      const pairs = {')': '(', ']': '[', '}': '{'};
      final open = pairs[end];
      final excessClosing =
          open != null &&
          end.allMatches(value).length > open.allMatches(value).length;
      if (!'.,;:!?'.contains(end) && !excessClosing) break;
      value = value.substring(0, value.length - 1);
    }
    if (hit >= match.start && hit < match.start + value.length) {
      if (value.startsWith('file://') && fileContext() == null) return null;
      return TerminalSemanticTarget(text: value);
    }
  }
  final context = fileContext();
  if (context == null) return null;
  for (final match in _token.allMatches(text)) {
    if (hit < match.start || hit >= match.end) continue;
    // Never recognize a cut-off suffix/prefix of a wrapped token.
    if (truncated(match)) return null;
    var value = match.group(0)!;
    while (value.isNotEmpty && '.,;:!?]}'.contains(value[value.length - 1])) {
      value = value.substring(0, value.length - 1);
    }
    int? line;
    int? col;
    final location = _location.firstMatch(value);
    if (location != null) {
      line = int.tryParse(location.group(1)!);
      col = int.tryParse(location.group(2) ?? '');
      if (line == null ||
          line > 2147483647 ||
          (col != null && col > 2147483647)) {
        return null;
      }
      value = value.substring(0, location.start);
    }
    if (value.length >= 2 &&
        (value.startsWith('"') && value.endsWith('"') ||
            value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    value = value.replaceAll(r'\ ', ' ');
    if (value.isEmpty ||
        value.contains('://') ||
        value.contains(':') ||
        value.contains(r'\') ||
        value.runes.any((c) => c < 32 || c == 127) ||
        !(value.contains('/') || _filename.hasMatch(value))) {
      return null;
    }
    // Home expansion requires an independently captured home directory.
    if (value.startsWith('~')) return null;
    return TerminalSemanticTarget(
      text: match.group(0)!,
      fileTarget: TerminalSemanticFileTarget(
        path: value,
        line: line,
        column: col,
        context: context,
      ),
    );
  }
  return null;
}
