import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_usage.dart';
import 'package:app/features/ai/ai_usage_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

Map<String, Object?> usageJson({int remaining = 0, int reserved = 2000}) => {
  'daily_budget_nano_usd': 1000000000,
  'remaining_nano_usd': remaining,
  'usage': {
    'spent_nano_usd': 1000,
    'reserved_nano_usd': reserved,
    'input_tokens': 12,
    'cached_input_tokens': 4,
    'output_tokens': 2,
    'pending_requests': 1,
  },
  'reset_at': '2026-11-02T00:00:00Z',
};
AiUsageRecord record(String id, String status) => AiUsageRecord.fromJson({
  'id': id,
  'model': 'deepseek',
  'provider': 'deepseek',
  'status': status,
  'created_at': '2026-11-01T00:00:00Z',
  'reserved_nano_usd': 2000,
  'usage': {
    'spent_nano_usd': status == 'settled' ? 1000 : 0,
    'input_tokens': 12,
    'cached_input_tokens': 4,
    'output_tokens': 2,
  },
  'pricing_snapshot': {'version': 'test-v1'},
});

class _RealHttpOverrides extends HttpOverrides {}

class FakeUsageApi implements AiUsageApi {
  bool fail = false;
  int calls = 0;
  @override
  Future<AiUsageSnapshot> usage() async {
    if (fail) throw const AiFailure('usage_connection');
    return AiUsageSnapshot.fromJson(usageJson());
  }

  @override
  Future<AiUsagePageData> requests({String? before}) async {
    calls++;
    return before == null
        ? AiUsagePageData([record('one', 'pending')], 'cursor')
        : AiUsagePageData([record('two', 'settled')], '');
  }
}

void main() {
  test('quota points preserve small cached token charges', () {
    expect(aiQuotaPoints(1), '0.0005');
    expect(aiQuotaPoints(2000), '1');
    expect(aiQuotaPoints(7800), '3.9');
  });
  test(
    'HTTP usage uses backend path/auth and does not follow redirects',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var redirect = false;
      server.listen((request) async {
        expect(request.uri.path, '/v1/ai/usage');
        expect(request.headers.value('authorization'), 'Bearer session-token');
        if (redirect) {
          request.response.statusCode = 302;
          request.response.headers.set('location', '/unexpected');
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(usageJson(remaining: 5000)));
        }
        await request.response.close();
      });
      final client = AiUsageClient(
        AiConfiguration(
          endpoint: 'http://127.0.0.1:${server.port}/v1/ai',
          apiKey: 'session-token',
          model: 'default',
        ),
      );
      expect((await client.usage()).remaining, 5000);
      redirect = true;
      await expectLater(client.usage(), throwsA(isA<AiFailure>()));
    }, _RealHttpOverrides()),
  );
  test(
    'refresh and pagination retain pending records and mark stale data',
    () async {
      final api = FakeUsageApi();
      final controller = AiUsageController(api);
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.loadRecords();
      await controller.loadRecords(more: true);
      expect(controller.records.map((e) => e.status), ['pending', 'settled']);
      expect(controller.nextCursor, isEmpty);
      api.fail = true;
      await controller.refresh();
      expect(controller.snapshot, isNotNull);
      expect(controller.error, 'usage_connection');
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'quota page at 390px $brightness explains exhausted and pending amounts',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() => tester.view.resetPhysicalSize());
        final api = FakeUsageApi();
        final controller = AiUsageController(api);
        addTearDown(controller.dispose);
        if (Platform.environment['IANVS_USAGE_CAPTURE'] == '1') {
          await tester.runAsync(() async {
            final bytes = await File(
              '/System/Library/Fonts/Supplemental/Arial.ttf',
            ).readAsBytes();
            await (FontLoader(
              'UsagePreview',
            )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
          });
        }
        await tester.pumpApp(
          AiUsagePage(controller: controller),
          brightness: brightness,
          platform: TargetPlatform.iOS,
          fontFamily: Platform.environment['IANVS_USAGE_CAPTURE'] == '1'
              ? 'UsagePreview'
              : null,
          wrapper: (child) =>
              RepaintBoundary(key: const Key('usage-capture'), child: child),
        );
        await tester.pumpAndSettle();
        if (Platform.environment['IANVS_USAGE_CAPTURE'] == '1') {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('usage-capture')),
            );
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '/tmp/ianvs-usage-${brightness.name}.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(find.text('0 points remaining'), findsOneWidget);
        expect(find.textContaining('No credits available.'), findsOneWidget);
        expect(find.textContaining('Reserved 1 points'), findsWidgets);
        await tester.scrollUntilVisible(find.text('Load more'), 250);
        await tester.tap(find.text('Load more'));
        await tester.pumpAndSettle();
        expect(controller.records.length, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
