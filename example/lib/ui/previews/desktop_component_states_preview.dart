import 'package:flutter/material.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../../features/sessions/session_state.dart';
import '../../features/shell/shell_screen.dart';
import '../app_ui.dart';
import 'composer_preview_data.dart';
import 'mobile_prd_component_previews.dart';

enum DesktopPreviewComponent {
  block,
  contextChip,
  candidate,
  button,
  tab,
  splitter,
}

/// Facts change production controller data; pointer/keyboard states are never
/// forced by the catalogue. Use a mouse, press/hold, Tab and arrow keys.
enum DesktopPreviewFact {
  defaultState,
  selected,
  removalUnavailable,
  emptyDraft,
  submitting,
  running,
  failed,
  unknown,
  vertical,
}

enum _PreviewEnvironment {
  light,
  dark,
  highContrastLight,
  highContrastDark,
  standardText,
  doubleText,
  narrowPane,
  reduceMotion,
}

/// Native preview entrypoint: flutter run -d macos
/// --target lib/ui/previews/desktop_component_states_preview.dart.
///
/// The production shell presentation imports the native PTY library. Flutter's
/// web Widget Previewer cannot compile that dependency, so this catalogue is
/// deliberately not registered with @Preview. It instantiates no terminal runtime.
void main() => runApp(const DesktopComponentStatesPreview());

Widget desktopComponentStatesLightPreview() =>
    const DesktopComponentStatesPreview();

Widget desktopComponentStatesDarkPreview() =>
    const DesktopComponentStatesPreview(brightness: Brightness.dark);

Widget desktopComponentStatesContrastPreview() =>
    const DesktopComponentStatesPreview(
      brightness: Brightness.dark,
      highContrast: true,
      reduceMotion: true,
    );

Widget desktopComponentStatesNarrowPreview() =>
    const DesktopComponentStatesPreview(
      textScale: 2,
      narrowPane: true,
      reduceMotion: true,
    );

/// Real components with existing deterministic in-memory fixtures. No terminal
/// backend, app configuration store, model connection or OS command is started.
/// The import graph has native dependencies; this is not a web-compatible entry.
class DesktopComponentStatesPreview extends StatefulWidget {
  const DesktopComponentStatesPreview({
    this.initialComponent = DesktopPreviewComponent.block,
    this.initialFact = DesktopPreviewFact.defaultState,
    this.brightness = Brightness.light,
    this.highContrast = false,
    this.textScale = 1,
    this.narrowPane = false,
    this.reduceMotion = false,
    this.themeTransform,
    super.key,
  });

  final DesktopPreviewComponent initialComponent;
  final DesktopPreviewFact initialFact;
  final Brightness brightness;
  final bool highContrast;
  final double textScale;
  final bool narrowPane;
  final bool reduceMotion;

  /// Allows capture tests to keep pinned fonts across interactive theme changes.
  final ThemeData Function(ThemeData)? themeTransform;

  @override
  State<DesktopComponentStatesPreview> createState() =>
      _DesktopComponentStatesPreviewState();
}

