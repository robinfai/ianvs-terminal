import 'dart:async';
import 'dart:io';

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/recording/sampled_recording_library.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/platform/app_shutdown_coordinator.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'desktop_test_platform.dart';
import 'memory_app_preferences_repository.dart';
import 'memory_paste_history_repository.dart';
import 'memory_profile_repository.dart';
import 'sampled_recording_backend.dart';
import 'sampled_recording_files.dart';
import 'shell_command_actions.dart';

final List<Future<void> Function()> _cleanups = [];

void sampledShellTest(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  desktopTestWidgets(description, (tester) async {
    _cleanups.clear();
    try {
      await body(tester);
    } finally {
      for (final cleanup in _cleanups.reversed) {
        await cleanup();
      }
      _cleanups.clear();
    }
  });
}

class SampledShellHarness {
  SampledShellHarness(
    this.directory,
    this.files,
    this.library,
    this.container,
    this.backend,
  );
  final Directory directory;
  final SampledTestFiles files;
  final SampledRecordingLibrary library;
  final ProviderContainer container;
  final SampledTestBackend backend;
  late SampledRecordingEntry entry;
}

class _Config extends LocalTerminalConfigRepository {
  @override
  Future<LocalTerminalConfigDocument?> load() async =>
      const LocalTerminalConfigDocument(
        layout: LocalTerminalLayoutConfig(restoreLayout: true),
      );
  @override
  Future<void> save(LocalTerminalConfigDocument document) async {}
}

Future<SampledShellHarness> pumpSampledShell(
  WidgetTester tester, {
  Size size = const Size(1100, 900),
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
  bool seed = true,
  ShellRecordingFilePicker? picker,
  SampledTestFiles? recordingFiles,
  SampledRecordingLibrary Function(SampledTestFiles files, Directory directory)?
  libraryBuilder,
}) async {
  final directory = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('sampled-shell-'),
  ))!;
  final files = recordingFiles ?? SampledTestFiles();
  final library =
      libraryBuilder?.call(files, directory) ??
      SampledRecordingLibrary(
        files: files,
        directoryResolver: () async => directory,
      );
  final backend = SampledTestBackend();
  final container = ProviderContainer(
    overrides: [
      ptySessionBackendProvider.overrideWithValue(backend),
      profileRepositoryProvider.overrideWithValue(
        MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      ),
      appPreferencesRepositoryProvider.overrideWithValue(
        MemoryAppPreferencesRepository(null),
      ),
      pasteHistoryRepositoryProvider.overrideWithValue(
        MemoryPasteHistoryRepository(),
      ),
      localTerminalConfigRepositoryProvider.overrideWithValue(_Config()),
      localTerminalLayoutRepositoryProvider.overrideWithValue(
        LocalTerminalLayoutRepository(directoryResolver: () async => directory),
      ),
      sampledRecordingLibraryProvider.overrideWithValue(library),
      if (picker != null)
        shellRecordingFilePickerProvider.overrideWithValue(picker),
    ],
  );
  final harness = SampledShellHarness(
    directory,
    files,
    library,
    container,
    backend,
  );
  if (seed) {
    harness.entry = (await tester.runAsync(
      () => seedSampledRecording(library),
    ))!;
  }
  await tester.binding.setSurfaceSize(size);
  _cleanups.add(() async {
    files.inspectBarrier?.complete();
    files.inspectBarrier = null;
    await tester.pumpWidget(const SizedBox.shrink());
    var finished = false;
    final ending = container
        .read(appShutdownCoordinatorProvider)
        .shutdown(bounded: false);
    unawaited(ending.then((_) => finished = true));
    await pumpSampledUntil(tester, () => finished);
    await ending;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await directory.delete(recursive: true);
    });
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildIanvsTerminalTheme(
          Brightness.light,
          platform: TargetPlatform.macOS,
        ),
        darkTheme: buildIanvsTerminalTheme(
          Brightness.dark,
          platform: TargetPlatform.macOS,
        ),
        themeMode: themeMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: const ShellScreen(),
      ),
    ),
  );
  await pumpSampledUntil(
    tester,
    () => container.read(sessionControllerProvider).isReady,
  );
  return harness;
}

Future<void> pumpSampledUntil(
  WidgetTester tester,
  bool Function() ready,
) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    if (ready()) {
      await tester.pump();
      return;
    }
  }
  fail('Sampled recording shell did not settle');
}

Future<void> openSampledShelf(WidgetTester tester) async {
  await openShellCommand(tester, 'shell-open-recording');
  await pumpSampledUntil(
    tester,
    () => find.byKey(const Key('saved-recordings-shelf')).evaluate().isNotEmpty,
  );
}

Future<void> openSampledEntry(
  WidgetTester tester,
  SampledShellHarness harness,
) async {
  await openSampledShelf(tester);
  final entry = find.byKey(ValueKey('recording-entry-${harness.entry.path}'));
  await pumpSampledUntil(
    tester,
    () => find
        .descendant(
          of: find.byKey(const Key('saved-recordings-shelf')),
          matching: find.byType(LinearProgressIndicator),
        )
        .evaluate()
        .isEmpty,
  );
  await tester.scrollUntilVisible(
    entry,
    250,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('recording-library-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(entry);
  await tester.pumpAndSettle();
  await tester.tap(entry);
  await pumpSampledUntil(
    tester,
    () =>
        find
            .byKey(const Key('recording-replay-layout'))
            .evaluate()
            .isNotEmpty &&
        harness.files.seeks.isNotEmpty,
  );
  await tester.pumpAndSettle();
}

Future<T> pumpSampledFuture<T>(
  WidgetTester tester,
  Future<T> Function() action,
) async {
  var done = false;
  T? result;
  Object? error;
  StackTrace? stack;
  unawaited(
    action().then(
      (value) {
        result = value;
        done = true;
      },
      onError: (Object e, StackTrace s) {
        error = e;
        stack = s;
        done = true;
      },
    ),
  );
  await pumpSampledUntil(tester, () => done);
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return result as T;
}
