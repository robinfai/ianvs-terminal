import 'dart:async';
import 'dart:io';

import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/services/data_api_runtime.dart';
import 'package:app/data/services/data_api_sensitive_cipher.dart';
import 'package:app/data/sync/api_sync_panel.dart';
import 'package:app/data/sync/local_first_sync.dart';
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_data_api_resource_client.dart';

void main() {
  testWidgets('bundled local API is not presented as cross-device sync', (
    tester,
  ) async {
    final harness = _SyncHarness.conflicting();
    await _pumpPanel(
      tester,
      harness.coordinator,
      runtime: DataApiRuntime.local(
        baseUri: Uri.parse('http://127.0.0.1:1234'),
        localAccessToken: 'fixture',
        encryptionKey: 'fixture',
        closeLocalSidecar: () async {},
      ),
    );
    expect(find.byKey(const Key('api-sync-now')), findsNothing);
    expect(
      find.text('Saved on this device. API sync is optional.'),
      findsNothing,
    );
  });

  testWidgets('disabled sync shows local-only status and no actions', (
    tester,
  ) async {
    await _pumpPanel(tester, null);

    expect(
      find.text('Saved on this device. API sync is optional.'),
      findsNothing,
    );
    expect(find.byKey(const Key('api-sync-now')), findsNothing);
    expect(find.byKey(const Key('api-sync-keep-local')), findsNothing);
    expect(find.byKey(const Key('api-sync-use-remote')), findsNothing);
  });

  testWidgets('healthy sync is quiet and manual success expires', (
    tester,
  ) async {
    final coordinator = LocalFirstSyncCoordinator(
      documents: [],
      client: MemoryDataApiResourceClient(),
      checkpoints: _MemoryCheckpointStore(),
    );
    addTearDown(coordinator.close);
    await _pumpPanel(tester, coordinator);
    expect(find.byKey(const Key('api-sync-status')), findsNothing);
    expect(find.textContaining('Conflicting'), findsNothing);
    await tester.tap(find.byKey(const Key('api-sync-now')));
    await tester.pumpAndSettle();
    expect(find.text('Sync complete'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Sync complete'), findsNothing);
  });

  testWidgets('manual success is visible inside a fullscreen settings dialog', (
    tester,
  ) async {
    final coordinator = LocalFirstSyncCoordinator(
      documents: [],
      client: MemoryDataApiResourceClient(),
      checkpoints: _MemoryCheckpointStore(),
    );
    addTearDown(coordinator.close);
    await _pumpPanel(
      tester,
      coordinator,
      panel: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const Dialog.fullscreen(child: ApiSyncPanel()),
          ),
          child: const Text('Open settings'),
        ),
      ),
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('api-sync-now')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Sync complete'),
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Sync complete'), findsNothing);
    expect(find.text('Sync now'), findsOneWidget);
  });

  testWidgets(
    'decryption failure identifies affected data without leaking payload',
    (tester) async {
      final coordinator = LocalFirstSyncCoordinator(
        documents: [
          _binding(
            read: () => {'name': 'local'},
            write: (_) => fail('must preserve local'),
          ),
        ],
        client: const _FailingClient(
          DataApiSensitiveAuthenticationException(
            kind: 'profile',
            id: 'default',
          ),
        ),
        checkpoints: _MemoryCheckpointStore(),
      );
      addTearDown(coordinator.close);
      await coordinator.synchronize();
      await _pumpPanel(tester, coordinator);
      expect(
        find.textContaining('Connections: The current key cannot decrypt'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('api-sync-keep-local')), findsNothing);
      expect(
        coordinator.failures['profile/default']!.reason,
        LocalFirstSyncFailureReason.encryptionMismatch,
      );
    },
  );

  for (final choice in <_ConflictChoice>[
    _ConflictChoice.keepLocal,
    _ConflictChoice.useRemote,
  ]) {
    testWidgets('$choice resolves conflicts through the coordinator', (
      tester,
    ) async {
      final harness = _SyncHarness.conflicting();
      await harness.coordinator.synchronize();
      expect(harness.coordinator.phase, LocalFirstSyncPhase.conflict);
      await _pumpPanel(tester, harness.coordinator);

      expect(find.textContaining('Connections: /name'), findsOneWidget);
      expect(find.byKey(const Key('api-sync-keep-local')), findsOneWidget);
      expect(find.byKey(const Key('api-sync-use-remote')), findsOneWidget);

      await tester.tap(
        find.byKey(
          choice == _ConflictChoice.keepLocal
              ? const Key('api-sync-keep-local')
              : const Key('api-sync-use-remote'),
        ),
      );
      await tester.pumpAndSettle();

      final expected = <String, Object?>{
        'name': choice == _ConflictChoice.keepLocal ? 'local' : 'remote',
      };
      expect(harness.local, expected);
      expect(harness.remote.resources['profile/default']!.data, expected);
      expect(harness.coordinator.phase, LocalFirstSyncPhase.idle);
      expect(harness.coordinator.conflicts, isEmpty);
    });
  }

  testWidgets('failed retry keeps local data and shows unavailable status', (
    tester,
  ) async {
    final local = <String, Object?>{'name': 'durable local edit'};
    final coordinator = LocalFirstSyncCoordinator(
      documents: <SyncDocumentBinding>[
        _binding(
          read: () => local,
          write: (value) {
            fail('An unavailable retry must not write local data.');
          },
        ),
      ],
      client: const _FailingClient(SocketException('API connection refused')),
      checkpoints: _MemoryCheckpointStore(),
    );
    addTearDown(coordinator.close);
    await _pumpPanel(tester, coordinator);

    await tester.tap(find.byKey(const Key('api-sync-now')));
    await tester.pumpAndSettle();

    expect(local, <String, Object?>{'name': 'durable local edit'});
    expect(find.text('Sync failed. Local data is preserved.'), findsOneWidget);
    expect(coordinator.phase, LocalFirstSyncPhase.unavailable);
  });

  testWidgets('live 401 directs the user to reconnect and sign in', (
    tester,
  ) async {
    final local = <String, Object?>{'name': 'durable local edit'};
    final coordinator = LocalFirstSyncCoordinator(
      documents: <SyncDocumentBinding>[
        _binding(
          read: () => local,
          write: (_) => fail('A 401 must not rewrite local data.'),
        ),
      ],
      client: const _FailingClient(
        DataApiRequestException(
          statusCode: 401,
          code: 'unauthorized',
          message: 'a valid bearer token is required',
        ),
      ),
      checkpoints: _MemoryCheckpointStore(),
    );
    addTearDown(coordinator.close);

    await coordinator.synchronize();
    await _pumpPanel(tester, coordinator);

    expect(
      find.text(
        'Connections: Your session has expired. Sign out and sign in again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Sync failed. Local data is preserved.'), findsOneWidget);
    expect(local, <String, Object?>{'name': 'durable local edit'});
  });

  testWidgets('retry restores saved transport and merges pending edits', (
    tester,
  ) async {
    final harness = _SyncHarness.recoverable();
    var attempts = 0;
    await _pumpPanel(
      tester,
      harness.coordinator,
      restoreTransport: () async {
        attempts++;
        await harness.restoreTransport();
      },
    );

    await tester.tap(find.byKey(const Key('api-sync-now')));
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(harness.local, {'name': 'local', 'tag': 'remote'});
    expect(harness.remote.resources['profile/default']!.data, harness.local);
    expect(harness.checkpoints.value, harness.local);
    expect(harness.coordinator.phase, LocalFirstSyncPhase.idle);

    await tester.tap(find.byKey(const Key('api-sync-now')));
    await tester.pumpAndSettle();
    expect(attempts, 1, reason: 'A healthy transport needs no bootstrap.');
  });

  testWidgets('restoration is shared and the retry button stays busy', (
    tester,
  ) async {
    final harness = _SyncHarness.recoverable();
    final gate = Completer<void>();
    var attempts = 0;
    Future<void> restore() async {
      attempts++;
      await gate.future;
      await harness.restoreTransport();
    }

    await _pumpPanel(tester, harness.coordinator, restoreTransport: restore);
    await tester.tap(find.byKey(const Key('api-sync-now')));
    await tester.pump();

    expect(harness.coordinator.phase, LocalFirstSyncPhase.syncing);
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('api-sync-now')))
          .onPressed,
      isNull,
    );
    final sameAttempt = harness.coordinator.retry(restoreTransport: restore);
    await tester.tap(find.byKey(const Key('api-sync-now')));
    expect(attempts, 1);

    await _pumpPanel(
      tester,
      harness.coordinator,
      restoreTransport: restore,
      panel: const SizedBox.shrink(),
    );
    await _pumpPanel(tester, harness.coordinator, restoreTransport: restore);
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('api-sync-now')))
          .onPressed,
      isNull,
      reason: 'Reopening settings must not start a second restoration.',
    );

    gate.complete();
    await tester.pumpAndSettle();
    await sameAttempt;
    expect(harness.coordinator.phase, LocalFirstSyncPhase.idle);
  });

  testWidgets('a failed restore preserves edits and permits another attempt', (
    tester,
  ) async {
    final harness = _SyncHarness.recoverable();
    var attempts = 0;
    await _pumpPanel(
      tester,
      harness.coordinator,
      restoreTransport: () async {
        if (++attempts == 1) {
          throw const FileSystemException('private vault diagnostic');
        }
        await harness.restoreTransport();
      },
    );
    await tester.tap(find.byKey(const Key('api-sync-now')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(harness.coordinator.phase, LocalFirstSyncPhase.unavailable);
    expect(harness.local, {'name': 'local', 'tag': 'base'});
    expect(harness.checkpoints.value, {'name': 'base', 'tag': 'base'});
    expect(find.textContaining('private vault diagnostic'), findsNothing);

    await tester.tap(find.byKey(const Key('api-sync-now')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(harness.coordinator.phase, LocalFirstSyncPhase.idle);
    expect(harness.local, {'name': 'local', 'tag': 'remote'});
  });

  testWidgets('missing saved credentials request sign-in after retry', (
    tester,
  ) async {
    final harness = _SyncHarness.recoverable();
    await _pumpPanel(
      tester,
      harness.coordinator,
      restoreTransport: () async {
        throw const DataApiAuthenticationRequiredException();
      },
    );
    await tester.tap(find.byKey(const Key('api-sync-now')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      harness.coordinator.failureReason,
      LocalFirstSyncFailureReason.authenticationRequired,
    );
    expect(find.textContaining('Your session has expired.'), findsOneWidget);
    expect(harness.local, {'name': 'local', 'tag': 'base'});
    expect(harness.checkpoints.value, {'name': 'base', 'tag': 'base'});
  });

  testWidgets('disposing the app during restore releases the late transport', (
    tester,
  ) async {
    final harness = _SyncHarness.recoverable();
    final gate = Completer<void>();
    var closed = 0;
    await _pumpPanel(
      tester,
      harness.coordinator,
      restoreTransport: () async {
        await gate.future;
        await harness.coordinator.setTransport(
          nextClient: harness.remote,
          nextCheckpoints: harness.checkpoints,
          nextClose: () async => closed++,
        );
      },
    );
    await tester.tap(find.byKey(const Key('api-sync-now')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(closed, 1);
    expect(harness.remote.resources['profile/default']!.data, {
      'name': 'base',
      'tag': 'remote',
    });
  });
}

Future<void> _pumpPanel(
  WidgetTester tester,
  LocalFirstSyncCoordinator? coordinator, {
  Future<void> Function()? restoreTransport,
  Widget panel = const ApiSyncPanel(),
  DataApiRuntime? runtime,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dataApiRuntimeProvider.overrideWithValue(runtime),
        localFirstSyncProvider.overrideWith((ref) => coordinator),
        applyApiSyncConfigurationProvider.overrideWithValue(restoreTransport),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: panel),
      ),
    ),
  );
  await tester.pump();
}

enum _ConflictChoice { keepLocal, useRemote }

final class _SyncHarness {
  _SyncHarness._({
    required this._local,
    required this.remote,
    required this.coordinator,
    required this.checkpoints,
  });

  factory _SyncHarness.conflicting() {
    final local = _LocalDocument(<String, Object?>{'name': 'local'});
    final remote = MemoryDataApiResourceClient()
      ..resources['profile/default'] = dataApiTestResource(
        kind: 'profile',
        id: 'default',
        data: <String, Object?>{'name': 'remote'},
      );
    final checkpoints = _MemoryCheckpointStore()
      ..value = <String, Object?>{'name': 'base'};
    final coordinator = LocalFirstSyncCoordinator(
      documents: <SyncDocumentBinding>[
        _binding(
          read: () => local.value,
          write: (value) => local.value = value,
        ),
      ],
      client: remote,
      checkpoints: checkpoints,
    );
    return _SyncHarness._(
      local: local,
      remote: remote,
      coordinator: coordinator,
      checkpoints: checkpoints,
    );
  }

  factory _SyncHarness.recoverable() {
    final local = _LocalDocument({'name': 'local', 'tag': 'base'});
    final remote = MemoryDataApiResourceClient()
      ..resources['profile/default'] = dataApiTestResource(
        kind: 'profile',
        id: 'default',
        data: {'name': 'base', 'tag': 'remote'},
      );
    final checkpoints = _MemoryCheckpointStore()
      ..value = {'name': 'base', 'tag': 'base'};
    return _SyncHarness._(
      local: local,
      remote: remote,
      checkpoints: checkpoints,
      coordinator: LocalFirstSyncCoordinator(
        enabledButUnavailable: true,
        documents: [
          _binding(
            read: () => local.value,
            write: (value) => local.value = value,
          ),
        ],
      ),
    );
  }

  final _LocalDocument _local;
  Map<String, Object?> get local => _local.value;
  final MemoryDataApiResourceClient remote;
  final LocalFirstSyncCoordinator coordinator;
  final _MemoryCheckpointStore checkpoints;

  Future<void> restoreTransport() => coordinator.setTransport(
    nextClient: remote,
    nextCheckpoints: checkpoints,
  );
}

final class _LocalDocument {
  _LocalDocument(this.value);

  Map<String, Object?> value;
}

SyncDocumentBinding _binding({
  required Map<String, Object?> Function() read,
  required void Function(Map<String, Object?> value) write,
}) {
  return SyncDocumentBinding(
    kind: 'profile',
    id: 'default',
    readLocal: () async => read(),
    writeLocal: (value) async => write(value!),
    decodeRemote: (resource) =>
        Map<String, Object?>.from(resource.data! as Map),
    encodeRemote: (value) => (data: value, sensitive: null),
    validate: (value) {},
  );
}

final class _MemoryCheckpointStore implements SyncCheckpointStore {
  Map<String, Object?>? value;

  @override
  Future<Map<String, Object?>?> read(String resource) async => value;

  @override
  Future<void> write(String resource, Map<String, Object?>? value) async {
    this.value = value;
  }
}

final class _FailingClient implements DataApiResourceClient {
  const _FailingClient(this.error);

  final Exception error;

  @override
  bool get canAccessResources => true;

  @override
  Future<DataApiResource?> getResource({
    required String kind,
    required String id,
    bool includeSensitive = false,
  }) async {
    throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
