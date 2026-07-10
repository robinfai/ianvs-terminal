import 'dart:convert';

final class FlutterProfileDevice {
  const FlutterProfileDevice({
    required this.id,
    required this.name,
    required this.rawTargetPlatform,
    required this.category,
  });

  final String id;
  final String name;
  final String rawTargetPlatform;
  final String category;

  static List<FlutterProfileDevice> parseMachineJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException(
        'flutter devices --machine did not return a list',
      );
    }
    return decoded
        .whereType<Map>()
        .map((entry) {
          final json = entry.cast<String, Object?>();
          return FlutterProfileDevice(
            id: _stringValue(json['id']),
            name: _stringValue(json['name']),
            rawTargetPlatform: _stringValue(
              json['targetPlatform'] ?? json['platform'],
            ),
            category: _stringValue(json['category']),
          );
        })
        .toList(growable: false);
  }

  bool get isSupported => unsupportedReason == null;

  String? get unsupportedReason {
    if (id.isEmpty) {
      return 'missing device id';
    }
    if (category == 'web' || rawTargetPlatform.startsWith('web-')) {
      return 'web targets cannot compile the native dart:ffi dependency';
    }
    return null;
  }

  String get targetPlatform {
    if (rawTargetPlatform.startsWith('android')) {
      return 'android';
    }
    if (rawTargetPlatform.startsWith('ios')) {
      return 'ios';
    }
    if (rawTargetPlatform.startsWith('darwin') || id == 'macos') {
      return 'macos';
    }
    if (rawTargetPlatform.startsWith('linux')) {
      return 'linux';
    }
    if (rawTargetPlatform.startsWith('windows')) {
      return 'windows';
    }
    return rawTargetPlatform.isEmpty ? id : rawTargetPlatform;
  }

  String get targetLabel => _pathSegment('$id-$rawTargetPlatform');
}

final class FlutterProfileMatrixCommand {
  const FlutterProfileMatrixCommand({
    required this.device,
    required this.outputRoot,
    required this.workloads,
    required this.repeats,
    required this.frameCount,
    this.correctnessSuitesPassed = false,
  });

  final FlutterProfileDevice device;
  final String outputRoot;
  final List<String> workloads;
  final int repeats;
  final int frameCount;
  final bool correctnessSuitesPassed;

  List<String> get flutterDriveArgs {
    final outputPath = '$outputRoot/${device.targetLabel}';
    return <String>[
      'drive',
      '--driver=test_driver/integration_test.dart',
      '--target=integration_test/terminal_render_profile_test.dart',
      '-d',
      device.id,
      '--profile',
      '--dart-define=IANVS_BENCH_PROFILE_OUTPUT=$outputPath',
      '--dart-define=IANVS_BENCH_PROFILE_TARGET_LABEL=${device.targetLabel}',
      '--dart-define=IANVS_BENCH_PROFILE_WORKLOADS=${workloads.join(',')}',
      '--dart-define=IANVS_BENCH_PROFILE_REPEATS=$repeats',
      '--dart-define=IANVS_BENCH_PROFILE_FRAME_COUNT=$frameCount',
      '--dart-define=IANVS_BENCH_CORRECTNESS_SUITES_PASSED=$correctnessSuitesPassed',
    ];
  }
}

