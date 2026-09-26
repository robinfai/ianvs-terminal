import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:app/features/recording/sampled_recording_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Native recording round trip timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  final libraryPath = <String>[
    'native/core/target/debug/libianvs_core.dylib',
    '../native/core/target/debug/libianvs_core.dylib',
    'native/core/target/debug/libianvs_core.so',
    '../native/core/target/debug/libianvs_core.so',
  ].map(File.new).where((file) => file.existsSync()).firstOrNull?.absolute.path;
  test(
    'real PTY capture closes, reopens and seeks with exact hook command text',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'sampled-native-roundtrip-',
      );
      final backend = NativePtyBackend.fromBindings(
        NativePtyBindings(ffi.DynamicLibrary.open(libraryPath!)),
      );
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      final api = NativeRecordingFileApi(libraryPath: libraryPath);
      final library = SampledRecordingLibrary(
        files: api,
        directoryResolver: () async => root,
      );
      String hook(Map<String, Object?> json) => utf8
          .encode(jsonEncode(json))
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      const command = "printf '%s' 'quoted 雪 argument'";
      final start = hook({
        'hook': 'preexec',
        'command': command,
        'context_id': 'root',
      });
      final finish = hook({
        'hook': 'command_finished',
        'command': command,
        'context_id': 'root',
        'exit_code': 7,
      });
      final script =
          "printf 'READY-FOR-CAPTURE\\n'; read gate; printf '\\033Phook;$start\\033\\\\'; printf 'retained native screen 雪\\n'; printf '\\033Phook;$finish\\033\\\\'; printf 'CAPTURE-FINISHED\\n'; read finish_gate";
      final session = runtime.createSession(
        TerminalSessionConfig(
          launch: TerminalLaunchConfig(
            program: '/bin/sh',
            args: ['-c', script],
          ),
        ),
      );
      SampledRecordingClaim? claim;
      final client = SampledRecordingCaptureClient(backend: backend);
      try {
        expect(
          backend.runtimeCapabilities!.recordingSchemaVersions,
          contains(2),
        );
        await _until(() {
          runtime.refreshSession(session);
          return runtime
              .viewportFor(session)
              .frame
              .rows
              .any((row) => row.text.contains('READY-FOR-CAPTURE'));
        });
        claim = await library.reserve(
          sessionId: session,
          sessionEpoch: runtime.sessionEpochFor(session)!,
          title: 'Real native round trip',
          hostname: 'fixture.local',
        );
        await library.start(claim, client);
        await _until(
          () =>
              client.status(claim!.handle).phase ==
              SampledCapturePhase.capturing,
        );
        runtime.sendInput(session, utf8.encode('go\n'));
        await _until(() {
          runtime.refreshSession(session);
          return runtime
              .viewportFor(session)
              .frame
              .rows
              .any((row) => row.text.contains('CAPTURE-FINISHED'));
        });
        final path = await library.finish(claim, client);
        runtime.closeSession(session);
        expect(runtime.hasSession(session), isFalse);
        final reopenedLibrary = SampledRecordingLibrary(
          files: api,
          directoryResolver: () async => root,
        );
        final opened = await reopenedLibrary.openRecording(path);
        try {
          expect(
            opened.recording.info.completion,
            SampledRecordingCompletion.finished,
          );
          final end = (await opened.recording.seek(
            opened.recording.info.duration,
          ))!;
          expect(
            end.frame.rows.any(
              (row) => row.text.contains('retained native screen 雪'),
            ),
            isTrue,
          );
          final events = await opened.recording.timeline();
          expect(
            events.events.any(
              (event) =>
                  event.kind == SampledTimelineKind.commandFinished &&
                  event.command == command &&
                  event.exitCode == 7,
            ),
            isTrue,
          );
          await opened.recording.seek(Duration.zero);
        } finally {
          await opened.close();
        }
        final primary = File('$path/records.bin');
        final originalBytes = await primary.readAsBytes();
        final originalFiles = await Directory(
          path,
        ).list().map((entry) => entry.path).toList();
        final importedLibrary = SampledRecordingLibrary(
          files: api,
          directoryResolver: () async =>
              Directory('${root.path}/imported-library'),
        );
        final imported = await importedLibrary.openPickedRecording(path);
        try {
          expect(imported.entry.keep, isTrue);
          expect(imported.entry.id, opened.entry.id);
          expect(imported.entry.path, isNot(path));
          final end = (await imported.recording.seek(
            imported.recording.info.duration,
          ))!;
          expect(
            end.frame.rows.any(
              (row) => row.text.contains('retained native screen 雪'),
            ),
            isTrue,
          );
          final commands = await imported.recording.search(
            query: 'quoted 雪',
            kind: SampledRecordingSearchKind.command,
          );
          expect(
            commands.hits.any((hit) => hit.preview.contains('quoted 雪')),
            isTrue,
          );
        } finally {
          await imported.close();
        }
        await importedLibrary.deleteRecording(imported.entry.path);
        expect(await primary.readAsBytes(), originalBytes);
        expect(
          await Directory(path).list().map((entry) => entry.path).toList(),
          unorderedEquals(originalFiles),
        );
        expect(reopenedLibrary.activeClaims, isEmpty);
      } finally {
        if (claim?.dispatched == true && library.activeClaims.isNotEmpty) {
          await library.finish(claim!, client);
        }
        runtime.dispose();
        api.dispose();
        await root.delete(recursive: true);
      }
    },
    skip: libraryPath == null
        ? 'Build native/core to run actual PTY acceptance.'
        : false,
  );
}
