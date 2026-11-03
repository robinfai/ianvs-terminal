import 'dart:async';
import 'dart:io';

import 'package:app/features/recording/recording_retention_surface.dart';
import 'package:app/features/recording/sampled_recording_library.dart';
import 'package:app/platform/app_shutdown_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sampled_recording_shell.dart';

class _MaintenanceLibrary extends SampledRecordingLibrary {
  _MaintenanceLibrary({required super.files, required super.directoryResolver});
  int cleanupCalls = 0;
  Completer<void>? cleanupBarrier;
  @override
  Future<void> applyRetention() async {
    cleanupCalls++;
    await cleanupBarrier?.future;
    await super.applyRetention();
  }
}

Future<void> _openActions(
  WidgetTester tester,
  SampledShellHarness harness,
) async {
  final actions = find.byKey(
    ValueKey('recording-actions-${harness.entry.path}'),
  );
  await pumpSampledUntil(
    tester,
    () =>
        actions.evaluate().isNotEmpty &&
        find
            .descendant(
              of: find.byKey(const Key('saved-recordings-shelf')),
              matching: find.byType(LinearProgressIndicator),
            )
            .evaluate()
            .isEmpty,
  );
  await tester.ensureVisible(actions);
  await tester.pumpAndSettle();
  await tester.tap(actions);
  await tester.pumpAndSettle();
}

void main() {
  sampledShellTest(
    'shutdown waits for pending periodic cleanup and schedules no further cleanup',
    (tester) async {
      late _MaintenanceLibrary library;
      final harness = await pumpSampledShell(
        tester,
        libraryBuilder: (files, directory) => library = _MaintenanceLibrary(
          files: files,
          directoryResolver: () async => directory,
        ),
      );
      expect(library.cleanupCalls, 1);
      final barrier = Completer<void>();
      library.cleanupBarrier = barrier;
      try {
        await tester.pump(const Duration(minutes: 5));
        expect(library.cleanupCalls, 2);
        AppShutdownResult? result;
        final shutdown = harness.container
            .read(appShutdownCoordinatorProvider)
            .shutdown(bounded: false);
        unawaited(shutdown.then((value) => result = value));
        await tester.pump(const Duration(minutes: 10));
        expect(result, isNull);
        expect(harness.backend.closedSessionIds, isEmpty);
        expect(library.cleanupCalls, 2);
        expect(tester.takeException(), isNull);
        barrier.complete();
        await pumpSampledUntil(tester, () => result != null);
        expect(result!.safeToTerminate, isTrue);
        expect(harness.backend.closedSessionIds, isNotEmpty);
      } finally {
        if (!barrier.isCompleted) barrier.complete();
      }
    },
  );

  sampledShellTest(
    'Keep can change during replay while Delete remains unavailable',
    (tester) async {
      final harness = await pumpSampledShell(tester);
      await openSampledEntry(tester, harness);
      final sessions = harness.backend.createdSessions.length;
      final writes = harness.backend.writes.length;
      await openSampledShelf(tester);
      await _openActions(tester, harness);
      final deletion = find.widgetWithText(
        PopupMenuItem<String>,
        'Close replay before deleting',
      );
      expect(tester.widget<PopupMenuItem<String>>(deletion).enabled, isFalse);
      await tester.tap(find.text('Keep recording'));
      await pumpSampledUntil(
        tester,
        () => find.textContaining(' · Kept').evaluate().isNotEmpty,
      );
      final kept = await pumpSampledFuture(
        tester,
        harness.library.listRecordings,
      );
      expect(kept.single.keep, isTrue);
      await _openActions(tester, harness);
      await tester.tap(find.text('Allow automatic cleanup'));
      await pumpSampledUntil(
        tester,
        () => find.textContaining(' · Kept').evaluate().isEmpty,
      );
      final unkept = await pumpSampledFuture(
        tester,
        harness.library.listRecordings,
      );
      expect(unkept.single.keep, isFalse);
      expect(find.byKey(const Key('recording-replay-layout')), findsOneWidget);
      expect(harness.backend.createdSessions, hasLength(sessions));
      expect(harness.backend.writes, hasLength(writes));
    },
  );

  sampledShellTest(
    'retention settings persist from the library and reopen with saved values',
    (tester) async {
      final harness = await pumpSampledShell(tester);
      await openSampledShelf(tester);
      final settings = find.byKey(const Key('recording-library-retention'));
      await tester.ensureVisible(settings);
      await tester.tap(settings);
      final surface = find.byType(RecordingRetentionSurface);
      await pumpSampledUntil(
        tester,
        () =>
            surface.evaluate().isNotEmpty &&
            !tester.widget<RecordingRetentionSurface>(surface).loading,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const Key('recording-retention-days')),
        '14',
      );
      await tester.enterText(
        find.byKey(const Key('recording-retention-capacity')),
        '2',
      );
      await tester.tap(find.byKey(const Key('recording-retention-save')));
      await pumpSampledUntil(tester, () => surface.evaluate().isEmpty);
      final loaded = await pumpSampledFuture(
        tester,
        harness.library.loadRetentionPolicy,
      );
      expect(loaded.maximumAgeDays, 14);
      expect(loaded.maximumBytes, 2 * 1024 * 1024 * 1024);
      await tester.ensureVisible(settings);
      await tester.tap(settings);
      await pumpSampledUntil(
        tester,
        () =>
            surface.evaluate().isNotEmpty &&
            !tester.widget<RecordingRetentionSurface>(surface).loading,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('14'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(surface, findsNothing);
    },
  );

  sampledShellTest(
    'cancel preserves a recording and confirmed deletion removes its bundle and indexes',
    (tester) async {
      final harness = await pumpSampledShell(tester);
      await tester.runAsync(
        () => File(
          '${harness.entry.path}/search.index',
        ).writeAsString('disposable search fixture'),
      );
      await openSampledShelf(tester);
      await _openActions(tester, harness);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete recording?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => Directory(harness.entry.path).exists()),
        isTrue,
      );
      await _openActions(tester, harness);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recording-delete-confirm')));
      await pumpSampledUntil(
        tester,
        () => find
            .byKey(const Key('recording-library-empty'))
            .evaluate()
            .isNotEmpty,
      );
      expect(
        await tester.runAsync(() => Directory(harness.entry.path).exists()),
        isFalse,
      );
      expect(
        await pumpSampledFuture(tester, harness.library.listRecordings),
        isEmpty,
      );
      expect(
        await tester.runAsync(
          () => File(
            '${harness.directory.path}/entries/${harness.entry.id}.json',
          ).exists(),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
