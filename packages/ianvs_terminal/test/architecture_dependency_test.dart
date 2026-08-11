import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'terminal input depends on a capability port, not runtime orchestration',
    () {
      final source = File(
        'lib/src/terminal/terminal_input_controller.dart',
      ).readAsStringSync();

      expect(source, contains("import 'terminal_input_sink.dart';"));
      expect(source, isNot(contains("import '../runtime/")));
      expect(source, contains('final TerminalInputSink runtime;'));
    },
  );
}
