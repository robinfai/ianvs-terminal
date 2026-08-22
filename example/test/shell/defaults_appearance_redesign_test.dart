import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/shell/defaults_appearance_dialog.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wide defaults dialog navigates to compact permission controls', (
    tester,
  ) async {
    await _pumpDefaultsDialog(tester, surfaceSize: const Size(1200, 900));

    for (final key in <Key>[
      const Key('defaults-section-general'),
      const Key('defaults-section-appearance'),
      const Key('defaults-section-shortcuts'),
      const Key('defaults-section-security'),
      const Key('defaults-section-data'),
    ]) {
      expect(find.byKey(key), findsOneWidget);
    }
    expect(
      find.byKey(const Key('defaults-current-profile-summary')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('defaults-terminal-permissions-panel')),
      findsNothing,
    );
    expect(find.byKey(const Key('shortcut-editor-list')), findsNothing);
    expect(find.byKey(const Key('defaults-language-options')), findsOneWidget);

    await tester.tap(find.byKey(const Key('default-language-option-english')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('defaults-save')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('defaults-section-security')));
    await tester.pumpAndSettle();

    expect(find.text('Security & permissions'), findsNWidgets(2));
    expect(
      find.byKey(const Key('defaults-terminal-permissions-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('defaults-current-profile-summary')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('defaults-terminal-preset-filter')),
      findsNothing,
    );
    expect(find.byKey(const Key('defaults-language-options')), findsNothing);
    expect(
      find.byKey(const Key('defaults-osc52-policy-dropdown')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('defaults-open-url-policy-dropdown')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('defaults-request-attention-policy-dropdown')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Require confirmation for each accepted request from the active terminal.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('defaults-osc52-policy-dropdown')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Allow trusted terminal sessions to use OSC 52 without prompting.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('defaults-save')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('defaults-manage-report-variables')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('defaults-report-variable-management')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide defaults dialog renders shortcuts as a persistent tab', (
    tester,
  ) async {
    await _pumpDefaultsDialog(tester, surfaceSize: const Size(800, 700));

    await tester.tap(find.byKey(const Key('defaults-section-shortcuts')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('defaults-shortcuts-tab-panel')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shortcut-editor-filter')), findsOneWidget);
    expect(find.byKey(const Key('shortcut-editor-list')), findsOneWidget);
    expect(find.byKey(const Key('defaults-shortcuts-entry')), findsNothing);
    expect(find.byKey(const Key('defaults-shortcuts-back')), findsNothing);
    expect(find.byKey(const Key('defaults-shortcuts-done')), findsNothing);
    expect(find.byKey(const Key('defaults-save')), findsOneWidget);
    expect(
      find.byKey(const Key('defaults-terminal-permissions-panel')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('defaults-section-appearance')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('defaults-terminal-preset-filter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('defaults-canvas-inset-panel')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shortcut-editor-list')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('language selection is returned when defaults are saved', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    DefaultsAndAppearanceSelection? selection;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildIanvsTerminalTheme(
          Brightness.light,
          platform: TargetPlatform.macOS,
        ),
        home: Builder(
          builder: (context) => TextButton(
            key: const Key('open-defaults'),
            onPressed: () async {
              selection = await showDialog<DefaultsAndAppearanceSelection>(
                context: context,
                builder: (_) => const DefaultsAndAppearanceDialog(
                  profiles: [],
                  configuredDefaultProfileId: null,
                  effectiveDefaultProfileId: null,
                  themeMode: TerminalThemeMode.system,
                  terminalViewportPadding:
                      TerminalAppAppearance.defaultTerminalViewportPadding,
                  restoreLayout: false,
                  osc52Policy: LocalTerminalOsc52Policy.profile,
                  openUrlPolicy: LocalTerminalOpenUrlPolicy.ask,
                  requestAttentionPolicy:
                      LocalTerminalRequestAttentionPolicy.disabled,
                  reportVariableDecisions: {},
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-defaults')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('default-language-option-english')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('defaults-save')));
    await tester.pumpAndSettle();

    expect(selection?.languageMode, TerminalLanguageMode.english);
  });

  testWidgets('compact defaults dialog keeps the touch-friendly radio layout', (
    tester,
  ) async {
    await _pumpDefaultsDialog(tester, surfaceSize: const Size(390, 844));

    expect(find.byKey(const Key('defaults-section-general')), findsNothing);
    expect(find.byKey(const Key('defaults-osc52-options')), findsOneWidget);
    expect(
      find.byKey(const Key('default-osc52-policy-profile')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('defaults-terminal-permissions-panel')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDefaultsDialog(
  WidgetTester tester, {
  required Size surfaceSize,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = surfaceSize;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildIanvsTerminalTheme(
        Brightness.light,
        platform: TargetPlatform.macOS,
      ),
      home: const Scaffold(
        body: DefaultsAndAppearanceDialog(
          profiles: [],
          configuredDefaultProfileId: null,
          effectiveDefaultProfileId: null,
          themeMode: TerminalThemeMode.system,
          terminalViewportPadding:
              TerminalAppAppearance.defaultTerminalViewportPadding,
          restoreLayout: false,
          osc52Policy: LocalTerminalOsc52Policy.profile,
          openUrlPolicy: LocalTerminalOpenUrlPolicy.ask,
          requestAttentionPolicy: LocalTerminalRequestAttentionPolicy.disabled,
          reportVariableDecisions: {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
