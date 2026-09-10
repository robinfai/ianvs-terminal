import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/shell/defaults_appearance_dialog.dart';
import 'package:app/ui/components/app_configuration_field.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:app/ui/foundation/app_theme_tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpIosDefaultsDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildIanvsTerminalTheme(
        Brightness.dark,
        platform: TargetPlatform.iOS,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const DefaultsAndAppearanceDialog(
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
                ),
              ),
              child: const Text('Open defaults'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open defaults'));
  await tester.pumpAndSettle();
}

Future<void> _selectDataSectionWhenTabbed(WidgetTester tester) async {
  final dataSection = find.byKey(const Key('defaults-section-data'));
  if (dataSection.evaluate().isEmpty) {
    return;
  }
  await tester.tap(dataSection);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'defaults keeps focused content above the portrait iPhone keyboard',
    (tester) async {
      const surfaceSize = Size(430, 932);
      const keyboardHeight = 337.0;
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.view.reset);

      await _pumpIosDefaultsDialog(tester);

      final filter = find.byKey(const Key('defaults-terminal-preset-filter'));
      await tester.ensureVisible(filter);
      await tester.tap(filter);
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboardHeight * tester.view.devicePixelRatio,
      );
      await tester.pumpAndSettle();

      final keyboardTop = surfaceSize.height - keyboardHeight;
      expect(tester.getRect(filter).bottom, lessThanOrEqualTo(keyboardTop));
      expect(find.byKey(const Key('defaults-save')), findsNothing);
      final bodyScroll = tester.widget<SingleChildScrollView>(
        find
            .descendant(
              of: find.byKey(const Key('defaults-dialog')),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
      );
      expect(
        bodyScroll.keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'defaults retains usable body space above a landscape iPhone keyboard',
    (tester) async {
      const surfaceSize = Size(844, 390);
      const keyboardHeight = 216.0;
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.view.reset);

      await _pumpIosDefaultsDialog(tester);

      final filter = find.byKey(const Key('defaults-terminal-preset-filter'));
      await tester.ensureVisible(filter);
      await tester.tap(filter);
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboardHeight * tester.view.devicePixelRatio,
      );
      await tester.pumpAndSettle();

      final keyboardTop = surfaceSize.height - keyboardHeight;
      expect(find.text('Defaults & appearance'), findsOneWidget);
      expect(tester.getRect(filter).bottom, lessThanOrEqualTo(keyboardTop));
      expect(find.byKey(const Key('defaults-save')), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'defaults remote login uses readable errors and mobile keyboard progression',
    (tester) async {
      const surfaceSize = Size(844, 390);
      const keyboardHeight = 216.0;
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.view.reset);

      await _pumpIosDefaultsDialog(tester);
      await _selectDataSectionWhenTabbed(tester);
      final remote = find.byKey(const Key('data-api-remote'));
      await tester.scrollUntilVisible(
        remote,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(remote);
      await tester.pumpAndSettle();

      final url = find.byKey(const Key('data-api-remote-url'));
      final username = find.byKey(const Key('data-api-remote-username'));
      final password = find.byKey(const Key('data-api-remote-password'));
      final urlField = tester.widget<TextField>(url);
      final usernameField = tester.widget<TextField>(username);
      final passwordField = tester.widget<TextField>(password);
      expect(urlField.textInputAction, TextInputAction.next);
      expect(usernameField.textInputAction, TextInputAction.next);
      expect(passwordField.textInputAction, TextInputAction.done);
      expect(passwordField.onSubmitted, isNotNull);
      for (final field in [urlField, usernameField, passwordField]) {
        expect(field.decoration?.labelText, isNull);
      }
      for (final finder in [url, username, password]) {
        expect(
          find.ancestor(
            of: finder,
            matching: find.byType(AppConfigurationField),
          ),
          findsOneWidget,
        );
      }
      expect(urlField.decoration?.errorMaxLines, 2);
      expect(usernameField.decoration?.errorMaxLines, 2);
      expect(passwordField.decoration?.errorMaxLines, 2);
      expect(urlField.scrollPadding.bottom, greaterThanOrEqualTo(40));
      expect(usernameField.scrollPadding.bottom, greaterThanOrEqualTo(40));
      expect(passwordField.scrollPadding.bottom, greaterThanOrEqualTo(40));
      expect(
        find.text('Use 3–64 lowercase letters, numbers, . _ or -.'),
        findsNothing,
      );
      expect(find.text('Use 12–72 UTF-8 bytes.'), findsNothing);

      await tester.enterText(username, 'a');
      await tester.enterText(password, 'a');
      await tester.pump();
      expect(
        find.text('Use 3–64 lowercase letters, numbers, . _ or -.'),
        findsOneWidget,
      );
      expect(find.text('Use 12–72 UTF-8 bytes.'), findsOneWidget);

      await tester.ensureVisible(username);
      await tester.tap(username);
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboardHeight * tester.view.devicePixelRatio,
      );
      await tester.pumpAndSettle();

      final keyboardTop = surfaceSize.height - keyboardHeight;
      expect(tester.getRect(username).bottom, lessThanOrEqualTo(keyboardTop));
      expect(find.text('Defaults & appearance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('iOS disabled mode keeps local data without API sync', (
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
            localDataApiAvailable: false,
            localSessionsEnabled: false,
          ),
        ),
      ),
    );
    await tester.pump();
    await _selectDataSectionWhenTabbed(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('defaults-data-api-panel')),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Active mode: No data service'), findsOneWidget);
    expect(find.text('No data service'), findsOneWidget);
    expect(find.text('Keep using local data without API sync.'), findsWidgets);
    expect(find.byKey(const Key('data-api-local')), findsNothing);
  });

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
    await _selectDataSectionWhenTabbed(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('defaults-data-api-panel')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('data-api-local')), findsOneWidget);
    await tester.tap(find.byKey(const Key('data-api-remote')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('data-api-remote-url')))
          .controller
          ?.text,
      defaultRemoteDataApiBaseUrl,
    );

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
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('defaults-save')))
          .onPressed,
      isNotNull,
    );
    expect(find.text('Sync with the API after sign-in'), findsOneWidget);
  });

  testWidgets('configured loopback remote is presented as a mode', (
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
              'http://127.0.0.1:8787/',
            ),
            localDataApiAvailable: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await _selectDataSectionWhenTabbed(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('defaults-data-api-panel')),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Active mode: Remote service'), findsOneWidget);
    expect(
      find.text(
        'Keep local data available and sync supported changes with the '
        'configured API.',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('data-api-active-deployment')),
        matching: find.text('Running'),
      ),
      findsNothing,
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('data-api-active-deployment')))
          .label,
      contains('Active data mode: Remote service'),
    );

    final localSurface = find.byKey(const Key('data-api-local-surface'));
    final initialSurface = tester.widget<AnimatedContainer>(localSurface);
    final initialDecoration = initialSurface.decoration! as BoxDecoration;
    expect(initialDecoration.color, Colors.transparent);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(tester.getCenter(localSurface));
    await tester.pumpAndSettle();

    final hoveredSurface = tester.widget<AnimatedContainer>(localSurface);
    final hoveredDecoration = hoveredSurface.decoration! as BoxDecoration;
    expect(hoveredDecoration.color, isNot(Colors.transparent));
    expect(
      (hoveredDecoration.border! as Border).top.color,
      Theme.of(
        tester.element(localSurface),
      ).extension<AppThemeTokens>()!.borderStrong,
    );
    await pointer.removePointer();
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('data-api-remote-reconnect')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('data-api-remote-reconnect')));
    await tester.pump();
    expect(find.textContaining('one Ianvs master key'), findsOneWidget);
    expect(
      find.byKey(const Key('data-api-remote-encryption-key')),
      findsNothing,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('defaults-save')))
          .onPressed,
      isNull,
    );
    final expectedFieldSize = Theme.of(
      tester.element(find.byKey(const Key('data-api-remote-url'))),
    ).textTheme.bodyMedium?.fontSize;
    for (final key in <Key>[
      const Key('data-api-remote-url'),
      const Key('data-api-remote-username'),
      const Key('data-api-remote-password'),
    ]) {
      final field = tester.widget<TextField>(find.byKey(key));
      expect(field.style?.fontSize, expectedFieldSize);
      expect(field.decoration?.constraints?.minHeight, 28);
    }
    await tester.enterText(
      find.byKey(const Key('data-api-remote-username')),
      'alice',
    );
    await tester.enterText(
      find.byKey(const Key('data-api-remote-password')),
      'new-password',
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('defaults-save')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('enabling remote sync from local does not require migration', (
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
            dataApiConfiguration: DataApiConfiguration.local(),
            localDataApiAvailable: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await _selectDataSectionWhenTabbed(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('defaults-data-api-panel')),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.byKey(const Key('data-api-remote')));
    await tester.pump();

    expect(
      find.byKey(const Key('data-api-local-to-remote-migration')),
      findsNothing,
    );
    expect(find.text('Save changes'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('data-api-remote-url')),
      'https://sync.example.com/',
    );
    await tester.pump();

    expect(
      find.byKey(const Key('data-api-local-to-remote-migration')),
      findsNothing,
    );
    expect(find.text('Save changes'), findsOneWidget);
  });

  testWidgets('active local runtime allows remote sync without migration', (
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
            activeDataApiDeployment: DataApiDeployment.local,
            localDataApiAvailable: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await _selectDataSectionWhenTabbed(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('defaults-data-api-panel')),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.byKey(const Key('data-api-remote')));
    await tester.pump();

    expect(
      find.byKey(const Key('data-api-local-to-remote-migration')),
      findsNothing,
    );
    expect(find.text('Save changes'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('data-api-remote-url')),
      'https://sync.example.com/',
    );
    await tester.pump();

    expect(
      find.byKey(const Key('data-api-local-to-remote-migration')),
      findsNothing,
    );
    expect(find.text('Save changes'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const Key('data-api-active-deployment')))
          .label,
      contains('Active data mode: Bundled local service'),
    );
  });

  testWidgets('disabling remote sync does not require reverse migration', (
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
              'https://sync.example.com/',
            ),
            localDataApiAvailable: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await _selectDataSectionWhenTabbed(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('defaults-data-api-panel')),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.byKey(const Key('data-api-local')));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('data-api-remote')),
        matching: find.text('Current mode'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('data-api-remote')),
        matching: find.text('Running'),
      ),
      findsNothing,
    );

    expect(
      find.byKey(const Key('data-api-remote-to-local-migration')),
      findsNothing,
    );
    expect(find.text('Save changes'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('defaults-save')))
          .onPressed,
      isNotNull,
    );
  });
}
