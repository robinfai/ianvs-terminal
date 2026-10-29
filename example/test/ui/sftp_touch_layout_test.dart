import 'dart:ui' show SemanticsAction;

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
          SftpDirectorySnapshot(
            path: request.path,
            entries: const [
              SftpDirectoryEntry(
                name: 'folder',
                kind: SftpDirectoryEntryKind.directory,
              ),
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
  testWidgets(
    'desktop SFTP exposes named toolbar actions and one actionable file row',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 800);
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      final actions = SftpFileActions();
      addTearDown(actions.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(
            Brightness.light,
            platform: TargetPlatform.macOS,
          ),
          home: Scaffold(
            body: SftpSidePanel(
              target: const SftpSessionTarget(
                sessionId: 'test',
                profileName: 'Review',
                host: 'example.test',
                user: 'tester',
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
        expect(
          tester.getSemantics(find.byKey(Key(key))).getSemanticsData().label,
          isNotEmpty,
        );
      }
      final row = tester
          .getSemantics(find.byKey(const Key('sftp-entry-notes.txt')))
          .getSemanticsData();
      expect(row.label, contains('notes.txt'));
      expect(row.hasAction(SemanticsAction.tap), isTrue);
      final folder = find.byKey(const Key('sftp-entry-folder'));
      final rect = tester.getRect(folder);
      await tester.tapAt(Offset(rect.right - 80, rect.center.dy));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SelectableText>(find.byKey(const Key('sftp-current-path')))
            .data,
        '/folder',
      );
      await tester.tapAt(Offset(rect.right - 80, rect.center.dy));
      await tester.pump();
      expect(
        tester
            .widget<SelectableText>(find.byKey(const Key('sftp-current-path')))
            .data,
        '/folder',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tapAt(Offset(rect.right - 80, rect.center.dy));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SelectableText>(find.byKey(const Key('sftp-current-path')))
            .data,
        '/folder/folder',
      );
      handle.dispose();
    },
  );

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
      expect(
        find.byKey(const Key('sftp-context-copy-full-path')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sftp-context-edit-locally')), findsNothing);
      expect(
        find.byKey(const Key('sftp-context-create-directory')),
        findsNothing,
      );
      expect(find.byKey(const Key('sftp-context-delete')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
