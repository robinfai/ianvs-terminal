import 'dart:async';
import 'dart:io';

import 'package:app/features/sftp/sftp_file_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SftpFileActions', () {
    test(
      'cleans a failed editor launch so the action can be retried',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'ianvs-sftp-actions-test-',
        );
        final platform = _TestSftpFileActionPlatform(
          root,
          openFailuresRemaining: 1,
        );
        final actions = SftpFileActions(platform: platform);
        addTearDown(() async {
          actions.dispose();
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });
        var downloads = 0;

        Future<void> download(String path) async {
          downloads += 1;
          await File(path).writeAsString('remote contents');
        }

        await expectLater(
          actions.editLocally(
            sessionId: 'session-1',
            remotePath: '/deploy.log',
            fileName: 'deploy.log',
            download: download,
            upload: (_) async {},
          ),
          throwsA(isA<ProcessException>()),
        );

        expect(platform.createdDirectories.single.existsSync(), isFalse);

        final retryPath = await actions.editLocally(
          sessionId: 'session-1',
          remotePath: '/deploy.log',
          fileName: 'deploy.log',
          download: download,
          upload: (_) async {},
        );

        expect(downloads, 2);
        expect(platform.openedPaths, <String>[retryPath]);
        expect(File(retryPath).readAsStringSync(), 'remote contents');
      },
    );

    test('uses a shell-safe basename for the temporary edit', () async {
      final root = await Directory.systemTemp.createTemp(
        'ianvs-sftp-safe-name-test-',
      );
      final platform = _TestSftpFileActionPlatform(root);
      final actions = SftpFileActions(platform: platform);
      addTearDown(() async {
        actions.dispose();
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final localPath = await actions.editLocally(
        sessionId: 'session-1',
        remotePath: '/a&calc.exe',
        fileName: 'a&calc.exe',
        download: (path) => File(path).writeAsString('safe'),
        upload: (_) async {},
      );

      expect(localPath, isNot(contains('&')));
      expect(localPath, endsWith('a_calc.exe'));
      expect(File(localPath).readAsStringSync(), 'safe');
    });

    test('retries a transient editor upload until it succeeds', () async {
      final root = await Directory.systemTemp.createTemp(
        'ianvs-sftp-retry-test-',
      );
      final platform = _TestSftpFileActionPlatform(root);
      final actions = SftpFileActions(
        platform: platform,
        settleDelay: const Duration(milliseconds: 10),
      );
      addTearDown(() async {
        actions.dispose();
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      var uploadAttempts = 0;
      String? uploadedContents;
      final localPath = await actions.editLocally(
        sessionId: 'session-1',
        remotePath: '/deploy.log',
        fileName: 'deploy.log',
        download: (path) => File(path).writeAsString('before'),
        upload: (path) async {
          uploadAttempts += 1;
          if (uploadAttempts < 3) {
            throw const FileSystemException('temporary failure');
          }
          uploadedContents = await File(path).readAsString();
        },
      );

      await File(localPath).writeAsString('after', flush: true);
      await _waitUntil(() => uploadedContents != null);

      expect(uploadAttempts, 3);
      expect(uploadedContents, 'after');
      expect(actions.unresolvedFailuresForSession('session-1'), isEmpty);
    });

    test(
      'ignores a watcher event when the downloaded file is unchanged',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'ianvs-sftp-unchanged-event-test-',
        );
        final watch = StreamController<FileSystemEvent>();
        final platform = _TestSftpFileActionPlatform(
          root,
          watchStream: watch.stream,
        );
        final actions = SftpFileActions(
          platform: platform,
          settleDelay: const Duration(milliseconds: 10),
        );
        addTearDown(() async {
          actions.dispose();
          await watch.close();
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });
        final uploads = <String>[];
        final localPath = await actions.editLocally(
          sessionId: 'session-1',
          remotePath: '/deploy.log',
          fileName: 'deploy.log',
          download: (path) => File(path).writeAsString('before'),
          upload: (path) async => uploads.add(await File(path).readAsString()),
        );

        watch.add(FileSystemModifyEvent(localPath, false, true));
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(uploads, isEmpty);

        await File(localPath).writeAsString('after', flush: true);
        watch.add(FileSystemModifyEvent(localPath, false, true));
        await _waitUntil(() => uploads.isNotEmpty);
        expect(uploads, <String>['after']);
      },
    );

    test('uploads immutable generations when another save arrives', () async {
      final root = await Directory.systemTemp.createTemp(
        'ianvs-sftp-generation-test-',
      );
      final platform = _TestSftpFileActionPlatform(root);
      final actions = SftpFileActions(
        platform: platform,
        settleDelay: const Duration(milliseconds: 10),
      );
      addTearDown(() async {
        actions.dispose();
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final uploads = <String>[];
      final localPath = await actions.editLocally(
        sessionId: 'session-1',
        remotePath: '/deploy.log',
        fileName: 'deploy.log',
        download: (path) => File(path).writeAsString('before'),
        upload: (path) async {
          if (uploads.isEmpty) {
            firstStarted.complete();
            await releaseFirst.future;
          }
          uploads.add(await File(path).readAsString());
        },
      );

      await File(localPath).writeAsString('save A generation', flush: true);
      await firstStarted.future;
      await File(
        localPath,
      ).writeAsString('save B newer generation', flush: true);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      releaseFirst.complete();
      await _waitUntil(() => uploads.length == 2);

      expect(uploads, <String>['save A generation', 'save B newer generation']);
    });

    test('dispose preserves a newer save during a slow upload', () async {
      final root = await Directory.systemTemp.createTemp(
        'ianvs-sftp-dispose-generation-test-',
      );
      final watch = StreamController<FileSystemEvent>();
      final platform = _TestSftpFileActionPlatform(
        root,
        watchStream: watch.stream,
      );
      final actions = SftpFileActions(
        platform: platform,
        settleDelay: const Duration(milliseconds: 10),
      );
      addTearDown(() async {
        await watch.close();
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final uploadStarted = Completer<void>();
      final releaseUpload = Completer<void>();
      final uploadFinished = Completer<void>();
      final localPath = await actions.editLocally(
        sessionId: 'session-1',
        remotePath: '/deploy.log',
        fileName: 'deploy.log',
        download: (path) => File(path).writeAsString('before'),
        upload: (path) async {
          uploadStarted.complete();
          await releaseUpload.future;
          expect(await File(path).readAsString(), 'save A generation');
          uploadFinished.complete();
        },
      );

      await File(localPath).writeAsString('save A generation', flush: true);
      watch.add(FileSystemModifyEvent(localPath, false, true));
      await uploadStarted.future;
      await File(
        localPath,
      ).writeAsString('save B newer generation', flush: true);
      watch.add(FileSystemModifyEvent(localPath, false, true));
      await Future<void>.delayed(Duration.zero);
      actions.dispose();
      releaseUpload.complete();
      await uploadFinished.future;

      expect(File(localPath).readAsStringSync(), 'save B newer generation');
    });

    test('dispose immediately after a save preserves the local edit', () async {
      final root = await Directory.systemTemp.createTemp(
        'ianvs-sftp-immediate-dispose-test-',
      );
      final watch = StreamController<FileSystemEvent>();
      final actions = SftpFileActions(
        platform: _TestSftpFileActionPlatform(root, watchStream: watch.stream),
      );
      addTearDown(() async {
        await watch.close();
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final localPath = await actions.editLocally(
        sessionId: 'session-1',
        remotePath: '/deploy.log',
        fileName: 'deploy.log',
        download: (path) => File(path).writeAsString('before'),
        upload: (_) async {},
      );

      File(localPath).writeAsStringSync('last-moment save', flush: true);
      actions.dispose();

      expect(File(localPath).readAsStringSync(), 'last-moment save');
    });

    test('keeps an unsynced local copy after retry exhaustion', () async {
      final root = await Directory.systemTemp.createTemp(
        'ianvs-sftp-recovery-test-',
      );
      final platform = _TestSftpFileActionPlatform(root);
      final actions = SftpFileActions(
        platform: platform,
        settleDelay: const Duration(milliseconds: 5),
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      var uploadAttempts = 0;
      final localPath = await actions.editLocally(
        sessionId: 'session-1',
        remotePath: '/deploy.log',
        fileName: 'deploy.log',
        download: (path) => File(path).writeAsString('before'),
        upload: (_) async {
          uploadAttempts += 1;
          throw const FileSystemException('offline');
        },
      );

      await File(localPath).writeAsString('unsynced', flush: true);
      await _waitUntil(
        () => actions.unresolvedFailuresForSession('session-1').isNotEmpty,
      );
      actions.dispose();

      expect(uploadAttempts, 5);
      expect(File(localPath).readAsStringSync(), 'unsynced');
    });

    test('serializes remote operations for the same path', () async {
      final root = await Directory.systemTemp.createTemp(
        'ianvs-sftp-serialization-test-',
      );
      final actions = SftpFileActions(
        platform: _TestSftpFileActionPlatform(root),
      );
      addTearDown(() async {
        actions.dispose();
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final releaseFirst = Completer<void>();
      var secondStarted = false;
      final busyStates = <bool>[];
      final subscription = actions.busyEvents.listen(
        (event) => busyStates.add(event.isBusy),
      );
      addTearDown(subscription.cancel);

      final first = actions.runRemoteOperation<void>(
        sessionId: 'session-1',
        remotePath: '/deploy.log',
        operation: () => releaseFirst.future,
      );
      final second = actions.runRemoteOperation<void>(
        sessionId: 'session-1',
        remotePath: '/deploy.log',
        operation: () async => secondStarted = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(secondStarted, isFalse);

      releaseFirst.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(secondStarted, isTrue);
      expect(busyStates, <bool>[true, false]);
    });

    test('reports a save chooser failure instead of swallowing it', () async {
      final root = await Directory.systemTemp.createTemp(
        'ianvs-sftp-chooser-test-',
      );
      final platform = _TestSftpFileActionPlatform(
        root,
        chooseSaveError: const FileSystemException('chooser unavailable'),
      );
      final actions = SftpFileActions(platform: platform);
      addTearDown(() async {
        actions.dispose();
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final events = <SftpFileActionEvent>[];
      final subscription = actions.events.listen(events.add);
      addTearDown(subscription.cancel);

      await expectLater(
        actions.downloadAs(
          sessionId: 'session-1',
          remotePath: '/deploy.log',
          suggestedName: 'deploy.log',
          download: (_) async {},
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(events.single.kind, SftpFileActionEventKind.failed);
    });

    test('reports a temporary-directory failure', () async {
      final root = await Directory.systemTemp.createTemp(
        'ianvs-sftp-temp-error-test-',
      );
      final platform = _TestSftpFileActionPlatform(
        root,
        createEditError: const FileSystemException('temp unavailable'),
      );
      final actions = SftpFileActions(platform: platform);
      addTearDown(() async {
        actions.dispose();
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final events = <SftpFileActionEvent>[];
      final subscription = actions.events.listen(events.add);
      addTearDown(subscription.cancel);

      await expectLater(
        actions.editLocally(
          sessionId: 'session-1',
          remotePath: '/deploy.log',
          fileName: 'deploy.log',
          download: (_) async {},
          upload: (_) async {},
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(events.single.kind, SftpFileActionEventKind.failed);
    });

    test('preserves the edit when the directory watcher ends', () async {
      final root = await Directory.systemTemp.createTemp(
        'ianvs-sftp-watch-done-test-',
      );
      final watch = StreamController<FileSystemEvent>();
      final platform = _TestSftpFileActionPlatform(
        root,
        watchStream: watch.stream,
      );
      final actions = SftpFileActions(platform: platform);
      addTearDown(() async {
        await watch.close();
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final localPath = await actions.editLocally(
        sessionId: 'session-1',
        remotePath: '/deploy.log',
        fileName: 'deploy.log',
        download: (path) => File(path).writeAsString('before'),
        upload: (_) async {},
      );

      await watch.close();
      await _waitUntil(
        () => actions.unresolvedFailuresForSession('session-1').isNotEmpty,
      );
      await File(localPath).writeAsString('edited after watcher ended');
      actions.dispose();

      expect(File(localPath).readAsStringSync(), 'edited after watcher ended');
    });
  });
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not met before the test deadline.');
}

final class _TestSftpFileActionPlatform implements SftpFileActionPlatform {
  _TestSftpFileActionPlatform(
    this.root, {
    this.openFailuresRemaining = 0,
    this.chooseSaveError,
    this.createEditError,
    this.watchStream,
  });

  final Directory root;
  int openFailuresRemaining;
  final Exception? chooseSaveError;
  final Exception? createEditError;
  final Stream<FileSystemEvent>? watchStream;
  final List<Directory> createdDirectories = <Directory>[];
  final List<String> openedPaths = <String>[];

  @override
  Future<String?> chooseSaveLocation(String suggestedName) async {
    final error = chooseSaveError;
    if (error != null) {
      throw error;
    }
    return null;
  }

  @override
  Future<Directory> createEditDirectory() async {
    final error = createEditError;
    if (error != null) {
      throw error;
    }
    final directory = await Directory(
      '${root.path}${Platform.pathSeparator}edit-${createdDirectories.length}',
    ).create();
    createdDirectories.add(directory);
    return directory;
  }

  @override
  Future<void> openFile(String path) async {
    if (openFailuresRemaining > 0) {
      openFailuresRemaining -= 1;
      throw const ProcessException('editor', <String>[]);
    }
    openedPaths.add(path);
  }

  @override
  Stream<FileSystemEvent> watchDirectory(String path) {
    return watchStream ?? Directory(path).watch();
  }
}
