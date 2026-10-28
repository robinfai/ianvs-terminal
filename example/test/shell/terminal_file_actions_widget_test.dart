import 'dart:convert';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sftp/sftp_side_panel.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/ianvs_terminal_debug.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';
import '../support/no_io_local_terminal_layout_repository.dart';

class _FileBackend extends FakePtyBackend {
  _FileBackend({required this.remote});
  final bool remote;
  String contextId = 'root';
  String? link;
  String? routeLease;

  void showRaw(
    String id, {
    String token = '101',
    String cwd = '/old/project',
    String? shellHostname,
    bool owned = true,
  }) {
    setFrame(id, {
      'rows': [
        {'index': 0, 'text': 'logs/error.txt:12:3'},
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': false},
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'semantic_snapshot_token': token,
      'semantic_blocks': [
        {
          'id': 'raw-historical',
          if (routeLease != null) 'sftp_context_id': routeLease,
          'cwd': cwd,
          'context_id': contextId,
          'shell_hostname':
              shellHostname ?? (remote ? 'server.test' : 'localhost'),
        },
      ],
      'semantic_row_contexts': [
        if (owned) {'viewport_row': 0, 'block_id': 'raw-historical'},
      ],
      if (link != null)
        'hyperlinks': [
          {'row': 0, 'start_col': 0, 'end_col': 18, 'uri': link},
        ],
    });
  }

  @override
  PtyRuntimeCapabilities get runtimeCapabilities =>
      PtyRuntimeCapabilities.fromJson({
        'schema_version': 1,
        'runtime_contract': 'ianvs-runtime-contract-v1',
        'frame_schema_versions': <String>[],
        'recording_schema_versions': <int>[],
        'features': [
          'session-config.json.v1',
          'ssh-session.v1',
          ptyRuntimeFeatureSftpDirectoryListingV1,
          ptyRuntimeFeatureSftpFileOperationsV1,
        ],
      });

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = jsonDecode(requestJson) as Map;
    if (request['kind'] == 'composer.state') {
      return jsonEncode({
        'state': 'ready',
        'lease': 'ready-$sessionId',
        'cwd': '/new/directory',
        'contextId': contextId,
        'transport': remote ? 'shell' : 'local',
        'dialect': 'zsh',
      });
    }
    if (request['kind'] == 'terminal.live_screen') {
      return jsonEncode({'text': ''});
    }
    if (request['kind'] == 'terminal.command_blocks') {
      final block = {
        'id': 'historical',
        if (routeLease != null) 'sftpContextId': routeLease,
        'command': 'cat log',
        'cwd': '/old/project',
        'contextId': contextId,
        'shellHostname': remote ? 'server.test' : 'localhost',
        'exitCode': 0,
        'totalLines': 1,
        'matchingLines': 1,
        'offset': 0,
        'lines': [
          {'index': 0, 'source_row': 40, 'text': 'logs/error.txt:12:3'},
        ],
        if (link != null)
          'hyperlinks': [
            {'row': 0, 'start_col': 0, 'end_col': 18, 'uri': link},
          ],
      };
      return jsonEncode(
        request['id'] == null
            ? {
                'blocks': [block],
              }
            : {'block': block},
      );
    }
    return super.requestSessionJson(sessionId, requestJson);
  }
}

