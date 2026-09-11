import 'dart:convert';
import 'dart:io';

import 'package:app/app.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_editor.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sftp/sftp_side_panel.dart';
import 'package:app/features/shell/instant_replay_store.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:app/ui/app_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_pty_backend.dart';
import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_profile_repository.dart';
import '../test/support/no_io_local_session_recording_repository.dart';

class _IosMobileReviewPtyBackend extends FakePtyBackend
    implements PtyReplaySessionBackend, PtyReplaySessionConfigV1Backend {
  @override
  String createReplaySessionV1(String config) => createSessionV1(config);
  @override
  void replayExit(String sessionId, {int? exitCode}) {}
  @override
  void replayOutput(String sessionId, List<int> bytes) {
    final output = utf8.decode(bytes, allowMalformed: true);
    setFrame(sessionId, <String, Object?>{
      'rows': <Object?>[
        for (final (i, line) in output.split('\n').indexed)
          <String, Object?>{
            'index': i,
            'text': line,
            'style_runs': <Object?>[],
          },
      ],
      'cursor': <String, Object?>{'row': 3, 'col': 0, 'visible': false},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[
        <String, Object?>{'start': 0, 'end': 24},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'window_title': null,
      'window_icon_name': null,
    });
  }

  @override
  PtyRuntimeCapabilities get runtimeCapabilities =>
      PtyRuntimeCapabilities.fromJson(<String, Object?>{
        'schema_version': 1,
        'runtime_contract': 'ianvs-runtime-contract-v1',
        'frame_schema_versions': <Object?>['terminal-frame-diff-v1'],
        'recording_schema_versions': <Object?>[],
        'features': <Object?>[
          'session-config.json.v1',
          'ssh-session.v1',
          ptyRuntimeFeatureSftpDirectoryListingV1,
          ptyRuntimeFeatureSftpFileOperationsV1,
        ],
      });
}

class _ReviewRecordings extends LocalSessionRecordingRepository
    with NoIoLocalSessionRecordingRecovery {
  _ReviewRecordings()
    : super(directoryResolver: () async => Directory.systemTemp);
  final entry = LocalSessionRecordingEntry(
    path: '/review/mobile-session.ndjson',
    displayName: 'Deployment check',
    createdAtUtc: DateTime.utc(2026, 9, 11, 2),
    duration: const Duration(seconds: 30),
    fileSizeBytes: 2048,
    sessionId: 'review-recording',
    schemaVersion: 1,
    inputPolicy: terminal.TerminalRecordingInputPolicy.redact,
  );
  terminal.TerminalRecording
  get recording => const terminal.TerminalRecordingCodec().decode(
    [
      {
        'record_type': 'metadata',
        'schema_version': 1,
        'session_id': 'review-recording',
        'created_at_utc': '2026-09-11T02:00:00.000Z',
        'input_policy': 'redact',
      },
      {
        'record_type': 'event',
        'schema_version': 1,
        'session_id': 'review-recording',
        'sequence': 0,
        'monotonic_offset_micros': 0,
        'event_kind': 'session_started',
        'payload': {'terminal_emulation': 'xterm256', 'cols': 80, 'rows': 24},
      },
      for (final (i, seconds) in [1, 15, 30].indexed)
        {
          'record_type': 'event',
          'schema_version': 1,
          'session_id': 'review-recording',
          'sequence': i + 1,
          'monotonic_offset_micros': seconds * 1000000,
          'event_kind': 'pty_output',
          'payload': {
            'bytes_base64': base64Encode(
              utf8.encode(
                'reviewer@server:~\$ deploy --check\nConnection verified\nStep ${i + 1} complete\nAll services healthy',
              ),
            ),
          },
        },
    ].map(jsonEncode).join('\n'),
  );
  @override
  Future<List<LocalSessionRecordingEntry>> listRecordings() async => [entry];
  @override
  Future<terminal.TerminalRecording> load(String path) async => recording;
}

class _ReviewDirectorySource implements SftpDirectoryDataSource {
  @override
  SftpDirectoryLoadOperation startListDirectory(SftpDirectoryRequest request) =>
      SftpDirectoryLoadOperation(
        onCancel: () {},
        future: Future.value(
          const SftpDirectorySnapshot(
            path: '/home/reviewer',
            entries: [
              SftpDirectoryEntry(
                name: 'Documents',
                kind: SftpDirectoryEntryKind.directory,
              ),
              SftpDirectoryEntry(
                name: 'review-notes.txt',
                kind: SftpDirectoryEntryKind.file,
                sizeBytes: 2048,
              ),
              SftpDirectoryEntry(
                name: 'a-long-project-deployment-checklist.md',
                kind: SftpDirectoryEntryKind.file,
                sizeBytes: 8192,
              ),
            ],
          ),
        ),
      );
}

terminal.TerminalFrameDiff _frame(String text) {
  return terminal.TerminalFrameDiff(
    rows: <terminal.TerminalRow>[
      terminal.TerminalRow(index: 0, text: text),
      const terminal.TerminalRow(
        index: 1,
        text: r'$ flutter test --device iPhone',
      ),
      const terminal.TerminalRow(
        index: 2,
        text: 'Mobile replay controls are ready.',
      ),
    ],
    cursor: const terminal.TerminalCursor(row: 2, col: 34, visible: true),
    viewportRows: 24,
    viewportCols: 80,
    dirtyRanges: const <terminal.TerminalDirtyRange>[
      terminal.TerminalDirtyRange(start: 0, end: 3),
    ],
    scrollbackOffset: 0,
    scrollbackMaxOffset: 0,
  );
}

Future<void> _waitForWidget(
  WidgetTester tester,
  Finder finder, {
  required String description,
}) async {
  for (var tick = 0; tick < 200; tick += 1) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for $description.');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: name);
    final metrics = <String, Object>{};
    for (final key in [
      'ssh-host',
      'ssh-user',
      'ssh-auth-method',
      'ssh-password',
      'ssh-connect',
      'mobile-replay-transport',
      'mobile-replay-toggle',
      'defaults-section-general',
      'defaults-mobile-back',
    ]) {
      final finder = find.byKey(Key(key));
      if (finder.evaluate().length == 1) {
        final size = tester.getSize(finder);
        metrics[key] = {'width': size.width, 'height': size.height};
      }
    }
    debugPrint(
      'TRAIL_DENSITY_METRICS ${jsonEncode({'screen': name, 'metrics': metrics})}',
    );
    await binding.takeScreenshot(name);
  }

  Future<void> tapKey(WidgetTester tester, String name) async {
    final finder = find.byKey(Key(name));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('iPhone main flows render with the shared design system', (
    tester,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    final backend = _IosMobileReviewPtyBackend();
    var now = DateTime(2026, 8, 19, 14, 30);
    final replayStore = InstantReplayStore(now: () => now);
    final reviewRecordings = _ReviewRecordings();
    final profile = TerminalProfile(
      id: 'ios-mobile-review',
      name: 'Trail UI Review',
      shell: '/usr/bin/ssh',
      connection: const terminal.TerminalConnectionConfig.ssh(
        host: 'review.example.test',
        user: 'reviewer',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(backend),
          sftpDirectoryDataSourceProvider.overrideWithValue(
            _ReviewDirectorySource(),
          ),
          profileRepositoryProvider.overrideWithValue(
            MemoryProfileRepository(
              TerminalProfilesDocument(profiles: <TerminalProfile>[profile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            MemoryAppPreferencesRepository(null),
          ),
          instantReplayStoreProvider.overrideWithValue(replayStore),
          localSessionRecordingRepositoryProvider.overrideWithValue(
            reviewRecordings,
          ),
        ],
        child: const IanvsTerminalApp(),
      ),
    );
    await tester.pumpAndSettle();

    await capture(tester, '01-ssh-home');
    await tapKey(tester, 'ios-ssh-create-profile');
    await capture(tester, '02-ssh-form');
    await tester.enterText(
      find.byKey(const Key('ssh-host')),
      'review.example.test',
    );
    await tester.ensureVisible(find.byKey(const Key('ssh-user')));
    await tester.enterText(find.byKey(const Key('ssh-user')), 'reviewer');
    await capture(tester, '03-ssh-input');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.ensureVisible(find.byKey(const Key('ssh-password')));
    await tester.enterText(
      find.byKey(const Key('ssh-password')),
      'demo-password',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await capture(tester, '19-ssh-ready');
    await tapKey(tester, 'ssh-more-settings-toggle');
    await capture(tester, '20-ssh-more-settings');
    await tapKey(tester, 'ssh-more-settings-toggle');
    Navigator.of(tester.element(find.byKey(const Key('ssh-host')))).pop();
    await tester.pumpAndSettle();
    await tapKey(tester, 'shell-command-defaults');
    await capture(tester, '05-settings');
    for (final section in [
      'general',
      'appearance',
      'security',
      'data',
      'shortcuts',
    ]) {
      await tapKey(tester, 'defaults-section-$section');
      await capture(tester, '06-settings-$section');
      if (section == 'data') {
        await tapKey(tester, 'data-api-remote');
        await tester.ensureVisible(
          find.byKey(const Key('data-api-remote-username')),
        );
        await capture(tester, '07-sync-form');
        await tester.drag(
          find.byKey(const Key('defaults-appearance-scroll')),
          const Offset(0, -600),
        );
        await capture(tester, '08-sync-form-bottom');
      }
      await tapKey(
        tester,
        section == 'shortcuts'
            ? 'defaults-shortcuts-back'
            : 'defaults-mobile-back',
      );
    }
    await tapKey(tester, 'defaults-mobile-back');
    final profileTile = find.byKey(
      const Key('ios-ssh-empty-profile-ios-mobile-review'),
    );
    await _waitForWidget(
      tester,
      profileTile,
      description: 'the iPhone SSH profile launcher',
    );
    await tester.tap(profileTile);
    await tester.pumpAndSettle();

    await capture(tester, '09-terminal');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    final sessionId = container.read(sessionControllerProvider).activeSessionId;
    expect(sessionId, isNotNull);
    replayStore.record(sessionId!, _frame('First captured mobile frame'));
    now = now.add(const Duration(seconds: 3));
    replayStore.record(sessionId, _frame('Second captured mobile frame'));

    await container
        .read(sessionControllerProvider.notifier)
        .setThemeMode(TerminalThemeMode.dark);
    await capture(tester, '10-terminal-dark');
    await tapKey(tester, 'shell-chrome-menu');
    await capture(tester, '04-session-options');
    Navigator.of(
      tester.element(find.byKey(const Key('mobile-session-menu'))),
    ).pop();
    await tester.pumpAndSettle();
    await tapKey(tester, 'shell-open-sftp-panel');
    await capture(tester, '14-sftp-directory');
    await tapKey(tester, 'sftp-entry-actions-review-notes.txt');
    await capture(tester, '19-file-actions');
    expect(find.byKey(const Key('sftp-context-edit-locally')), findsNothing);
    Navigator.of(
      tester.element(find.byKey(const Key('sftp-context-copy-full-path'))),
    ).pop();
    await tester.pumpAndSettle();
    await tapKey(tester, 'sftp-right-panel-close');
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await tester.pumpAndSettle();
    await _waitForWidget(
      tester,
      find.byKey(const Key('shell-search-scrollback-top')),
      description: 'terminal toolbar after returning from files',
    );
    await tapKey(tester, 'shell-search-scrollback-top');
    await capture(tester, '11-terminal-search');
    await tapKey(tester, 'terminal-search-close');
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await tester.pumpAndSettle();
    await _waitForWidget(
      tester,
      find.byKey(const Key('shell-open-recording')),
      description: 'replay entry after dismissing search keyboard',
    );
    await tapKey(tester, 'shell-open-recording');
    await capture(tester, '13-replay-library');
    await tapKey(tester, 'shell-replay-recent-activity');
    await _waitForWidget(
      tester,
      find.byKey(const Key('instant-replay-layout')),
      description: 'instant replay after native window metrics resolve',
    );
    expect(find.byKey(const Key('instant-replay-layout')), findsOneWidget);
    expect(find.byKey(const Key('mobile-replay-player')), findsOneWidget);
    expect(find.byKey(const Key('instant-replay-floating-dock')), findsNothing);
    expect(tester.takeException(), isNull);

    await capture(tester, '10-replay');
    await tapKey(tester, 'mobile-replay-more');
    await capture(tester, '15-replay-options');
    Navigator.of(
      tester.element(find.byKey(const Key('mobile-replay-options-sheet'))),
    ).pop();
    await tester.pumpAndSettle();
    await tapKey(tester, 'mobile-replay-open-search');
    await tester.enterText(
      find.byKey(const Key('mobile-replay-search')),
      'captured',
    );
    await capture(tester, '16-replay-search');
    await tapKey(tester, 'mobile-replay-close-search');
    await tapKey(tester, 'mobile-replay-close');
    await tapKey(tester, 'recording-entry-/review/mobile-session.ndjson');
    await _waitForWidget(
      tester,
      find.byKey(const Key('mobile-replay-player')),
      description: 'saved recording player',
    );
    await tapKey(tester, 'mobile-replay-forward-ten');
    await capture(tester, '17-saved-replay');
    await tapKey(tester, 'mobile-replay-content-only');
    await capture(tester, '18-saved-replay-content');
    await tapKey(tester, 'mobile-replay-show-controls');

    if (const bool.fromEnvironment('IANVS_MOBILE_LAYOUT_REVIEW')) {
      final previousPolicy = binding.framePolicy;
      final previousPointers = binding.shouldPropagateDevicePointerEvents;
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      binding.shouldPropagateDevicePointerEvents = true;
      debugPrint('TRAIL MOBILE REVIEW READY');
      try {
        await Future<void>.delayed(
          const Duration(
            seconds: int.fromEnvironment(
              'IANVS_MOBILE_REVIEW_SECONDS',
              defaultValue: 180,
            ),
          ),
        );
      } finally {
        binding.framePolicy = previousPolicy;
        binding.shouldPropagateDevicePointerEvents = previousPointers;
      }
    }
  });
  testWidgets('iPhone profile configuration renders all sections', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildIanvsTerminalTheme(
            brightness,
            platform: TargetPlatform.iOS,
          ),
          home: Scaffold(
            body: ProfileEditorDialog(initialValue: defaultTerminalProfile()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final section in [
        'general',
        'startup',
        'terminal',
        'appearance',
        'keys',
        'automation',
        'advanced',
      ]) {
        await tapKey(tester, 'profile-editor-nav-$section');
        await capture(tester, '12-profile-${brightness.name}-$section');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}
