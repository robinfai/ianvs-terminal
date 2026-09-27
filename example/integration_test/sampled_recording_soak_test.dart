import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/app.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/recording/sampled_recording_library.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/platform/app_shutdown_coordinator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;
import 'package:integration_test/integration_test.dart';

import '../test/support/macos_integration_test_lifecycle.dart';
import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_local_terminal_config_repository.dart';
import '../test/support/memory_paste_history_repository.dart';
import '../test/support/memory_profile_repository.dart';

const _seconds = int.fromEnvironment('IANVS_RECORDING_SOAK_SECONDS');
const _output = String.fromEnvironment('IANVS_RECORDING_SOAK_OUTPUT');
const _fixture = String.fromEnvironment('IANVS_RECORDING_SSH_FIXTURE');
const _revision = String.fromEnvironment('IANVS_RECORDING_SOAK_REVISION');
const _standalone = bool.fromEnvironment('IANVS_RECORDING_STANDALONE');

// Fixed histograms avoid a growing collection of per-frame/per-input metrics.
class _Histogram {
  static const limits = [
    1000,
    2000,
    4000,
    8000,
    16000,
    33000,
    50000,
    100000,
    250000,
    500000,
    1000000,
    2000000,
    5000000,
    15000000,
  ];
  final counts = List<int>.filled(limits.length + 1, 0);
  int total = 0;
  int sum = 0;
  int maximum = 0;
  void add(int micros) {
    var bucket = 0;
    while (bucket < limits.length && micros > limits[bucket]) {
      bucket++;
    }
    counts[bucket]++;
    total++;
    sum += micros;
    if (micros > maximum) maximum = micros;
  }

  Map<String, Object?> toJson() => {
    'count': total,
    'sum_micros': sum,
    'max_micros': maximum,
    'upper_bounds_micros': limits,
    'buckets': counts,
  };
}

