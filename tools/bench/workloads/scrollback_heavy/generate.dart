import 'dart:io';

import '../../src/workloads.dart';

void main() {
  final catalog = BenchWorkloadCatalog();
  for (final name in const <String>[
    'scrollback_heavy.lines_1000',
    'scrollback_heavy.lines_100k',
    'scrollback_heavy.lines_200k',
  ]) {
    final workload = catalog.resolve(name);
    workload.writeToDirectory(
      Directory('tools/bench/workloads/scrollback_heavy/${workload.profile}'),
    );
    stdout.writeln('generated $name');
  }
}
