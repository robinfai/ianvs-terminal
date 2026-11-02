import 'dart:async';

import '../../features/shell/window_bridge.dart';
import '../services/data_api_client.dart';

/// Developer ID apps cannot use the native Apple sign-in entitlement.
/// The retrieval secret stays in the app; the browser only gets a flow ID.
Future<Map<String, Object?>> desktopAppleIdentity(
  DataApiClient client,
  Uri baseUri, {
  bool Function()? isCancelled,
}) async {
  if (baseUri.scheme != 'https') {
    throw StateError('Apple sign-in requires HTTPS.');
  }
  final flow = await client.desktopAppleExchange('start', const {});
  final id = flow['id']! as String;
  final secret = flow['secret']! as String;
  var consumed = false;
  try {
    await WindowBridge.openExternalUrl(
      baseUri
          .resolve('/desktop/apple')
          .replace(fragment: 'flow=$id')
          .toString(),
    );
    final deadline = DateTime.now().add(const Duration(minutes: 4));
    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled?.call() ?? false) {
        throw StateError('Apple sign-in cancelled.');
      }
      await Future<void>.delayed(const Duration(seconds: 8));
      final response = await client.desktopAppleExchange('poll', {
        'id': id,
        'secret': secret,
      });
      final token = response['identity_token'];
      if (token is String && token.isNotEmpty) {
        consumed = true;
        return {
          'provider': 'apple',
          'identity_token': token,
          'nonce': response['nonce'],
        };
      }
    }
    throw TimeoutException('Apple sign-in timed out. Please retry.');
  } finally {
    if (!consumed) {
      try {
        await client.desktopAppleExchange('cancel', {
          'id': id,
          'secret': secret,
        });
      } on Object catch (_) {
        /* Server expiry also removes abandoned flows. */
      }
    }
  }
}
