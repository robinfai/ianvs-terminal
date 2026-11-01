import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_models.dart';
import 'ai_settings.dart';

Map<String, Object?> _map(Object? value) =>
    (value! as Map).cast<String, Object?>();

class AiCreditProduct {
  const AiCreditProduct(this.id, this.points, this.title, this.price);
  final String id;
  final int points;
  final String title;
  final String price;
}

abstract interface class AiPurchaseApi {
  Future<Map<String, Object?>> catalog();
  Future<Map<String, Object?>> verify(String transactionId);
  Future<List<Map<String, Object?>>> history();
}

class AiPurchaseClient implements AiPurchaseApi {
  const AiPurchaseClient(this.configuration);
  final AiConfiguration configuration;
  Future<Map<String, Object?>> _request(
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final uri = configuration.completionsUri;
    final target = uri.replace(
      path: uri.path.replaceFirst(
        RegExp(r'/chat/completions$'),
        '/purchases$path',
      ),
      query: null,
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      return await (() async {
        final request = await client.openUrl(
          body == null ? 'GET' : 'POST',
          target,
        );
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${configuration.apiKey.trim()}',
        );
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(body));
        }
        final response = await request.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 1024 * 1024) {
            throw const AiFailure('purchase_unavailable');
          }
          bytes.addAll(chunk);
        }
        if (response.statusCode != 200) {
          throw AiFailure(
            path != '/verify'
                ? 'purchase_unavailable'
                : response.statusCode == 403
                ? 'purchase_account_mismatch'
                : 'purchase_verification_pending',
          );
        }
        return _map(jsonDecode(utf8.decode(bytes)));
      })().timeout(const Duration(seconds: 30));
    } on AiFailure {
      rethrow;
    } on Object {
      throw const AiFailure('purchase_unavailable');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<Map<String, Object?>> catalog() => _request('/products');
  @override
  Future<Map<String, Object?>> verify(String transactionId) =>
      _request('/verify', {'transaction_id': transactionId});
  @override
  Future<List<Map<String, Object?>>> history() async =>
      ((await _request(''))['data']! as List).map(_map).toList();
}

abstract interface class AiPurchaseStore {
  set onChanged(VoidCallback? callback);
  Future<List<Map<String, Object?>>> products(List<String> ids);
  Future<Map<String, Object?>> purchase(String id, String accountToken);
  Future<List<Map<String, Object?>>> unfinished();
  Future<void> finish(String id);
}

class AppleAiPurchaseStore implements AiPurchaseStore {
  static const _channel = MethodChannel('app/ai_purchases');
  @override
  set onChanged(VoidCallback? callback) => _channel.setMethodCallHandler(
    callback == null
        ? null
        : (call) async {
            if (call.method == 'transactionsChanged') callback();
          },
  );
  @override
  Future<List<Map<String, Object?>>> products(List<String> ids) async =>
      (await _channel.invokeListMethod<Object?>('products', {'ids': ids}) ?? [])
          .map(_map)
          .toList();
  @override
  Future<Map<String, Object?>> purchase(String id, String accountToken) async =>
      _map(
        await _channel.invokeMethod<Object?>('purchase', {
          'product_id': id,
          'app_account_token': accountToken,
        }),
      );
  @override
  Future<List<Map<String, Object?>>> unfinished() async =>
      (await _channel.invokeListMethod<Object?>('unfinished') ?? [])
          .map(_map)
          .toList();
  @override
  Future<void> finish(String id) =>
      _channel.invokeMethod<void>('finish', {'transaction_id': id});
}

