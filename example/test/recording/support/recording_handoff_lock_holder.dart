import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    exitCode = 64;
    return;
  }
  final handle = await File(arguments.single).open(mode: FileMode.append);
  try {
    await handle.lock(FileLock.blockingExclusive);
    stdout.writeln('locked');
    await stdout.flush();
    await stdin.transform(utf8.decoder).first;
    await handle.unlock();
  } finally {
    await handle.close();
  }
}
