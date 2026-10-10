import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/app_ui.dart';
import 'package:app/ui/previews/desktop_component_states_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../design/configuration_capture_binding.dart';
import '../design/visual_capture_fonts.dart';

void desktopTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(
    description,
    body,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

void main() {
  ConfigurationCaptureBinding();
  setUpAll(loadVisualCaptureFonts);
  const evidence = String.fromEnvironment('DESKTOP_STATE_PREVIEW_EVIDENCE_DIR');
  final captures = <Map<String, Object?>>[];
  tearDownAll(() async {
    if (evidence.isEmpty) return;
    await Directory(evidence).create(recursive: true);
    await File('$evidence/capture-manifest.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'capture_class': 'flutter_widget_production_components',
        'physical_device': false,
        'host_os': Platform.operatingSystemVersion,
        'target_platform': TargetPlatform.macOS.name,
        'source_label': const String.fromEnvironment(
          'DESKTOP_STATE_PREVIEW_SOURCE',
        ),
        'fonts':
            'visual_capture_fonts.dart: repository and pinned Flutter SDK assets',
        'native_pty': false,
        'model_api': false,
        'widget_test_device_pixel_ratio': 1,
        'png_export_pixel_ratio': 2,
        'native_display_dpi_verified': false,
        'native_system_fonts_verified': false,
        'captures': captures,
      }),
    );
  });

  late GlobalKey boundary;
  Future<void> mount(
    WidgetTester tester,
    DesktopPreviewComponent component, {
    DesktopPreviewFact fact = DesktopPreviewFact.defaultState,
    Brightness brightness = Brightness.light,
    bool contrast = false,
    double scale = 1,
    bool reduceMotion = false,
    Size size = const Size(1120, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    boundary = GlobalKey();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: DesktopComponentStatesPreview(
            initialComponent: component,
            initialFact: fact,
            brightness: brightness,
            highContrast: contrast,
            textScale: scale,
            reduceMotion: reduceMotion,
            themeTransform: withVisualCaptureFonts,
          ),
        ),
      );
      // Existing AI fixtures load an in-memory store before building controls.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(tester.takeException(), isNull);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (evidence.isEmpty) return;
    await tester.runAsync(() async {
      await Directory(evidence).create(recursive: true);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$evidence/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      final context = tester.element(
        find.byKey(const Key('desktop-preview-applicability')),
      );
      captures.add({
        'name': name,
        'file': '$name.png',
        'width': image.width,
        'height': image.height,
        'brightness': Theme.of(context).brightness.name,
        'high_contrast': MediaQuery.highContrastOf(context),
        'text_scale': MediaQuery.textScalerOf(context).scale(1),
        'reduce_motion': MediaQuery.disableAnimationsOf(context),
        'pointer_keyboard_state': name,
        'default_target_platform': defaultTargetPlatform.name,
      });
      image.dispose();
    });
  }

  Future<TestGesture> mouseAt(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(target));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    return mouse;
  }

  Future<void> settleHeldState(WidgetTester tester) async {
    // Tap-down can wait for the gesture arena's press timeout. Then let the
    // actual ink animation finish while the pointer is still held down.
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pumpAndSettle();
  }

  Future<void> tabUntil(
    WidgetTester tester,
    bool Function() reached, {
    bool reverse = false,
  }) async {
    for (var i = 0; i < 20 && !reached(); i++) {
      if (reverse) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      if (reverse) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(
      reached(),
      isTrue,
      reason: 'Production control is reachable by Tab.',
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  bool focusWithin(WidgetTester tester, Finder target) {
    final element = tester.element(target);
    final context = FocusManager.instance.primaryFocus?.context;
    var inside = identical(context, element);
    context?.visitAncestorElements((ancestor) {
      inside |= identical(ancestor, element);
      return !inside;
    });
    return inside;
  }

  for (final variant in [
    (
      name: 'light',
      brightness: Brightness.light,
      contrast: false,
      scale: 1.0,
      size: const Size(1120, 800),
    ),
    (
      name: 'dark',
      brightness: Brightness.dark,
      contrast: false,
      scale: 1.0,
      size: const Size(1120, 800),
    ),
    (
      name: 'contrast-light',
      brightness: Brightness.light,
      contrast: true,
      scale: 1.0,
      size: const Size(1120, 800),
    ),
    (
      name: 'contrast-dark',
      brightness: Brightness.dark,
      contrast: true,
      scale: 1.0,
      size: const Size(1120, 800),
    ),
    (
      name: 'narrow-2x',
      brightness: Brightness.dark,
      contrast: false,
      scale: 2.0,
      size: const Size(520, 900),
    ),
  ]) {
    for (final component in DesktopPreviewComponent.values) {
      desktopTest(
        '${variant.name} ${component.name} renders the production control without overflow',
        (tester) async {
          await mount(
            tester,
            component,
            brightness: variant.brightness,
            contrast: variant.contrast,
            scale: variant.scale,
            size: variant.size,
            reduceMotion: variant.contrast || variant.scale == 2,
          );
          final context = tester.element(
            find.byKey(const Key('desktop-preview-applicability')),
          );
          expect(Theme.of(context).platform, TargetPlatform.macOS);
          expect(defaultTargetPlatform, TargetPlatform.macOS);
          expect(ComposerTheme.of(context).highContrast, variant.contrast);
          switch (component) {
            case DesktopPreviewComponent.block:
              expect(find.byType(TerminalCommandBlocksView), findsOneWidget);
            case DesktopPreviewComponent.contextChip:
              expect(find.byType(InputChip), findsOneWidget);
            case DesktopPreviewComponent.candidate:
              expect(
                find.byKey(const Key('composer-completion-list')),
                findsOneWidget,
              );
            case DesktopPreviewComponent.button:
              expect(
                find.byKey(const Key('composer-primary-action')),
                findsOneWidget,
              );
            case DesktopPreviewComponent.tab:
              expect(find.byType(ShellTabComponentPreview), findsOneWidget);
            case DesktopPreviewComponent.splitter:
              expect(find.byType(ShellDividerComponentPreview), findsOneWidget);
          }
          await capture(tester, '${variant.name}-${component.name}-default');
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  desktopTest(
    'native catalogue environment controls reach the required variants',
    (tester) async {
      await mount(tester, DesktopPreviewComponent.tab);
      Future<void> choose(String label) async {
        await tester.tap(find.byKey(const Key('desktop-preview-environment')));
        await tester.pumpAndSettle();
        final item = find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            )
            .first;
        await tester.ensureVisible(item);
        await tester.pumpAndSettle();
        await tester.tap(item);
        await tester.pumpAndSettle();
      }

      BuildContext environment() => tester.element(
        find.byKey(const Key('desktop-preview-applicability')),
      );
      await choose('High contrast dark');
      expect(Theme.of(environment()).brightness, Brightness.dark);
      expect(
        ComposerTheme.of(environment()).resultStyle.fontFamily,
        visualCaptureMonoFont,
      );
      expect(ComposerTheme.of(environment()).highContrast, isTrue);
      expect(MediaQuery.highContrastOf(environment()), isTrue);
      await choose('Text 2×');
      expect(MediaQuery.textScalerOf(environment()).scale(1), 2);
      await choose('Reduce motion');
      expect(MediaQuery.disableAnimationsOf(environment()), isTrue);
      await choose('Constrain fixture to 520 px');
      expect(
        tester
            .getSize(find.byKey(const Key('desktop-preview-fixture-bounds')))
            .width,
        520,
      );
      await capture(tester, 'native-menu-high-contrast-dark-2x-reduced-520px');
      await choose('Light');
      expect(Theme.of(environment()).brightness, Brightness.light);
      expect(ComposerTheme.of(environment()).highContrast, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final fact in [
    DesktopPreviewFact.running,
    DesktopPreviewFact.failed,
    DesktopPreviewFact.unknown,
  ]) {
    desktopTest(
      'Block ${fact.name} is a controller fact independent of selection',
      (tester) async {
        await mount(tester, DesktopPreviewComponent.block, fact: fact);
        final controller = tester
            .widget<TerminalCommandBlocksView>(
              find.byType(TerminalCommandBlocksView),
            )
            .controller;
        expect(controller.selected, isEmpty);
        expect(
          controller.blocks.single.running,
          fact == DesktopPreviewFact.running,
        );
        expect(
          controller.blocks.single.exitCode,
          fact == DesktopPreviewFact.failed ? 1 : null,
        );
        await capture(tester, 'block-${fact.name}');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  desktopTest('Block command keyboard focus does not select until activation', (
    tester,
  ) async {
    await mount(tester, DesktopPreviewComponent.block);
    final view = tester.widget<TerminalCommandBlocksView>(
      find.byType(TerminalCommandBlocksView),
    );
    final title = find
        .ancestor(
          of: find.text('cat /srv/应用/config.yaml'),
          matching: find.byType(InkWell),
        )
        .first;
    await tabUntil(tester, () => focusWithin(tester, title));
    expect(view.controller.selected, isEmpty);
    await capture(tester, 'block-focused');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(view.controller.selected, contains('prd-source'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  desktopTest(
    'Block hover and held press do not select until activation; focus stays meaningful',
    (tester) async {
      await mount(tester, DesktopPreviewComponent.block);
      final view = tester.widget<TerminalCommandBlocksView>(
        find.byType(TerminalCommandBlocksView),
      );
      final title = find.text('cat /srv/应用/config.yaml');
      expect(view.controller.selected, isEmpty);
      final mouse = await mouseAt(tester, title);
      expect(view.controller.selected, isEmpty);
      await capture(tester, 'block-hover');
      await mouse.down(tester.getCenter(title));
      await settleHeldState(tester);
      expect(view.controller.selected, isEmpty);
      await capture(tester, 'block-pressed');
      await mouse.up();
      await tester.pump();
      expect(view.controller.selected, contains('prd-source'));
      expect(FocusManager.instance.primaryFocus, isNotNull);
      await mouse.removePointer();
      await tester.pumpAndSettle();
      await capture(tester, 'block-selected');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  desktopTest(
    'ContextChip keeps inspect separate from source deletion and supports keyboard focus',
    (tester) async {
      await mount(tester, DesktopPreviewComponent.contextChip);
      final task = tester
          .widget<TerminalAiComponentPreview>(
            find.byType(TerminalAiComponentPreview),
          )
          .controller;
      bool chipFocused() {
        var inside = false;
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
          element,
        ) {
          if (element.widget is InputChip) inside = true;
          return !inside;
        });
        return inside;
      }

      await tabUntil(tester, chipFocused);
      await capture(tester, 'contextChip-focused');
      final mouse = await mouseAt(tester, find.text('cat /srv/应用/config.yaml'));
      await capture(tester, 'contextChip-hover');
      await mouse.down(tester.getCenter(find.text('cat /srv/应用/config.yaml')));
      await settleHeldState(tester);
      expect(task.attachments, hasLength(1));
      await capture(tester, 'contextChip-pressed');
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(task.attachments, hasLength(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ai-context-delete-prd-source')),
      );
      await tester.pumpAndSettle();
      expect(task.attachments, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  desktopTest(
    'ContextChip removal unavailable does not falsely disable inspection',
    (tester) async {
      await mount(
        tester,
        DesktopPreviewComponent.contextChip,
        fact: DesktopPreviewFact.removalUnavailable,
      );
      final chip = tester.widget<InputChip>(find.byType(InputChip));
      expect(chip.onDeleted, isNull);
      expect(chip.onPressed, isNotNull);
      expect(chip.isEnabled, isTrue);
      await capture(tester, 'contextChip-removal-unavailable');
      await tester.tap(find.byType(InputChip));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  desktopTest(
    'candidate hover and arrows highlight without executing; Enter only accepts the draft',
    (tester) async {
      await mount(tester, DesktopPreviewComponent.candidate);
      final controller = tester
          .widget<TerminalComposerView>(find.byType(TerminalComposerView))
          .controller;
      final draft = controller.editor.text;
      final label = controller.items.first.label;
      final row = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            (widget.properties.label?.startsWith('$label,') ?? false),
      );
      final mouse = await mouseAt(tester, row);
      expect(controller.selectedIndex, 0);
      expect(controller.editor.text, draft);
      expect(controller.ownership, ComposerOwnership.ready);
      await capture(tester, 'candidate-hover');
      await mouse.down(tester.getCenter(row));
      await settleHeldState(tester);
      expect(controller.editor.text, draft);
      await capture(tester, 'candidate-pressed');
      await mouse.cancel();
      await mouse.removePointer();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.selectedIndex, greaterThanOrEqualTo(0));
      expect(
        tester
            .widget<EditableText>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is EditableText &&
                    widget.controller == controller.editor,
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      await capture(tester, 'candidate-keyboard-highlight');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.editor.text, isNot(draft));
      expect(controller.ownership, ComposerOwnership.ready);
      expect(controller.completionMenuOpen, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  desktopTest(
    'primary action has real keyboard focus before Enter activates the fixture',
    (tester) async {
      await mount(tester, DesktopPreviewComponent.button);
      final action = find.byKey(const Key('composer-primary-action'));
      final controller = tester
          .widget<TerminalComposerView>(find.byType(TerminalComposerView))
          .controller;
      final draft = controller.editor.text;
      // Forward Tab belongs to shell completion inside the editor. Shift+Tab
      // uses the same production traversal contract to reach nearby actions.
      await tabUntil(tester, () => focusWithin(tester, action), reverse: true);
      expect(controller.editor.text, draft);
      await capture(tester, 'button-focused');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.editor.text, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  desktopTest(
    'primary action pressed is not submitted; release uses only the local fixture',
    (tester) async {
      await mount(tester, DesktopPreviewComponent.button);
      final controller = tester
          .widget<TerminalComposerView>(find.byType(TerminalComposerView))
          .controller;
      final action = find.byKey(const Key('composer-primary-action'));
      final draft = controller.editor.text;
      final mouse = await mouseAt(tester, action);
      await capture(tester, 'button-hover');
      await mouse.down(tester.getCenter(action));
      await settleHeldState(tester);
      expect(controller.ownership, ComposerOwnership.ready);
      expect(controller.editor.text, draft);
      await capture(tester, 'button-pressed');
      await mouse.up();
      await tester.pump();
      expect(controller.editor.text, isEmpty);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final fact in [
    DesktopPreviewFact.emptyDraft,
    DesktopPreviewFact.submitting,
  ]) {
    desktopTest(
      'button $fact exposes the production disabled cause and cannot act',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await mount(tester, DesktopPreviewComponent.button, fact: fact);
        final action = find.byKey(const Key('composer-primary-action'));
        expect(tester.widget<FilledButton>(action).onPressed, isNull);
        final reason = fact == DesktopPreviewFact.emptyDraft
            ? 'Enter a complete command to run'
            : 'Wait for the shell to be ready';
        expect(find.byTooltip(reason), findsOneWidget);
        final node = tester.getSemantics(action);
        expect(node.flagsCollection.isEnabled, ui.Tristate.isFalse);
        final data = node.getSemanticsData();
        expect(
          [data.label, data.hint, data.tooltip].join('\n'),
          contains(reason),
        );
        final controller = tester
            .widget<TerminalComposerView>(find.byType(TerminalComposerView))
            .controller;
        final before = controller.editor.value;
        await tester.tap(action, warnIfMissed: false);
        await tester.pump();
        expect(controller.editor.value, before);
        await capture(tester, 'button-${fact.name}-disabled');
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  desktopTest(
    'tab hover/press/focus are not activation and keyboard activation selects once',
    (tester) async {
      await mount(tester, DesktopPreviewComponent.tab);
      final tab = find.byKey(const Key('shell-tab-catalogue-tab'));
      final mouse = await mouseAt(tester, tab);
      BorderSide paintedSide() =>
          (tester
                      .widget<Material>(
                        find.descendant(
                          of: tab,
                          matching: find.byType(Material),
                        ),
                      )
                      .shape!
                  as OutlinedBorder)
              .side;
      final hoveredSide = paintedSide();
      expect(
        find.text('Local activations: 0 · close callbacks: 0'),
        findsOneWidget,
      );
      await capture(tester, 'tab-hover');
      await mouse.down(tester.getCenter(tab));
      await settleHeldState(tester);
      expect(
        find.text('Local activations: 0 · close callbacks: 0'),
        findsOneWidget,
      );
      await capture(tester, 'tab-pressed');
      await mouse.cancel();
      await tabUntil(
        tester,
        () => tester.widget<TextButton>(tab).focusNode!.hasFocus,
      );
      await tester.pumpAndSettle();
      expect(paintedSide().width, 2);
      expect(paintedSide(), isNot(hoveredSide));
      await capture(tester, 'tab-focused');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        find.text('Local activations: 1 · close callbacks: 0'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ShellTabComponentPreview>(
              find.byType(ShellTabComponentPreview),
            )
            .selected,
        isTrue,
      );
      await capture(tester, 'tab-selected');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(tab).focusNode!.hasFocus, isFalse);
      expect(paintedSide().width, isNot(2));
      await capture(tester, 'tab-selected-unfocused');
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final vertical in [false, true]) {
    desktopTest(
      'splitter ${vertical ? 'vertical' : 'horizontal'} distinguishes hover from real drag',
      (tester) async {
        await mount(
          tester,
          DesktopPreviewComponent.splitter,
          fact: vertical
              ? DesktopPreviewFact.vertical
              : DesktopPreviewFact.defaultState,
        );
        final target = find.byKey(const Key('desktop-preview-splitter'));
        final line = find.byKey(
          Key(
            'shell-pane-divider-line-${vertical ? 'vertical' : 'horizontal'}',
          ),
        );
        double thickness() =>
            vertical ? tester.getSize(line).height : tester.getSize(line).width;
        expect(thickness(), 1);
        final mouse = await mouseAt(tester, target);
        expect(thickness(), 2);
        expect(find.text('Local resize delta: 0.0'), findsOneWidget);
        await capture(
          tester,
          'splitter-${vertical ? 'vertical' : 'horizontal'}-hover',
        );
        final start = tester.getCenter(target);
        await mouse.down(start);
        await settleHeldState(tester);
        expect(find.text('Local resize delta: 0.0'), findsOneWidget);
        await mouse.moveTo(
          start + (vertical ? const Offset(0, 30) : const Offset(30, 0)),
        );
        await tester.pump();
        await mouse.moveTo(
          start + (vertical ? const Offset(0, 50) : const Offset(50, 0)),
        );
        await settleHeldState(tester);
        expect(find.text('Local resize delta: 0.0'), findsNothing);
        await capture(
          tester,
          'splitter-${vertical ? 'vertical' : 'horizontal'}-dragging',
        );
        await mouse.up();
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 160));
        expect(thickness(), 1);
        expect(
          find.textContaining('No persistent selected, whole-control disabled'),
          findsOneWidget,
        );
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    desktopTest(
      'splitter ${vertical ? 'vertical' : 'horizontal'} keyboard focus and semantics resize the real local fixture',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await mount(
          tester,
          DesktopPreviewComponent.splitter,
          fact: vertical
              ? DesktopPreviewFact.vertical
              : DesktopPreviewFact.defaultState,
          contrast: true,
          reduceMotion: true,
        );
        final preview = tester.widget<ShellDividerComponentPreview>(
          find.byType(ShellDividerComponentPreview),
        );
        final target = find.byKey(const Key('desktop-preview-splitter'));
        final mouse = await mouseAt(tester, target);
        final line = find.byKey(
          Key(
            'shell-pane-divider-line-${vertical ? 'vertical' : 'horizontal'}',
          ),
        );
        Color lineColor() =>
            (tester.widget<AnimatedContainer>(line).decoration!
                    as BoxDecoration)
                .color!;
        final hoverColor = lineColor();
        await tabUntil(tester, () => preview.focusNode!.hasPrimaryFocus);
        expect(lineColor(), isNot(hoverColor));
        expect(lineColor(), tester.element(target).appTheme.focusRing);
        expect(find.text('Local resize delta: 0.0'), findsOneWidget);
        await capture(
          tester,
          'splitter-${vertical ? 'vertical' : 'horizontal'}-focused-high-contrast',
        );
        await tester.sendKeyEvent(
          vertical
              ? LogicalKeyboardKey.arrowDown
              : LogicalKeyboardKey.arrowRight,
        );
        await tester.pumpAndSettle();
        expect(find.text('Local resize delta: 10.0'), findsOneWidget);
        final node = tester.getSemantics(
          find.byKey(
            Key(
              'shell-pane-divider-semantics-${vertical ? 'vertical' : 'horizontal'}',
            ),
          ),
        );
        final beforeValue = node.getSemanticsData().value;
        tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          node.id,
          ui.SemanticsAction.increase,
        );
        await tester.pumpAndSettle();
        expect(find.text('Local resize delta: 20.0'), findsOneWidget);
        expect(node.getSemanticsData().value, isNot(beforeValue));
        expect(preview.focusNode!.hasPrimaryFocus, isTrue);
        await capture(
          tester,
          'splitter-${vertical ? 'vertical' : 'horizontal'}-keyboard-resized',
        );
        await mouse.removePointer();
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
