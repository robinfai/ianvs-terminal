import 'dart:convert';

import 'package:test/test.dart';

import '../tools/select_physical_ios_device.dart';

void main() {
  group('selectPhysicalIosDeviceId', () {
    test('selects the only supported physical iOS device', () {
      final source = jsonEncode(<Map<String, Object?>>[
        _device(
          id: 'simulator',
          name: 'iPhone Simulator',
          targetPlatform: 'ios',
          emulator: true,
        ),
        _device(
          id: 'physical-iphone',
          name: "Robin's iPhone",
          targetPlatform: 'ios',
          emulator: false,
        ),
        _device(
          id: 'macos',
          name: 'macOS',
          targetPlatform: 'darwin',
          emulator: false,
        ),
        _device(
          id: 'unsupported-ios',
          name: 'Unsupported iPhone',
          targetPlatform: 'ios',
          emulator: false,
          isSupported: false,
        ),
      ]);

      expect(selectPhysicalIosDeviceId(source), 'physical-iphone');
    });

    test('honors an explicit physical device id', () {
      final source = jsonEncode(<Map<String, Object?>>[
        _device(
          id: 'iphone-a',
          name: 'iPhone A',
          targetPlatform: 'ios',
          emulator: false,
        ),
        _device(
          id: 'iphone-b',
          name: 'iPhone B',
          targetPlatform: 'ios',
          emulator: false,
        ),
      ]);

      expect(
        selectPhysicalIosDeviceId(source, requestedDeviceId: 'iphone-b'),
        'iphone-b',
      );
    });

    test('rejects an explicit simulator id', () {
      final source = jsonEncode(<Map<String, Object?>>[
        _device(
          id: 'simulator',
          name: 'iPhone Simulator',
          targetPlatform: 'ios',
          emulator: true,
        ),
      ]);

      expect(
        () => selectPhysicalIosDeviceId(source, requestedDeviceId: 'simulator'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('not a connected, supported physical iOS device'),
          ),
        ),
      );
    });

    test('requires an explicit id when multiple physical devices exist', () {
      final source = jsonEncode(<Map<String, Object?>>[
        _device(
          id: 'iphone-a',
          name: 'iPhone A',
          targetPlatform: 'ios',
          emulator: false,
        ),
        _device(
          id: 'iphone-b',
          name: 'iPhone B',
          targetPlatform: 'ios',
          emulator: false,
        ),
      ]);

      expect(
        () => selectPhysicalIosDeviceId(source),
        throwsA(
          isA<StateError>()
              .having(
                (error) => error.message,
                'message',
                contains('Multiple physical iOS devices were found'),
              )
              .having(
                (error) => error.message,
                'selection hint',
                contains('IPHONE_DEVICE=<device-id>'),
              ),
        ),
      );
    });

    test('reports when no physical device exists', () {
      expect(
        () => selectPhysicalIosDeviceId('[]'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('No connected, supported physical iPhone was found'),
          ),
        ),
      );
    });
  });

  group('trySelectPhysicalIosDeviceId', () {
    test('returns null when no physical iPhone exists', () {
      expect(trySelectPhysicalIosDeviceId('[]'), isNull);
    });

    test('still rejects an explicit non-physical device id', () {
      final source = jsonEncode(<Map<String, Object?>>[
        _device(
          id: 'simulator',
          name: 'iPhone Simulator',
          targetPlatform: 'ios',
          emulator: true,
        ),
      ]);

      expect(
        () => trySelectPhysicalIosDeviceId(
          source,
          requestedDeviceId: 'simulator',
        ),
        throwsStateError,
      );
    });
  });
}

Map<String, Object?> _device({
  required String id,
  required String name,
  required String targetPlatform,
  required bool emulator,
  bool isSupported = true,
}) {
  return <String, Object?>{
    'id': id,
    'name': name,
    'targetPlatform': targetPlatform,
    'emulator': emulator,
    'isSupported': isSupported,
  };
}
