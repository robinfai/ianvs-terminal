import 'dart:io';

import '../../src/workloads.dart';

void main() {
  final catalog = BenchWorkloadCatalog();
  for (final name in const <String>[
    'burst_stdout.seq_1000',
    'burst_stdout.seq_100k',
    'burst_stdout.repeated_payload_100k',
  ]) {
    final workload = catalog.resolve(name);
    workload.writeToDirectory(
      Directory('tools/bench/workloads/burst_stdout/${workload.profile}'),
    );
    stdout.writeln('generated $name');
  }
}
