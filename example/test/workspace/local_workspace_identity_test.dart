import 'package:app/features/workspace/local_workspace_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TerminalWorkspaceIdentity', () {
    test('derives stable project identity from a normalized local path', () {
      final first = TerminalWorkspaceIdentity.forProject('/repo/ianvs/');
      final second = TerminalWorkspaceIdentity.forProject('/repo/ianvs');

      expect(first, second);
      expect(first.id, startsWith('project-'));
      expect(first.name, 'ianvs');
      expect(first.projectPath, '/repo/ianvs');
    });

    test('rejects an ambiguous relative project path', () {
      expect(
        () => TerminalWorkspaceIdentity.forProject('repo/ianvs'),
        throwsArgumentError,
      );
    });

    test('workspace v3 roundtrips identity and ignores additive fields', () {
      final workspace = TerminalWorkspace(
        identity: TerminalWorkspaceIdentity.forProject(
          '/repo/ianvs',
          name: 'Ianvs Terminal',
        ),
        tabs: [_tab('tab-1')],
        activeTabId: 'tab-1',
      );
      final json = <Object?, Object?>{
        ...workspace.toJson(),
        'futureField': true,
      };

      final decoded = TerminalWorkspace.fromJson(json);

      expect(decoded.schemaVersion, currentTerminalWorkspaceSchemaVersion);
      expect(decoded.identity, workspace.identity);
      expect(decoded.toJson(), containsPair('id', workspace.identity.id));
      expect(decoded.toJson(), containsPair('name', 'Ianvs Terminal'));
      expect(decoded.toJson(), containsPair('projectPath', '/repo/ianvs'));
      expect(decoded.toJson(), isNot(contains('futureField')));
    });

    test('workspace mutations preserve identity', () {
      final identity = TerminalWorkspaceIdentity.forProject('/repo/ianvs');
      final workspace = TerminalWorkspace(identity: identity)
          .addTab(_tab('tab-1'))
          .addTab(_tab('tab-2'))
          .closeActiveTab()
          .reopenClosedTab();

      expect(workspace.identity, identity);
    });

    test('legacy workspace versions migrate to the default identity', () {
      final workspace = TerminalWorkspace.fromJson({
        'schemaVersion': 2,
        'tabs': [_tab('tab-1').toJson()],
        'activeTabId': 'tab-1',
      });

      expect(workspace.identity, TerminalWorkspaceIdentity.defaultWorkspace);
    });

    test('current workspace schema requires explicit identity fields', () {
      expect(
        () => TerminalWorkspace.fromJson({
          'schemaVersion': currentTerminalWorkspaceSchemaVersion,
          'tabs': const <Object?>[],
        }),
        throwsFormatException,
      );
    });
  });

  group('TerminalWorkspaceIndex', () {
    test('marks workspaces recent with deterministic dedupe and bound', () {
      var index = const TerminalWorkspaceIndex();
      for (var value = 0; value < maxRecentTerminalWorkspaces + 2; value++) {
        index = index.markOpened(
          TerminalWorkspaceIdentity.forProject('/repo/$value'),
          openedAtUtc: DateTime.utc(2026, 7, 21, 5, value),
        );
      }
      final reopened = index.recent.last.identity;
      index = index.markOpened(
        reopened,
        openedAtUtc: DateTime.utc(2026, 7, 21, 6),
      );

      expect(index.recent, hasLength(maxRecentTerminalWorkspaces));
      expect(index.currentWorkspaceId, reopened.id);
      expect(index.recent.first.identity, reopened);
      expect(
        index.recent.where((entry) => entry.identity == reopened),
        hasLength(1),
      );
    });

    test('index v1 roundtrips and ignores additive fields', () {
      final identity = TerminalWorkspaceIdentity.forProject('/repo/ianvs');
      final index = const TerminalWorkspaceIndex().markOpened(
        identity,
        openedAtUtc: DateTime.utc(2026, 7, 21, 5),
      );
      final json = <Object?, Object?>{...index.toJson(), 'futureField': true};

      final decoded = TerminalWorkspaceIndex.fromJson(json);

      expect(decoded.currentWorkspaceId, identity.id);
      expect(decoded.recent.single.identity, identity);
      expect(
        decoded.recent.single.lastOpenedAtUtc,
        DateTime.utc(2026, 7, 21, 5),
      );
      expect(
        decoded.toJson()['schemaVersion'],
        currentTerminalWorkspaceIndexSchemaVersion,
      );
      expect(decoded.toJson(), isNot(contains('futureField')));
    });

    test('rejects a future index schema explicitly', () {
      expect(
        () => TerminalWorkspaceIndex.fromJson({
          'schemaVersion': currentTerminalWorkspaceIndexSchemaVersion + 1,
          'recent': const <Object?>[],
        }),
        throwsA(isA<UnsupportedTerminalWorkspaceIndexSchemaVersion>()),
      );
    });
  });
}

TerminalWorkspaceTab _tab(String id) {
  final paneId = 'pane-$id';
  return TerminalWorkspaceTab(
    id: id,
    activePaneId: paneId,
    root: TerminalPaneNode.leaf(
      id: paneId,
      sessionDescriptor: TerminalSessionDescriptor(
        id: 'descriptor-$id',
        profileId: 'default',
      ),
    ),
  );
}
