import 'dart:convert';
import 'dart:io';

/// Selects a supported physical iOS device from `flutter devices --machine`.
String selectPhysicalIosDeviceId(String source, {String? requestedDeviceId}) {
  return trySelectPhysicalIosDeviceId(
        source,
        requestedDeviceId: requestedDeviceId,
      ) ??
      (throw StateError(
        'No connected, supported physical iPhone was found. Unlock the device, '
        'trust this Mac, and enable Developer Mode before trying again.',
      ));
}

/// Selects a supported physical iOS device, or returns `null` when none exist.
///
/// An explicit [requestedDeviceId] remains strict and throws when it is not a
/// connected, supported physical iOS device. Multiple matches also require an
/// explicit selection.
String? trySelectPhysicalIosDeviceId(
  String source, {
  String? requestedDeviceId,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    throw FormatException(
      'Could not parse `flutter devices --machine`: ${error.message}',
    );
  }
  if (decoded is! List<Object?>) {
    throw const FormatException(
      '`flutter devices --machine` did not return a device list.',
    );
  }

  final physicalDevices = decoded
      .whereType<Map<Object?, Object?>>()
      .map(_FlutterDevice.fromJson)
      .where((device) => device.isSupportedPhysicalIos)
      .toList(growable: false);
  final requestedId = requestedDeviceId?.trim() ?? '';

  if (requestedId.isNotEmpty) {
    final matchingDevices = physicalDevices
        .where((device) => device.id == requestedId)
        .toList(growable: false);
    if (matchingDevices.length != 1) {
      throw StateError(
        'IPHONE_DEVICE=$requestedId is not a connected, supported physical '
        'iOS device.',
      );
    }
    return matchingDevices.single.id;
  }

  if (physicalDevices.isEmpty) {
    return null;
  }
  if (physicalDevices.length > 1) {
    final choices = physicalDevices
        .map((device) => '  ${device.name} (${device.id})')
        .join('\n');
    throw StateError(
      'Multiple physical iOS devices were found:\n$choices\n'
      'Choose one with: make install-iphone IPHONE_DEVICE=<device-id>',
    );
  }
  return physicalDevices.single.id;
}

Future<void> main(List<String> arguments) async {
  final optional = arguments.firstOrNull == '--optional';
  final positionalArguments = optional
      ? arguments.skip(1).toList(growable: false)
      : arguments;
  if (positionalArguments.length > 1) {
    stderr.writeln(
      'Usage: dart run tools/select_physical_ios_device.dart '
      '[--optional] [device-id]',
    );
    exitCode = 64;
    return;
  }

  try {
    final source = await utf8.decoder.bind(stdin).join();
    final selectedDeviceId = optional
        ? trySelectPhysicalIosDeviceId(
            source,
            requestedDeviceId: positionalArguments.firstOrNull,
          )
        : selectPhysicalIosDeviceId(
            source,
            requestedDeviceId: positionalArguments.firstOrNull,
          );
    if (selectedDeviceId != null) {
      stdout.writeln(selectedDeviceId);
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}

final class _FlutterDevice {
  const _FlutterDevice({
    required this.id,
    required this.name,
    required this.targetPlatform,
    required this.emulator,
    required this.isSupported,
  });

  factory _FlutterDevice.fromJson(Map<Object?, Object?> json) {
    return _FlutterDevice(
      id: json['id'] is String ? json['id']! as String : '',
      name: json['name'] is String ? json['name']! as String : 'Unknown device',
      targetPlatform: json['targetPlatform'] is String
          ? json['targetPlatform']! as String
          : '',
      emulator: json['emulator'] == true,
      isSupported: json['isSupported'] == true,
    );
  }

  final String id;
  final String name;
  final String targetPlatform;
  final bool emulator;
  final bool isSupported;

  bool get isSupportedPhysicalIos =>
      id.isNotEmpty &&
      targetPlatform.startsWith('ios') &&
      !emulator &&
      isSupported;
}
