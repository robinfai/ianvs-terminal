import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/sftp/sftp_file_actions.dart';
import 'package:app/features/sftp/sftp_image_preview.dart';
import 'package:app/features/sftp/sftp_side_panel.dart';
import 'package:app/ui/app_ui.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Source implements SftpDirectoryDataSource, SftpFileDataSource {
  String fileName = 'notes.txt';
  bool failDownload = false;
  bool failCreate = false;
  bool empty = false;
  final mutations = <SftpEntryMutationRequest>[];
  final downloads = <SftpFileTransferRequest>[];
  final uploads = <SftpFileTransferRequest>[];
  @override
  SftpDirectoryLoadOperation startListDirectory(SftpDirectoryRequest request) =>
      SftpDirectoryLoadOperation(
        onCancel: () {},
        future: Future.value(
          SftpDirectorySnapshot(
            path: request.path,
            entries: empty
                ? const []
                : [
                    SftpDirectoryEntry(
                      name: fileName,
                      kind: SftpDirectoryEntryKind.file,
                    ),
                  ],
          ),
        ),
      );
  @override
  Future<void> downloadFile(SftpFileTransferRequest request) async {
    downloads.add(request);
    if (failDownload) throw StateError('Download failed');
    if (isSftpPreviewImage(fileName)) {
      await File(request.localPath).writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=',
        ),
      );
    }
  }

  @override
  Future<void> uploadFile(SftpFileTransferRequest request) async {
    uploads.add(request);
  }

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
  int saveCalls = 0;
  final save = Completer<String?>();
  @override
  Future<String?> chooseSaveLocation(String suggestedName) {
    saveCalls++;
    return save.future;
  }

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
  _Platform platform, {
  Future<XFile?> Function()? picker,
}) async {
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
            pickUploadFile: picker,
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
  for (final fail in [false, true]) {
    testWidgets('image click previews without Save dialog (failure: $fail)', (
      tester,
    ) async {
      final source = _Source()
        ..fileName = 'photo.PNG'
        ..failDownload = fail;
      final platform = _Platform();
      await _pump(tester, ValueNotifier(0), source, platform);
      await tester.tap(find.byKey(const Key('sftp-entry-photo.PNG')));
      await tester.runAsync(() async {
        await tester.pump();
        // Allow real temporary-file IO to complete outside the fake clock.
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (source.downloads.isNotEmpty &&
              !await File(source.downloads.single.localPath).parent.exists()) {
            break;
          }
        }
      });
      await tester.pumpAndSettle();
      expect(find.byType(SftpImagePreview), findsOneWidget);
      expect(source.downloads, hasLength(1));
      expect(platform.saveCalls, 0);
      await tester.runAsync(() async {
        expect(
          await File(source.downloads.single.localPath).parent.exists(),
          isFalse,
        );
      });
      expect(find.text('Retry'), fail ? findsOneWidget : findsNothing);
      if (!fail) expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.text('Download'));
      await tester.pump();
      expect(platform.saveCalls, 1);
      platform.save.complete(null);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
      expect(find.byType(SftpImagePreview), findsNothing);
    });
  }

  testWidgets(
    'upload requires destination confirmation and does not retarget after profile changes',
    (tester) async {
      final source = _Source();
      final version = ValueNotifier(0);
      await _pump(
        tester,
        version,
        source,
        _Platform(),
        picker: () async => XFile('/tmp/upload.txt'),
      );
      await tester.tap(find.byKey(const Key('sftp-upload-file')));
      await tester.pumpAndSettle();
      expect(source.uploads, isEmpty);
      version.value++;
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(source.uploads, isEmpty);
      await tester.tap(find.byKey(const Key('sftp-upload-file')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(source.uploads, hasLength(1));
      expect(source.uploads.single.remotePath, '/directory1/upload.txt');
      expect(source.uploads.single.target.host, 'host1.test');
    },
  );

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
