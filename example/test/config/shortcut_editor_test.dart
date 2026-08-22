import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/shortcut_editor.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/shell/defaults_appearance_dialog.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('records a shortcut and reports a live conflict', (tester) async {
    await _pumpEditor(tester);

    await tester.enterText(
      find.byKey(const Key('shortcut-editor-filter')),
      'new tab',
    );
    await tester.pump();
    expect(find.text('New tab'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('New tab')).style?.fontWeight,
      FontWeight.w600,
    );

    await tester.tap(find.byKey(const Key('shortcut-edit-newTab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shortcut-capture-dialog')), findsOneWidget);

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.comma, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.comma, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.pump();

    expect(find.text('⌘,'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shortcut-capture-apply')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('shortcut-editor-conflict-summary')),
      findsOneWidget,
    );
    expect(find.textContaining('New tab and Open defaults'), findsOneWidget);
  });

  testWidgets('rejects unsafe unmodified printable keys', (tester) async {
    await _pumpEditor(tester);
    await tester.enterText(
      find.byKey(const Key('shortcut-editor-filter')),
      'new tab',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('shortcut-edit-newTab')));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN, platform: 'macos');
    await tester.pump();

    expect(find.byKey(const Key('shortcut-capture-error')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('shortcut-capture-apply')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('supports per-action and all-default restoration', (
    tester,
  ) async {
    const customConfig = LocalTerminalKeybindingsConfig(
      overrides: {
        TerminalActionId.newTab: LocalTerminalKeyBindingOverride(
          binding: LocalTerminalKeyBinding(
            scope: TerminalKeyBindingScope.focusedApp,
            key: 'Key N',
            meta: true,
          ),
        ),
      },
    );
    LocalTerminalKeybindingsConfig? latest;
    await _pumpEditor(
      tester,
      config: customConfig,
      onChanged: (value) => latest = value,
    );
    await tester.enterText(
      find.byKey(const Key('shortcut-editor-filter')),
      'new tab',
    );
    await tester.pump();

    expect(find.text('⌘N'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shortcut-restore-newTab')));
    await tester.pump();
    expect(latest, const LocalTerminalKeybindingsConfig());
    expect(find.text('⌘T'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shortcut-disable-newTab')));
    await tester.pump();
    expect(latest!.overrides[TerminalActionId.newTab]?.enabled, isFalse);
    expect(
      find.descendant(
        of: find.byKey(const Key('shortcut-edit-newTab')),
        matching: find.text('Add shortcut'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('shortcut-editor-restore-all')));
    await tester.pump();
    expect(latest, const LocalTerminalKeybindingsConfig());
    expect(find.text('⌘T'), findsOneWidget);
  });

  testWidgets('defaults dialog blocks saving a conflicting configuration', (
    tester,
  ) async {
    const conflictingConfig = LocalTerminalKeybindingsConfig(
      overrides: {
        TerminalActionId.newTab: LocalTerminalKeyBindingOverride(
          binding: LocalTerminalKeyBinding(
            scope: TerminalKeyBindingScope.focusedApp,
            key: 'Comma',
            meta: true,
          ),
        ),
      },
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
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
            keybindings: conflictingConfig,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('defaults-save')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('defaults-section-shortcuts')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shortcut-editor-restore-all')));
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('defaults-save')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('desktop shortcut editor lives inside the shortcuts tab', (
    tester,
  ) async {
    await _pumpDefaultsDialog(tester, surfaceSize: const Size(1000, 820));

    await tester.tap(find.byKey(const Key('defaults-section-appearance')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('default-theme-option-dark')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('defaults-section-shortcuts')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defaults-appearance-scroll')), findsNothing);
    expect(
      find.byKey(const Key('defaults-shortcuts-tab-panel')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shortcut-editor-list')), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('shortcut-editor-list-panel')),
        matching: find.byType(Scrollbar),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('defaults-shortcuts-done')), findsNothing);
    expect(find.byKey(const Key('defaults-shortcuts-back')), findsNothing);
    expect(find.byKey(const Key('defaults-save')), findsOneWidget);
    expect(find.byKey(const Key('defaults-section-general')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('defaults-section-appearance')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('default-theme-option-dark')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('defaults-save')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('mobile shortcut editor is a full-screen single-scroll page', (
    tester,
  ) async {
    await _pumpDefaultsDialog(tester, surfaceSize: const Size(390, 844));

    final dialogSize = tester.getSize(find.byKey(const Key('defaults-dialog')));
    expect(dialogSize, const Size(390, 844));
    expect(find.byKey(const Key('defaults-mobile-back')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('defaults-shortcuts-entry')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('defaults-shortcuts-entry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defaults-appearance-scroll')), findsNothing);
    expect(
      find.byKey(const Key('shortcut-editor-mobile-menu')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('defaults-shortcuts-done')), findsNothing);
    expect(find.byKey(const Key('shortcut-editor-list')), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('shortcut-editor-list-panel')),
        matching: find.byType(Scrollbar),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('defaults-shortcuts-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('defaults-shortcuts-entry')), findsOneWidget);
  });

  testWidgets('remains usable at narrow width and large text scale', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      surfaceSize: const Size(520, 760),
      textScaler: const TextScaler.linear(2),
      config: const LocalTerminalKeybindingsConfig(
        overrides: {
          TerminalActionId.newTab: LocalTerminalKeyBindingOverride(
            binding: LocalTerminalKeyBinding(
              scope: TerminalKeyBindingScope.focusedApp,
              key: 'Key N',
              meta: true,
            ),
          ),
        },
      ),
    );
    await tester.enterText(
      find.byKey(const Key('shortcut-editor-filter')),
      'new tab',
    );
    await tester.pump();

    expect(find.byKey(const Key('shortcut-edit-newTab')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  LocalTerminalKeybindingsConfig config =
      const LocalTerminalKeybindingsConfig(),
  ValueChanged<LocalTerminalKeybindingsConfig>? onChanged,
  Size surfaceSize = const Size(900, 720),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = surfaceSize;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildIanvsTerminalTheme(Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 780,
              child: _ShortcutEditorHarness(
                initialConfig: config,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
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
          requestAttentionPolicy: LocalTerminalRequestAttentionPolicy.disabled,
          reportVariableDecisions: {},
        ),
      ),
    ),
  );
  await tester.pump();
}

class _ShortcutEditorHarness extends StatefulWidget {
  const _ShortcutEditorHarness({
    required this.initialConfig,
    required this.onChanged,
  });

  final LocalTerminalKeybindingsConfig initialConfig;
  final ValueChanged<LocalTerminalKeybindingsConfig>? onChanged;

  @override
  State<_ShortcutEditorHarness> createState() => _ShortcutEditorHarnessState();
}

class _ShortcutEditorHarnessState extends State<_ShortcutEditorHarness> {
  late LocalTerminalKeybindingsConfig _config;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
  }

  @override
  Widget build(BuildContext context) {
    return ShortcutEditorPanel(
      config: _config,
      onChanged: (value) {
        setState(() => _config = value);
        widget.onChanged?.call(value);
      },
    );
  }
}
