import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/shell/defaults_appearance_dialog.dart';
import 'package:app/ui/components/app_dropdown_form_field.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

void main() {
  testWidgets('global SSH switches save independently', (tester) async {
    final profile = defaultTerminalProfile();
    DefaultsAndAppearanceSelection? selection;
    await _pumpDefaultsDialogLauncher(
      tester,
      profiles: [profile],
      configuredDefaultProfileId: profile.id,
      effectiveDefaultProfileId: profile.id,
      onSelection: (value) => selection = value,
    );
    final wrapper = find.byKey(const Key('defaults-ssh-wrapper'));
    final injection = find.byKey(const Key('defaults-ssh-auto-inject'));
    await tester.ensureVisible(wrapper);
    await tester.tap(wrapper);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(injection).value, isTrue);
    await tester.tap(find.byKey(const Key('defaults-save')));
    await tester.pumpAndSettle();
    expect(selection?.sshWrapper, isFalse);
    expect(selection?.sshAutoInject, isTrue);
  });
  testWidgets('shortcut empty results keep the list width', (tester) async {
    await _pumpDefaultsDialog(tester, surfaceSize: const Size(1200, 900));
    await tester.tap(find.byKey(const Key('defaults-section-shortcuts')));
    await tester.pumpAndSettle();
    final list = find.byKey(const Key('shortcut-editor-list-panel'));
    final width = tester.getSize(list).width;
    await tester.enterText(
      find.byKey(const Key('shortcut-editor-filter')),
      'no-match-acceptance',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching actions'), findsOneWidget);
    expect(tester.getSize(list).width, width);
    expect(tester.takeException(), isNull);
  });

  testWidgets('change status clears when a selection is reverted', (
    tester,
  ) async {
    await _pumpDefaultsDialog(tester, surfaceSize: const Size(1200, 900));
    expect(find.text('No changes'), findsOneWidget);
    await tester.tap(find.byKey(const Key('defaults-language-options')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('default-language-option-english')).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.byKey(const Key('defaults-section-appearance')));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.byKey(const Key('defaults-section-general')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('defaults-language-options')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('default-language-option-system')).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('No changes'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('defaults-save')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('reset menu stages a profile reset and cancel discards it', (
    tester,
  ) async {
    final profile = defaultTerminalProfile();
    DefaultsAndAppearanceSelection? selection;
    await _pumpDefaultsDialogLauncher(
      tester,
      profiles: [profile],
      configuredDefaultProfileId: profile.id,
      effectiveDefaultProfileId: profile.id,
      onSelection: (value) => selection = value,
    );
    await tester.tap(find.byKey(const Key('defaults-reset-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset default'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.byKey(const Key('defaults-cancel')));
    await tester.pumpAndSettle();
    expect(selection, isNull);
    await tester.tap(find.byKey(const Key('open-defaults-profile-test')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppDropdownFormField<String>>(
            find.byKey(const Key('defaults-profile-select')),
          )
          .initialValue,
      profile.id,
    );
    expect(find.text('No changes'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'all desktop sections reflow at 680 px and 2x text in $brightness',
      (tester) async {
        await _pumpDefaultsDialog(
          tester,
          surfaceSize: const Size(680, 620),
          textScale: 2,
          brightness: brightness,
        );
        for (final section in [
          'appearance',
          'shortcuts',
          'security',
          'data',
          'general',
        ]) {
          final navigation = find.byKey(Key('defaults-section-$section'));
          await tester.ensureVisible(navigation);
          await tester.tap(navigation);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: section);
          if (section != 'shortcuts') {
            await tester.drag(
              find.byKey(const Key('defaults-appearance-scroll')),
              const Offset(0, -1500),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$section bottom');
          }
          expect(
            find.byKey(const Key('defaults-save')).hitTestable(),
            findsOneWidget,
          );
        }
      },
    );
  }

  for (final size in [
    const Size(375, 667),
    const Size(402, 874),
    const Size(874, 402),
  ]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets(
        'iPhone settings sections remain reachable at $size and ${scale}x',
        (tester) async {
          await _pumpDefaultsDialog(
            tester,
            surfaceSize: size,
            textScale: scale,
            platform: TargetPlatform.iOS,
            brightness: scale == 2 ? Brightness.dark : Brightness.light,
          );
          expect(
            find.byKey(const Key('defaults-mobile-sections')),
            findsOneWidget,
          );
          for (final section in [
            'general',
            'appearance',
            'security',
            'data',
            'shortcuts',
          ]) {
            final item = find.byKey(Key('defaults-section-$section'));
            final menuScroll = find.descendant(
              of: find.byKey(const Key('defaults-mobile-sections')),
              matching: find.byType(Scrollable),
            );
            await tester.scrollUntilVisible(item, 100, scrollable: menuScroll);
            await tester.pumpAndSettle();
            final viewport = tester.getRect(
              find.byKey(const Key('defaults-mobile-sections')),
            );
            final visibleItem = tester.getRect(item).intersect(viewport);
            expect(visibleItem.height, greaterThan(0));
            await tester.tapAt(visibleItem.center);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const Key('defaults-mobile-sections')),
              findsNothing,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$section at $size and $scale',
            );
            if (section != 'shortcuts') {
              final scroll = find.byKey(
                const Key('defaults-appearance-scroll'),
              );
              await tester.drag(scroll, const Offset(0, -1800));
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: 'scrolled $section',
              );
            }
            await tester.tap(
              find.byKey(
                Key(
                  section == 'shortcuts'
                      ? 'defaults-shortcuts-back'
                      : 'defaults-mobile-back',
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const Key('defaults-mobile-sections')),
              findsOneWidget,
            );
          }
        },
      );
    }
  }

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
      findsNothing,
    );
    expect(
      find.byKey(const Key('defaults-terminal-permissions-panel')),
      findsNothing,
    );
    expect(find.byKey(const Key('shortcut-editor-list')), findsNothing);
    expect(find.byKey(const Key('defaults-language-options')), findsOneWidget);

    await tester.tap(find.byKey(const Key('defaults-language-options')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('default-language-option-english')).last,
    );
    await tester.pumpAndSettle();
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

    await tester.ensureVisible(
      find.byKey(const Key('defaults-manage-report-variables')),
    );
    await tester.pumpAndSettle();
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
    await tester.tap(find.byKey(const Key('defaults-language-options')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('default-language-option-english')).last,
    );
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.tap(find.byKey(const Key('defaults-save')));
    await tester.pumpAndSettle();

    expect(selection?.languageMode, TerminalLanguageMode.english);
  });

  testWidgets('stale configured profile saves automatic fallback', (
    tester,
  ) async {
    final profile = defaultTerminalProfile();
    DefaultsAndAppearanceSelection? selection;
    await _pumpDefaultsDialogLauncher(
      tester,
      profiles: [profile],
      configuredDefaultProfileId: 'deleted-profile',
      effectiveDefaultProfileId: profile.id,
      onSelection: (value) => selection = value,
    );

    expect(
      tester
          .widget<AppDropdownFormField<String>>(
            find.byKey(const Key('defaults-profile-select')),
          )
          .initialValue,
      isNull,
    );
    expect(
      find.text(
        'New tabs use ${profile.name} automatically until you choose a fixed default.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('defaults-save')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('defaults-save')));
    await tester.pumpAndSettle();

    expect(selection?.configuredDefaultProfileId, isNull);
  });

  testWidgets('fixed profile can be changed back to automatic fallback', (
    tester,
  ) async {
    final profile = defaultTerminalProfile();
    DefaultsAndAppearanceSelection? selection;
    await _pumpDefaultsDialogLauncher(
      tester,
      profiles: [profile],
      configuredDefaultProfileId: profile.id,
      effectiveDefaultProfileId: profile.id,
      onSelection: (value) => selection = value,
    );

    await tester.tap(find.byKey(const Key('defaults-profile-select')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('default-profile-option-fallback')).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('defaults-save')));
    await tester.pumpAndSettle();

    expect(selection?.configuredDefaultProfileId, isNull);
  });

  testWidgets('long SSH option fits compact enlarged text', (tester) async {
    final profile = TerminalProfile(
      id: 'long-ssh',
      name:
          'Production bastion with a deliberately long descriptive profile name',
      shell: '/bin/zsh',
      connection: const terminal.TerminalConnectionConfig.ssh(
        host: 'an-extremely-long-bastion-hostname-for-production.example.test',
        user: 'deployment-operator-with-a-long-name',
        port: 2222,
      ),
    );
    await _pumpDefaultsDialog(
      tester,
      surfaceSize: const Size(390, 844),
      textScale: 1.5,
      profiles: [profile],
      effectiveDefaultProfileId: profile.id,
    );

    await tester.tap(find.byKey(const Key('defaults-profile-select')));
    await tester.pumpAndSettle();
    final option = find.byKey(const Key('default-profile-option-long-ssh'));
    expect(option, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(option.last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('small Mac settings stays navigable in $brightness', (
      tester,
    ) async {
      await _pumpDefaultsDialog(
        tester,
        surfaceSize: const Size(680, 520),
        brightness: brightness,
        textScale: 1.5,
      );
      final general = find.byKey(const Key('defaults-section-general'));
      expect(general, findsOneWidget);
      await tester.tap(general);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('defaults-terminal-preset-filter')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('defaults-terminal-preset-filter')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('defaults-section-data')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('defaults-section-data')));
      await tester.pumpAndSettle();
    });
  }

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
  Brightness brightness = Brightness.light,
  double textScale = 1,
  TargetPlatform platform = TargetPlatform.macOS,
  List<TerminalProfile> profiles = const [],
  String? configuredDefaultProfileId,
  String? effectiveDefaultProfileId,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = surfaceSize;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildIanvsTerminalTheme(brightness, platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: DefaultsAndAppearanceDialog(
          profiles: profiles,
          configuredDefaultProfileId: configuredDefaultProfileId,
          effectiveDefaultProfileId: effectiveDefaultProfileId,
          themeMode: TerminalThemeMode.system,
          terminalViewportPadding:
              TerminalAppAppearance.defaultTerminalViewportPadding,
          restoreLayout: false,
          osc52Policy: LocalTerminalOsc52Policy.profile,
          openUrlPolicy: LocalTerminalOpenUrlPolicy.ask,
          requestAttentionPolicy: LocalTerminalRequestAttentionPolicy.disabled,
          reportVariableDecisions: const {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDefaultsDialogLauncher(
  WidgetTester tester, {
  required List<TerminalProfile> profiles,
  required String? configuredDefaultProfileId,
  required String? effectiveDefaultProfileId,
  required ValueChanged<DefaultsAndAppearanceSelection?> onSelection,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildIanvsTerminalTheme(
        Brightness.light,
        platform: TargetPlatform.macOS,
      ),
      home: Builder(
        builder: (context) => TextButton(
          key: const Key('open-defaults-profile-test'),
          onPressed: () async {
            onSelection(
              await showDialog<DefaultsAndAppearanceSelection>(
                context: context,
                builder: (_) => DefaultsAndAppearanceDialog(
                  profiles: profiles,
                  configuredDefaultProfileId: configuredDefaultProfileId,
                  effectiveDefaultProfileId: effectiveDefaultProfileId,
                  themeMode: TerminalThemeMode.system,
                  terminalViewportPadding:
                      TerminalAppAppearance.defaultTerminalViewportPadding,
                  restoreLayout: false,
                  osc52Policy: LocalTerminalOsc52Policy.profile,
                  openUrlPolicy: LocalTerminalOpenUrlPolicy.ask,
                  requestAttentionPolicy:
                      LocalTerminalRequestAttentionPolicy.disabled,
                  reportVariableDecisions: const {},
                ),
              ),
            );
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-defaults-profile-test')));
  await tester.pumpAndSettle();
}
