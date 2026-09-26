import 'dart:async';
import 'dart:io';

import 'package:app/platform/app_shutdown_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../support/sampled_recording_files.dart';
import '../support/sampled_recording_shell.dart';

class _PickerFiles extends SampledTestFiles {
  final ids = <String, String>{};
  RecordingFileCancellation? copyCancellation;
  Completer<void>? copying;
  bool started = false;
  int copied = 0;

  @override
  Future<Map<String, Object?>> run(
    String operation,
    Map<String, Object?> payload, {
    RecordingFileCancellation? cancellation,
  }) async {
    if (operation == 'copy_bundle') {
      final destination = payload['destination_path']! as String;
      final source = payload['source_path']! as String;
      await Directory(destination).create();
      await File('$source/records.bin').copy('$destination/records.bin');
      started = true;
      copied++;
      copyCancellation = cancellation;
      await copying?.future;
      if (cancellation?.isCancelled == true) {
        throw const RecordingFileCancelled();
      }
      ids[destination] = source.split('/').last.split('.').first;
      final info = await run('inspect', {'bundle_path': destination});
      return {'inspection': info, 'copied_bytes': info['source_bytes']};
    }
    if (operation == 'publish_bundle') {
      final staging = payload['staging_path']! as String;
      final destination = payload['destination_path']! as String;
      await Directory(staging).rename(destination);
      ids[destination] = ids.remove(staging)!;
      return {};
    }
    final result = await super.run(
      operation,
      payload,
      cancellation: cancellation,
    );
    if (result['metadata'] is Map && ids.containsKey(payload['bundle_path'])) {
      (result['metadata']! as Map)['recording_id'] =
          ids[payload['bundle_path']];
    }
    return result;
  }
}

void main() {
  for (final cancelWithShutdown in [null, false, true]) {
    sampledShellTest(
      'external picker copies and replays without PTY side effects (cancel=$cancelWithShutdown)',
      (tester) async {
        final sourceRoot = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('picked-recording-'),
        ))!;
        final source = Directory('${sourceRoot.path}/${'e' * 32}.trailrec');
        await tester.runAsync(() async {
          await source.create();
          await File(
            '${source.path}/records.bin',
          ).writeAsString('source remains unchanged');
        });
        addTearDown(() async => sourceRoot.delete(recursive: true));
        final files = _PickerFiles();
        if (cancelWithShutdown != null) files.copying = Completer<void>();
        final harness = await pumpSampledShell(
          tester,
          seed: false,
          recordingFiles: files,
          picker: ({initialDirectory}) async => source.path,
        );
        final sessions = harness.backend.createdSessions.length;
        final writes = harness.backend.writes.length;
        try {
          await openSampledShelf(tester);
          await tester.tap(
            find.byKey(const Key('recording-library-open-file')),
          );
          await pumpSampledUntil(tester, () => files.started);
          if (cancelWithShutdown == null) {
            await pumpSampledUntil(tester, () => files.seeks.isNotEmpty);
            expect(
              find.byKey(const Key('recording-replay-layout')),
              findsOneWidget,
            );
            final entries = await pumpSampledFuture(
              tester,
              harness.library.listRecordings,
            );
            expect(entries.single.keep, isTrue);
            expect(entries.single.path, isNot(source.path));
            expect(files.copied, 1);
            expect(harness.backend.createdSessions, hasLength(sessions));
            expect(harness.backend.writes, hasLength(writes));
          } else {
            AppShutdownResult? shutdownResult;
            if (cancelWithShutdown) {
              // Periodic cleanup queues behind the copy. Shutdown must cancel
              // the import before waiting for that maintenance operation.
              await tester.pump(const Duration(minutes: 5));
              unawaited(
                harness.container
                    .read(appShutdownCoordinatorProvider)
                    .shutdown(bounded: false)
                    .then((result) => shutdownResult = result),
              );
            } else {
              await tester.tap(
                find.byKey(const Key('recording-library-close')),
              );
            }
            await pumpSampledUntil(
              tester,
              () => files.copyCancellation!.isCancelled,
            );
            expect(shutdownResult, isNull);
            expect(harness.backend.closedSessionIds, isEmpty);
            final staged = await pumpSampledFuture(
              tester,
              () => Directory(
                '${harness.directory.path}/.imports',
              ).list().toList(),
            );
            expect(staged, hasLength(2));
            files.copying!.complete();
            await pumpSampledFuture(tester, harness.library.drain);
            if (cancelWithShutdown) {
              await pumpSampledUntil(tester, () => shutdownResult != null);
              expect(shutdownResult!.safeToTerminate, isTrue);
            }
            expect(
              await pumpSampledFuture(tester, harness.library.listRecordings),
              isEmpty,
            );
            expect(
              await pumpSampledFuture(
                tester,
                () => Directory(
                  '${harness.directory.path}/.imports',
                ).list().toList(),
              ),
              isEmpty,
            );
            expect(
              find.byKey(const Key('recording-replay-layout')),
              findsNothing,
            );
          }
          expect(
            await tester.runAsync(
              () => File('${source.path}/records.bin').readAsString(),
            ),
            'source remains unchanged',
          );
          expect(tester.takeException(), isNull);
        } finally {
          if (files.copying?.isCompleted == false) files.copying!.complete();
        }
      },
    );
  }
}