/// One application-wide coordinator; delivery outlives the purchase page.
/// StoreKit retains unfinished transactions across app restarts and offline time.
class AiPurchaseController extends ChangeNotifier with WidgetsBindingObserver {
  AiPurchaseController({required this.store, required this.onCredited}) {
    store.onChanged = () => unawaited(recover());
    WidgetsBinding.instance.addObserver(this);
  }
  final AiPurchaseStore store;
  final Future<void> Function() onCredited;
  AiPurchaseApi? _api;
  String? _accountToken;
  bool enabled = false;
  bool loading = false;
  bool buying = false;
  bool recovering = false;
  bool _disposed = false;
  int _epoch = 0;
  String? message;
  List<AiCreditProduct> products = [];
  List<Map<String, Object?>> history = [];
  final Map<String, Future<void>> _deliveries = {};

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> configure(AiPurchaseApi? api) async {
    _epoch++;
    _api = api;
    _accountToken = null;
    products = [];
    history = [];
    enabled = false;
    message = null;
    loading = false;
    _notify();
    if (api != null) await refresh();
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  Future<void> refresh() async {
    final api = _api;
    if (_disposed || api == null || loading) return;
    final epoch = _epoch;
    loading = true;
    message = null;
    _notify();
    try {
      final catalog = await api.catalog();
      if (!_current(epoch)) return;
      enabled = catalog['enabled'] == true;
      if (!enabled) {
        products = [];
        return;
      }
      _accountToken = (catalog['app_account_token']! as String).toLowerCase();
      final amounts = <String, int>{
        for (final raw in catalog['products']! as List)
          _map(raw)['id']! as String: _map(raw)['quota_points']! as int,
      };
      final found = await store.products(amounts.keys.toList());
      if (!_current(epoch)) return;
      products = found
          .where((item) => amounts.containsKey(item['id']))
          .map(
            (item) => AiCreditProduct(
              item['id']! as String,
              amounts[item['id']]!,
              item['title']! as String,
              item['price']! as String,
            ),
          )
          .toList();
      await recover();
      final records = await api.history();
      if (_current(epoch)) history = records;
    } on Object catch (error) {
      if (_current(epoch)) message = _error(error);
    } finally {
      if (_current(epoch)) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> buy(AiCreditProduct product) async {
    final token = _accountToken;
    if (_disposed ||
        buying ||
        !enabled ||
        token == null ||
        !products.contains(product)) {
      return;
    }
    final epoch = _epoch;
    buying = true;
    message = null;
    _notify();
    try {
      final result = await store.purchase(product.id, token);
      if (!_current(epoch)) {
        return; // The original account will recover it later.
      }
      switch (result['status']) {
        case 'purchased':
          await _deliver(_map(result['transaction']), epoch);
        case 'pending':
          message = 'purchase_pending';
        case 'cancelled':
          message = 'purchase_cancelled';
        default:
          message = 'purchase_verification_pending';
      }
      final records = await _api!.history();
      if (_current(epoch)) history = records;
    } on Object catch (error) {
      if (_current(epoch)) message = _error(error);
    } finally {
      buying = false;
      _notify();
    }
  }

  Future<void> recover() async {
    if (_disposed || _api == null || _accountToken == null || recovering) {
      return;
    }
    final epoch = _epoch;
    recovering = true;
    _notify();
    try {
      for (final transaction in await store.unfinished()) {
        if (!_current(epoch)) return;
        // Never submit or finish another signed-in account's transactions.
        if ((transaction['app_account_token'] as String?)?.toLowerCase() !=
            _accountToken) {
          continue;
        }
        await _deliver(transaction, epoch);
      }
    } on Object catch (error) {
      if (_current(epoch)) message = _error(error);
    } finally {
      recovering = false;
      _notify();
    }
  }

  Future<void> _deliver(Map<String, Object?> transaction, int epoch) async {
    final id = transaction['transaction_id']! as String;
    final existing = _deliveries[id];
    if (existing != null) {
      await existing;
      return;
    }
    final api = _api!;
    Future<void> deliver() async {
      final result = await api.verify(id);
      final status = _map(result['purchase'])['status'];
      if (status != 'credited' && status != 'revoked') {
        throw const AiFailure('purchase_verification_pending');
      }
      // Finish only after durable backend acknowledgement; retry is idempotent.
      await store.finish(id);
      if (_current(epoch)) {
        message = status == 'credited'
            ? 'purchase_success'
            : 'purchase_revoked';
        await onCredited();
      }
    }

    final future = deliver();
    _deliveries[id] = future;
    try {
      await future;
    } finally {
      _deliveries.removeWhere((key, _) => key == id);
    }
  }

  String _error(Object error) =>
      error is AiFailure ? error.code : 'purchase_verification_pending';
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    store.onChanged = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final aiPurchaseProvider = Provider<AiPurchaseController?>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
  final settings = ref.read(aiSettingsProvider);
  final controller = AiPurchaseController(
    store: AppleAiPurchaseStore(),
    onCredited: () async {
      await settings.usage?.refresh();
    },
  );
  AiConfiguration? previous;
  void changed() {
    final next = settings.gatewayConfiguration;
    if (previous?.hasSameValues(next) ?? next == null) return;
    previous = next;
    unawaited(
      controller.configure(next == null ? null : AiPurchaseClient(next)),
    );
  }

  settings.addListener(changed);
  scheduleMicrotask(changed);
  ref.onDispose(() {
    settings.removeListener(changed);
    controller.dispose();
  });
  return controller;
});
