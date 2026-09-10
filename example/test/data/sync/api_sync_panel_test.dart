import 'dart:io';

import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/sync/api_sync_panel.dart';
import 'package:app/data/sync/local_first_sync.dart';
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_data_api_resource_client.dart';

void main() {
  testWidgets('disabled sync shows local-only status and no actions', (
    tester,
  ) async {
    await _pumpPanel(tester, null);

    expect(
      find.text('Saved on this device. API sync is optional.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('api-sync-now')), findsNothing);
    expect(find.byKey(const Key('api-sync-keep-local')), findsNothing);
    expect(find.byKey(const Key('api-sync-use-remote')), findsNothing);
  });

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

      expect(find.textContaining('profile/default: /name'), findsOneWidget);
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
    expect(
      find.text(
        'Sync could not finish. Local data is available; check the API '
        'connection and encryption key, then retry.',
      ),
      findsOneWidget,
    );
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
        'Please sign in to the API again. Local data is still available. '
        'Choose Reconnect / sign in, then retry sync.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Sync could not finish. Local data is available; check the API '
        'connection and encryption key, then retry.',
      ),
      findsNothing,
    );
    expect(local, <String, Object?>{'name': 'durable local edit'});
  });
}

Future<void> _pumpPanel(
  WidgetTester tester,
  LocalFirstSyncCoordinator? coordinator,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [localFirstSyncProvider.overrideWith((ref) => coordinator)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ApiSyncPanel()),
      ),
    ),
  );
  await tester.pump();
}

enum _ConflictChoice { keepLocal, useRemote }

final class _SyncHarness {
  _SyncHarness._({
    required _LocalDocument local,
    required this.remote,
    required this.coordinator,
  }) : _local = local;

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
    );
  }

  final _LocalDocument _local;
  Map<String, Object?> get local => _local.value;
  final MemoryDataApiResourceClient remote;
  final LocalFirstSyncCoordinator coordinator;
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
