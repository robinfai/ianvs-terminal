import 'dart:async';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_purchase_page.dart';
import 'package:app/features/ai/ai_purchases.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

class FakePurchaseApi implements AiPurchaseApi {
  FakePurchaseApi(this.token);
  final String token;
  bool fail = false;
  int calls = 0;
  int credits = 0;
  final Set<String> received = {};
  Completer<void>? gate;
  @override
  Future<Map<String, Object?>> catalog() async => {
    'enabled': true,
    'app_account_token': token,
    'products': [
      {'id': 'pack', 'quota_points': 1000},
    ],
  };
  @override
  Future<Map<String, Object?>> verify(String id) async {
    calls++;
    if (fail) throw const AiFailure('purchase_verification_pending');
    await gate?.future;
    if (received.add(id)) credits += 1000;
    return {
      'purchase': {'status': 'credited'},
    };
  }

  @override
  Future<List<Map<String, Object?>>> history() async => [];
}

class FakePurchaseStore implements AiPurchaseStore {
  @override
  VoidCallback? onChanged;
  List<Map<String, Object?>> queue = [];
  final List<String> finished = [];
  String status = 'purchased';
  Completer<void>? gate;
  @override
  Future<List<Map<String, Object?>>> products(List<String> ids) async => [
    {'id': 'pack', 'title': 'AI credits', 'price': '¥6.00'},
  ];
  @override
  Future<Map<String, Object?>> purchase(String id, String token) async {
    await gate?.future;
    if (status != 'purchased') return {'status': status};
    final transaction = {
      'transaction_id': '123',
      'product_id': id,
      'app_account_token': token,
    };
    queue.add(transaction);
    return {'status': status, 'transaction': transaction};
  }

  @override
  Future<List<Map<String, Object?>>> unfinished() async => [...queue];
  @override
  Future<void> finish(String id) async {
    finished.add(id);
    queue.removeWhere((value) => value['transaction_id'] == id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePurchaseStore store;
  late FakePurchaseApi api;
  late AiPurchaseController controller;
  late int refreshed;
  setUp(() {
    store = FakePurchaseStore();
    api = FakePurchaseApi('account-one');
    refreshed = 0;
    controller = AiPurchaseController(
      store: store,
      onCredited: () async {
        refreshed++;
      },
    );
  });
  tearDown(() => controller.dispose());
  test('finishes only after durable credit and refreshes balance', () async {
    await controller.configure(api);
    api.gate = Completer<void>();
    final purchase = controller.buy(controller.products.single);
    await Future<void>.delayed(Duration.zero);
    expect(store.finished, isEmpty);
    expect(controller.buying, isTrue);
    api.gate!.complete();
    await purchase;
    expect(api.credits, 1000);
    expect(store.finished, ['123']);
    expect(refreshed, 1);
    expect(controller.message, 'purchase_success');
  });
  test(
    'offline delivery remains unfinished and can recover without another purchase',
    () async {
      await controller.configure(api);
      api.fail = true;
      await controller.buy(controller.products.single);
      expect(store.finished, isEmpty);
      expect(store.queue, hasLength(1));
      expect(api.credits, 0);
      api.fail = false;
      await controller.recover();
      await controller.recover();
      expect(api.credits, 1000);
      expect(store.finished, ['123']);
      expect(refreshed, 1);
    },
  );
  test(
    'cancellation and pending approval never grant or finish credit',
    () async {
      await controller.configure(api);
      for (final status in ['cancelled', 'pending']) {
        store.status = status;
        await controller.buy(controller.products.single);
        expect(controller.message, 'purchase_$status');
      }
      expect(api.calls, 0);
      expect(store.finished, isEmpty);
    },
  );
  test(
    'account change during payment preserves transaction for original account',
    () async {
      await controller.configure(api);
      store.gate = Completer<void>();
      final payment = controller.buy(controller.products.single);
      final other = FakePurchaseApi('account-two');
      await controller.configure(other);
      store.gate!.complete();
      await payment;
      await controller.recover();
      expect(api.credits, 0);
      expect(other.credits, 0);
      expect(store.finished, isEmpty);
      await controller.configure(api);
      expect(api.credits, 1000);
      expect(other.calls, 0);
      expect(store.finished, ['123']);
    },
  );
  test('duplicate StoreKit update shares in-flight delivery', () async {
    await controller.configure(api);
    api.gate = Completer<void>();
    final purchase = controller.buy(controller.products.single);
    await Future<void>.delayed(Duration.zero);
    final recovery = controller.recover();
    await Future<void>.delayed(Duration.zero);
    expect(api.calls, 1);
    api.gate!.complete();
    await Future.wait([purchase, recovery]);
    expect(api.credits, 1000);
    expect(store.finished, ['123']);
  });
  test(
    'cold start recovers unfinished transaction for matching account only',
    () async {
      store.queue = [
        {'transaction_id': 'old', 'app_account_token': 'account-one'},
        {'transaction_id': 'other', 'app_account_token': 'account-two'},
      ];
      await controller.configure(api);
      expect(store.finished, ['old']);
      expect(store.queue.single['transaction_id'], 'other');
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'purchase page ${brightness.name} shows localized store price and delivery result',
      (tester) async {
        await controller.configure(api);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpApp(
          AiPurchasePage(controller: controller),
          brightness: brightness,
          platform: TargetPlatform.iOS,
        );
        await tester.pumpAndSettle();
        expect(find.text('1000 points'), findsOneWidget);
        expect(find.text('Buy · ¥6.00'), findsOneWidget);
        await tester.tap(find.text('Buy · ¥6.00'));
        await tester.pumpAndSettle();
        expect(find.text('Credits added to your account.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
