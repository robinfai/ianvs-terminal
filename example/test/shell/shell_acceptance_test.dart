import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/shell_screen.dart';

void main() {
  group('shellAcceptanceProbeProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('is disabled by default', () {
      expect(container.read(shellAcceptanceProbeProvider), isNull);
    });
  });
}
