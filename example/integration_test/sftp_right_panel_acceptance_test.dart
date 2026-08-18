import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sftp/sftp_file_actions.dart';
import 'package:app/features/sftp/sftp_side_panel.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_pty_backend.dart';
import '../test/support/macos_integration_test_lifecycle.dart';
import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_local_terminal_config_repository.dart';
import '../test/support/memory_paste_history_repository.dart';
import '../test/support/memory_profile_repository.dart';
import '../test/support/no_io_local_session_recording_repository.dart';
import '../test/support/no_io_local_terminal_layout_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SFTP right panel acceptance', () {
    testWidgets(
      'opens from the command palette beside an active SSH terminal and browses directories',
      (tester) async {
        await _pumpShell(
          tester,
          surfaceSize: const Size(1280, 800),
          profile: _sshProfile(),
        );

        expect(find.byType(TerminalViewport), findsOneWidget);
        await _openSftpFromCommandPalette(tester);

        final terminalRect = tester.getRect(
          find.byKey(const Key('shell-terminal-surface')),
        );
        final panelRect = tester.getRect(
          find.byKey(const Key('sftp-right-panel-container')),
        );
        expect(panelRect.left, greaterThanOrEqualTo(terminalRect.right));
        expect(panelRect.top, closeTo(terminalRect.top, 1));
        expect(panelRect.bottom, closeTo(terminalRect.bottom, 1));
        expect(
          panelRect.width,
          inInclusiveRange(
            SftpSupportingPaneLayout.minimumDockedWidth,
            SftpSupportingPaneLayout.maximumDockedWidth,
          ),
        );
        expect(find.byKey(const Key('sftp-right-panel-scrim')), findsNothing);
        expect(find.text('root@example.test:2222'), findsOneWidget);
        expect(find.text('app'), findsOneWidget);
        expect(find.text('deploy.log'), findsOneWidget);

        await tester.tap(find.text('app'));
        await tester.pump();
        await tester.pump();

        expect(find.text('/app'), findsOneWidget);
        expect(find.text('main.dart'), findsOneWidget);

        final dockedTerminalWidth = terminalRect.width;
        await tester.tap(find.byKey(const Key('sftp-right-panel-close')));
        await tester.pump();

        expect(find.byKey(const Key('sftp-right-panel')), findsNothing);
        expect(
          tester.getRect(find.byKey(const Key('shell-terminal-surface'))).width,
          greaterThan(dockedTerminalWidth),
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'uses a right-anchored modal side sheet when the window is narrow',
      (tester) async {
        const surfaceSize = Size(700, 620);
        await _pumpShell(
          tester,
          surfaceSize: surfaceSize,
          profile: _sshProfile(),
        );

        final terminalWidthBefore = tester
            .getRect(find.byKey(const Key('shell-terminal-surface')))
            .width;
        await _openSftpFromCommandPalette(tester);

        final terminalRect = tester.getRect(
          find.byKey(const Key('shell-terminal-surface')),
        );
        final panelRect = tester.getRect(
          find.byKey(const Key('sftp-right-panel-container')),
        );
        expect(find.byKey(const Key('sftp-right-panel-scrim')), findsOneWidget);
        expect(panelRect.right, closeTo(surfaceSize.width, 1));
        expect(panelRect.center.dx, greaterThan(surfaceSize.width / 2));
        expect(
          panelRect.width,
          lessThanOrEqualTo(SftpSupportingPaneLayout.maximumModalWidth),
        );
        expect(terminalRect.width, closeTo(terminalWidthBefore, 1));
        expect(panelRect.top, closeTo(terminalRect.top, 1));
        expect(panelRect.bottom, closeTo(terminalRect.bottom, 1));

        await tester.tapAt(Offset(panelRect.left / 2, panelRect.center.dy));
        await tester.pump();

        expect(find.byKey(const Key('sftp-right-panel')), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'hides underlying terminal semantics while the narrow modal is open',
      (tester) async {
        ensureMacosIntegrationTestFramesEnabled(tester.binding);
        await tester.binding.setSurfaceSize(const Size(700, 620));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final semantics = tester.ensureSemantics();

        Future<void> pumpLayout({required bool panelOpen}) {
          return tester.pumpWidget(
            MaterialApp(
              theme: buildIanvsTerminalTheme(Brightness.light),
              home: SftpSupportingPaneLayout(
                primary: Semantics(
                  label: 'Underlying terminal content',
                  child: const SizedBox.expand(),
                ),
                supportingPane: panelOpen
                    ? Semantics(
                        label: 'SFTP modal content',
                        child: const SizedBox.expand(),
                      )
                    : null,
                onDismissSupportingPane: () {},
              ),
            ),
          );
        }

        await pumpLayout(panelOpen: true);
        expect(
          find.bySemanticsLabel('Underlying terminal content'),
          findsNothing,
        );
        expect(find.bySemanticsLabel('SFTP modal content'), findsOneWidget);

        await pumpLayout(panelOpen: false);
        expect(
          find.bySemanticsLabel('Underlying terminal content'),
          findsOneWidget,
        );
        semantics.dispose();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'keeps the SFTP command unavailable for a local terminal session',
      (tester) async {
        await _pumpShell(
          tester,
          surfaceSize: const Size(1100, 760),
          profile: defaultTerminalProfile(),
        );

        await tester.tap(find.byKey(const Key('shell-chrome-menu')));
        await tester.pumpAndSettle();
        final action = find.byKey(const Key('shell-open-sftp-panel'));
        await tester.ensureVisible(action);
        await tester.pump();

        expect(action, findsOneWidget);
        final actionTile = find.descendant(
          of: action,
          matching: find.byType(ListTile),
        );
        expect(tester.widget<ListTile>(actionTile).enabled, isFalse);
        expect(find.byKey(const Key('sftp-right-panel')), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'keeps the SFTP command unavailable without the runtime capability',
      (tester) async {
        await _pumpShell(
          tester,
          surfaceSize: const Size(1100, 760),
          profile: _sshProfile(),
          supportsSftpCapability: false,
        );

        await tester.tap(find.byKey(const Key('shell-chrome-menu')));
        await tester.pumpAndSettle();
        final action = find.byKey(const Key('shell-open-sftp-panel'));
        await tester.ensureVisible(action);
        await tester.pump();
        final actionTile = find.descendant(
          of: action,
          matching: find.byType(ListTile),
        );

        expect(tester.widget<ListTile>(actionTile).enabled, isFalse);
        expect(find.byKey(const Key('sftp-right-panel')), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'keeps narrow-sheet focus modal, scales text, and closes with Escape',
      (tester) async {
        await _pumpShell(
          tester,
          surfaceSize: const Size(700, 620),
          profile: _sshProfile(),
          textScale: 2,
        );

        await _openSftpFromCommandPalette(tester);
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byKey(const Key('sftp-panel-header'))).height,
          greaterThan(48),
        );
        final panelContext = tester.element(
          find.byKey(const Key('sftp-right-panel')),
        );
        for (var index = 0; index < 24; index += 1) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        }
        await tester.pump();

        expect(FocusScope.of(panelContext).hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('sftp-right-panel')), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'keeps SFTP and toolbelt mutually exclusive and closes on session switch',
      (tester) async {
        await _pumpShell(
          tester,
          surfaceSize: const Size(1100, 760),
          profile: _sshProfile(),
        );
        await _openSftpFromCommandPalette(tester);

        await tester.tap(find.byKey(const Key('shell-chrome-menu')));
        await tester.pumpAndSettle();
        final toolbelt = find.byKey(const Key('shell-top-toolbelt'));
        await tester.ensureVisible(toolbelt);
        await tester.tap(toolbelt);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('sftp-right-panel')), findsNothing);
        expect(find.byKey(const Key('shell-toolbelt-panel')), findsOneWidget);

        await _openSftpFromCommandPalette(tester);
        expect(find.byKey(const Key('shell-toolbelt-panel')), findsNothing);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ShellScreen)),
        );
        final sessions = container.read(sessionControllerProvider.notifier);
        final previousSessionId = container
            .read(sessionControllerProvider)
            .activeSessionId;
        sessions.createSession(
          _sshProfile().copyWith(id: 'ssh-secondary', name: 'Secondary SSH'),
        );
        await tester.pumpAndSettle();

        expect(
          container.read(sessionControllerProvider).activeSessionId,
          isNot(previousSessionId),
        );
        expect(find.byKey(const Key('sftp-right-panel')), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'renders synchronous failures and refreshes into an empty directory',
      (tester) async {
        final dataSource = _RetryingSftpDirectoryDataSource();
        await _pumpShell(
          tester,
          surfaceSize: const Size(1100, 760),
          profile: _sshProfile(),
          sftpDataSource: dataSource,
        );
        await _openSftpFromCommandPalette(tester);

        expect(find.text('Remote files unavailable'), findsOneWidget);
        expect(dataSource.calls, 1);
        await tester.tap(find.byKey(const Key('sftp-retry')));
        await tester.pumpAndSettle();

        expect(find.text('This remote directory is empty.'), findsOneWidget);
        expect(dataSource.calls, 2);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'cancels directory work on refresh and panel close',
      (tester) async {
        final dataSource = _PendingSftpDirectoryDataSource();
        await _pumpShell(
          tester,
          surfaceSize: const Size(1100, 760),
          profile: _sshProfile(),
          sftpDataSource: dataSource,
        );
        await _openSftpFromCommandPalette(tester, settleAfterOpen: false);

        expect(dataSource.starts, 1);
        expect(dataSource.cancellations, 0);
        await tester.tap(find.byKey(const Key('sftp-refresh')));
        await tester.pump();
        expect(dataSource.starts, 2);
        expect(dataSource.cancellations, 1);

        await tester.tap(find.byKey(const Key('sftp-right-panel-close')));
        await tester.pump();
        expect(dataSource.cancellations, 2);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'opens through a user-configured release action shortcut',
      (tester) async {
        await _pumpShell(
          tester,
          surfaceSize: const Size(1100, 760),
          profile: _sshProfile(),
          localConfig: const LocalTerminalConfigDocument(
            keybindings: LocalTerminalKeybindingsConfig(
              overrides: <TerminalActionId, LocalTerminalKeyBindingOverride>{
                TerminalActionId.openSftpPanel: LocalTerminalKeyBindingOverride(
                  binding: LocalTerminalKeyBinding(
                    scope: TerminalKeyBindingScope.focusedApp,
                    key: 'Key S',
                    meta: true,
                    shift: true,
                  ),
                ),
              },
            ),
          ),
        );

        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.metaLeft,
          platform: 'macos',
        );
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.shiftLeft,
          platform: 'macos',
        );
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.keyS,
          platform: 'macos',
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS, platform: 'macos');
        await tester.sendKeyUpEvent(
          LogicalKeyboardKey.shiftLeft,
          platform: 'macos',
        );
        await tester.sendKeyUpEvent(
          LogicalKeyboardKey.metaLeft,
          platform: 'macos',
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('sftp-right-panel')), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'single-clicking a file chooses a save location and downloads it',
      (tester) async {
        final root = await Directory.systemTemp.createTemp(
          'ianvs-sftp-download-acceptance-',
        );
        addTearDown(() => root.delete(recursive: true));
        final destination = '${root.path}/deploy.log';
        final platform = _TestSftpFileActionPlatform(
          root: root,
          saveDestination: destination,
        );
        final actions = SftpFileActions(
          platform: platform,
          settleDelay: const Duration(milliseconds: 40),
        );
        addTearDown(actions.dispose);
        final backend = _SshCapableFakePtyBackend(supportsSftpCapability: true);
        await _pumpShell(
          tester,
          surfaceSize: const Size(1100, 760),
          profile: _sshProfile(),
          ptyBackend: backend,
          fileActions: actions,
        );
        await _openSftpFromCommandPalette(tester);

        await tester.tap(find.text('deploy.log'));
        await tester.pumpAndSettle();

        expect(platform.saveSuggestions, <String>['deploy.log']);
        expect(await File(destination).readAsString(), 'initial remote log\n');
        expect(backend.downloadedRemotePaths, <String>['/deploy.log']);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'shows directory and file context menus with Edit locally only for files',
      (tester) async {
        await _pumpShell(
          tester,
          surfaceSize: const Size(1100, 760),
          profile: _sshProfile(),
        );
        await _openSftpFromCommandPalette(tester);

        await tester.tap(
          find.byKey(const ValueKey('sftp-entry-app')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('Copy full path'), findsOneWidget);
        expect(find.text('Create directory'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
        expect(find.text('Edit locally'), findsNothing);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('sftp-entry-deploy.log')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('Copy full path'), findsOneWidget);
        expect(find.text('Edit locally'), findsOneWidget);
        expect(find.text('Create directory'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'Edit locally opens a temp copy and uploads editor saves to the same remote path',
      (tester) async {
        final root = await Directory.systemTemp.createTemp(
          'ianvs-sftp-edit-acceptance-',
        );
        addTearDown(() => root.delete(recursive: true));
        final platform = _TestSftpFileActionPlatform(root: root);
        final actions = SftpFileActions(
          platform: platform,
          settleDelay: const Duration(milliseconds: 40),
        );
        addTearDown(actions.dispose);
        final backend = _SshCapableFakePtyBackend(supportsSftpCapability: true);
        await _pumpShell(
          tester,
          surfaceSize: const Size(1100, 760),
          profile: _sshProfile(),
          ptyBackend: backend,
          fileActions: actions,
        );
        await _openSftpFromCommandPalette(tester);
        await tester.tap(
          find.byKey(const ValueKey('sftp-entry-deploy.log')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sftp-context-edit-locally')));
        await tester.pumpAndSettle();

        expect(platform.openedPaths, hasLength(1));
        final localPath = platform.openedPaths.single;
        expect(localPath, startsWith(root.path));
        expect(await File(localPath).readAsString(), 'initial remote log\n');

        await tester.tap(find.byKey(const Key('sftp-right-panel-close')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('sftp-right-panel')), findsNothing);

        await File(localPath).writeAsString('saved in editor\n', flush: true);
        for (
          var attempt = 0;
          attempt < 30 && backend.uploads.isEmpty;
          attempt += 1
        ) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(backend.uploads, hasLength(1));
        expect(backend.uploads.single.remotePath, '/deploy.log');
        expect(utf8.decode(backend.uploads.single.bytes), 'saved in editor\n');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'context menu creates a directory and deletes the selected remote file',
      (tester) async {
        final backend = _SshCapableFakePtyBackend(supportsSftpCapability: true);
        await _pumpShell(
          tester,
          surfaceSize: const Size(1100, 760),
          profile: _sshProfile(),
          ptyBackend: backend,
        );
        await _openSftpFromCommandPalette(tester);

        await tester.tap(
          find.byKey(const ValueKey('sftp-entry-app')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('sftp-context-create-directory')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('sftp-create-directory-name')),
          'logs',
        );
        await tester.tap(
          find.byKey(const Key('sftp-create-directory-confirm')),
        );
        await tester.pumpAndSettle();
        expect(find.text('logs'), findsOneWidget);
        expect(backend.createdDirectories, <String>['/logs']);

        await tester.tap(
          find.byKey(const ValueKey('sftp-entry-deploy.log')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sftp-context-delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sftp-delete-confirm')));
        await tester.pumpAndSettle();
        expect(find.text('deploy.log'), findsNothing);
        expect(backend.deletedRemotePaths, <String>['/deploy.log']);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  });
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required Size surfaceSize,
  required TerminalProfile profile,
  double textScale = 1,
  SftpDirectoryDataSource? sftpDataSource,
  LocalTerminalConfigDocument? localConfig,
  bool supportsSftpCapability = true,
  _SshCapableFakePtyBackend? ptyBackend,
  SftpFileActions? fileActions,
}) async {
  ensureMacosIntegrationTestFramesEnabled(tester.binding);
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shellAnimationsEnabledProvider.overrideWithValue(false),
        ptySessionBackendProvider.overrideWithValue(
          ptyBackend ??
              _SshCapableFakePtyBackend(
                supportsSftpCapability: supportsSftpCapability,
              ),
        ),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(profiles: [profile]),
          ),
        ),
        pasteHistoryRepositoryProvider.overrideWithValue(
          MemoryPasteHistoryRepository(),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          MemoryLocalTerminalConfigRepository(localConfig),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          noIoLocalTerminalLayoutRepository(),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          noIoLocalSessionRecordingRepository(),
        ),
        if (sftpDataSource != null)
          sftpDirectoryDataSourceProvider.overrideWithValue(sftpDataSource),
        if (fileActions != null)
          sftpFileActionsProvider.overrideWithValue(fileActions),
      ],
      child: MaterialApp(
        theme: buildIanvsTerminalTheme(Brightness.light),
        darkTheme: buildIanvsTerminalTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const ShellScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _openSftpFromCommandPalette(
  WidgetTester tester, {
  bool settleAfterOpen = true,
}) async {
  await tester.tap(find.byKey(const Key('shell-chrome-menu')));
  await tester.pumpAndSettle();
  final action = find.byKey(const Key('shell-open-sftp-panel'));
  await tester.ensureVisible(action);
  await tester.pump();
  final actionTile = find.descendant(
    of: action,
    matching: find.byType(ListTile),
  );
  expect(tester.widget<ListTile>(actionTile).enabled, isTrue);
  await tester.tap(actionTile);
  if (settleAfterOpen) {
    await tester.pumpAndSettle();
  } else {
    for (var frame = 0; frame < 8; frame += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
  expect(find.byKey(const Key('sftp-right-panel')), findsOneWidget);
}

TerminalProfile _sshProfile() {
  return TerminalProfile(
    id: 'ssh-client',
    name: 'Example SSH',
    shell: '/bin/sh',
    connection: const terminal.TerminalConnectionConfig.ssh(
      host: 'example.test',
      user: 'root',
      port: 2222,
    ),
  );
}

class _SshCapableFakePtyBackend extends FakePtyBackend {
  _SshCapableFakePtyBackend({required this.supportsSftpCapability});

  final bool supportsSftpCapability;
  int _nextSftpJobId = 0;
  final Map<String, String> _sftpJobs = <String, String>{};
  final Map<String, bool> _sftpOperationJobs = <String, bool>{};
  final Map<String, List<int>> _remoteFiles = <String, List<int>>{
    '/deploy.log': utf8.encode('initial remote log\n'),
    '/app/main.dart': utf8.encode('void main() {}\n'),
  };
  final List<String> _rootDirectories = <String>['app'];
  final List<String> downloadedRemotePaths = <String>[];
  final List<({String remotePath, List<int> bytes})> uploads =
      <({String remotePath, List<int> bytes})>[];
  final List<String> createdDirectories = <String>[];
  final List<String> deletedRemotePaths = <String>[];

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
          if (supportsSftpCapability) ...<String>[
            ptyRuntimeFeatureSftpDirectoryListingV1,
            ptyRuntimeFeatureSftpFileOperationsV1,
          ],
          'zmodem.receive.v1',
          'zmodem.send.v1',
        ],
      });

  @override
  String? requestSessionV1Json(String sessionId, String requestV1Json) {
    final request = (jsonDecode(requestV1Json) as Map).cast<String, Object?>();
    final operation = request['operation'];
    if (operation is! String || !operation.startsWith('ssh.sftp.')) {
      return super.requestSessionV1Json(sessionId, requestV1Json);
    }
    final payload = (request['payload']! as Map).cast<String, Object?>();
    final responsePayload = switch (operation) {
      'ssh.sftp.list_directory_start' => () {
        final jobId = (++_nextSftpJobId).toString();
        _sftpJobs[jobId] = payload['path']! as String;
        return <String, Object?>{'jobId': jobId};
      }(),
      'ssh.sftp.list_directory_poll' => _sftpDirectoryPayload(
        _sftpJobs.remove(payload['jobId']),
      ),
      'ssh.sftp.list_directory_cancel' => <String, Object?>{
        'cancelled': _sftpJobs.remove(payload['jobId']) != null,
      },
      'ssh.sftp.operation_start' => () {
        final jobId = (++_nextSftpJobId).toString();
        _sftpOperationJobs[jobId] = _handleSftpOperation(payload);
        return <String, Object?>{'jobId': jobId};
      }(),
      'ssh.sftp.operation_poll' => <String, Object?>{
        'status': _sftpOperationJobs.remove(payload['jobId']) == true
            ? 'complete'
            : 'failed',
      },
      'ssh.sftp.operation_cancel' => <String, Object?>{
        'cancelled': _sftpOperationJobs.remove(payload['jobId']) != null,
      },
      _ => <String, Object?>{'status': 'failed'},
    };
    return jsonEncode(<String, Object?>{
      'schema_version': 1,
      'contract': 'ianvs-session-response-v1',
      'request_id': request['request_id'],
      'session_id': sessionId,
      'operation': operation,
      'ok': true,
      'timestamp_micros': 1,
      'payload': responsePayload,
    });
  }

  Map<String, Object?> _sftpDirectoryPayload(String? path) {
    if (path == '/app') {
      return <String, Object?>{
        'status': 'complete',
        'path': '/app',
        'entries': <Object?>[
          <String, Object?>{
            'name': 'main.dart',
            'kind': 'file',
            'size_bytes': 2450,
            'permissions': '-rw-r--r--',
          },
        ],
      };
    }
    if (path == '/') {
      return <String, Object?>{
        'status': 'complete',
        'path': '/',
        'entries': <Object?>[
          for (final name in _rootDirectories)
            <String, Object?>{
              'name': name,
              'kind': 'directory',
              'permissions': 'drwxr-xr-x',
            },
          for (final entry in _remoteFiles.entries)
            if (_parentRemotePath(entry.key) == '/')
              <String, Object?>{
                'name': _remoteFileName(entry.key),
                'kind': 'file',
                'size_bytes': entry.value.length,
                'permissions': '-rw-r-----',
              },
        ],
      };
    }
    return <String, Object?>{'status': 'failed'};
  }

  bool _handleSftpOperation(Map<String, Object?> payload) {
    final action = payload['action'];
    final remotePath = payload['remotePath'];
    if (action is! String || remotePath is! String) {
      return false;
    }
    switch (action) {
      case 'download_file':
        final localPath = payload['localPath'];
        final bytes = _remoteFiles[remotePath];
        if (localPath is! String || bytes == null) {
          return false;
        }
        File(localPath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes, flush: true);
        downloadedRemotePaths.add(remotePath);
        return true;
      case 'upload_file':
        final localPath = payload['localPath'];
        if (localPath is! String || !_remoteFiles.containsKey(remotePath)) {
          return false;
        }
        final bytes = File(localPath).readAsBytesSync();
        _remoteFiles[remotePath] = bytes;
        uploads.add((remotePath: remotePath, bytes: bytes));
        return true;
      case 'create_directory':
        if (_parentRemotePath(remotePath) != '/') {
          return false;
        }
        final name = _remoteFileName(remotePath);
        if (_rootDirectories.contains(name)) {
          return false;
        }
        _rootDirectories.add(name);
        createdDirectories.add(remotePath);
        return true;
      case 'delete_entry':
        final isDirectory = payload['isDirectory'];
        final removed = isDirectory == true
            ? _rootDirectories.remove(_remoteFileName(remotePath))
            : _remoteFiles.remove(remotePath) != null;
        if (removed) {
          deletedRemotePaths.add(remotePath);
        }
        return removed;
      default:
        return false;
    }
  }
}

class _RetryingSftpDirectoryDataSource implements SftpDirectoryDataSource {
  int calls = 0;

  @override
  SftpDirectoryLoadOperation startListDirectory(SftpDirectoryRequest request) {
    calls += 1;
    if (calls == 1) {
      throw StateError('synchronous adapter failure');
    }
    return SftpDirectoryLoadOperation(
      future: Future<SftpDirectorySnapshot>.value(
        SftpDirectorySnapshot(
          path: request.path,
          entries: const <SftpDirectoryEntry>[],
        ),
      ),
      onCancel: () {},
    );
  }
}

class _PendingSftpDirectoryDataSource implements SftpDirectoryDataSource {
  int starts = 0;
  int cancellations = 0;

  @override
  SftpDirectoryLoadOperation startListDirectory(SftpDirectoryRequest request) {
    starts += 1;
    final completer = Completer<SftpDirectorySnapshot>();
    return SftpDirectoryLoadOperation(
      future: completer.future,
      onCancel: () {
        cancellations += 1;
        if (!completer.isCompleted) {
          completer.complete(
            SftpDirectorySnapshot(
              path: request.path,
              entries: const <SftpDirectoryEntry>[],
            ),
          );
        }
      },
    );
  }
}

final class _TestSftpFileActionPlatform implements SftpFileActionPlatform {
  _TestSftpFileActionPlatform({required this.root, this.saveDestination});

  final Directory root;
  final String? saveDestination;
  final List<String> saveSuggestions = <String>[];
  final List<String> openedPaths = <String>[];

  @override
  Future<String?> chooseSaveLocation(String suggestedName) async {
    saveSuggestions.add(suggestedName);
    return saveDestination;
  }

  @override
  Future<Directory> createEditDirectory() => root.createTemp('edit-');

  @override
  Future<void> openFile(String path) async {
    openedPaths.add(path);
  }

  @override
  Stream<FileSystemEvent> watchDirectory(String path) =>
      Directory(path).watch();
}

String _parentRemotePath(String path) {
  final slash = path.lastIndexOf('/');
  return slash <= 0 ? '/' : path.substring(0, slash);
}

String _remoteFileName(String path) =>
    path.substring(path.lastIndexOf('/') + 1);
