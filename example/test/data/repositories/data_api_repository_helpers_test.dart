import 'package:app/data/repositories/data_api_repository_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dataApiJsonEquivalent', () {
    test('treats equivalent JSON numbers equally across runtimes', () {
      expect(
        dataApiJsonEquivalent(
          <String, Object?>{
            'fontSize': 14.0,
            'nested': <Object?>[22, 1.5],
          },
          <String, Object?>{
            'nested': <Object?>[22.0, 1.5],
            'fontSize': 14,
          },
        ),
        isTrue,
      );
    });

    test('still rejects different values and document shapes', () {
      expect(dataApiJsonEquivalent(14, 14.5), isFalse);
      expect(
        dataApiJsonEquivalent(
          <String, Object?>{'value': 1},
          <String, Object?>{'value': 1, 'extra': null},
        ),
        isFalse,
      );
      expect(dataApiJsonEquivalent(<Object?>[1, 2], <Object?>[1, 3]), isFalse);
    });
  });
}
