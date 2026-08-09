import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpHarness(
    WidgetTester tester,
    Widget child, {
    TargetPlatform platform = TargetPlatform.macOS,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildIanvsTerminalTheme(Brightness.light, platform: platform),
        builder: textScale == 1
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('app panel uses semantic panel styling', (tester) async {
    await pumpHarness(
      tester,
      const AppPanel(
        key: Key('app-panel'),
        tone: AppPanelTone.overlay,
        child: Text('Inside'),
      ),
    );

    final panel = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(AppPanel),
        matching: find.byType(DecoratedBox),
      ),
    );
    final decoration = panel.decoration as BoxDecoration;
    expect(decoration.color!.toARGB32(), const Color(0xFFFFFFFF).toARGB32());
    expect(find.text('Inside'), findsOneWidget);
  });

  testWidgets('app actions expand to 48 points on touch platforms', (
    tester,
  ) async {
    await pumpHarness(
      tester,
      const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppActionButton(
            buttonKey: Key('touch-dense-action'),
            size: AppActionSize.dense,
            icon: Icons.close_rounded,
          ),
          AppActionButton(
            buttonKey: Key('touch-regular-action'),
            label: 'Save',
          ),
        ],
      ),
      platform: TargetPlatform.iOS,
    );

    expect(
      tester.getSize(find.byKey(const Key('touch-dense-action'))),
      const Size.square(48),
    );
    expect(
      tester.getSize(find.byKey(const Key('touch-regular-action'))).height,
      48,
    );
  });

  testWidgets('single-line inputs keep one height across decoration variants', (
    tester,
  ) async {
    const fieldKeys = <Key>[
      Key('plain-input'),
      Key('prefix-input'),
      Key('suffix-input'),
      Key('both-icons-input'),
      Key('dropdown-input'),
    ];
    final cases =
        <({TargetPlatform platform, double textScale, double? expectedHeight})>[
          (platform: TargetPlatform.macOS, textScale: 1, expectedHeight: 36),
          (platform: TargetPlatform.iOS, textScale: 1, expectedHeight: 48),
          (
            platform: TargetPlatform.macOS,
            textScale: 1.8,
            expectedHeight: null,
          ),
        ];

    for (final testCase in cases) {
      await pumpHarness(
        tester,
        SizedBox(
          width: 760,
          child: Row(
            children: [
              const Expanded(
                child: TextField(
                  key: Key('plain-input'),
                  decoration: InputDecoration(hintText: 'Plain'),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: TextField(
                  key: Key('prefix-input'),
                  decoration: InputDecoration(
                    hintText: 'Prefix',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('suffix-input'),
                  decoration: InputDecoration(
                    hintText: 'Suffix',
                    suffixIcon: IconButton(
                      tooltip: 'Clear suffix input',
                      onPressed: () {},
                      icon: const Icon(Icons.clear_rounded),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: const Key('both-icons-input'),
                  decoration: InputDecoration(
                    hintText: 'Both',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: 'Show value',
                      onPressed: () {},
                      icon: const Icon(Icons.visibility_outlined),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppDropdownFormField<String>(
                  key: const Key('dropdown-input'),
                  initialValue: 'one',
                  decoration: const InputDecoration(),
                  items: const [
                    DropdownMenuItem(value: 'one', child: Text('One')),
                  ],
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
        platform: testCase.platform,
        textScale: testCase.textScale,
      );

      final heights = fieldKeys
          .map((key) => tester.getSize(find.byKey(key)).height)
          .toList(growable: false);
      final referenceHeight = heights.first;
      for (final height in heights.skip(1)) {
        expect(
          height,
          closeTo(referenceHeight, 0.5),
          reason:
              'Input heights must match for ${testCase.platform} '
              'at ${testCase.textScale}x text scale: $heights',
        );
      }
      if (testCase.expectedHeight case final expectedHeight?) {
        expect(referenceHeight, closeTo(expectedHeight, 0.01));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('app dialog scaffold renders title subtitle footer and close', (
    tester,
  ) async {
    var closeCount = 0;
    await pumpHarness(
      tester,
      AppDialogScaffold(
        key: const Key('dialog'),
        title: 'Preferences',
        subtitle: 'Tune the shell',
        body: const Text('Body'),
        footer: const Text('Footer'),
        onClose: () => closeCount += 1,
      ),
    );

    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Tune the shell'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
    expect(find.text('Footer'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Preferences dialog')),
      matchesSemantics(label: 'Preferences dialog'),
    );

    await tester.tap(find.byTooltip('Close dialog'));
    await tester.pump();

    expect(closeCount, 1);
  });

  testWidgets('app action button supports enabled and disabled states', (
    tester,
  ) async {
    var tapCount = 0;
    await pumpHarness(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppActionButton(
            key: const Key('enabled-action'),
            icon: Icons.add_rounded,
            label: 'Create',
            onPressed: () => tapCount += 1,
          ),
          const SizedBox(height: 12),
          const AppActionButton(
            buttonKey: Key('dense-action'),
            tone: AppActionTone.ghost,
            size: AppActionSize.dense,
            icon: Icons.close_rounded,
          ),
          const SizedBox(height: 12),
          const AppActionButton(
            buttonKey: Key('icon-only-action'),
            tone: AppActionTone.ghost,
            size: AppActionSize.compact,
            icon: Icons.delete_outline,
          ),
          const SizedBox(height: 12),
          const AppActionButton(
            key: Key('disabled-action'),
            tone: AppActionTone.secondary,
            icon: Icons.block,
            label: 'Disabled',
          ),
        ],
      ),
    );

    await tester.tap(find.text('Create'));
    await tester.pump();
    await tester.tap(find.text('Disabled'));
    await tester.pump();

    final enabledButton = tester.getSize(
      find.widgetWithText(FilledButton, 'Create'),
    );
    final denseIconButton = tester.getSize(
      find.byKey(const Key('dense-action')),
    );
    final iconOnlyButton = tester.getSize(
      find.byKey(const Key('icon-only-action')),
    );
    final disabledButton = tester.getSize(
      find.widgetWithText(OutlinedButton, 'Disabled'),
    );
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Disabled'), findsOneWidget);
    expect(tapCount, 1);
    expect(enabledButton.height, 36);
    expect(denseIconButton.height, 28);
    expect(denseIconButton.width, 28);
    expect(iconOnlyButton.height, 32);
    expect(iconOnlyButton.width, 32);
    expect(disabledButton.height, 36);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('dense-action'))).tooltip,
      isNull,
    );
  });

  testWidgets('app field row renders label hint control and message', (
    tester,
  ) async {
    await pumpHarness(
      tester,
      const AppFieldRow(
        label: 'Font family',
        hint: 'Used by new sessions',
        message: 'Leave empty to inherit',
        control: TextField(),
      ),
    );

    expect(find.text('Font family'), findsOneWidget);
    expect(find.text('Used by new sessions'), findsOneWidget);
    expect(find.text('Leave empty to inherit'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<Text>(find.text('Font family')).style?.fontSize, 11.5);
    expect(
      tester
          .widget<Text>(find.text('Used by new sessions'))
          .style
          ?.color
          ?.toARGB32(),
      const Color(0xFF6B6B70).toARGB32(),
    );
  });

  testWidgets('app empty state renders action affordance', (tester) async {
    var tapCount = 0;
    await pumpHarness(
      tester,
      AppEmptyState(
        title: 'No sessions',
        message: 'Open a shell tab to get started.',
        supportingText: 'Default profile: Local Shell',
        action: AppActionButton(
          key: const Key('empty-action'),
          icon: Icons.add_box_outlined,
          label: 'New tab',
          onPressed: () => tapCount += 1,
        ),
      ),
    );

    await tester.tap(find.text('New tab'));
    await tester.pump();

    final emptyStateSize = tester.getSize(find.byType(AppEmptyState));
    expect(find.text('No sessions'), findsOneWidget);
    expect(find.text('Open a shell tab to get started.'), findsOneWidget);
    expect(find.text('Default profile: Local Shell'), findsOneWidget);
    expect(tapCount, 1);
    expect(emptyStateSize.width, lessThanOrEqualTo(340));
  });

  testWidgets('app dialog scaffold uses compact shell-style geometry', (
    tester,
  ) async {
    await pumpHarness(
      tester,
      AppDialogScaffold(
        title: 'Preferences',
        subtitle: 'Tune the shell',
        body: const Text('Body'),
        footer: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppActionButton(
              buttonKey: Key('dialog-cancel'),
              tone: AppActionTone.secondary,
              size: AppActionSize.compact,
              label: 'Cancel',
            ),
          ],
        ),
        onClose: () {},
      ),
    );

    final closeButtonSize = tester.getSize(find.byTooltip('Close dialog'));
    final footerButtonSize = tester.getSize(
      find.byKey(const Key('dialog-cancel')),
    );
    expect(closeButtonSize.height, 28);
    expect(closeButtonSize.width, 28);
    expect(footerButtonSize.height, 32);
  });

  testWidgets('app panel selected tone exposes workstation selection surface', (
    tester,
  ) async {
    await pumpHarness(
      tester,
      const AppPanel(
        key: Key('selected-panel'),
        tone: AppPanelTone.selected,
        child: Text('Selected pane'),
      ),
    );

    final panel = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(AppPanel),
        matching: find.byType(DecoratedBox),
      ),
    );
    final decoration = panel.decoration as BoxDecoration;
    expect(decoration.color!.toARGB32(), const Color(0xFFD9ECFF).toARGB32());
    expect(
      (decoration.border! as Border).top.color.toARGB32(),
      const Color(0xFFA7A7AD).toARGB32(),
    );
  });
}
