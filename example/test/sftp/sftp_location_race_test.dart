import 'dart:async';
import 'dart:io';

import 'package:app/features/sftp/sftp_file_actions.dart';
import 'package:app/features/sftp/sftp_side_panel.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Source implements SftpDirectoryDataSource, SftpFileDataSource {
  bool failCreate = false;
  bool empty = false;
  final mutations = <SftpEntryMutationRequest>[];
  final downloads = <SftpFileTransferRequest>[];
  @override
  SftpDirectoryLoadOperation startListDirectory(SftpDirectoryRequest request) =>
      SftpDirectoryLoadOperation(
        onCancel: () {},
        future: Future.value(
          SftpDirectorySnapshot(
            path: request.path,
            entries: empty
                ? const []
                : const [
                    SftpDirectoryEntry(
                      name: 'notes.txt',
                      kind: SftpDirectoryEntryKind.file,
                    ),
                  ],
          ),
        ),
      );
  @override
  Future<void> downloadFile(SftpFileTransferRequest request) async {
    downloads.add(request);
  }

  @override
  Future<void> uploadFile(SftpFileTransferRequest request) async {}
  @override
  Future<void> createDirectory(SftpEntryMutationRequest request) async {
    if (failCreate) throw StateError('Test failure');
    mutations.add(request);
  }

  @override
  Future<void> deleteEntry(SftpEntryMutationRequest request) async {
    mutations.add(request);
  }
}

class _Platform implements SftpFileActionPlatform {
  final save = Completer<String?>();
  @override
  Future<String?> chooseSaveLocation(String suggestedName) => save.future;
  @override
  Future<Directory> createEditDirectory() =>
      throw StateError('Unexpected editor');
  @override
  Future<void> openFile(String path) async =>
      throw StateError('Unexpected editor');
  @override
  Stream<FileSystemEvent> watchDirectory(String path) => const Stream.empty();
}

Future<SftpFileActions> _pump(
  WidgetTester tester,
  ValueNotifier<int> version,
  _Source source,
  _Platform platform,
) async {
  final actions = SftpFileActions(platform: platform);
  addTearDown(actions.dispose);
  addTearDown(version.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildIanvsTerminalTheme(
        Brightness.light,
        platform: TargetPlatform.macOS,
      ),
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: version,
          builder: (_, value, _) => SftpSidePanel(
            target: SftpSessionTarget(
              sessionId: 'same-session',
              sessionEpoch: value,
              profileName: 'Remote',
              host: 'host$value.test',
              user: 'dev',
              port: 22,
            ),
            initialPath: '/directory$value',
            dataSource: source,
            fileActions: actions,
            onClose: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return actions;
}

Future<void> _menu(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const Key('sftp-entry-notes.txt')),
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'SFTP empty desktop directory offers creation without an entry menu',
    (tester) async {
      final source = _Source()..empty = true;
      await _pump(tester, ValueNotifier(1), source, _Platform());
      expect(find.byKey(const Key('sftp-create-folder')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sftp-empty-create-directory')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('sftp-create-directory-name')),
        'new folder',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('sftp-create-directory-confirm')));
      await tester.pumpAndSettle();
      expect(source.mutations.single.remotePath, '/directory1/new folder');
      expect(find.byKey(const Key('sftp-create-directory-name')), findsNothing);
    },
  );

  testWidgets(
    'SFTP queued delete rechecks location when remote operation starts',
    (tester) async {
      final version = ValueNotifier(1);
      final source = _Source();
      final actions = await _pump(tester, version, source, _Platform());
      await _menu(tester);
      await tester.tap(find.byKey(const Key('sftp-context-delete')));
      await tester.pumpAndSettle();
      final held = Completer<void>();
      final first = actions.runRemoteOperation(
        sessionId: 'same-session@1',
        remotePath: '/directory1/notes.txt',
        operation: () => held.future,
      );
      await tester.tap(find.byKey(const Key('sftp-delete-confirm')));
      await tester.pump();
      version.value = 2;
      await tester.pumpAndSettle();
      held.complete();
      await first;
      await tester.pumpAndSettle();
      expect(source.mutations, isEmpty);
    },
  );

  testWidgets('SFTP create failure retains name and allows retry', (
    tester,
  ) async {
    final version = ValueNotifier(1);
    final source = _Source()..failCreate = true;
    await _pump(tester, version, source, _Platform());
    await _menu(tester);
    await tester.tap(find.byKey(const Key('sftp-context-create-directory')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('sftp-create-directory-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('sftp-create-directory-name')),
      'child',
    );
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sftp-create-directory-name')), findsOneWidget);
    expect(find.text('child'), findsOneWidget);
    expect(source.mutations, isEmpty);
    source.failCreate = false;
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(source.mutations, hasLength(1));
    expect(find.byKey(const Key('sftp-create-directory-name')), findsNothing);
  });

  testWidgets('SFTP create dialog expires when location changes', (
    tester,
  ) async {
    final version = ValueNotifier(1);
    final source = _Source();
    await _pump(tester, version, source, _Platform());
    await _menu(tester);
    await tester.tap(find.byKey(const Key('sftp-context-create-directory')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('sftp-create-directory-name')),
      'child',
    );
    version.value = 2;
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(source.mutations, isEmpty);
  });

  testWidgets(
    'SFTP menu cannot retarget a same-named entry after location ABA',
    (tester) async {
      final version = ValueNotifier(1);
      final source = _Source();
      await _pump(tester, version, source, _Platform());
      await _menu(tester);
      version.value = 2;
      await tester.pumpAndSettle();
      version.value = 1;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sftp-context-delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sftp-delete-confirm')), findsNothing);
      expect(source.mutations, isEmpty);
    },
  );

  testWidgets('SFTP delete confirmation expires when target changes', (
    tester,
  ) async {
    final version = ValueNotifier(1);
    final source = _Source();
    await _pump(tester, version, source, _Platform());
    await _menu(tester);
    await tester.tap(find.byKey(const Key('sftp-context-delete')));
    await tester.pumpAndSettle();
    version.value = 2;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sftp-delete-confirm')));
    await tester.pumpAndSettle();
    expect(source.mutations, isEmpty);
  });

  testWidgets('SFTP save picker cannot start download after target changes', (
    tester,
  ) async {
    final version = ValueNotifier(1);
    final source = _Source();
    final platform = _Platform();
    await _pump(tester, version, source, platform);
    await tester.tap(find.byKey(const Key('sftp-entry-notes.txt')));
    await tester.pump();
    version.value = 2;
    await tester.pumpAndSettle();
    platform.save.complete('/tmp/notes.txt');
    await tester.pumpAndSettle();
    expect(source.downloads, isEmpty);
  });

  testWidgets('SFTP current target delete still executes exactly once', (
    tester,
  ) async {
    final version = ValueNotifier(1);
    final source = _Source();
    await _pump(tester, version, source, _Platform());
    await _menu(tester);
    await tester.tap(find.byKey(const Key('sftp-context-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sftp-delete-confirm')));
    await tester.pumpAndSettle();
    expect(source.mutations.single.remotePath, '/directory1/notes.txt');
    expect(source.mutations.single.target.sessionEpoch, 1);
  });
}
