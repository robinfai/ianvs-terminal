import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

const _scope = CommandOccurrenceScope(
  sessionId: 'session',
  sessionEpoch: 1,
  transport: CommandTransportIdentity(
    kind: CommandTransportKind.ssh,
    host: 'actual-server',
    user: 'login-user',
    port: 2222,
  ),
);

Map<String, Object?> _block(
  String id, {
  String context = 'root',
  String command = 'pwd',
  int row = 100,
  bool segmented = false,
}) => {
  'id': id,
  'command': command,
  'contextId': context,
  'submissionId': 'submission-$id',
  'cwd': '/at-execution',
  'shellHostname': 'declared-shell-host',
  'shellUsername': 'declared-shell-user',
  'startedAt': 1000,
  'finishedAt': 2000,
  'exitCode': null,
  'running': false,
  'totalLines': 1,
  'sourceLineCount': 1,
  'segmented': segmented,
  'lines': [
    {'index': 0, 'source_row': row, 'text': 'file.dart:7', 'wrapped': false},
  ],
};

void main() {
  group(CommandOccurrence, () {
    test(
      'historical route leases remain isolated when shell context ids are reused',
      () {
        final first = CommandOccurrence.fromBlock(
          CommandBlock.fromJson({
            ..._block('one', context: 'nested'),
            'sftpContextId': 'nested@1',
          })!,
          _scope,
        );
        final next = CommandOccurrence.fromBlock(
          CommandBlock.fromJson({
            ..._block('two', context: 'nested'),
            'sftpContextId': 'nested@2',
          })!,
          _scope,
        );
        expect(first.contextId, next.contextId);
        expect(first.sftpContextId, 'nested@1');
        expect(next.sftpContextId, 'nested@2');
        expect(first.withoutCurrentOutput().sftpContextId, 'nested@1');
        expect(
          first.withoutCurrentOutput(unavailable: true).sftpContextId,
          'nested@1',
        );
        expect(CommandBlock.fromJson(_block('unknown'))!.sftpContextId, isNull);
        expect(
          CommandBlock.fromJson({
            ..._block('invalid'),
            'sftpContextId': 'bad/lease',
          })!.sftpContextId,
          isNull,
        );
      },
    );

    test(
      'keeps declared shell identity separate from actual transport and unknown status',
      () {
        final block = CommandBlock.fromJson(_block('one'))!;
        final occurrence = CommandOccurrence.fromBlock(block, _scope);
        expect(occurrence.cwd, '/at-execution');
        expect(occurrence.shellHostname, 'declared-shell-host');
        expect(occurrence.scope.transport.host, 'actual-server');
        expect(occurrence.scope.transport.user, 'login-user');
        expect(occurrence.startedAt, 1000);
        expect(occurrence.finishedAt, 2000);
        expect(occurrence.succeeded, isNull);
        expect(occurrence.outputRetained, isTrue);
        final restarted = CommandOccurrence.fromBlock(
          block,
          const CommandOccurrenceScope(
            sessionId: 'session',
            sessionEpoch: 2,
            transport: CommandTransportIdentity(
              kind: CommandTransportKind.local,
            ),
          ),
        );
        expect(restarted.id, isNot(occurrence.id));
      },
    );

    test(
      'composite presentation preserves native occurrence identity without cross-session collisions',
      () {
        final original = CommandBlock.fromJson(_block('one'))!;
        final projected = CommandBlock.fromJson({
          ..._block('one'),
          'id': 'session/one',
          'sourceBlockId': 'one',
        })!;
        final first = CommandOccurrence.fromBlock(original, _scope);
        final composite = CommandOccurrence.fromBlock(projected, _scope);
        expect(composite.id, first.id);
        expect(composite.presentationBlockId, 'session/one');
        final other = CommandOccurrence.fromBlock(
          projected,
          const CommandOccurrenceScope(
            sessionId: 'another-session',
            sessionEpoch: 1,
            transport: CommandTransportIdentity(
              kind: CommandTransportKind.local,
            ),
          ),
        );
        expect(other.id, isNot(first.id));
        final controller = CommandBlockController(
          occurrenceScope: _scope,
          request: (_) => {
            'blocks': [
              {..._block('one'), 'id': 'session/one', 'sourceBlockId': 'one'},
            ],
          },
        );
        addTearDown(controller.dispose);
        controller.refresh();
        expect(controller.occurrenceFor('session/one')?.id, first.id);
        expect(
          controller.occurrenceForId(first.id)?.presentationBlockId,
          'session/one',
        );
      },
    );

    test('never upgrades absent shell identity from connection labels', () {
      final block = CommandBlock.fromJson({
        ..._block('one'),
        'shellHostname': null,
        'shellUsername': null,
      })!;
      final occurrence = CommandOccurrence.fromBlock(block, _scope);
      expect(occurrence.shellHostname, isNull);
      expect(occurrence.shellUsername, isNull);
      expect(occurrence.scope.transport.host, 'actual-server');
    });
  });

  group(CommandBlockController, () {
    test('new nested route does not overwrite an older occurrence lease', () {
      var blocks = [
        {..._block('one', context: 'nested'), 'sftpContextId': 'nested@1'},
      ];
      final controller = CommandBlockController(
        occurrenceScope: _scope,
        request: (_) => {'blocks': blocks},
      );
      addTearDown(controller.dispose);
      controller.refresh();
      final original = controller.occurrenceFor('one')!;
      blocks = [
        {..._block('two', context: 'nested'), 'sftpContextId': 'nested@2'},
      ];
      controller.refresh();
      expect(
        controller.occurrenceForId(original.id)!.sftpContextId,
        'nested@1',
      );
      expect(controller.occurrenceFor('two')!.sftpContextId, 'nested@2');
    });

    test('retained metadata lookup rejects revoked and replaced scopes', () {
      CommandOccurrenceScope? scope = _scope;
      var blocks = [_block('one')];
      final controller = CommandBlockController(
        occurrenceScopeForBlock: (_) => scope,
        request: (_) => {'blocks': blocks},
      );
      addTearDown(controller.dispose);
      controller.refresh();
      final id = controller.occurrenceFor('one')!.id;
      blocks = [];
      controller.refresh();
      expect(controller.occurrenceForId(id), isNotNull);
      scope = null;
      expect(controller.occurrenceFor('one'), isNull);
      expect(controller.occurrenceForId(id), isNull);
      expect(controller.occurrenceForSubmission('submission-one'), isNull);
      expect(controller.refreshOccurrenceOutput('one'), isNull);
      scope = const CommandOccurrenceScope(
        sessionId: 'session',
        sessionEpoch: 2,
        transport: CommandTransportIdentity(kind: CommandTransportKind.local),
      );
      expect(controller.occurrenceForId(id), isNull);
    });

    test(
      'reused block id in a new generation discards cached output and selection',
      () {
        var scope = _scope;
        final controller = CommandBlockController(
          occurrenceScopeForBlock: (_) => scope,
          request: (query) => query.containsKey('id')
              ? {
                  'block': {..._block('one'), 'command': 'old page'},
                }
              : {
                  'blocks': [_block('one')],
                },
        );
        addTearDown(controller.dispose);
        controller.refresh();
        controller.page('one', 0);
        controller.select('one');
        expect(
          controller.displayBlock(controller.blocks.single).command,
          'old page',
        );
        scope = const CommandOccurrenceScope(
          sessionId: 'session',
          sessionEpoch: 2,
          transport: CommandTransportIdentity(kind: CommandTransportKind.local),
        );
        controller.refresh();
        expect(
          controller.displayBlock(controller.blocks.single).command,
          'pwd',
        );
        expect(controller.selected, isEmpty);
        expect(controller.activeId, isNull);
      },
    );

    test(
      'identical native snapshots adopt a new scope epoch without reusing old identity',
      () {
        var scope = _scope;
        final controller = CommandBlockController(
          occurrenceScopeForBlock: (_) => scope,
          request: (_) => {
            'blocks': [_block('one')],
          },
        );
        addTearDown(controller.dispose);
        controller.refresh();
        final oldId = controller.occurrenceFor('one')!.id;
        scope = const CommandOccurrenceScope(
          sessionId: 'session',
          sessionEpoch: 2,
          transport: CommandTransportIdentity(kind: CommandTransportKind.local),
        );
        controller.refresh();
        expect(controller.occurrenceFor('one')?.scope.sessionEpoch, 2);
        expect(controller.occurrenceForId(oldId), isNull);
      },
    );

    test(
      'an absent list entry cannot revoke affirmative missing-output evidence',
      () {
        var blocks = [_block('one')];
        final controller = CommandBlockController(
          occurrenceScope: _scope,
          request: (query) =>
              query.containsKey('id') ? {'missing': true} : {'blocks': blocks},
        );
        addTearDown(controller.dispose);
        controller.refresh();
        controller.refreshOccurrenceOutput('one');
        blocks = [_block('two')];
        controller.refresh();
        expect(
          controller.occurrenceFor('one')?.outputRetention,
          CommandOutputRetention.unavailable,
        );
      },
    );

    test(
      'projects lifecycle updates without duplicate history and retains bounded metadata after output disappears',
      () {
        var blocks = <Map<String, Object?>>[
          {..._block('one'), 'running': true, 'finishedAt': null},
        ];
        var missing = false;
        final controller = CommandBlockController(
          occurrenceScope: _scope,
          maximumOccurrences: 2,
          request: (query) => query.containsKey('id')
              ? {'missing': missing}
              : {'blocks': blocks},
        );
        addTearDown(controller.dispose);
        controller.refresh();
        final identity = controller.occurrences.single.id;
        expect(
          controller.occurrences.single.lifecycle,
          CommandOccurrenceLifecycle.running,
        );
        blocks = [
          {..._block('one'), 'exitCode': 7},
        ];
        controller.refresh();
        expect(controller.occurrences.single.id, identity);
        expect(controller.occurrences.single.succeeded, isFalse);
        expect(
          controller
              .occurrenceForSubmission('submission-one', contextId: 'root')
              ?.id,
          identity,
        );
        blocks = [];
        controller.refresh();
        expect(controller.occurrences.single.command, 'pwd');
        expect(
          controller.occurrences.single.outputRetention,
          CommandOutputRetention.unknown,
        );
        expect(controller.occurrences.single.finishedAt, 2000);
        missing = true;
        expect(
          controller.refreshOccurrenceOutput('one')?.outputRetained,
          isFalse,
        );
        blocks = [_block('two'), _block('three')];
        controller.refresh();
        expect(controller.occurrences.map((o) => o.blockId), ['two', 'three']);
      },
    );

    test(
      'does not fabricate completion when an open command leaves the bounded list',
      () {
        var blocks = <Map<String, Object?>>[
          {
            ..._block('one'),
            'running': true,
            'finishedAt': null,
            'exitCode': null,
          },
        ];
        final controller = CommandBlockController(
          occurrenceScope: _scope,
          request: (_) => {'blocks': blocks},
        );
        addTearDown(controller.dispose);
        controller.refresh();
        blocks = [];
        controller.refresh();
        expect(
          controller.occurrences.single.lifecycle,
          CommandOccurrenceLifecycle.unknown,
        );
        expect(controller.occurrences.single.finishedAt, isNull);
        expect(controller.occurrences.single.succeeded, isNull);
      },
    );

    test(
      'shared source rows stay ambiguous when a display filter hides one owner',
      () {
        final parent = _block('parent');
        final child = _block('child', context: 'child');
        final controller = CommandBlockController(
          occurrenceScope: _scope,
          request: (query) => query.containsKey('id')
              ? {
                  'block': {...child, 'lines': <Object?>[], 'matchingLines': 0},
                }
              : {
                  'blocks': [parent, child],
                },
        );
        addTearDown(controller.dispose);
        controller.refresh();
        expect(controller.occurrenceForSourceRow(100), isNull);
        controller.filter('child', const CommandBlockFilter(query: 'absent'));
        expect(controller.displayBlock(controller.blocks.last).lines, isEmpty);
        expect(controller.occurrenceForSourceRow(100), isNull);
        expect(controller.occurrenceForSourceRow(101), isNull);
      },
    );

    test(
      'segmented output and revoked scope never authorize a row through fallback',
      () {
        CommandOccurrenceScope? dynamicScope = _scope;
        var block = _block('parent', segmented: true);
        final controller = CommandBlockController(
          occurrenceScope: _scope,
          occurrenceScopeForBlock: (_) => dynamicScope,
          request: (_) => {
            'blocks': [block],
          },
        );
        addTearDown(controller.dispose);
        controller.refresh();
        expect(controller.occurrenceForSourceRow(100), isNull);
        block = _block('parent');
        controller.refresh();
        final id = controller.occurrenceForSourceRow(100)!.id;
        dynamicScope = null;
        expect(controller.occurrenceFor('parent'), isNull);
        expect(controller.occurrenceForId(id), isNull);
        expect(controller.occurrenceForSourceRow(100), isNull);
      },
    );
  });

  group(TerminalComposerController, () {
    test(
      'projects only current session generation and shell context without creating execution evidence for shell history',
      () {
        final editor = TerminalComposerController(
          targetId: 'session',
          provider: (query, _) async => CompletionBatch(query, const []),
        );
        addTearDown(editor.dispose);
        final root = CommandOccurrence.fromBlock(
          CommandBlock.fromJson(_block('root', command: 'root-command'))!,
          _scope,
        );
        final child = CommandOccurrence.fromBlock(
          CommandBlock.fromJson(
            _block('child', context: 'child', command: 'child-command'),
          )!,
          _scope,
        );
        final other = CommandOccurrence.fromBlock(
          CommandBlock.fromJson(
            _block('other', command: 'other-host-command'),
          )!,
          const CommandOccurrenceScope(
            sessionId: 'other',
            sessionEpoch: 1,
            transport: CommandTransportIdentity(
              kind: CommandTransportKind.ssh,
              host: 'other-host',
            ),
          ),
        );
        editor.setActive(true);
        editor.updateOccurrenceHistory(
          [root, child, other],
          scope: _scope,
          contextId: 'root',
          shellHistory: ['shell-only-command'],
        );
        editor.openHistory();
        expect(
          editor.historyItems,
          containsAll(['root-command', 'shell-only-command']),
        );
        expect(editor.historyItems, isNot(contains('child-command')));
        expect(editor.historyItems, isNot(contains('other-host-command')));
        editor.dismissHistory();
        editor.updateOccurrenceHistory(
          [root, child],
          scope: _scope,
          contextId: 'child',
        );
        editor.openHistory();
        expect(editor.historyItems, ['child-command']);
      },
    );
  });
}