class _DesktopComponentStatesPreviewState
    extends State<DesktopComponentStatesPreview> {
  late DesktopPreviewComponent component = widget.initialComponent;
  late DesktopPreviewFact fact = widget.initialFact;
  late Brightness brightness = widget.brightness;
  late bool highContrast = widget.highContrast;
  late double textScale = widget.textScale;
  late bool reduceMotion = widget.reduceMotion;
  late bool narrowPane = widget.narrowPane;
  int generation = 0;

  ThemeData get previewTheme {
    final theme = buildIanvsTerminalTheme(
      brightness,
      platform: TargetPlatform.macOS,
      highContrast: highContrast,
    );
    return widget.themeTransform?.call(theme) ?? theme;
  }

  void _setEnvironment(_PreviewEnvironment value) => setState(() {
    switch (value) {
      case _PreviewEnvironment.light:
      case _PreviewEnvironment.dark:
      case _PreviewEnvironment.highContrastLight:
      case _PreviewEnvironment.highContrastDark:
        brightness = switch (value) {
          _PreviewEnvironment.dark ||
          _PreviewEnvironment.highContrastDark => Brightness.dark,
          _ => Brightness.light,
        };
        highContrast =
            value == _PreviewEnvironment.highContrastLight ||
            value == _PreviewEnvironment.highContrastDark;
      case _PreviewEnvironment.standardText:
        textScale = 1;
      case _PreviewEnvironment.doubleText:
        textScale = 2;
      case _PreviewEnvironment.narrowPane:
        narrowPane = !narrowPane;
      case _PreviewEnvironment.reduceMotion:
        reduceMotion = !reduceMotion;
    }
  });

  Widget get _environmentMenu => PopupMenuButton<_PreviewEnvironment>(
    key: const Key('desktop-preview-environment'),
    tooltip: 'Preview environment',
    onSelected: _setEnvironment,
    itemBuilder: (context) => [
      for (final entry in const {
        _PreviewEnvironment.light: 'Light',
        _PreviewEnvironment.dark: 'Dark',
        _PreviewEnvironment.highContrastLight: 'High contrast light',
        _PreviewEnvironment.highContrastDark: 'High contrast dark',
      }.entries)
        PopupMenuItem(value: entry.key, child: Text(entry.value)),
      const PopupMenuDivider(),
      CheckedPopupMenuItem(
        value: _PreviewEnvironment.standardText,
        checked: textScale == 1,
        child: const Text('Text 1×'),
      ),
      CheckedPopupMenuItem(
        value: _PreviewEnvironment.doubleText,
        checked: textScale == 2,
        child: const Text('Text 2×'),
      ),
      CheckedPopupMenuItem(
        value: _PreviewEnvironment.narrowPane,
        checked: narrowPane,
        child: const Text('Constrain fixture to 520 px'),
      ),
      CheckedPopupMenuItem(
        value: _PreviewEnvironment.reduceMotion,
        checked: reduceMotion,
        child: const Text('Reduce motion'),
      ),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '${brightness.name} · ${highContrast ? 'high contrast · ' : ''}'
        '${textScale.toStringAsFixed(0)}× · '
        '${reduceMotion ? 'reduced motion' : 'standard motion'}'
        '${narrowPane ? ' · 520 px' : ''}',
      ),
    ),
  );

  static List<DesktopPreviewFact> facts(DesktopPreviewComponent component) =>
      switch (component) {
        DesktopPreviewComponent.block => const [
          DesktopPreviewFact.defaultState,
          DesktopPreviewFact.selected,
          DesktopPreviewFact.running,
          DesktopPreviewFact.failed,
          DesktopPreviewFact.unknown,
        ],
        DesktopPreviewComponent.contextChip => const [
          DesktopPreviewFact.defaultState,
          DesktopPreviewFact.removalUnavailable,
        ],
        DesktopPreviewComponent.candidate || DesktopPreviewComponent.tab =>
          const [DesktopPreviewFact.defaultState, DesktopPreviewFact.selected],
        DesktopPreviewComponent.button => const [
          DesktopPreviewFact.defaultState,
          DesktopPreviewFact.emptyDraft,
          DesktopPreviewFact.submitting,
        ],
        DesktopPreviewComponent.splitter => const [
          DesktopPreviewFact.defaultState,
          DesktopPreviewFact.vertical,
        ],
      };

  String get applicability => switch (component) {
    DesktopPreviewComponent.block =>
      'Hover / press the command title; click to select; Tab reaches actions. '
          'Selection and execution facts are independent. No whole-block disabled state.',
    DesktopPreviewComponent.contextChip =>
      'Hover / hold / Tab exercise the real InputChip. Activate to inspect; delete removes only the source. '
          'No selected state. Removal unavailable still permits inspection.',
    DesktopPreviewComponent.candidate =>
      'Hover highlights a candidate; arrow keys move the same highlight while focus stays in the editor. '
          'Click / Enter accepts into the draft only. Rows have no independent focus or disabled state.',
    DesktopPreviewComponent.button =>
      'Hover / hold / Shift+Tab exercise the real primary action. Pressing without releasing does not submit. '
          'Disabled causes come from the production button tooltip and shell status.',
    DesktopPreviewComponent.tab =>
      'Hover and keyboard focus use distinct production treatments; release / Enter activates. '
          'Selection means active tab. No disabled state or separate pressed colour is implemented.',
    DesktopPreviewComponent.splitter =>
      'Hover / drag and Tab / axis arrow keys use the production resize handle. Press alone does not resize. '
          'Keyboard and accessibility resize use the same local callback. No persistent selected, whole-control disabled or independent pressed state; a boundary disables only its resize action.',
  };

  Widget _fixture() => switch (component) {
    DesktopPreviewComponent.block => TerminalAiComponentFixture(
      component: MobilePrdPreviewComponent.block,
      state: switch (fact) {
        DesktopPreviewFact.selected => MobilePrdPreviewState.selected,
        DesktopPreviewFact.running => MobilePrdPreviewState.loading,
        DesktopPreviewFact.failed => MobilePrdPreviewState.error,
        DesktopPreviewFact.unknown => MobilePrdPreviewState.unknown,
        _ => MobilePrdPreviewState.defaultState,
      },
    ),
    DesktopPreviewComponent.contextChip => TerminalAiComponentFixture(
      component: MobilePrdPreviewComponent.contextChip,
      state: fact == DesktopPreviewFact.removalUnavailable
          ? MobilePrdPreviewState.disabled
          : MobilePrdPreviewState.defaultState,
    ),
    DesktopPreviewComponent.candidate ||
    DesktopPreviewComponent.button => _ComposerFixture(
      scenario: component == DesktopPreviewComponent.candidate
          ? ComposerRedesignScenario.completion
          : switch (fact) {
              DesktopPreviewFact.emptyDraft => ComposerRedesignScenario.empty,
              DesktopPreviewFact.submitting =>
                ComposerRedesignScenario.submitting,
              _ => ComposerRedesignScenario.longPath,
            },
      selectCandidate:
          component == DesktopPreviewComponent.candidate &&
          fact == DesktopPreviewFact.selected,
    ),
    DesktopPreviewComponent.tab => _TabFixture(
      selected: fact == DesktopPreviewFact.selected,
    ),
    DesktopPreviewComponent.splitter => _SplitterFixture(
      direction: fact == DesktopPreviewFact.vertical
          ? Axis.vertical
          : Axis.horizontal,
    ),
  };

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: previewTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        highContrast: highContrast,
        disableAnimations: reduceMotion,
      ),
      child: child!,
    ),
    home: Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Desktop component states'),
                  DropdownButton<DesktopPreviewComponent>(
                    key: const Key('desktop-preview-component'),
                    value: component,
                    items: [
                      for (final item in DesktopPreviewComponent.values)
                        DropdownMenuItem(value: item, child: Text(item.name)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          component = value;
                          fact = DesktopPreviewFact.defaultState;
                        });
                      }
                    },
                  ),
                  DropdownButton<DesktopPreviewFact>(
                    key: const Key('desktop-preview-fact'),
                    value: fact,
                    items: [
                      for (final item in facts(component))
                        DropdownMenuItem(value: item, child: Text(item.name)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => fact = value);
                    },
                  ),
                  TextButton(
                    key: const Key('desktop-preview-reset'),
                    onPressed: () => setState(() => generation++),
                    child: const Text('Reset local fixture'),
                  ),
                  _environmentMenu,
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                applicability,
                key: const Key('desktop-preview-applicability'),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: narrowPane ? 520 : double.infinity,
                  ),
                  child: SizedBox.expand(
                    key: const Key('desktop-preview-fixture-bounds'),
                    child: KeyedSubtree(
                      key: ValueKey((component, fact, generation)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _fixture(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ComposerFixture extends StatefulWidget {
  const _ComposerFixture({
    required this.scenario,
    required this.selectCandidate,
  });
  final ComposerRedesignScenario scenario;
  final bool selectCandidate;

  @override
  State<_ComposerFixture> createState() => _ComposerFixtureState();
}

class _ComposerFixtureState extends State<_ComposerFixture> {
  late final fixture = ComposerRedesignFixture(widget.scenario);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      fixture.activate();
      await Future<void>.delayed(Duration.zero);
      if (mounted && widget.selectCandidate) fixture.revealSelection();
    });
  }

  @override
  void dispose() {
    fixture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: TerminalComposerView(
      controller: fixture.controller,
      targetLabel: fixture.targetLabel,
      autofocus: widget.scenario == ComposerRedesignScenario.completion,
      onUseTerminal: () {},
    ),
  );
}

class _TabFixture extends StatefulWidget {
  const _TabFixture({required this.selected});
  final bool selected;
  @override
  State<_TabFixture> createState() => _TabFixtureState();
}

class _TabFixtureState extends State<_TabFixture> {
  final focus = FocusNode(debugLabel: 'Preview production tab');
  late bool selected = widget.selected;
  int activations = 0;
  int closes = 0;
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 320,
        height: 44,
        child: ShellTabComponentPreview(
          tab: const TerminalTab(
            sessionId: 'catalogue-tab',
            title: 'Build · staging',
            profileId: 'fixture',
          ),
          selected: selected,
          focusNode: focus,
          onActivate: () => setState(() {
            selected = true;
            activations++;
          }),
          onClose: () => setState(() => closes++),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Local activations: $activations · close callbacks: $closes',
        key: const Key('desktop-preview-tab-events'),
      ),
    ],
  );
}

