import 'dart:io';

import '../../src/workloads.dart';

void main() {
  final catalog = BenchWorkloadCatalog();
  for (final name in const <String>[
    'resize_churn.tiny',
    'resize_churn.basic',
    'resize_churn.extended',
  ]) {
    final workload = catalog.resolve(name);
    workload.writeToDirectory(
      Directory('tools/bench/workloads/resize_churn/${workload.profile}'),
    );
    stdout.writeln('generated $name');
  }
}
