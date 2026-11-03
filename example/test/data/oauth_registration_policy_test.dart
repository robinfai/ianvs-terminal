import 'dart:convert';
import 'dart:io';
import 'package:app/data/configuration/oauth_sign_in_panel.dart';
import 'package:app/data/services/data_api_device_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class _NetworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _NetworkBinding();
  late Directory installationDirectory;
  setUpAll(() async {
    installationDirectory = await Directory.systemTemp.createTemp(
      'oauth-installation-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => installationDirectory.path,
        );
    // The process-wide identity future must live outside any individual
    // widget test's FakeAsync zone.
    await dataApiDeviceIdentity(Uri.parse('http://127.0.0.1'));
  });
  tearDownAll(() => installationDirectory.delete(recursive: true));
  for (final brightness in Brightness.values) {
    for (final registration in [true, false]) {
      testWidgets(
        'OAuth create policy: $registration $brightness',
        (tester) async {
          final directory = (await tester.runAsync(
            () => Directory.systemTemp.createTemp('oauth-choice-'),
          ))!;
          final server = (await tester.runAsync(
            () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
          ))!;
          final actions = <String>[];
          final pathsSeen = <String>[];
          var authenticated = false;
          final nonce = base64Url
              .encode(List.filled(32, 7))
              .replaceAll('=', '');
          server.listen((request) async {
            pathsSeen.add(request.uri.path);
            final data = await utf8.decoder.bind(request).join();
            Object body;
            switch (request.uri.path) {
              case '/healthz':
                body = {
                  'allow_registration': registration,
                  'password_auth_enabled': false,
                };
              case '/v1/auth/oauth/challenge':
                body = {'nonce': nonce};
              case '/v1/auth/oauth/begin':
                final action = (jsonDecode(data) as Map)['action'] as String;
                actions.add(action);
                if (action.isEmpty) {
                  request.response.statusCode = 409;
                  body = {
                    'error': {
                      'code': 'oauth_account_choice_required',
                      'message': 'Choose',
                    },
                  };
                } else {
                  body = {
                    'operation_id': nonce,
                    'kind': 'login',
                    'expires_at': DateTime.now()
                        .add(const Duration(minutes: 5))
                        .toUtc()
                        .toIso8601String(),
                  };
                }
              default:
                request.response.statusCode = 404;
                body = {};
            }
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode(body));
            await request.response.close();
          });
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          const apple = MethodChannel(
            'com.aboutyou.dart_packages.sign_in_with_apple',
          );
          const paths = MethodChannel('plugins.flutter.io/path_provider');
          messenger.setMockMethodCallHandler(
            apple,
            (_) async => {
              'type': 'appleid',
              'identityToken': 'fixture',
              'authorizationCode': 'fixture',
            },
          );
          messenger.setMockMethodCallHandler(
            paths,
            (_) async => directory.path,
          );
          addTearDown(() async {
            messenger.setMockMethodCallHandler(apple, null);
            messenger.setMockMethodCallHandler(paths, null);
            await tester.runAsync(() async {
              await server.close(force: true);
              await directory.delete(recursive: true);
            });
          });
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: OAuthSignInPanel(
                  baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
                  onAuthenticated: (_) async {
                    authenticated = true;
                  },
                ),
              ),
            ),
          );
          await tester.tap(find.byType(SignInWithAppleButton));
          await tester.pump();
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          Future<void> waitFor(bool Function() ready) async {
            for (var i = 0; i < 200 && !ready(); i++) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
              await tester.pump(const Duration(milliseconds: 10));
            }
            expect(
              ready(),
              isTrue,
              reason:
                  'paths=$pathsSeen; actions=$actions; text=${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).join(" | ")}',
            );
          }

          await waitFor(
            () =>
                find.text('First sign-in').evaluate().isNotEmpty &&
                find.byType(LinearProgressIndicator).evaluate().isEmpty,
          );
          expect(actions, ['']);
          expect(
            find.widgetWithText(OutlinedButton, 'Link an existing account'),
            findsOneWidget,
          );
          if (registration) {
            expect(
              find.widgetWithText(FilledButton, 'Create a new account'),
              findsOneWidget,
            );
            expect(
              tester.getTopLeft(find.text('Create a new account')).dy,
              lessThan(
                tester.getTopLeft(find.text('Link an existing account')).dy,
              ),
            );
            await tester.tap(find.text('Create a new account'));
            await waitFor(() => authenticated);
            expect(actions, ['', 'create']);
          } else {
            expect(find.text('Create a new account'), findsNothing);
            expect(
              find.textContaining('not accepting new accounts'),
              findsOneWidget,
            );
            await tester.tap(find.text('Link an existing account'));
            await tester.pumpAndSettle();
            expect(
              find.text('Link with username and password'),
              findsOneWidget,
            );
            expect(actions, ['']);
          }
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );
    }
  }
}