class _SplitterFixture extends StatefulWidget {
  const _SplitterFixture({required this.direction});
  final Axis direction;
  @override
  State<_SplitterFixture> createState() => _SplitterFixtureState();
}

class _SplitterFixtureState extends State<_SplitterFixture> {
  double delta = 0;
  final focus = FocusNode(debugLabel: 'Preview production splitter');

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Local resize delta: ${delta.toStringAsFixed(1)}',
        key: const Key('desktop-preview-split-events'),
      ),
      const SizedBox(height: 16),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = widget.direction == Axis.horizontal;
            final extent = horizontal
                ? constraints.maxWidth
                : constraints.maxHeight;
            final available = (extent - 10).clamp(0.0, double.infinity);
            double constrainedDelta(double value) =>
                value.clamp(-extent / 3, extent / 3);
            double leadingFor(double value) =>
                (available / 2 + constrainedDelta(value)).clamp(0.0, available);
            double ratioFor(double value) =>
                available == 0 ? 0 : leadingFor(value) / available;
            final leading = leadingFor(delta);
            return Flex(
              direction: widget.direction,
              children: [
                SizedBox(
                  width: horizontal ? leading : null,
                  height: horizontal ? null : leading,
                  child: const Center(child: Text('Pane A')),
                ),
                ShellDividerComponentPreview(
                  key: const Key('desktop-preview-splitter'),
                  direction: widget.direction,
                  focusNode: focus,
                  ratio: ratioFor(delta),
                  increasedRatio: ratioFor(delta + 10),
                  decreasedRatio: ratioFor(delta - 10),
                  onDragUpdate: (value) =>
                      setState(() => delta = constrainedDelta(delta + value)),
                ),
                const Expanded(child: Center(child: Text('Pane B'))),
              ],
            );
          },
        ),
      ),
    ],
  );
}
