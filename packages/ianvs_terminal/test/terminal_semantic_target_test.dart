import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

const provenance = TerminalSemanticContext(
  occurrenceId: 'session/epoch/block',
  sessionId: 'session',
  sessionEpoch: 4,
  cwd: '/old/project',
  contextId: 'shell-1',
  shellHostname: 'remote',
);

void main() {
  group('wrapped file URI ownership', () {
    TerminalSemanticTarget? resolve(TerminalSemanticContextResolver resolver) =>
        terminalSemanticTargetAt(
          rows: const [
            TerminalRow(index: 0, text: 'file:///old/pro', wrapped: true),
            TerminalRow(index: 1, text: 'ject/main.dart'),
          ],
          row: 1,
          column: 3,
          contextForRow: resolver,
        );

    test('accepts fragments belonging to the same occurrence snapshot', () {
      expect(resolve((_) => provenance)!.text, 'file:///old/project/main.dart');
    });

    test('rejects a fragment with an unknown owner', () {
      expect(resolve((row) => row.index == 0 ? null : provenance), isNull);
    });

    for (final changed in ['occurrence', 'revision']) {
      test('rejects fragments with different $changed identities', () {
        expect(
          resolve(
            (row) => TerminalSemanticContext(
              occurrenceId: changed == 'occurrence'
                  ? 'owner-${row.index}'
                  : 'owner',
              sessionId: 'session',
              sessionEpoch: 1,
              cwd: '/old/project',
              frameRevision: changed == 'revision' ? '${row.index + 1}' : '1',
              viewportRow: row.index,
            ),
          ),
          isNull,
        );
      });
    }

    test('ordinary wrapped https URLs need no file provenance', () {
      final target = terminalSemanticTargetAt(
        rows: const [
          TerminalRow(index: 0, text: 'https://example.', wrapped: true),
          TerminalRow(index: 1, text: 'com/main.dart'),
        ],
        row: 1,
        column: 2,
      );
      expect(target!.text, 'https://example.com/main.dart');
    });
  });

  TerminalSemanticTarget? at(String text, int col, {bool known = true}) =>
      terminalSemanticTargetAt(
        rows: [TerminalRow(index: 0, text: text)],
        row: 0,
        column: col,
        contextForRow: known ? (_) => provenance : null,
      );

  test('wrapped file refuses fragments from different frame revisions', () {
    final target = terminalSemanticTargetAt(
      rows: const [
        TerminalRow(index: 0, text: 'src/main.', wrapped: true),
        TerminalRow(index: 1, text: 'dart:7'),
      ],
      row: 1,
      column: 2,
      contextForRow: (row) => TerminalSemanticContext(
        occurrenceId: provenance.occurrenceId,
        sessionId: provenance.sessionId,
        sessionEpoch: provenance.sessionEpoch,
        cwd: provenance.cwd,
        frameRevision: '${row.index}',
        viewportRow: row.index,
      ),
    );
    expect(target, isNull);
  });

  test(
    'file locations preserve original command provenance without live cwd',
    () {
      final target = at('error src/main.dart:12:4', 10)!.fileTarget!;
      expect(target.path, 'src/main.dart');
      expect((target.line, target.column), (12, 4));
      expect(identical(target.context, provenance), isTrue);
      expect(target.context.cwd, '/old/project');
      expect(at('src/main.dart:12', 2, known: false), isNull);
      expect(at('/tmp/main.dart:12', 2, known: false), isNull);
    },
  );

  test('quoted and escaped spaces retain path and location', () {
    expect(
      at('"src/my file.dart":9:2', 8)!.fileTarget!.path,
      'src/my file.dart',
    );
    expect(at("'src/my file.dart':9", 8)!.fileTarget!.line, 9);
    expect(at(r'src/my\ file.dart:9', 8)!.fileTarget!.path, 'src/my file.dart');
    expect(at('README.md:3', 1)!.fileTarget!.line, 3);
    expect(at('ordinary words', 2), isNull);
    expect(at('~/secret:2', 2), isNull);
    expect(at('src/main.dart:0', 2), isNull);
  });

  test('URLs precede paths and trim surrounding diagnostic punctuation', () {
    final target = at('(https://example.com/a.dart),', 8, known: false)!;
    expect(target.text, 'https://example.com/a.dart');
    expect(target.fileTarget, isNull);
    expect(at('https://example.com/a.dart', 4)!.fileTarget, isNull);
  });

  test(
    'wide characters and soft wrapping map display cell to complete target',
    () {
      final target = terminalSemanticTargetAt(
        rows: const [
          TerminalRow(index: 0, text: '错 src/长', wrapped: true),
          TerminalRow(index: 1, text: '文件.dart:7:2'),
        ],
        row: 1,
        column: 3,
        contextForRow: (_) => provenance,
      )!.fileTarget!;
      expect(target.path, 'src/长文件.dart');
      expect((target.line, target.column), (7, 2));
      expect(at('错 src/main.dart:5', 6)!.fileTarget!.path, 'src/main.dart');
    },
  );

  test(
    'never joins hard lines, absent fragments or different command owners',
    () {
      expect(
        terminalSemanticTargetAt(
          rows: const [
            TerminalRow(index: 0, text: 'src/mai'),
            TerminalRow(index: 1, text: 'n.dart:7'),
          ],
          row: 1,
          column: 2,
          contextForRow: (_) => provenance,
        )!.fileTarget!.path,
        'n.dart',
      );
      expect(
        terminalSemanticTargetAt(
          rows: const [TerminalRow(index: 0, text: 'src/main.', wrapped: true)],
          row: 0,
          column: 2,
          contextForRow: (_) => provenance,
        ),
        isNull,
      );
      expect(
        terminalSemanticTargetAt(
          rows: const [
            TerminalRow(index: 0, text: 'src/', wrapped: true),
            TerminalRow(index: 1, text: 'main.dart'),
          ],
          row: 1,
          column: 2,
          contextForRow: (row) => row.index == 0
              ? provenance
              : const TerminalSemanticContext(
                  occurrenceId: 'other',
                  sessionId: 'session',
                  sessionEpoch: 4,
                  cwd: '/new',
                ),
        ),
        isNull,
      );
    },
  );

  test(
    'balanced URL parentheses survive and truncated logical lines do not open',
    () {
      expect(
        at('(https://example.com/a(b)),', 10)!.text,
        'https://example.com/a(b)',
      );
      final rows = List.generate(
        40,
        (i) => TerminalRow(
          index: i,
          text: i == 6 ? 'src/' : 'main.dart',
          wrapped: i < 39,
        ),
      );
      expect(
        terminalSemanticTargetAt(
          rows: rows,
          row: 39,
          column: 2,
          contextForRow: (_) => provenance,
        ),
        isNull,
      );
      expect(
        terminalSemanticTargetAt(
          rows: const [
            TerminalRow(
              index: 0,
              text: 'https://example.com/part',
              wrapped: true,
            ),
          ],
          row: 0,
          column: 5,
        ),
        isNull,
      );
    },
  );
  test('filtered source gaps do not splice paths across retained rows', () {
    expect(
      terminalSemanticTargetAt(
        rows: const [
          TerminalRow(index: 0, sourceRow: 0, text: 'src/', wrapped: true),
          TerminalRow(index: 1, sourceRow: 8, text: 'main.dart'),
        ],
        row: 0,
        column: 2,
        contextForRow: (_) => provenance,
      ),
      isNull,
    );
  });
}