final class FlutterProfileProcessCommand {
  const FlutterProfileProcessCommand({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
}

bool requiresCursorOverlayCorrectnessSuites(List<String> workloads) {
  final workloadSet = workloads.toSet();
  return workloadSet.contains('cursor_blink_idle_surface_profile') &&
      workloadSet.contains('cursor_blink_idle_overlay_profile');
}

List<FlutterProfileProcessCommand> cursorOverlayCorrectnessSuiteCommands(
  List<String> workloads,
) {
  if (!requiresCursorOverlayCorrectnessSuites(workloads)) {
    return const <FlutterProfileProcessCommand>[];
  }
  return const <FlutterProfileProcessCommand>[
    FlutterProfileProcessCommand(
      executable: 'flutter',
      arguments: <String>[
        'test',
        'test/terminal_viewport_render_test.dart',
        '--name',
        'cursor|graphic',
      ],
      workingDirectory: 'packages/ianvs_terminal',
    ),
    FlutterProfileProcessCommand(
      executable: 'flutter',
      arguments: <String>[
        'test',
        'test/terminal/render_terminal_viewport_test.dart',
        '--name',
        'cursor',
      ],
      workingDirectory: 'example',
    ),
    FlutterProfileProcessCommand(
      executable: 'flutter',
      arguments: <String>[
        'test',
        'test/terminal_input_controller_test.dart',
        '--plain-name',
        'terminal viewport keeps composing text visible across cursor blink frames',
      ],
      workingDirectory: 'example',
    ),
  ];
}

final class FlutterProfileMatrixOptions {
  const FlutterProfileMatrixOptions({
    required this.outputRoot,
    required this.readinessOutput,
    required this.runbookOutput,
    required this.workloads,
    required this.repeats,
    required this.frameCount,
    required this.requiredTargetCount,
    required this.deviceIds,
    required this.dryRun,
  });

  static const defaultWorkloads = <String>[
    'burst_stdout_profile',
    'scrollback_heavy_profile',
    'resize_churn_profile',
  ];

  final String outputRoot;
  final String? readinessOutput;
  final String? runbookOutput;
  final List<String> workloads;
  final int repeats;
  final int frameCount;
  final int requiredTargetCount;
  final List<String> deviceIds;
  final bool dryRun;

  static FlutterProfileMatrixOptions parse(List<String> args) {
    final values = <String, List<String>>{};
    var dryRun = false;
    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (arg == '--dry-run') {
        dryRun = true;
        continue;
      }
      if (!arg.startsWith('--')) {
        throw FormatException('Unexpected argument: $arg');
      }

      final withoutPrefix = arg.substring(2);
      final equalsIndex = withoutPrefix.indexOf('=');
      if (equalsIndex >= 0) {
        _addValue(
          values,
          withoutPrefix.substring(0, equalsIndex),
          withoutPrefix.substring(equalsIndex + 1),
        );
        continue;
      }

      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        throw FormatException('Missing value for --$withoutPrefix');
      }
      _addValue(values, withoutPrefix, args[index + 1]);
      index += 1;
    }

    return FlutterProfileMatrixOptions(
      outputRoot: _singleValue(
        values,
        'output',
        'build/bench-results-profile/matrix',
      ),
      readinessOutput: _optionalSingleValue(values, 'readiness-output'),
      runbookOutput: _optionalSingleValue(values, 'runbook-output'),
      workloads: _commaListValue(values, 'workloads', defaultWorkloads),
      repeats: _positiveIntValue(values, 'repeats', 5),
      frameCount: _positiveIntValue(values, 'frame-count', 96),
      requiredTargetCount: _positiveIntValue(values, 'require-target-count', 1),
      deviceIds: List<String>.unmodifiable(values['device'] ?? const []),
      dryRun: dryRun,
    );
  }
}

final class FlutterProfileReadinessRunbook {
  const FlutterProfileReadinessRunbook({
    required this.readiness,
    required this.outputRoot,
    required this.readinessOutput,
    required this.runbookOutput,
    required this.workloads,
    required this.repeats,
    required this.frameCount,
  });

  final FlutterProfileReadinessReport readiness;
  final String outputRoot;
  final String? readinessOutput;
  final String? runbookOutput;
  final List<String> workloads;
  final int repeats;
  final int frameCount;

