import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

/// macOS development-only storage. Secrets are plain text inside an
/// owner-only directory; production must continue to use platform storage.
final class DevelopmentSecretFile {
  DevelopmentSecretFile({required this._directoryResolver, required this.name});

  final Future<Directory> Function() _directoryResolver;
  final String name;
  Future<void> _tail = Future<void>.value();

  Future<File> _file() async {
    final root = await _directoryResolver();
    final directory = Directory('${root.path}/secrets');
    await directory.create(recursive: true);
    _restrict(directory.path, 448); // 0700
    return File('${directory.path}/$name');
  }

  Future<String?> read() => _serialized(() async {
    final file = await _file();
    if (!await file.exists()) return null;
    _restrict(file.path, 384); // 0600
    return file.readAsString();
  });

  Future<void> write(String? value) => _serialized(() async {
    final file = await _file();
    if (value == null) {
      if (await file.exists()) await file.delete();
      return;
    }
    // Restrict the staging directory before writing any secret bytes. Rename
    // within the same filesystem publishes the complete, flushed file.
    final staging = await file.parent.createTemp('.write-');
    try {
      _restrict(staging.path, 448);
      final temporary = await File('${staging.path}/value').create();
      _restrict(temporary.path, 384);
      await temporary.writeAsString(value, flush: true);
      await temporary.rename(file.path);
    } finally {
      await staging.delete(recursive: true);
    }
  });

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

final int Function(ffi.Pointer<Utf8>, int) _chmod = ffi.DynamicLibrary.process()
    .lookupFunction<
      ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Uint32),
      int Function(ffi.Pointer<Utf8>, int)
    >('chmod');

void _restrict(String path, int mode) {
  final nativePath = path.toNativeUtf8();
  try {
    if (_chmod(nativePath, mode) != 0) {
      throw FileSystemException(
        'Could not restrict development secret storage.',
        path,
      );
    }
  } finally {
    malloc.free(nativePath);
  }
}
