import 'dart:async';

import 'package:flutter/services.dart';

import '../services/data_api_client.dart';

/// Developer ID apps use a system authentication session with an automatic
/// callback. Identity tokens and the retrieval secret never travel in URLs.
Future<Map<String, Object?>> desktopAppleIdentity(
  DataApiClient client,
  Uri baseUri, {
  bool Function()? isCancelled,
}) async {
  if (baseUri.scheme != 'https') {
    throw StateError('Apple sign-in requires HTTPS.');
  }
  const channel = MethodChannel('app/window_bridge');
  final flow = await client.desktopAppleExchange('start', const {});
  final id = flow['id']! as String;
  final secret = flow['secret']! as String;
  Future<void> cancelSystemSession() async {
    try {
      await channel.invokeMethod<void>('cancelAppleWebAuthentication');
    } on Object {
      /* The native session may already have ended. */
    }
  }

  var consumed = false;
  Timer? cancellation;
  try {
    if (isCancelled?.call() ?? false) {
      throw PlatformException(code: 'oauth_cancelled');
    }
    cancellation = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (isCancelled?.call() ?? false) {
        cancellation?.cancel();
        unawaited(cancelSystemSession());
      }
    });
    final result = await channel
        .invokeMethod<String>('appleWebAuthentication', {
          'url': flow['authorization_url'],
          'state': id,
        })
        .timeout(const Duration(minutes: 4));
    final callback = Uri.tryParse(result ?? '');
    if (callback?.scheme != 'work.ianvs.trail.auth' ||
        callback?.host != 'apple' ||
        callback?.queryParameters['state'] != id) {
      throw StateError('Invalid Apple authentication callback.');
    }
    if (callback!.queryParameters['error'] == 'cancelled') {
      throw PlatformException(code: 'oauth_cancelled');
    }
    if (callback.queryParameters.containsKey('error')) {
      throw StateError('Apple authentication failed. Please retry.');
    }
    final response = await client.desktopAppleExchange('poll', {
      'id': id,
      'secret': secret,
    });
    final token = response['identity_token'];
    if (token is! String || token.isEmpty) {
      throw StateError('Apple did not return an identity token.');
    }
    consumed = true;
    return {
      'provider': 'apple',
      'identity_token': token,
      'nonce': response['nonce'],
    };
  } finally {
    cancellation?.cancel();
    if (!consumed) {
      await cancelSystemSession();
      try {
        await client.desktopAppleExchange('cancel', {
          'id': id,
          'secret': secret,
        });
      } on Object {
        /* Server expiry also removes abandoned flows. */
      }
    }
  }
}