  String toMarkdown() {
    final missingTargets =
        readiness.requiredTargetCount - readiness.supportedTargetCount;
    final buffer = StringBuffer()
      ..writeln('# Flutter Profile Target Runbook')
      ..writeln()
      ..writeln('- Ready: `${readiness.ready}`')
      ..writeln('- Required native targets: `${readiness.requiredTargetCount}`')
      ..writeln(
        '- Supported native targets: `${readiness.supportedTargetCount}`',
      )
      ..writeln(
        '- Missing native targets: `${missingTargets > 0 ? missingTargets : 0}`',
      )
      ..writeln()
      ..writeln('## Supported Targets')
      ..writeln()
      ..writeln('| id | name | platform | label |')
      ..writeln('|---|---|---|---|');
    for (final device in readiness.devices.where(
      (device) => device.isSupported,
    )) {
      buffer.writeln(
        '| ${_markdownCell(device.id)} | ${_markdownCell(device.name)} | '
        '${_markdownCell(device.targetPlatform)} | '
        '${_markdownCell(device.targetLabel)} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Skipped Targets')
      ..writeln()
      ..writeln('| id | name | platform | reason |')
      ..writeln('|---|---|---|---|');
    for (final device in readiness.devices.where(
      (device) => !device.isSupported,
    )) {
      buffer.writeln(
        '| ${_markdownCell(device.id)} | ${_markdownCell(device.name)} | '
        '${_markdownCell(device.targetPlatform)} | '
        '${_markdownCell(device.unsupportedReason ?? '')} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Commands')
      ..writeln()
      ..writeln('Discover targets:')
      ..writeln()
      ..writeln('```bash')
      ..writeln('flutter devices')
      ..writeln('flutter emulators')
      ..writeln('```')
      ..writeln()
      ..writeln(
        'Run the real Flutter profile matrix after connecting another native target:',
      )
      ..writeln()
      ..writeln('```bash')
      ..writeln(_matrixCommand())
      ..writeln('```')
      ..writeln()
      ..writeln('Merge the resulting target directories into a formal report:')
      ..writeln()
      ..writeln('```bash')
      ..writeln(_auditCommand())
      ..writeln('```')
      ..writeln();
    return buffer.toString();
  }

  String _matrixCommand() {
    return [
      'dart run tools/bench/runner/flutter_profile_matrix_runner.dart',
      '--output ${_shell(outputRoot)}',
      if (readinessOutput != null)
        '--readiness-output ${_shell(readinessOutput!)}',
      if (runbookOutput != null) '--runbook-output ${_shell(runbookOutput!)}',
      '--workloads ${_shell(workloads.join(','))}',
      '--repeats $repeats',
      '--frame-count $frameCount',
      '--require-target-count ${readiness.requiredTargetCount}',
    ].join(' ');
  }

  String _auditCommand() {
    return [
      'dart run tools/bench/analysis/flutter_profile_audit.dart',
      '--input ${_shell('$outputRoot/<target-run-a>')}',
      '--input ${_shell('$outputRoot/<target-run-b>')}',
      '--output ${_shell('$outputRoot/formal-report')}',
      if (readinessOutput != null)
        '--readiness-output ${_shell(readinessOutput!)}',
      if (runbookOutput != null) '--runbook-output ${_shell(runbookOutput!)}',
      '--workloads ${_shell(workloads.join(','))}',
      '--repeats $repeats',
      '--require-target-count ${readiness.requiredTargetCount}',
    ].join(' ');
  }
}

final class FlutterProfileReadinessReport {
  FlutterProfileReadinessReport.fromDevices(
    List<FlutterProfileDevice> devices, {
    required this.requiredTargetCount,
  }) : devices = List<FlutterProfileDevice>.unmodifiable(devices);

  final List<FlutterProfileDevice> devices;
  final int requiredTargetCount;

  int get supportedTargetCount =>
      devices.where((device) => device.isSupported).length;

  bool get ready => supportedTargetCount >= requiredTargetCount;

  Map<String, Object?> toJson() {
    final supportedTargets = devices
        .where((device) => device.isSupported)
        .map(_targetJson)
        .toList(growable: false);
    final unsupportedTargets = devices
        .where((device) => !device.isSupported)
        .map((device) {
          return <String, Object?>{
            ..._targetJson(device),
            'reason': device.unsupportedReason,
          };
        })
        .toList(growable: false);
    return <String, Object?>{
      'schema_version': 'ianvs-bench-flutter-profile-readiness-v1',
      'ready': ready,
      'required_target_count': requiredTargetCount,
      'supported_target_count': supportedTargetCount,
      'supported_targets': supportedTargets,
      'unsupported_targets': unsupportedTargets,
      'failures': [
        if (!ready)
          'requires $requiredTargetCount supported native Flutter targets, '
              'found $supportedTargetCount',
      ],
    };
  }

  Map<String, Object?> _targetJson(FlutterProfileDevice device) {
    return <String, Object?>{
      'id': device.id,
      'name': device.name,
      'category': device.category,
      'target_platform': device.targetPlatform,
      'raw_target_platform': device.rawTargetPlatform,
      'target_label': device.targetLabel,
    };
  }
}

void assertRequiredProfileTargetCount(
  List<FlutterProfileDevice> devices, {
  required int requiredCount,
}) {
  final supportedCount = devices.where((device) => device.isSupported).length;
  if (supportedCount >= requiredCount) {
    return;
  }
  final unsupportedDetails = devices
      .where((device) => !device.isSupported)
      .map((device) => '${device.id}: ${device.unsupportedReason}')
      .join('; ');
  throw StateError(
    'Profile matrix requires $requiredCount supported native Flutter targets, '
    'found $supportedCount. Unsupported targets: $unsupportedDetails',
  );
}

String _stringValue(Object? value) => value?.toString() ?? '';

String _pathSegment(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return sanitized.isEmpty ? 'unknown' : sanitized;
}

String _markdownCell(String value) => value.replaceAll('|', r'\|');

String _shell(String value) {
  if (RegExp(r'^[A-Za-z0-9._/,:=+-]+$').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", r"'\''")}'";
}

void _addValue(Map<String, List<String>> values, String key, String value) {
  values.putIfAbsent(key, () => <String>[]).add(value);
}

String _singleValue(
  Map<String, List<String>> values,
  String key,
  String fallback,
) {
  final entries = values[key];
  if (entries == null || entries.isEmpty) {
    return fallback;
  }
  return entries.last;
}

String? _optionalSingleValue(Map<String, List<String>> values, String key) {
  final entries = values[key];
  if (entries == null || entries.isEmpty) {
    return null;
  }
  return entries.last;
}

List<String> _commaListValue(
  Map<String, List<String>> values,
  String key,
  List<String> fallback,
) {
  final value = _singleValue(values, key, '');
  if (value.isEmpty) {
    return List<String>.unmodifiable(fallback);
  }
  final parsed = value
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
  if (parsed.isEmpty) {
    throw FormatException('Missing values for --$key');
  }
  return List<String>.unmodifiable(parsed);
}

int _positiveIntValue(
  Map<String, List<String>> values,
  String key,
  int fallback,
) {
  final source = _singleValue(values, key, '$fallback');
  final parsed = int.tryParse(source);
  if (parsed == null || parsed <= 0) {
    throw FormatException('--$key must be a positive integer');
  }
  return parsed;
}
