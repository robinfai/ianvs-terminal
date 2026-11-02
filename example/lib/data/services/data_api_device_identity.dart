import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

Future<String>? _installation;

/// Random per-installation identity, never synchronized through iCloud.
/// The origin-scoped hash is only a session deduplication hint after login.
Future<String> dataApiDeviceIdentity(Uri server) async {
  final installation = await (_installation ??= _loadInstallation().catchError((
    Object e,
  ) {
    _installation = null;
    Error.throwWithStackTrace(e, StackTrace.current);
  }));
  final hash = await Sha256().hash(
    utf8.encode('${server.origin}/$installation'),
  );
  return base64Url.encode(hash.bytes).replaceAll('=', '');
}

Future<String> _loadInstallation() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  final file = File('${directory.path}/auth-installation-id');
  if (await file.exists()) {
    final value = (await file.readAsString()).trim();
    if (RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) return value;
    throw const FormatException('Invalid local authentication installation ID');
  }
  final random = Random.secure();
  final id = base64Url
      .encode(List.generate(32, (_) => random.nextInt(256)))
      .replaceAll('=', '');
  await file.writeAsString(id, flush: true);
  return id;
}
