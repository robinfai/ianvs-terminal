import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final packageRoot = Directory('lib/src').existsSync()
      ? Directory.current
      : Directory('packages/ianvs_terminal');

  test(
    'terminal input depends on a capability port, not runtime orchestration',
    () {
      final source = File(
        '${packageRoot.path}/lib/src/terminal/terminal_input_controller.dart',
      ).readAsStringSync();

      expect(source, contains("import 'terminal_input_sink.dart';"));
      expect(source, isNot(contains("import '../runtime/")));
      expect(source, contains('final TerminalInputSink runtime;'));
    },
  );

  test('domain never imports transport implementations or generated proto', () {
    final violations = <String>[];
    for (final domain in <String>['terminal', 'config', 'recording']) {
      final directory = Directory('${packageRoot.path}/lib/src/$domain');
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final source = entity.readAsStringSync();
        if (RegExp(
          r'''import\s+['"][^'"]*(?:src/|\.\./)(?:proto|transport)/''',
        ).hasMatch(source)) {
          violations.add(entity.path);
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Domain files may depend on neutral contracts, but must receive '
          'decoded models from transport adapters: '
          '${violations.join(', ')}',
    );
  });

  test('runtime frame decoders receive domain models through transport', () {
    for (final relativePath in <String>[
      'runtime/terminal_frame_decoder.dart',
      'runtime/terminal_frame_packet_v1.dart',
    ]) {
      final source = File(
        '${packageRoot.path}/lib/src/$relativePath',
      ).readAsStringSync();
      expect(source, isNot(contains('../proto/')), reason: relativePath);
      expect(source, contains('../transport/'), reason: relativePath);
    }
  });
}
