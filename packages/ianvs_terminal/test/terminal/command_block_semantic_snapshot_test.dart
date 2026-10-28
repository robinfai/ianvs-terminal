import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  for (final mismatch in ['none', 'cwd', 'context', 'host', 'route']) {
    testWidgets(
      'Block file provenance rejects $mismatch mismatch with retained page',
      (tester) async {
        final block = CommandBlock.fromJson({
          'id': 'same-id',
          'command': 'cat file',
          'cwd': '/old',
          'contextId': 'old-context',
          'shellHostname': 'old-host',
          'sftpContextId': 'nested@1',
          'columns': 40,
          'exitCode': 0,
          'totalLines': 1,
          'lines': [
            {'index': 0, 'text': 'src/file.dart:12'},
          ],
        })!;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CommandBlockTerminal(
                block: block,
                semanticContext: TerminalSemanticContext(
                  occurrenceId: 'same-id',
                  sessionId: 'session',
                  sessionEpoch: 1,
                  cwd: mismatch == 'cwd' ? '/new' : '/old',
                  contextId: mismatch == 'context'
                      ? 'new-context'
                      : 'old-context',
                  shellHostname: mismatch == 'host' ? 'new-host' : 'old-host',
                  sftpContextId: mismatch == 'route' ? 'nested@2' : 'nested@1',
                ),
                onOpenLinkTarget: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        final viewport = tester.widget<TerminalViewport>(
          find.byType(TerminalViewport),
        );
        final target = terminalSemanticTargetAt(
          rows: viewport.controller.frame.rows,
          row: 0,
          column: 4,
          contextForRow: viewport.semanticContextForRow,
        );
        if (mismatch == 'none') {
          expect(target!.fileTarget!.context.cwd, '/old');
        } else {
          expect(target, isNull);
        }
      },
    );
  }
}
