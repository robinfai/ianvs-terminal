import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:app/features/recording/sampled_recording_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

Future<void> _until(bool Function() predicate, String description) async {
  final clock = Stopwatch()..start();
  while (!predicate() && clock.elapsed < const Duration(seconds: 15)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(predicate(), isTrue, reason: description);
}

void main() {
  final path =
      Platform.environment['IANVS_CORE_LIB'] ??
      <String>[
            'native/core/target/debug/libianvs_core.dylib',
            '../native/core/target/debug/libianvs_core.dylib',
            'native/core/target/debug/libianvs_core.so',
            '../native/core/target/debug/libianvs_core.so',
          ]
          .map(File.new)
          .where((file) => file.existsSync())
          .firstOrNull
          ?.absolute
          .path;
  for (final shell in ['/bin/bash', '/bin/zsh', '/opt/homebrew/bin/fish']) {
    test(
      'installed $shell hooks survive sampled recording and replay exactly',
      () async {
        final root = await Directory.systemTemp.createTemp('recorded-shell-');
        final settings = await Directory(
          '${root.path}/shell-settings',
        ).create();
        final backend = NativePtyBackend.fromBindings(
          NativePtyBindings(ffi.DynamicLibrary.open(path!)),
        );
        final runtime = TerminalRuntimeController(
          backend: backend,
          copyToClipboard: (_) async {},
          readClipboard: () async => '',
        );
        final files = NativeRecordingFileApi(libraryPath: path);
        final library = SampledRecordingLibrary(
          files: files,
          directoryResolver: () async => Directory('${root.path}/library'),
        );
        final client = SampledRecordingCaptureClient(backend: backend);
        final environment = <String, String>{
          'HISTFILE': '${settings.path}/history',
          if (shell.endsWith('/bash')) 'IANVS_SKIP_ORIGINAL_BASHRC': '1',
          if (shell.endsWith('/zsh')) 'ZDOTDIR': settings.path,
          if (shell.endsWith('/fish')) ...{
            'XDG_CONFIG_HOME': settings.path,
            'XDG_DATA_HOME': settings.path,
            'fish_history': 'ianvs_acceptance',
          },
        };
        final session = runtime.createSession(
          TerminalSessionConfig(
            launch: TerminalLaunchConfig(
              program: shell,
              env: environment,
              cwd: root.path,
            ),
          ),
        );
        SampledRecordingClaim? claim;
        void send(String command) =>
            runtime.sendInput(session, utf8.encode('$command\n'));
        String screen() {
          runtime.refreshSession(session);
          return runtime
              .viewportFor(session)
              .frame
              .rows
              .map((row) => row.text)
              .join('\n');
        }

        try {
          send(r"printf 'IANVS-%s\n' 'ready'");
          await _until(
            () => screen().contains('IANVS-ready'),
            'installed shell startup',
          );
          claim = await library.reserve(
            sessionId: session,
            sessionEpoch: runtime.sessionEpochFor(session)!,
            title: shell,
          );
          await library.start(claim, client);
          await _until(
            () =>
                client.status(claim!.handle).phase ==
                SampledCapturePhase.capturing,
            'capture start',
          );
          const quoted = r"printf 'IANVS-%s\n' 'quoted 雪 argument'";
          send(quoted);
          await _until(
            () => screen().contains('IANVS-quoted 雪 argument'),
            'quoted Unicode command output',
          );
          send('false');
          const done = r"printf 'IANVS-%s\n' 'done'";
          send(done);
          await _until(
            () => screen().contains('IANVS-done'),
            'finished marker',
          );
          await Future<void>.delayed(const Duration(milliseconds: 300));
          final destination = await library.finish(claim, client);
          runtime.closeSession(session);
          final opened = await library.openRecording(destination);
          try {
            final timeline = await opened.recording.timeline();
            for (final command in [quoted, 'false', done]) {
              expect(
                timeline.events.where(
                  (event) =>
                      event.kind == SampledTimelineKind.commandStarted &&
                      event.command == command,
                ),
                hasLength(1),
                reason: '$shell must preserve exact command text',
              );
              expect(
                timeline.events.where(
                  (event) =>
                      event.kind == SampledTimelineKind.commandFinished &&
                      event.command == command &&
                      event.exitCode == (command == 'false' ? 1 : 0),
                ),
                hasLength(1),
                reason: '$shell must preserve command completion',
              );
            }
            final frame = (await opened.recording.seek(
              opened.recording.info.duration,
            ))!;
            expect(
              frame.frame.rows.any(
                (row) => row.text.contains('IANVS-quoted 雪 argument'),
              ),
              isTrue,
            );
            final search = await opened.recording.search(
              query: 'quoted 雪 argument',
              kind: SampledRecordingSearchKind.command,
            );
            expect(search.hits, isNotEmpty);
            expect(runtime.hasSession(session), isFalse);
          } finally {
            await opened.close();
          }
        } finally {
          if (claim?.dispatched == true && library.activeClaims.isNotEmpty) {
            await library.finish(claim!, client);
          }
          runtime.dispose();
          files.dispose();
          await root.delete(recursive: true);
        }
      },
      skip: path == null
          ? 'Build native/core for actual shell recording acceptance.'
          : !File(shell).existsSync()
          ? 'Shell is not installed on this host: $shell'
          : false,
    );
  }
}
