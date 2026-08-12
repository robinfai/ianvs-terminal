import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    exitCode = 64;
    return;
  }
  final claimPath = arguments[0];
  final destinationPath = arguments[1];
  final sessionId = arguments[2];
  final nonce = arguments[3];
  final handle = await File(claimPath).open(mode: FileMode.append);
  try {
    await handle.lock(FileLock.blockingExclusive);
    handle
      ..truncateSync(0)
      ..setPositionSync(0)
      ..writeStringSync(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'destinationPath': destinationPath,
          'sessionId': sessionId,
          'nonce': nonce,
          'ownerPid': pid,
        }),
      )
      ..flushSync();
    stdout.writeln('reserved');
    await stdout.flush();
    await stdin.transform(utf8.decoder).first;
    await handle.unlock();
  } finally {
    await handle.close();
  }
}
