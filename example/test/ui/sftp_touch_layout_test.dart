import 'package:app/features/sftp/sftp_file_actions.dart';
import 'package:app/features/sftp/sftp_side_panel.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _DirectorySource implements SftpDirectoryDataSource {
  @override
  SftpDirectoryLoadOperation startListDirectory(SftpDirectoryRequest request) =>
      SftpDirectoryLoadOperation(
        onCancel: () {},
        future: Future.value(
          const SftpDirectorySnapshot(
            path: '/',
            entries: [
              SftpDirectoryEntry(
                name: 'notes.txt',
                kind: SftpDirectoryEntryKind.file,
              ),
            ],
          ),
        ),
      );
}

void main() {
  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('SFTP touch actions remain reachable at ${scale}x', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 667);
      addTearDown(tester.view.reset);
      final actions = SftpFileActions();
      addTearDown(actions.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(
            Brightness.dark,
            platform: TargetPlatform.iOS,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SftpSidePanel(
              target: const SftpSessionTarget(
                sessionId: 'test',
                profileName: 'Review',
                host: 'review.example.test',
                user: 'reviewer',
                port: 22,
              ),
              dataSource: _DirectorySource(),
              fileActions: actions,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final key in [
        'sftp-go-root',
        'sftp-go-up',
        'sftp-refresh',
        'sftp-right-panel-close',
      ]) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      expect(find.text('notes.txt'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sftp-entry-actions-notes.txt')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sftp-context-copy-full-path')), findsOneWidget);
      expect(find.byKey(const Key('sftp-context-edit-locally')), findsNothing);
      expect(find.byKey(const Key('sftp-context-create-directory')), findsNothing);
      expect(find.byKey(const Key('sftp-context-delete')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
