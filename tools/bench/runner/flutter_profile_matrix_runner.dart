import 'dart:convert';
import 'dart:io';

import '../src/flutter_profile_matrix.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage);
    return;
  }

  try {
    final options = FlutterProfileMatrixOptions.parse(args);
    final devices = await _loadFlutterDevices();
    final selectedDevices = _selectedDevices(devices, options);
    final readinessReport = FlutterProfileReadinessReport.fromDevices(
      selectedDevices,
      requiredTargetCount: options.requiredTargetCount,
    );
    if (options.readinessOutput != null) {
      _writeJsonFile(options.readinessOutput!, readinessReport.toJson());
    }
    if (options.runbookOutput != null) {
      _writeTextFile(
        options.runbookOutput!,
        FlutterProfileReadinessRunbook(
          readiness: readinessReport,
          outputRoot: options.outputRoot,
          readinessOutput: options.readinessOutput,
          runbookOutput: options.runbookOutput,
          workloads: options.workloads,
          repeats: options.repeats,
          frameCount: options.frameCount,
        ).toMarkdown(),
      );
    }
    assertRequiredProfileTargetCount(
      selectedDevices,
      requiredCount: options.requiredTargetCount,
    );

    final commands = selectedDevices
        .where((device) => device.isSupported)
        .map(
          (device) => FlutterProfileMatrixCommand(
            device: device,
            outputRoot: options.outputRoot,
            workloads: options.workloads,
            repeats: options.repeats,
            frameCount: options.frameCount,
          ),
        )
        .toList(growable: false);

    if (options.dryRun) {
      for (final command in commands) {
        stdout.writeln('flutter ${jsonEncode(command.flutterDriveArgs)}');
      }
      return;
    }

    for (final command in commands) {
      final exitCode = await _runFlutterDrive(command.flutterDriveArgs);
      if (exitCode != 0) {
        stderr.writeln('flutter drive failed with exit code $exitCode');
        ioExitCode = exitCode;
        return;
      }
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage);
    ioExitCode = 64;
  } on StateError catch (error) {
    stderr.writeln(error.message);
    ioExitCode = 1;
  } on Object catch (error) {
    stderr.writeln('Flutter profile matrix failed: $error');
    ioExitCode = 1;
  }
}

set ioExitCode(int value) {
  exitCode = value;
}

Future<List<FlutterProfileDevice>> _loadFlutterDevices() async {
  final result = await Process.run('flutter', const [
    'devices',
    '--machine',
  ], workingDirectory: 'example');
  if (result.exitCode != 0) {
    throw StateError('flutter devices --machine failed: ${result.stderr}');
  }
  return FlutterProfileDevice.parseMachineJson(result.stdout as String);
}

List<FlutterProfileDevice> _selectedDevices(
  List<FlutterProfileDevice> devices,
  FlutterProfileMatrixOptions options,
) {
  if (options.deviceIds.isEmpty) {
    return devices;
  }
  final selected = <FlutterProfileDevice>[];
  for (final id in options.deviceIds) {
    final matches = devices.where((device) => device.id == id);
    if (matches.isEmpty) {
      throw StateError('Requested Flutter device not found: $id');
    }
    selected.add(matches.single);
  }
  return selected;
}

void _writeJsonFile(String path, Map<String, Object?> json) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  file.writeAsStringSync('${encoder.convert(json)}\n');
}

void _writeTextFile(String path, String content) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

Future<int> _runFlutterDrive(List<String> args) async {
  final process = await Process.start(
    'flutter',
    args,
    workingDirectory: 'example',
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

const _usage = '''
Ianvs real Flutter profile matrix runner

Usage:
  dart run tools/bench/runner/flutter_profile_matrix_runner.dart \\
    --output build/bench-results-profile/<run> \\
    --require-target-count 2

Options:
  --output <dir>                 Root output directory.
  --readiness-output <file>      Write target readiness JSON before gates.
  --runbook-output <file>        Write target setup/run commands before gates.
  --workloads <a,b,c>            Profile workloads to run.
  --repeats <n>                  Repeat count per workload. Default: 5.
  --frame-count <n>              Frame count per repeat. Default: 96.
  --device <id>                  Restrict to a device; may be repeated.
  --require-target-count <n>     Minimum supported native targets. Default: 1.
  --dry-run                      Print flutter drive commands without running.

Web targets are skipped because the current profile harness depends on native
dart:ffi packages through ianvs_pty.
''';
