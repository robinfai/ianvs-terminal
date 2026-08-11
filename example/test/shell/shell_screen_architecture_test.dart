import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shell screen library stays within explicit coordinator budgets', () {
    final shellScreen = _shellScreenFile();
    final source = shellScreen.readAsStringSync();
    final partNames = RegExp(
      r"^part '([^']+)';$",
      multiLine: true,
    ).allMatches(source).map((match) => match.group(1)!).toList();
    final partFiles = partNames
        .map((name) => File('${shellScreen.parent.path}/$name'))
        .toList(growable: false);

    expect(partNames, hasLength(27));
    expect(
      partFiles.where((file) => !file.existsSync()),
      isEmpty,
      reason: 'Every declared shell part must exist.',
    );

    final entryLineCount = shellScreen.readAsLinesSync().length;
    final partLineCounts = <String, int>{
      for (final file in partFiles) file.path: file.readAsLinesSync().length,
    };
    final aggregateLineCount = partLineCounts.values.fold(
      entryLineCount,
      (total, lines) => total + lines,
    );

    expect(entryLineCount, lessThanOrEqualTo(1600));
    expect(
      partLineCounts.entries.where((entry) => entry.value > 4100),
      isEmpty,
      reason: 'No shell part may become another unchecked mega-file.',
    );
    expect(
      aggregateLineCount,
      lessThanOrEqualTo(28000),
      reason: 'The complete part library, not only its entrypoint, is bounded.',
    );
  });
}

File _shellScreenFile() {
  const rootPath = 'example/lib/features/shell/shell_screen.dart';
  const packagePath = 'lib/features/shell/shell_screen.dart';
  return File(File(rootPath).existsSync() ? rootPath : packagePath);
}