Future<void> _until(bool Function() condition, String description) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 20)) {
      fail('Timed out: $description');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

String _workload(String phase) => switch (phase) {
  'logs' =>
    r"i=0; while [ $i -lt 120 ]; do printf 'log %04d 雪 abcdefghijklmnopqrstuvwxyz0123456789\n' $i; i=$((i+1)); done",
  'tui' =>
    r"printf '\033[?1049h'; i=0; while [ $i -lt 20 ]; do printf '\033[2J\033[H\033[32mTUI frame %d 雪\033[0m\n' $i; j=0; while [ $j -lt 16 ]; do printf 'row %02d progress=%03d\n' $j $i; j=$((j+1)); done; i=$((i+1)); sleep 0.05; done; printf '\033[?1049l'",
  _ => r"pwd; printf 'quoted argument: %s\n' '保留 雪 spaces'",
};

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (_standalone) {
    unawaited(
      binding.allTestsPassed.future.then((passed) async {
        stdout.writeln(
          'IANVS_RECORDING_SOAK_RESULT=${passed ? 'passed' : 'failed'}',
        );
        await stdout.flush();
        exit(passed ? 0 : 1);
      }),
    );
  }
  testWidgets(
    'real-duration full-application recording soak',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(binding);
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      expect(_seconds, greaterThanOrEqualTo(60));
      expect(_output, isNotEmpty);
      expect(_fixture, isNotEmpty);
      final directory = await Directory(_output).create(recursive: true);
      final fixture =
          jsonDecode(await File(_fixture).readAsString())
              as Map<String, dynamic>;
      final nodes = fixture['nodes'] as Map<String, dynamic>;
      final remote = nodes['a'] as Map<String, dynamic>;
      final profileLocal = TerminalProfile(
        id: 'soak-local',
        name: 'Soak local Bash',
        shell: '/bin/bash',
        cwd: directory.path,
        env: {
          'IANVS_SKIP_ORIGINAL_BASHRC': '1',
          'HISTFILE': '${directory.path}/shell-history',
        },
      );
      final profileRemote = TerminalProfile.configured(
        id: 'soak-ssh',
        name: 'Soak SSH',
        sessionConfig: terminal.TerminalSessionConfig(
          launch: const terminal.TerminalLaunchConfig(program: '/bin/sh'),
          connection: terminal.TerminalConnectionConfig.ssh(
            host: '127.0.0.1',
            user: 'lab',
            port: remote['port'] as int,
            auth: terminal.TerminalSshAuthMethod.publicKey,
            privateKeys: [fixture['key'] as String],
            hostKeyPolicy: terminal.TerminalSshHostKeyPolicy.strict,
            knownHostsFile: fixture['known_hosts'] as String,
            keepaliveSeconds: 15,
          ),
          shellIntegration: const terminal.TerminalShellIntegrationConfig(
            sshAutoInject: true,
            sshWrapper: true,
          ),
        ),
      );
      final backend = NativePtyBackend.load();
      final files = terminal.NativeRecordingFileApi();
      final library = SampledRecordingLibrary(
        files: files,
        directoryResolver: () async =>
            Directory('${directory.path}/recordings-v2'),
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(backend),
          sampledRecordingLibraryProvider.overrideWithValue(library),
          sampledRecordingFileApiProvider.overrideWithValue(files),
          profileRepositoryProvider.overrideWithValue(
            MemoryProfileRepository(
              TerminalProfilesDocument(profiles: [profileLocal, profileRemote]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            MemoryAppPreferencesRepository(null),
          ),
          pasteHistoryRepositoryProvider.overrideWithValue(
            MemoryPasteHistoryRepository(),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            MemoryLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                layout: LocalTerminalLayoutConfig(restoreLayout: false),
              ),
            ),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            LocalTerminalLayoutRepository(
              directoryResolver: () async => directory,
            ),
          ),
          shellAnimationsEnabledProvider.overrideWithValue(false),
        ],
      );
      final report = <String, Object?>{
        'requested_seconds': _seconds,
        'revision': _revision,
        'os': Platform.operatingSystemVersion,
        'release_mode': kReleaseMode,
        'qualifies_long_duration': false,
        'passed': false,
        'latency_scope':
            'runtime dispatch of a short echo command to its naturally refreshed visible marker; excludes workload execution time and physical keyboard dispatch',
        'frame_policy':
            'fullyLive; no forced pumps or manual runtime refresh during workloads',
      };
      final metrics = await File(
        '${directory.path}/metrics.jsonl',
      ).open(mode: FileMode.append);
      final buildTimes = <String, _Histogram>{};
      final rasterTimes = <String, _Histogram>{};
      final inputTimes = <String, _Histogram>{};
      final workloadTimes = <String, _Histogram>{};
      final markers = <String, String>{};
      var phase = 'setup';
      var sequence = 0;
      var maximumHeartbeatGapMicros = 0;
      final lifetime = Stopwatch()..start();
      var lastMetricMicros = 0;
      void timings(List<FrameTiming> values) {
        for (final frame in values) {
          (buildTimes[phase] ??= _Histogram()).add(
            frame.buildDuration.inMicroseconds,
          );
          (rasterTimes[phase] ??= _Histogram()).add(
            frame.rasterDuration.inMicroseconds,
          );
        }
      }

      SchedulerBinding.instance.addTimingsCallback(timings);
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const IanvsTerminalApp(),
          ),
        );
        await _until(
          () => container.read(sessionControllerProvider).isReady,
          'local startup',
        );
        final controller = container.read(sessionControllerProvider.notifier);
        final runtime = container.read(terminalRuntimeControllerProvider);
        final local = container
            .read(sessionControllerProvider)
            .activeSessionId!;
        controller.createSession(profileRemote);
        final ssh = container.read(sessionControllerProvider).activeSessionId!;
        expect(ssh, isNot(local));
        final sessions = {'local': local, 'ssh': ssh};
        final client = container.read(sampledRecordingCaptureClientProvider)!;
        String text(String id) => runtime
            .viewportFor(id)
            .frame
            .rows
            .map((row) => row.text)
            .join('\n');
        Future<void> command(
          String name,
          String body, {
          bool retainMarker = true,
        }) async {
          final id = sessions[name]!;
          expect(
            runtime.hasSession(id),
            isTrue,
            reason: '$name session must remain alive',
          );
          final tag = 'soak_${sequence++}_${name}_end';
          final line = "$body; printf 'IANVS-%s\\n' '$tag'";
          final latency = Stopwatch()..start();
          runtime.sendInput(id, utf8.encode('$line\n'));
          await _until(
            () => text(id).contains('IANVS-$tag'),
            '$name command $tag',
          );
          (workloadTimes['$phase/$name'] ??= _Histogram()).add(
            latency.elapsedMicroseconds,
          );
          final echoTag = 'ping_${sequence++}_${name}_end';
          final echoClock = Stopwatch()..start();
          runtime.sendInput(
            id,
            utf8.encode("printf 'IANVS-%s\\n' '$echoTag'\n"),
          );
          await _until(
            () => text(id).contains('IANVS-$echoTag'),
            '$name input echo',
          );
          (inputTimes['$phase/$name'] ??= _Histogram()).add(
            echoClock.elapsedMicroseconds,
          );
          // Bash DEBUG hooks may report only the first simple command of a
          // compound input line. Search the independent echo command, whose
          // complete text is actually supplied by the shell hook.
          if (retainMarker) markers['$name/$phase'] = echoTag;
        }

        Future<void> metric() async {
          final now = lifetime.elapsedMicroseconds;
          final gap = now - lastMetricMicros;
          if (lastMetricMicros != 0 && gap > maximumHeartbeatGapMicros) {
            maximumHeartbeatGapMicros = gap;
          }
          lastMetricMicros = now;
          final cpu = await Process.run('/bin/ps', [
            '-p',
            '$pid',
            '-o',
            'time=,rss=,%cpu=',
          ]);
          expect(cpu.exitCode, 0);
          final disk = await Process.run('/bin/df', ['-Pk', directory.path]);
          expect(disk.exitCode, 0);
          final availableKiB = int.parse(
            disk.stdout
                .toString()
                .trim()
                .split('\n')
                .last
                .trim()
                .split(RegExp(r'\s+'))[3],
          );
          final bytes = await library.storageBytes();
          expect(
            availableKiB,
            greaterThan(2 * 1024 * 1024),
            reason: 'Leave at least 2 GiB free on the host',
          );
          expect(
            bytes,
            lessThan(10 * 1024 * 1024 * 1024),
            reason: 'Bound this owned acceptance run to 10 GiB',
          );
          final captures = <Map<String, Object?>>[];
          for (final claim in library.activeClaims) {
            final status = client.status(claim.handle);
            expect(status.phase, terminal.SampledCapturePhase.capturing);
            expect(status.error, isNull);
            captures.add({
              'capture_id': claim.handle.captureId,
              'session_id': claim.handle.sessionId,
              'written_records': status.written.recordCount,
              'committed_records': status.committed.recordCount,
              'written_duration_micros': status.written.durationMicros,
              'committed_duration_micros': status.committed.durationMicros,
              'uncommitted_timeline_micros':
                  status.written.durationMicros -
                  status.committed.durationMicros,
            });
          }
          final sample = {
            'utc': DateTime.now().toUtc().toIso8601String(),
            'elapsed_micros': now,
            'phase': phase,
            'rss_bytes': ProcessInfo.currentRss,
            'max_rss_bytes': ProcessInfo.maxRss,
            'ps_time_rss_kib_cpu_percent': cpu.stdout.toString().trim(),
            'library_bytes': bytes,
            'available_disk_kib': availableKiB,
            'captures': captures,
          };
          await metrics.writeString('${jsonEncode(sample)}\n');
          await metrics.flush();
          await File(
            '${directory.path}/heartbeat.json',
          ).writeAsString(jsonEncode(sample), flush: true);
        }

        await command('local', 'pwd', retainMarker: false);
        await command('ssh', 'hostname', retainMarker: false);
        const phaseSeconds = _seconds > 86400 ? 60 : 10;
        Future<void> runPhases(int seconds, String mode) async {
          final clock = Stopwatch()..start();
          var lastPhase = -1;
          while (clock.elapsed.inSeconds < seconds) {
            final index = (clock.elapsed.inSeconds ~/ phaseSeconds) % 4;
            final workload = ['shell', 'logs', 'tui', 'idle'][index];
            phase = '$mode/$workload';
            if (lastPhase != index) {
              controller.activateSession(index.isEven ? local : ssh);
              lastPhase = index;
            }
            if (workload != 'idle') {
              await command('local', _workload(workload));
              await command('ssh', _workload(workload));
            }
            if (lifetime.elapsedMicroseconds - lastMetricMicros >= 10000000) {
              await metric();
            }
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }

        // Equivalent workloads without capture form a measured application baseline.
        await runPhases(phaseSeconds * 4, 'baseline');
        for (final id in sessions.values) {
          expect(await controller.startSessionRecording(id), isTrue);
        }
        await _until(
          () =>
              library.activeClaims.length == 2 &&
              library.activeClaims.every(
                (claim) =>
                    client.status(claim.handle).phase ==
                    terminal.SampledCapturePhase.capturing,
              ),
          'both recording writers started',
        );
        final recordingClock = Stopwatch()..start();
        report['capture_started_utc'] = DateTime.now()
            .toUtc()
            .toIso8601String();
        await runPhases(_seconds, 'recording');
        phase = 'recording/final';
        await command('local', 'pwd');
        await command('ssh', 'hostname');
        await metric();
        recordingClock.stop();
        report['capture_elapsed_micros'] = recordingClock.elapsedMicroseconds;
        report['capture_ended_utc'] = DateTime.now().toUtc().toIso8601String();
        expect(
          recordingClock.elapsed.inSeconds,
          greaterThanOrEqualTo(_seconds),
        );
        expect(
          maximumHeartbeatGapMicros,
          lessThan(120000000),
          reason:
              'sleep/suspension or stalled progress invalidates a continuous run',
        );
        final paths = <String, String>{};
        for (final name in sessions.keys) {
          paths[name] = (await controller.stopSessionRecording(
            sessions[name]!,
          ))!;
          await library.setKeep(paths[name]!, true);
        }
        phase = 'verification';
        final verification = <Map<String, Object?>>[];
        for (final name in sessions.keys) {
          final openWatch = Stopwatch()..start();
          final opened = await library.openRecording(paths[name]!);
          final openMicros = openWatch.elapsedMicroseconds;
          try {
            final info = opened.recording.info;
            expect(
              info.completion,
              terminal.SampledRecordingCompletion.finished,
            );
            expect(info.duration.inSeconds, greaterThanOrEqualTo(_seconds));
            final seekTimes = <int>[];
            for (var sample = 0; sample < 13; sample++) {
              final seekWatch = Stopwatch()..start();
              expect(
                await opened.recording.seek(
                  Duration(
                    microseconds: info.duration.inMicroseconds * sample ~/ 12,
                  ),
                ),
                isNotNull,
              );
              seekTimes.add(seekWatch.elapsedMicroseconds);
            }
            final searchTimes = <int>[];
            for (final item in markers.entries.where(
              (entry) => entry.key.startsWith('$name/recording/'),
            )) {
              final searchWatch = Stopwatch()..start();
              var cursor = 0;
              var found = false;
              while (true) {
                final page = await opened.recording.search(
                  query: item.value,
                  kind: terminal.SampledRecordingSearchKind.command,
                  cursor: cursor,
                );
                if (page.hits.isNotEmpty) {
                  found = true;
                  break;
                }
                if (page.nextCursor == null) break;
                cursor = page.nextCursor!;
              }
              expect(
                found,
                isTrue,
                reason: 'retained real hook command ${item.key}',
              );
              searchTimes.add(searchWatch.elapsedMicroseconds);
            }
            verification.add({
              'name': name,
              'id': info.id,
              'path': info.path,
              'source_bytes': info.sourceBytes,
              'duration_micros': info.duration.inMicroseconds,
              'visual_count': info.visualCount,
              'semantic_count': info.semanticCount,
              'open_micros': openMicros,
              'seek_micros': seekTimes,
              'command_search_micros': searchTimes,
            });
          } finally {
            await opened.close();
          }
        }
        report['recordings'] = verification;
        report['qualifies_long_duration'] =
            _seconds > 86400 &&
            recordingClock.elapsed.inSeconds > 86400 &&
            kReleaseMode;
        report['passed'] = true;
      } on Object catch (error) {
        report['error'] = '$error';
        rethrow;
      } finally {
        SchedulerBinding.instance.removeTimingsCallback(timings);
        report['maximum_heartbeat_gap_micros'] = maximumHeartbeatGapMicros;
        report['frame_build'] = buildTimes.map(
          (key, value) => MapEntry(key, value.toJson()),
        );
        report['frame_raster'] = rasterTimes.map(
          (key, value) => MapEntry(key, value.toJson()),
        );
        report['workload_completion'] = workloadTimes.map(
          (key, value) => MapEntry(key, value.toJson()),
        );
        report['input_to_frame'] = inputTimes.map(
          (key, value) => MapEntry(key, value.toJson()),
        );
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          final shutdown = await container
              .read(appShutdownCoordinatorProvider)
              .shutdown(bounded: false)
              .timeout(const Duration(seconds: 45));
          report['safe_to_terminate'] = shutdown.safeToTerminate;
          if (!shutdown.safeToTerminate) report['passed'] = false;
        } on Object catch (error) {
          report['passed'] = false;
          report['shutdown_error'] = '$error';
        }
        container.dispose();
        files.dispose();
        await metrics.close();
        await File('${directory.path}/result.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
          flush: true,
        );
        expect(report['passed'], isTrue);
      }
    },
    skip: _seconds == 0 || !Platform.isMacOS,
    timeout: const Timeout(Duration(seconds: _seconds + 900)),
  );
}
