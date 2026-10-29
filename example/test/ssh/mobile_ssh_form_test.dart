import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/ssh/new_session_launcher.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [
    const Size(375, 667),
    const Size(402, 874),
    const Size(874, 402),
  ]) {
    testWidgets('mobile SSH connects with fixed-size core fields at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.padding = FakeViewPadding(
        top: size.height > size.width ? 62 : 0,
        bottom: size.height > size.width ? 34 : 21,
      );
      addTearDown(tester.view.reset);
      SshProfileEditorResult? result;
      await _open(tester, onClosed: (value) => result = value);
      expect(find.byKey(const Key('ssh-profile-name')), findsNothing);
      expect(find.byKey(const Key('ssh-port')), findsNothing);
      expect(find.byKey(const Key('ssh-private-keys')), findsNothing);
      expect(find.byKey(const Key('ssh-clear-password')), findsNothing);
      expect(tester.takeException(), isNull);
      for (final entry in {
        'ssh-host': 'review.example.test',
        'ssh-user': 'reviewer',
        'ssh-password': 'demo-password',
      }.entries) {
        await tester.ensureVisible(find.byKey(Key(entry.key)));
        await tester.enterText(find.byKey(Key(entry.key)), entry.value);
      }
      // The new full-page form must also scroll above a software keyboard.
      tester.view.viewInsets = FakeViewPadding(
        bottom: size.height > size.width ? 300 : 180,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
      await tester.pumpAndSettle();
      final button = tester.getRect(find.byKey(const Key('ssh-connect')));
      expect(button.height, greaterThanOrEqualTo(44));
      expect(
        button.bottom,
        lessThanOrEqualTo(size.height - tester.view.viewInsets.bottom),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('ssh-connect')));
      await tester.pumpAndSettle();
      expect(result?.profile.name, 'review.example.test');
      expect(
        result?.profile.connection.auth,
        terminal.TerminalSshAuthMethod.password,
      );
      expect(result?.profile.connection.password, 'demo-password');
      expect(result?.saveProfile, isTrue);
      expect(result?.clearSecrets, isEmpty);
    });
  }

  testWidgets('empty SSH submission exposes a live error and focuses host', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 874);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    SshProfileEditorResult? result;
    await _open(tester, onClosed: (value) => result = value);
    await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
    await tester.tap(find.byKey(const Key('ssh-connect')));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byKey(const Key('ssh-validation-notice')), findsOneWidget);
    final notice = find
        .ancestor(
          of: find.byKey(const Key('ssh-validation-notice')),
          matching: find.byType(Semantics),
        )
        .first;
    expect(tester.widget<Semantics>(notice).properties.liveRegion, isTrue);
    final host = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('ssh-host')),
        matching: find.byType(EditableText),
      ),
    );
    expect(host.focusNode.hasFocus, isTrue);
    await tester.enterText(find.byKey(const Key('ssh-host')), 'host.example');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssh-validation-notice')), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('more settings preserves names and expands invalid hidden port', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 874);
    addTearDown(tester.view.reset);
    SshProfileEditorResult? result;
    final profile = defaultTerminalProfile().copyWith(
      name: 'Production',
      connection: const terminal.TerminalConnectionConfig.ssh(
        host: 'review.example.test',
        user: 'reviewer',
        auth: terminal.TerminalSshAuthMethod.password,
        password: 'saved-password',
      ),
    );
    await _open(tester, profile: profile, onClosed: (value) => result = value);
    expect(find.byKey(const Key('ssh-profile-name')), findsNothing);
    await tester.tap(find.byKey(const Key('ssh-more-settings-toggle')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('ssh-profile-name')))
          .controller!
          .text,
      'Production',
    );
    await tester.ensureVisible(find.byKey(const Key('ssh-port')));
    await tester.enterText(find.byKey(const Key('ssh-port')), '0');
    await tester.ensureVisible(
      find.byKey(const Key('ssh-more-settings-toggle')),
    );
    await tester.tap(find.byKey(const Key('ssh-more-settings-toggle')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
    await tester.tap(find.byKey(const Key('ssh-connect')));
    await tester.pumpAndSettle();
    expect(result, isNull);
    final port = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('ssh-port')),
        matching: find.byType(EditableText),
      ),
    );
    expect(port.focusNode.hasFocus, isTrue);
    await tester.enterText(find.byKey(const Key('ssh-port')), '2222');
    await tester.ensureVisible(
      find.byKey(const Key('ssh-more-settings-toggle')),
    );
    await tester.tap(find.byKey(const Key('ssh-more-settings-toggle')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ssh-connect')));
    await tester.tap(find.byKey(const Key('ssh-connect')));
    await tester.pumpAndSettle();
    expect(result?.profile.name, 'Production');
    expect(result?.profile.connection.port, 2222);
    expect(result?.profile.connection.password, 'saved-password');
    expect(result?.clearSecrets, isEmpty);
  });
}

Future<void> _open(
  WidgetTester tester, {
  double scale = 1,
  TerminalProfile? profile,
  required ValueChanged<SshProfileEditorResult?> onClosed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildIanvsTerminalTheme(
        scale == 2 ? Brightness.dark : Brightness.light,
        platform: TargetPlatform.iOS,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => onClosed(
              profile == null
                  ? await showCreateSshProfileDialog(context)
                  : await showDialog<SshProfileEditorResult>(
                      context: context,
                      useSafeArea: false,
                      builder: (_) =>
                          SshProfileEditorDialog(initialValue: profile),
                    ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
