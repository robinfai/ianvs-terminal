import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/configuration/oauth_sign_in_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Accounts implements DataApiOAuthAccountManager {
  _Accounts(this.providers, {this.fail = false});
  final List<String> providers;
  bool fail;
  @override
  Future<List<String>> linkedOAuthProviders() async {
    if (fail) {
      fail = false;
      throw StateError('network');
    }
    return providers;
  }

  @override
  Future<void> linkOAuthIdentity(Map<String, Object?> proof) async {}
}

void main() {
  Future<void> show(WidgetTester tester, _Accounts accounts) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OAuthSignInPanel(
            baseUri: Uri.parse('https://example.com'),
            accountManager: accounts,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('only the unlinked provider offers a link action', (
    tester,
  ) async {
    await show(tester, _Accounts(['apple']));
    expect(find.text('Apple · Linked'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Link Google'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Link Apple'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets('both linked providers show status without link buttons', (
    tester,
  ) async {
    await show(tester, _Accounts(['apple', 'google']));
    expect(find.text('Google · Linked'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
  });
  testWidgets('failed status load can retry without exposing link actions', (
    tester,
  ) async {
    await show(tester, _Accounts(['google'], fail: true));
    expect(find.byType(OutlinedButton), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Google · Linked'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Link Apple'), findsOneWidget);
  });
}