class _Directories implements SftpDirectoryDataSource {
  final requests = <SftpDirectoryRequest>[];
  @override
  SftpDirectoryLoadOperation startListDirectory(SftpDirectoryRequest request) {
    requests.add(request);
    return SftpDirectoryLoadOperation(
      onCancel: () {},
      future: Future.value(
        SftpDirectorySnapshot(
          path: request.path,
          entries: const [
            SftpDirectoryEntry(
              name: 'error.txt',
              kind: SftpDirectoryEntryKind.file,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<({ProviderContainer container, String id})> _pump(
  WidgetTester tester,
  _FileBackend backend,
  _Directories source,
  List<String> opened, {
  bool raw = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final profile = backend.remote
      ? TerminalProfile(
          id: 'remote',
          name: 'Remote',
          shell: '',
          connection: const TerminalConnectionConfig.ssh(
            host: 'server.test',
            user: 'dev',
          ),
        )
      : defaultTerminalProfile();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(backend),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(profiles: [profile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          MemoryLocalTerminalConfigRepository(null),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          noIoLocalTerminalLayoutRepository(),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          noIoLocalSessionRecordingRepository(),
        ),
        sftpDirectoryDataSourceProvider.overrideWithValue(source),
        shellExternalUrlOpenerProvider.overrideWithValue(
          (url) async => opened.add(url),
        ),
      ],
      child: MaterialApp(
        theme: buildIanvsTerminalTheme(
          Brightness.light,
          platform: TargetPlatform.macOS,
        ),
        home: const ShellScreen(),
      ),
    ),
  );
  await _settle(tester);
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ShellScreen)),
  );
  if (container.read(sessionControllerProvider).activeSessionId == null) {
    container.read(sessionControllerProvider.notifier).createSession(profile);
    await _settle(tester);
  }
  final id = container.read(sessionControllerProvider).activeSessionId!;
  // A shell context is not a host route: initial SSH/child shell can use a
  // non-root context while its real SFTP endpoint remains the root transport.
  if (backend.remote) {
    backend.contextId = 'initial-shell';
    backend.enqueueEvent(
      id,
      PtyEvent(
        kind: 'shell_hook',
        sessionId: id,
        payload: {
          'hook': 'bootstrap.ready',
          'context_id': backend.contextId,
          'parent_context_id': 'root',
          'context_kind': 'shell',
          'host_context_id': 'root',
          'registered': true,
          'shell': 'zsh',
          'sftp_route': false,
        },
      ),
    );
    container.read(terminalRuntimeControllerProvider).refreshSession(id);
    await _settle(tester);
  }
  if (raw) {
    backend.showRaw(id);
    container.read(terminalRuntimeControllerProvider).refreshSession(id);
    await _settle(tester);
    return (container: container, id: id);
  }
  await tester.tap(
    find.byKey(Key('shell-tab-$id')),
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('terminal-mode-blocks-$id')));
  await _settle(tester);
  expect(
    find.byKey(const ValueKey('block-terminal-historical')),
    findsOneWidget,
  );
  return (container: container, id: id);
}

Future<void> _clickFile(
  WidgetTester tester, {
  bool secondary = false,
  bool raw = false,
  bool settle = true,
}) async {
  final render = tester.renderObject<RenderTerminalViewport>(
    raw
        ? find
              .byWidgetPredicate(
                (widget) =>
                    widget.runtimeType.toString() == '_TerminalViewportSurface',
              )
              .first
        : find.descendant(
            of: find.byKey(const ValueKey('block-terminal-historical')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget.runtimeType.toString() == '_TerminalViewportSurface',
            ),
          ),
  );
  final position = render.localToGlobal(
    Offset(render.debugCellSize.width * 3, render.debugCellSize.height / 2),
  );
  final pointer = TestPointer(91, PointerDeviceKind.mouse);
  final timestamp = Duration(
    microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
  );
  await tester.sendEventToBinding(
    pointer.down(
      position,
      timeStamp: timestamp,
      buttons: secondary ? kSecondaryMouseButton : kPrimaryMouseButton,
    ),
  );
  await tester.sendEventToBinding(
    pointer.up(timeStamp: timestamp + const Duration(milliseconds: 1)),
  );
  if (settle) {
    await tester.pump(kDoubleTapTimeout);
    await _settle(tester);
  }
}

void main() {
  testWidgets(
    'nested SFTP uses native route lease and rejects missing lease',
    (tester) async {
      final backend = _FileBackend(remote: true);
      final source = _Directories();
      final opened = <String>[];
      final state = await _pump(tester, backend, source, opened, raw: true);
      Future<void> enter(String? lease, String token) async {
        backend.contextId = 'nested';
        backend.routeLease = lease;
        backend.enqueueEvent(
          state.id,
          PtyEvent(
            kind: 'shell_hook',
            sessionId: state.id,
            payload: {
              'hook': 'bootstrap.ready',
              'context_id': 'nested',
              'parent_context_id': 'root',
              'host_context_id': 'nested',
              'context_kind': 'ssh',
              'registered': true,
              'shell': 'zsh',
              'host': 'server.test',
              'user': 'dev',
              'port': 22,
              'sftp_route': true,
              'sftp_context_id': ?lease,
            },
          ),
        );
        backend.showRaw(state.id, token: token);
        state.container
            .read(terminalRuntimeControllerProvider)
            .refreshSession(state.id);
        await _settle(tester);
      }

      await enter('nested@1', '102');
      expect(
        state.container
            .read(sessionControllerProvider)
            .tabs
            .first
            .activePane
            .shellIntegration
            .sftpContextId,
        'nested@1',
      );
      await _clickFile(tester, raw: true);
      expect(source.requests.single.target.contextId, 'nested@1');
      await tester.tap(find.byKey(const Key('sftp-right-panel-close')));
      await _settle(tester);
      await enter(null, '103');
      expect(
        state.container
            .read(sessionControllerProvider)
            .tabs
            .first
            .activePane
            .shellIntegration
            .sftpContextId,
        isNull,
      );
      await _clickFile(tester, raw: true);
      expect(source.requests, hasLength(1));
      await enter('nested@2', '104');
      backend.routeLease = 'nested@1';
      backend.showRaw(state.id, token: '105');
      state.container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(state.id);
      await _settle(tester);
      await _clickFile(tester, raw: true);
      expect(source.requests, hasLength(1));
      backend.routeLease = 'nested@2';
      backend.showRaw(state.id, token: '106');
      state.container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(state.id);
      await _settle(tester);
      await _clickFile(tester, raw: true);
      expect(source.requests.last.target.contextId, 'nested@2');
      expect(source.requests, hasLength(2));
      expect(opened, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Normal nested remote claim cannot fall back to outer SFTP endpoint',
    (tester) async {
      final backend = _FileBackend(remote: true);
      final source = _Directories();
      final opened = <String>[];
      final state = await _pump(tester, backend, source, opened, raw: true);
      backend.showRaw(state.id, token: '102', shellHostname: 'nested.test');
      state.container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(state.id);
      await _settle(tester);
      await _clickFile(tester, raw: true);
      expect(source.requests, isEmpty);
      expect(opened, isEmpty);
      expect(find.text('Blocked file link'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final change in ['resize', 'scroll', 'close']) {
    testWidgets(
      'Normal menu refuses $change before a replacement frame arrives',
      (tester) async {
        final backend = _FileBackend(remote: true);
        final source = _Directories();
        final opened = <String>[];
        final state = await _pump(tester, backend, source, opened, raw: true);
        await _clickFile(tester, raw: true, secondary: true);
        final runtime = state.container.read(terminalRuntimeControllerProvider);
        switch (change) {
          case 'resize':
            runtime.resizeSessionCells(state.id, cols: 61, rows: 17);
          case 'scroll':
            runtime.scrollViewport(state.id, 1);
          case 'close':
            runtime.closeSession(state.id);
        }
        await tester.tap(find.text('Open link'));
        await _settle(tester);
        expect(source.requests, isEmpty);
        expect(opened, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  for (final secondary in [false, true]) {
    testWidgets(
      'Normal ${secondary ? 'menu' : 'click'} opens frozen SSH cwd in SFTP',
      (tester) async {
        final backend = _FileBackend(remote: true);
        final source = _Directories();
        final opened = <String>[];
        final state = await _pump(tester, backend, source, opened, raw: true);
        expect(source.requests, isEmpty);
        await _clickFile(tester, raw: true, secondary: secondary);
        if (secondary) {
          expect(source.requests, isEmpty);
          await tester.tap(find.text('Open link'));
          await _settle(tester);
        }
        expect(source.requests.single.path, '/old/project/logs');
        expect(source.requests.single.target.sessionId, state.id);
        expect(source.requests.single.target.host, 'server.test');
        expect(opened, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  for (final secondary in [false, true]) {
    testWidgets(
      'Normal ${secondary ? 'menu' : 'delayed click'} refuses same text under a new cwd snapshot',
      (tester) async {
        final backend = _FileBackend(remote: true);
        final source = _Directories();
        final opened = <String>[];
        final state = await _pump(tester, backend, source, opened, raw: true);
        await _clickFile(
          tester,
          raw: true,
          secondary: secondary,
          settle: secondary,
        );
        backend.showRaw(state.id, token: '102', cwd: '/different/project');
        state.container
            .read(terminalRuntimeControllerProvider)
            .refreshSession(state.id);
        if (secondary) await tester.tap(find.text('Open link'));
        await _settle(tester);
        expect(source.requests, isEmpty);
        expect(opened, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'Normal local confirmation refuses reflow snapshot after dialog',
    (tester) async {
      final backend = _FileBackend(remote: false);
      final source = _Directories();
      final opened = <String>[];
      final state = await _pump(tester, backend, source, opened, raw: true);
      await _clickFile(tester, raw: true);
      expect(find.text('Open local file link?'), findsOneWidget);
      expect(
        find.textContaining('file:///old/project/logs/error.txt'),
        findsOneWidget,
      );
      backend.showRaw(state.id, token: '102');
      state.container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(state.id);
      await tester.tap(find.text('Open').last);
      await _settle(tester);
      expect(opened, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Normal local file opens from displayed occurrence without Block cache',
    (tester) async {
      final backend = _FileBackend(remote: false);
      final source = _Directories();
      final opened = <String>[];
      await _pump(tester, backend, source, opened, raw: true);
      await _clickFile(tester, raw: true);
      expect(find.text('Open local file link?'), findsOneWidget);
      await tester.tap(find.text('Open').last);
      await _settle(tester);
      expect(opened, ['file:///old/project/logs/error.txt']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final osc8 in [false, true]) {
    testWidgets(
      'Normal ${osc8 ? 'OSC8 file' : 'file'} refuses missing or ambiguous row ownership',
      (tester) async {
        final backend = _FileBackend(remote: true);
        if (osc8) backend.link = 'file:///old/project/logs/error.txt';
        final source = _Directories();
        final opened = <String>[];
        final state = await _pump(tester, backend, source, opened, raw: true);
        backend.showRaw(state.id, token: '102', owned: false);
        state.container
            .read(terminalRuntimeControllerProvider)
            .refreshSession(state.id);
        await _settle(tester);
        await _clickFile(tester, raw: true);
        expect(source.requests, isEmpty);
        expect(opened, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'Normal OSC8 file uses frozen SSH route, never local filesystem',
    (tester) async {
      final backend = _FileBackend(remote: true)
        ..link = 'file://server.test/old/project/logs/error.txt';
      final source = _Directories();
      final opened = <String>[];
      await _pump(tester, backend, source, opened, raw: true);
      await _clickFile(tester, raw: true);
      expect(source.requests.single.path, '/old/project/logs');
      expect(opened, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'historical SSH block opens its SFTP parent, never the later cwd or local file',
    (tester) async {
      final source = _Directories();
      final opened = <String>[];
      final state = await _pump(
        tester,
        _FileBackend(remote: true),
        source,
        opened,
      );
      expect(source.requests, isEmpty);
      await _clickFile(tester);
      expect(source.requests.single.path, '/old/project/logs');
      expect(source.requests.single.target.sessionId, state.id);
      expect(source.requests.single.target.contextId, 'root');
      expect(source.requests.single.target.host, 'server.test');
      expect(opened, isEmpty);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('sftp-entry-error.txt')),
            )
            .selected,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Block context-menu Open uses the same historical SFTP target',
    (tester) async {
      final source = _Directories();
      final opened = <String>[];
      await _pump(tester, _FileBackend(remote: true), source, opened);
      await _clickFile(tester, secondary: true);
      expect(source.requests, isEmpty);
      await tester.tap(find.text('Open link'));
      await _settle(tester);
      expect(source.requests.single.path, '/old/project/logs');
      expect(opened, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'closing source during file confirmation prevents local open',
    (tester) async {
      final source = _Directories();
      final opened = <String>[];
      final state = await _pump(
        tester,
        _FileBackend(remote: false),
        source,
        opened,
      );
      await _clickFile(tester);
      expect(find.text('Open local file link?'), findsOneWidget);
      expect(
        find.textContaining('file:///old/project/logs/error.txt'),
        findsOneWidget,
      );
      state.container
          .read(terminalRuntimeControllerProvider)
          .closeSession(state.id);
      await tester.tap(find.text('Open').last);
      await _settle(tester);
      expect(opened, isEmpty);
      expect(source.requests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'OSC 8 authority from another host is not rebound to current SSH',
    (tester) async {
      final source = _Directories();
      final opened = <String>[];
      final backend = _FileBackend(remote: true)
        ..link = 'file://other.test/secret.txt';
      await _pump(tester, backend, source, opened);
      await _clickFile(tester);
      expect(source.requests, isEmpty);
      expect(opened, isEmpty);
      expect(find.text('Blocked file link'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
