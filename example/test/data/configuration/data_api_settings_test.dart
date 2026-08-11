import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/shell/defaults_appearance_dialog.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('remote selection requires ephemeral login credentials', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildIanvsTerminalTheme(Brightness.dark),
        home: const Scaffold(
          body: DefaultsAndAppearanceDialog(
            profiles: [],
            configuredDefaultProfileId: null,
            effectiveDefaultProfileId: null,
            themeMode: TerminalThemeMode.system,
            terminalViewportPadding:
                TerminalAppAppearance.defaultTerminalViewportPadding,
            restoreLayout: false,
            osc52Policy: LocalTerminalOsc52Policy.ask,
            openUrlPolicy: LocalTerminalOpenUrlPolicy.ask,
            requestAttentionPolicy:
                LocalTerminalRequestAttentionPolicy.disabled,
            reportVariableDecisions: {},
            dataApiConfiguration: DataApiConfiguration.disabled(),
            localDataApiAvailable: true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const Key('defaults-data-api-panel')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('data-api-local')), findsOneWidget);
    await tester.tap(find.byKey(const Key('data-api-remote')));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('data-api-remote-url')),
      'https://user:secret@example.com?unsafe=true',
    );
    await tester.pump();
    expect(find.textContaining('without credentials'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('defaults-save')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('data-api-remote-url')),
      'http://api.example.com/v1',
    );
    await tester.pump();
    expect(find.textContaining('requires HTTPS'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('data-api-remote-url')),
      'https://api.example.com/v1',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('defaults-save')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('data-api-remote-username')),
      'alice',
    );
    await tester.enterText(
      find.byKey(const Key('data-api-remote-password')),
      'correct horse battery staple',
    );
    await tester.enterText(
      find.byKey(const Key('data-api-remote-encryption-key')),
      'encryption-key-material',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('defaults-save')))
          .onPressed,
      isNotNull,
    );
    expect(find.textContaining('takes effect after restart'), findsOneWidget);
  });

  testWidgets('configured remote can explicitly reconnect with the same URL', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildIanvsTerminalTheme(Brightness.dark),
        home: Scaffold(
          body: DefaultsAndAppearanceDialog(
            profiles: const [],
            configuredDefaultProfileId: null,
            effectiveDefaultProfileId: null,
            themeMode: TerminalThemeMode.system,
            terminalViewportPadding:
                TerminalAppAppearance.defaultTerminalViewportPadding,
            restoreLayout: false,
            osc52Policy: LocalTerminalOsc52Policy.ask,
            openUrlPolicy: LocalTerminalOpenUrlPolicy.ask,
            requestAttentionPolicy:
                LocalTerminalRequestAttentionPolicy.disabled,
            reportVariableDecisions: const {},
            dataApiConfiguration: DataApiConfiguration.remote(
              'https://api.example.com/',
            ),
            localDataApiAvailable: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('defaults-data-api-panel')),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.byKey(const Key('data-api-remote-reconnect')));
    await tester.pump();
    expect(
      find.textContaining("Enter this account's existing key"),
      findsOneWidget,
    );
    expect(find.textContaining('lost key cannot be recovered'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('defaults-save')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('data-api-remote-username')),
      'alice',
    );
    await tester.enterText(
      find.byKey(const Key('data-api-remote-password')),
      'new-password',
    );
    await tester.enterText(
      find.byKey(const Key('data-api-remote-encryption-key')),
      'encryption-key-material',
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('defaults-save')))
          .onPressed,
      isNotNull,
    );
  });
}
