import 'dart:async';
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:app/features/recording/sampled_recording_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sampled_recording_shell.dart';

class _FailingLibrary extends SampledRecordingLibrary {
  _FailingLibrary({required super.files, required super.directoryResolver});
  bool fail = true;
  @override
  Future<List<SampledRecordingEntry>> listRecordings() => fail
      ? Future.error(const FileSystemException('library unavailable'))
      : super.listRecordings();
}

void main() {
  sampledShellTest(
    'saved recording opens with no replay PTY and retained commands seek and copy',
    (tester) async {
      final harness = await pumpSampledShell(tester);
      final sessions = harness.backend.createdSessions.length;
      final writes = harness.backend.writes.length;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await openSampledEntry(tester, harness);
      expect(find.byKey(const Key('saved-recordings-shelf')), findsNothing);
      expect(harness.backend.createdSessions, hasLength(sessions));
      await tester.tap(find.byTooltip('Copy visible'));
      await tester.pump();
      expect(copied, contains('雪'));
      await tester.tap(find.byTooltip('Commands'));
      await tester.pump();
      final command = find.textContaining('quoted 雪').first;
      expect(command, findsOneWidget);
      final seeks = harness.files.seeks.length;
      await tester.tap(command);
      await pumpSampledUntil(tester, () => harness.files.seeks.length > seeks);
      expect(harness.files.seeks.last, greaterThanOrEqualTo(100));
      expect(harness.backend.createdSessions, hasLength(sessions));
      expect(harness.backend.writes, hasLength(writes));
      // The fixture includes a clickable image at the viewport center. Focus
      // the padding so Escape targets the player, not its image preview.
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const Key('recording-replay-viewport'))) +
            const Offset(2, 2),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recording-replay-layout')), findsNothing);
      await pumpSampledFuture(
        tester,
        () => harness.library.deleteRecording(harness.entry.path),
      );
    },
  );

  sampledShellTest(
    'search hits seek to their time even in an already open recording without terminal side effects',
    (tester) async {
      final harness = await pumpSampledShell(tester);
      final sessions = harness.backend.createdSessions.length;
      final writes = harness.backend.writes.length;
      await openSampledEntry(tester, harness);
      harness.files.fixture['search'] = {
        'hits': [
          {
            'offset_micros': 6500000,
            'kind': 'command',
            'hostname': 'fixture.local',
            'row': null,
            'preview': 'search matched command',
          },
        ],
        'next_cursor': null,
        'scanned_bytes': 200,
        'total_bytes': 200,
      };
      await openSampledShelf(tester);
      final searchButton = find.byKey(const Key('recording-library-search'));
      await tester.ensureVisible(searchButton);
      await tester.tap(searchButton);
      await pumpSampledUntil(
        tester,
        () => find.byType(TextField).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).first, 'matched');
      final result = find.text('search matched command');
      await pumpSampledUntil(tester, () => result.evaluate().isNotEmpty);
      await tester.ensureVisible(result);
      await tester.tap(result);
      await pumpSampledUntil(tester, () => harness.files.seeks.last == 6500000);
      await tester.pump(const Duration(milliseconds: 300));
      expect(harness.files.searchRequests.single['query'], 'matched');
      expect(find.byKey(const Key('saved-recordings-shelf')), findsNothing);
      expect(find.byKey(const Key('recording-replay-layout')), findsOneWidget);
      expect(harness.backend.createdSessions, hasLength(sessions));
      expect(harness.backend.writes, hasLength(writes));
      expect(tester.takeException(), isNull);
    },
  );

  sampledShellTest(
    'a compact empty library offers file opening and exposes no unavailable items',
    (tester) async {
      await pumpSampledShell(tester, seed: false, size: const Size(820, 900));
      await openSampledShelf(tester);
      await pumpSampledUntil(
        tester,
        () => find
            .byKey(const Key('recording-library-empty'))
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.byKey(const Key('saved-recordings-shelf-compact')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('recording-library-error')), findsNothing);
      expect(
        find.byKey(const Key('recording-library-open-file')),
        findsOneWidget,
      );
    },
  );

  sampledShellTest(
    'library read errors can be retried without losing existing entries',
    (tester) async {
      late _FailingLibrary library;
      final harness = await pumpSampledShell(
        tester,
        libraryBuilder: (files, directory) => library = _FailingLibrary(
          files: files,
          directoryResolver: () async => directory,
        ),
      );
      await openSampledShelf(tester);
      await pumpSampledUntil(
        tester,
        () => find
            .byKey(const Key('recording-library-error'))
            .evaluate()
            .isNotEmpty,
      );
      library.fail = false;
      await tester.tap(find.byKey(const Key('recording-library-refresh')));
      await pumpSampledUntil(
        tester,
        () => find
            .byKey(ValueKey('recording-entry-${harness.entry.path}'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.byKey(const Key('recording-library-error')), findsNothing);
    },
  );

  sampledShellTest(
    'closing the shelf cancels a pending picker and ignores its late path',
    (tester) async {
      final picked = Completer<String?>();
      final harness = await pumpSampledShell(
        tester,
        picker: ({initialDirectory}) => picked.future,
      );
      await openSampledShelf(tester);
      await tester.tap(find.byKey(const Key('recording-library-open-file')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('recording-library-close')));
      picked.complete(harness.entry.path);
      await tester.pump();
      expect(find.byKey(const Key('recording-replay-layout')), findsNothing);
      expect(harness.files.operations, isNot(contains('inspect')));
    },
  );

  sampledShellTest(
    'cancelled file opening retains the lease until its read settles',
    (tester) async {
      final harness = await pumpSampledShell(tester);
      harness.files.inspectBarrier = Completer<void>();
      await openSampledShelf(tester);
      final entry = find.byKey(
        ValueKey('recording-entry-${harness.entry.path}'),
      );
      await pumpSampledUntil(tester, () => entry.evaluate().isNotEmpty);
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await pumpSampledUntil(
        tester,
        () => harness.files.operations.contains('inspect'),
      );
      await tester.tap(find.byKey(const Key('recording-library-close')));
      await tester.pump();
      expect(harness.files.inspectCancellation!.isCancelled, isTrue);
      await pumpSampledFuture(
        tester,
        () => expectLater(
          harness.library.deleteRecording(harness.entry.path),
          throwsA(isA<RecordingLibraryBusy>()),
        ),
      );
      harness.files.inspectBarrier!.complete();
      harness.files.inspectBarrier = null;
      for (var i = 0; i < 5; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(find.byKey(const Key('recording-replay-layout')), findsNothing);
      await pumpSampledFuture(
        tester,
        () => harness.library.deleteRecording(harness.entry.path),
      );
    },
  );

  sampledShellTest(
    'opening a picked managed bundle and reselecting it keeps one viewer',
    (tester) async {
      late String path;
      final harness = await pumpSampledShell(
        tester,
        picker: ({initialDirectory}) async => path,
      );
      path = harness.entry.path;
      await openSampledShelf(tester);
      await tester.tap(find.byKey(const Key('recording-library-open-file')));
      await pumpSampledUntil(tester, () => harness.files.seeks.isNotEmpty);
      final reads = harness.files.operations
          .where((op) => op == 'inspect')
          .length;
      await openSampledShelf(tester);
      final entry = find.byKey(ValueKey('recording-entry-$path'));
      await pumpSampledUntil(tester, () => entry.evaluate().isNotEmpty);
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pump();
      expect(find.byKey(const Key('saved-recordings-shelf')), findsNothing);
      expect(
        harness.files.operations.where((op) => op == 'inspect'),
        hasLength(reads),
      );
      expect(find.byKey(const Key('recording-library-error')), findsNothing);
    },
  );

  sampledShellTest(
    'Escape returns focus to replay and Tab leaves the read-only viewport',
    (tester) async {
      final harness = await pumpSampledShell(tester);
      await openSampledEntry(tester, harness);
      // The fixture includes a clickable image at the viewport center. Focus
      // the padding so Escape targets the player, not its image preview.
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const Key('recording-replay-viewport'))) +
            const Offset(2, 2),
      );
      await tester.pump();
      final replayFocus = FocusManager.instance.primaryFocus;
      expect(replayFocus?.debugLabel, 'sampled-recording-replay');
      await openSampledShelf(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pump();
      expect(find.byKey(const Key('saved-recordings-shelf')), findsNothing);
      expect(FocusManager.instance.primaryFocus, same(replayFocus));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isNot(same(replayFocus)));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recording-replay-layout')), findsNothing);
    },
  );

  sampledShellTest(
    'compact dark replay at double text scale exposes usable playback semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final harness = await pumpSampledShell(
          tester,
          size: const Size(820, 900),
          textScaler: const TextScaler.linear(2),
          themeMode: ThemeMode.dark,
        );
        await openSampledEntry(tester, harness);
        final play = find.byTooltip('Play replay');
        final data = tester.getSemantics(play).getSemanticsData();
        expect(data.tooltip, 'Play replay');
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        await tester.tap(play);
        await tester.pump(const Duration(milliseconds: 10));
        expect(find.byTooltip('Pause replay'), findsOneWidget);
        await tester.tap(find.byTooltip('Pause replay'));
        await tester.pump();
        expect(find.byTooltip('Play replay'), findsOneWidget);
        expect(
          find.byKey(const Key('sampled-recording-timeline')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
