import 'package:app/features/profiles/profile_editor.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

void main() {
  testWidgets(
    'profile editor seeds nested terminal fields and saves structured changes',
    (tester) async {
      const initialProfile = TerminalProfile.configured(
        id: 'default',
        name: 'Local Shell',
        tags: ['work', 'prod'],
        sessionConfig: terminal.TerminalSessionConfig(
          launch: terminal.TerminalLaunchConfig(
            program: '/bin/bash',
            args: ['-lc', 'printf hello'],
            env: {'TERM_PROGRAM': 'ianvs terminal'},
            cwd: '/tmp',
          ),
          emulation: TerminalEmulation.vt220,
          scrollbackLines: 4096,
          display: terminal.TerminalDisplayConfig(
            font: terminal.TerminalFontConfig(
              family: 'Menlo',
              fallback: ['Monaco', 'Apple Symbols'],
              size: 13.5,
              lineHeight: 1.4,
            ),
            colors: terminal.TerminalColorPalette(
              special: terminal.TerminalSpecialColors(
                foreground: '#AABBCC',
                background: '#101112',
                cursor: '#778899',
                selection: '#334455',
                tab: '#335577',
              ),
              normal: terminal.TerminalAnsiColors(
                red: '#AA5500',
                blue: '#3355AA',
              ),
              bright: terminal.TerminalAnsiColors(
                yellow: '#FFCC33',
                cyan: '#77DDFF',
              ),
            ),
            cursor: terminal.TerminalCursorConfig(
              shape: TerminalCursorShape.beam,
              blink: false,
            ),
          ),
          interaction: terminal.TerminalInteractionConfig(
            copyOnSelect: true,
            optionDragMode: TerminalOptionDragMode.normalSelection,
          ),
        ),
      );

      TerminalProfile? savedProfile;
      await _pumpEditorHarness(
        tester,
        initialValue: initialProfile,
        onSaved: (value) => savedProfile = value,
      );

      expect(
        tester
            .widget<TextFormField>(_findByKey(const Key('profile-editor-name')))
            .controller!
            .text,
        'Local Shell',
      );
      expect(
        tester
            .widget<TextFormField>(_findByKey(const Key('profile-editor-tags')))
            .controller!
            .text,
        'work, prod',
      );
      expect(
        tester
            .widget<TextFormField>(
              _findByKey(const Key('profile-editor-shell')),
            )
            .controller!
            .text,
        '/bin/bash',
      );
      expect(find.text('Colors', skipOffstage: false), findsOneWidget);
      expect(find.text('Special', skipOffstage: false), findsOneWidget);
      expect(find.text('ANSI normal', skipOffstage: false), findsOneWidget);
      expect(find.text('ANSI bright', skipOffstage: false), findsOneWidget);
      expect(find.text('Cursor', skipOffstage: false), findsOneWidget);
      expect(find.text('Keys'), findsAtLeastNWidgets(1));
      expect(find.text('Advanced'), findsAtLeastNWidgets(1));
      expect(find.text('VT220', skipOffstage: false), findsOneWidget);
      expect(find.text('Beam', skipOffstage: false), findsOneWidget);
      for (final fieldKey in _allColorFieldKeys) {
        expect(_findByKey(Key(fieldKey)), findsOneWidget);
      }
      expect(
        tester.getSize(_findByKey(const Key('profile-editor-save'))).height,
        36,
      );
      final shellFieldHeight = tester
          .getSize(_findByKey(const Key('profile-editor-shell')))
          .height;
      expect(
        tester.getSize(_findByKey(const Key('profile-editor-name'))).height,
        greaterThanOrEqualTo(64),
      );
      expect(shellFieldHeight, greaterThanOrEqualTo(64));
      expect(
        tester.getSize(_findByKey(const Key('profile-editor-add-arg'))).height,
        32,
      );

      await tester.enterText(
        _findByKey(const Key('profile-editor-name')),
        'Workspace Shell',
      );
      await tester.enterText(
        _findByKey(const Key('profile-editor-tags')),
        'work, staging, staging',
      );
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-shell')),
      );
      await tester.enterText(
        _findByKey(const Key('profile-editor-shell')),
        '/bin/fish',
      );
      await tester.enterText(_findByKey(const Key('profile-editor-cwd')), '');

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-arg-0-down')),
      );
      await tester.tap(_findByKey(const Key('profile-editor-arg-0-down')));
      await tester.pump();
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-add-arg')),
      );
      await tester.tap(_findByKey(const Key('profile-editor-add-arg')));
      await tester.pump();
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-arg-2')),
      );
      await tester.enterText(
        _findByKey(const Key('profile-editor-arg-2')),
        '--login',
      );

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-add-env')),
      );
      await tester.tap(_findByKey(const Key('profile-editor-add-env')));
      await tester.pump();
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-env-key-1')),
      );
      await tester.enterText(
        _findByKey(const Key('profile-editor-env-key-1')),
        'COLORTERM',
      );
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-env-value-1')),
      );
      await tester.enterText(
        _findByKey(const Key('profile-editor-env-value-1')),
        'truecolor',
      );

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-emulation')),
      );
      await tester.tap(_findByKey(const Key('profile-editor-emulation')));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(_findByKey(const Key('profile-editor-emulation')))
            .height,
        greaterThanOrEqualTo(shellFieldHeight),
      );
      await tester.tap(find.text('xterm-256color').last);
      await tester.pumpAndSettle();
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-scrollback')),
      );
      await tester.enterText(
        _findByKey(const Key('profile-editor-scrollback')),
        '12000',
      );
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-shell-integration')),
      );
      await tester.tap(
        _findByKey(const Key('profile-editor-shell-integration')),
      );
      await tester.pump();

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-font-family')),
      );
      await tester.enterText(
        _findByKey(const Key('profile-editor-font-family')),
        'JetBrainsMono Nerd Font Mono',
      );
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-fallback-1-remove')),
      );
      expect(
        tester
            .getSize(_findByKey(const Key('profile-editor-fallback-1-remove')))
            .height,
        28,
      );
      await tester.tap(
        _findByKey(const Key('profile-editor-fallback-1-remove')),
      );
      await tester.pump();
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-add-fallback')),
      );
      await tester.tap(_findByKey(const Key('profile-editor-add-fallback')));
      await tester.pump();
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-fallback-1')),
      );
      await tester.enterText(
        _findByKey(const Key('profile-editor-fallback-1')),
        'Menlo',
      );
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-font-size')),
      );
      await tester.enterText(
        _findByKey(const Key('profile-editor-font-size')),
        '15',
      );
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-font-line-height')),
      );
      await tester.enterText(
        _findByKey(const Key('profile-editor-font-line-height')),
        '1.6',
      );

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-color-foreground')),
      );
      expect(
        tester.getSize(
          _findByKey(const Key('profile-editor-swatch-foreground')),
        ),
        const Size(30, 30),
      );
      await tester.enterText(
        _findByKey(const Key('profile-editor-color-foreground')),
        '112233',
      );
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-color-background')),
      );
      await tester.tap(
        _findByKey(const Key('profile-editor-color-background')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getCenter(_findByKey(const Key('profile-editor-pick-background')))
            .dy,
        closeTo(
          tester
              .getCenter(
                _findByKey(const Key('profile-editor-swatch-background')),
              )
              .dy,
          6,
        ),
      );
      final dialogRect = tester.getRect(
        _findByKey(const Key('profile-editor-dialog')),
      );
      final backgroundSwatchRect = tester.getRect(
        _findByKey(const Key('profile-editor-swatch-background')),
      );
      expect(
        dialogRect.right - backgroundSwatchRect.right,
        greaterThanOrEqualTo(20),
      );
      expect(
        tester
            .widget<TextFormField>(
              _findByKey(const Key('profile-editor-color-foreground')),
            )
            .controller!
            .text,
        '#112233',
      );
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-color-cursor')),
      );
      await tester.enterText(
        _findByKey(const Key('profile-editor-color-cursor')),
        '',
      );
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-color-selection')),
      );
      await tester.enterText(
        _findByKey(const Key('profile-editor-color-selection')),
        '#445566',
      );
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-color-tab')),
      );
      await tester.enterText(
        _findByKey(const Key('profile-editor-color-tab')),
        '#556677',
      );
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-color-normal-red')),
      );
      await tester.enterText(
        _findByKey(const Key('profile-editor-color-normal-red')),
        '#BB5500',
      );
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-color-bright-blue')),
      );
      await tester.enterText(
        _findByKey(const Key('profile-editor-color-bright-blue')),
        '#55AAFF',
      );

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-cursor-shape')),
      );
      final cursorShapeRect = tester.getRect(
        _findByKey(const Key('profile-editor-cursor-shape')),
      );
      expect(
        dialogRect.right - cursorShapeRect.right,
        greaterThanOrEqualTo(20),
      );
      await tester.tap(_findByKey(const Key('profile-editor-cursor-shape')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block').last);
      await tester.pumpAndSettle();
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-cursor-blink')),
      );
      expect(
        tester
            .getSize(_findByKey(const Key('profile-editor-cursor-blink')))
            .height,
        lessThanOrEqualTo(42),
      );
      await tester.tap(_findByKey(const Key('profile-editor-cursor-blink')));
      await tester.pump();

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-copy-on-select')),
      );
      await tester.tap(_findByKey(const Key('profile-editor-copy-on-select')));
      await tester.pump();
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-option-drag-blockSelection')),
      );
      await tester.tap(
        _findByKey(const Key('profile-editor-option-drag-blockSelection')),
      );
      await tester.pump();
      final blockSelectionTile = tester.widget<RadioListTile<Object?>>(
        _findByKey(const Key('profile-editor-option-drag-blockSelection')),
      );
      expect(blockSelectionTile.contentPadding, EdgeInsets.zero);

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-save')),
      );
      await tester.tap(_findByKey(const Key('profile-editor-save')));
      await tester.pumpAndSettle();

      expect(savedProfile, isNotNull);
      expect(savedProfile!.name, 'Workspace Shell');
      expect(savedProfile!.tags, const ['work', 'staging']);
      expect(savedProfile!.shell, '/bin/fish');
      expect(savedProfile!.cwd, isNull);
      expect(savedProfile!.args, ['printf hello', '-lc', '--login']);
      expect(savedProfile!.env, {
        'TERM_PROGRAM': 'ianvs terminal',
        'COLORTERM': 'truecolor',
      });
      expect(savedProfile!.terminalEmulation, TerminalEmulation.xterm256);
      expect(savedProfile!.scrollbackLines, 12000);
      expect(savedProfile!.sessionConfig.shellIntegration.enabled, isFalse);
      expect(
        savedProfile!.appearance.font.family,
        'JetBrainsMono Nerd Font Mono',
      );
      expect(savedProfile!.appearance.font.fallback, ['Monaco', 'Menlo']);
      expect(savedProfile!.appearance.font.size, 15);
      expect(savedProfile!.appearance.font.lineHeight, 1.6);
      expect(savedProfile!.appearance.colors.foreground, '#112233');
      expect(savedProfile!.appearance.colors.background, '#101112');
      expect(savedProfile!.appearance.colors.cursor, isNull);
      expect(savedProfile!.appearance.colors.selection, '#445566');
      expect(savedProfile!.appearance.colors.tab, '#556677');
      expect(savedProfile!.appearance.colors.normal.red, '#BB5500');
      expect(savedProfile!.appearance.colors.normal.blue, '#3355AA');
      expect(savedProfile!.appearance.colors.bright.blue, '#55AAFF');
      expect(savedProfile!.appearance.colors.bright.yellow, '#FFCC33');
      expect(savedProfile!.appearance.cursor.shape, TerminalCursorShape.block);
      expect(savedProfile!.appearance.cursor.blink, isTrue);
      expect(savedProfile!.interaction.copyOnSelect, isFalse);
      expect(
        savedProfile!.interaction.optionDragMode,
        TerminalOptionDragMode.blockSelection,
      );
    },
  );

  testWidgets('profile editor groups controls under the profile hierarchy', (
    tester,
  ) async {
    await _pumpEditorHarness(
      tester,
      initialValue: TerminalProfile(
        id: 'default',
        name: 'Local Shell',
        shell: '/bin/zsh',
      ),
      onSaved: (_) {},
    );

    _expectDescendant(
      const Key('profile-editor-section-identity'),
      const Key('profile-editor-name'),
    );
    _expectDescendant(
      const Key('profile-editor-section-identity'),
      const Key('profile-editor-tags'),
    );
    _expectDescendant(
      const Key('profile-editor-section-startup'),
      const Key('profile-editor-group-command'),
    );
    _expectDescendant(
      const Key('profile-editor-group-command'),
      const Key('profile-editor-shell'),
    );
    _expectDescendant(
      const Key('profile-editor-group-launch-data'),
      const Key('profile-editor-add-arg'),
    );
    _expectDescendant(
      const Key('profile-editor-group-launch-data'),
      const Key('profile-editor-add-env'),
    );
    _expectDescendant(
      const Key('profile-editor-section-automation'),
      const Key('profile-editor-triggers'),
    );
    _expectDescendant(
      const Key('profile-editor-section-automation'),
      const Key('profile-editor-switch-rules'),
    );
    _expectDescendant(
      const Key('profile-editor-section-terminal'),
      const Key('profile-editor-emulation'),
    );
    _expectDescendant(
      const Key('profile-editor-section-advanced'),
      const Key('profile-editor-shell-integration'),
    );
    _expectDescendant(
      const Key('profile-editor-section-appearance'),
      const Key('profile-editor-font-family'),
    );
    _expectDescendant(
      const Key('profile-editor-section-appearance'),
      const Key('profile-editor-theme-presets'),
    );
    _expectDescendant(
      const Key('profile-editor-group-cursor'),
      const Key('profile-editor-cursor-shape'),
    );
    _expectDescendant(
      const Key('profile-editor-section-keys'),
      const Key('profile-editor-copy-on-select'),
    );

    expect(find.text('General'), findsAtLeastNWidgets(1));
    expect(find.text('Startup'), findsAtLeastNWidgets(1));
    expect(find.text('Terminal'), findsAtLeastNWidgets(1));
    expect(find.text('Appearance'), findsAtLeastNWidgets(1));
    expect(find.text('Keys'), findsAtLeastNWidgets(1));
    expect(find.text('Automation'), findsAtLeastNWidgets(1));
    expect(find.text('Advanced'), findsAtLeastNWidgets(1));
    expect(
      find.text('Existing sessions do not hot-update after profile edits.'),
      findsNothing,
    );
    for (final section in [
      'general',
      'startup',
      'terminal',
      'appearance',
      'keys',
      'automation',
      'advanced',
    ]) {
      expect(_findByKey(Key('profile-editor-nav-$section')), findsOneWidget);
    }
  });

  testWidgets(
    'profile editor uses a wide section rail and aligned color controls',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 820);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpEditorHarness(
        tester,
        initialValue: TerminalProfile(
          id: 'default',
          name: 'Local Shell',
          shell: '/bin/zsh',
        ),
        onSaved: (_) {},
      );

      final dialog = _findByKey(const Key('profile-editor-dialog'));
      final generalNav = _findByKey(const Key('profile-editor-nav-general'));
      final nameField = _findByKey(const Key('profile-editor-name'));
      expect(tester.getSize(dialog).width, greaterThanOrEqualTo(940));
      expect(
        tester.getTopLeft(generalNav).dx,
        lessThan(tester.getTopLeft(nameField).dx),
      );

      await tester.tap(_findByKey(const Key('profile-editor-nav-appearance')));
      await tester.pumpAndSettle();
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-color-foreground')),
      );

      final labelLeft = tester.getTopLeft(find.text('Foreground')).dx;
      final fieldLeft = tester
          .getTopLeft(_findByKey(const Key('profile-editor-color-foreground')))
          .dx;
      final swatchLeft = tester
          .getTopLeft(_findByKey(const Key('profile-editor-swatch-foreground')))
          .dx;
      final pickLeft = tester
          .getTopLeft(_findByKey(const Key('profile-editor-pick-foreground')))
          .dx;
      final resetLeft = tester
          .getTopLeft(_findByKey(const Key('profile-editor-reset-foreground')))
          .dx;
      expect(labelLeft, lessThan(fieldLeft));
      expect(fieldLeft, lessThan(swatchLeft));
      expect(swatchLeft, lessThan(pickLeft));
      expect(pickLeft, lessThan(resetLeft));
    },
  );

  testWidgets('profile editor section navigation jumps to deep sections', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 820);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _pumpEditorHarness(
      tester,
      initialValue: TerminalProfile(
        id: 'default',
        name: 'Local Shell',
        shell: '/bin/zsh',
      ),
      onSaved: (_) {},
    );

    expect(
      _findByKey(const Key('profile-editor-section-nav')),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.byKey(const Key('profile-editor-section-general')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('profile-editor-section-startup')),
      findsNothing,
    );

    await tester.tap(_findByKey(const Key('profile-editor-nav-advanced')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('profile-editor-section-general')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('profile-editor-section-advanced')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('profile-editor-section-automation')),
      findsNothing,
    );

    final advancedTop = tester
        .getTopLeft(_findByKey(const Key('profile-editor-section-advanced')))
        .dy;
    final footerTop =
        tester.getTopLeft(_findByKey(const Key('profile-editor-save'))).dy - 12;
    expect(advancedTop, greaterThan(0));
    expect(advancedTop, lessThan(footerTop));

    await tester.tap(_findByKey(const Key('profile-editor-nav-appearance')));
    await tester.pumpAndSettle();

    final appearanceTop = tester
        .getTopLeft(_findByKey(const Key('profile-editor-section-appearance')))
        .dy;
    expect(appearanceTop, greaterThan(0));
    expect(appearanceTop, lessThan(footerTop));
  });

  testWidgets('profile editor search filters and jumps to matching sections', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 820);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    TerminalProfile? savedProfile;
    await _pumpEditorHarness(
      tester,
      initialValue: TerminalProfile(
        id: 'default',
        name: 'Local Shell',
        shell: '/bin/zsh',
      ),
      onSaved: (value) => savedProfile = value,
    );

    final searchField = _findByKey(const Key('profile-editor-section-search'));
    expect(searchField, findsOneWidget);

    await tester.enterText(searchField, 'font');
    await tester.pumpAndSettle();

    expect(
      _findByKey(const Key('profile-editor-nav-appearance')),
      findsOneWidget,
    );
    expect(_findByKey(const Key('profile-editor-nav-general')), findsNothing);
    expect(find.text('1 section found'), findsOneWidget);

    await tester.tap(_findByKey(const Key('profile-editor-nav-appearance')));
    await tester.pumpAndSettle();

    final appearanceTop = tester
        .getTopLeft(_findByKey(const Key('profile-editor-section-appearance')))
        .dy;
    final footerTop =
        tester.getTopLeft(_findByKey(const Key('profile-editor-save'))).dy - 12;
    expect(appearanceTop, greaterThan(0));
    expect(appearanceTop, lessThan(footerTop));

    await tester.enterText(searchField, 'profile switching');
    await tester.pumpAndSettle();

    expect(
      _findByKey(const Key('profile-editor-nav-automation')),
      findsOneWidget,
    );
    expect(
      _findByKey(const Key('profile-editor-nav-appearance')),
      findsNothing,
    );
    expect(find.text('1 section found'), findsOneWidget);

    await tester.enterText(searchField, 'not-a-setting');
    await tester.pumpAndSettle();

    expect(
      _findByKey(const Key('profile-editor-section-search-empty')),
      findsOneWidget,
    );
    expect(find.text('No settings found'), findsOneWidget);

    await tester.tap(
      _findByKey(const Key('profile-editor-section-search-clear')),
    );
    await tester.pumpAndSettle();

    expect(_findByKey(const Key('profile-editor-nav-general')), findsOneWidget);
    expect(
      _findByKey(const Key('profile-editor-nav-advanced')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Close profile editor'));
    await tester.pumpAndSettle();

    expect(find.text('Discard profile changes?'), findsNothing);
    expect(_findByKey(const Key('profile-editor-dialog')), findsNothing);
    expect(savedProfile, isNull);
  });

  testWidgets(
    'profile editor exposes focused semantics and keyboard section traversal',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 820);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpEditorHarness(
        tester,
        initialValue: TerminalProfile(
          id: 'default',
          name: 'Local Shell',
          shell: '/bin/zsh',
        ),
        onSaved: (_) {},
      );

      expect(
        find.bySemanticsIdentifier('profile-editor-dialog'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('profile-editor-section-nav'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.bySemanticsIdentifier('profile-editor-nav-general'),
        ),
        matchesSemantics(
          label: 'General profile section',
          hasSelectedState: true,
          isSelected: true,
          isButton: true,
          hasTapAction: true,
        ),
      );

      final searchField = _findByKey(
        const Key('profile-editor-section-search'),
      );
      await tester.tap(searchField);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(
          find.bySemanticsIdentifier('profile-editor-nav-startup'),
        ),
        matchesSemantics(
          label: 'Startup profile section',
          hasSelectedState: true,
          isSelected: true,
          isButton: true,
          hasTapAction: true,
        ),
      );
    },
  );

  testWidgets('profile editor summarizes and resets dirty sections', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 820);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _pumpEditorHarness(
      tester,
      initialValue: TerminalProfile(
        id: 'default',
        name: 'Local Shell',
        shell: '/bin/zsh',
      ),
      onSaved: (_) {},
    );

    expect(_findByKey(const Key('profile-editor-dirty-summary')), findsNothing);

    await tester.enterText(
      _findByKey(const Key('profile-editor-name')),
      'Work Shell',
    );
    await tester.pumpAndSettle();

    expect(find.text('1 modified section'), findsOneWidget);
    expect(
      _findByKey(const Key('profile-editor-reset-general')),
      findsOneWidget,
    );

    await tester.enterText(
      _findByKey(const Key('profile-editor-section-search')),
      'font',
    );
    await tester.pumpAndSettle();
    await tester.tap(_findByKey(const Key('profile-editor-nav-appearance')));
    await tester.pumpAndSettle();
    await _ensureVisible(
      tester,
      _findByKey(const Key('profile-editor-font-family')),
    );
    final initialFontFamily = tester
        .widget<TextFormField>(
          _findByKey(const Key('profile-editor-font-family')),
        )
        .controller!
        .text;
    await tester.enterText(
      _findByKey(const Key('profile-editor-font-family')),
      'Fira Code',
    );
    await tester.pumpAndSettle();

    expect(find.text('2 modified sections'), findsOneWidget);
    expect(
      _findByKey(const Key('profile-editor-reset-appearance')),
      findsOneWidget,
    );

    await tester.tap(_findByKey(const Key('profile-editor-reset-appearance')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(
            _findByKey(const Key('profile-editor-font-family')),
          )
          .controller!
          .text,
      initialFontFamily,
    );
    expect(find.text('1 modified section'), findsOneWidget);

    await tester.tap(
      _findByKey(const Key('profile-editor-section-search-clear')),
    );
    await tester.pumpAndSettle();
    await tester.tap(_findByKey(const Key('profile-editor-reset-general')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(_findByKey(const Key('profile-editor-name')))
          .controller!
          .text,
      'Local Shell',
    );
    expect(_findByKey(const Key('profile-editor-dirty-summary')), findsNothing);

    await tester.tap(find.byTooltip('Close profile editor'));
    await tester.pumpAndSettle();

    expect(find.text('Discard profile changes?'), findsNothing);
    expect(_findByKey(const Key('profile-editor-dialog')), findsNothing);
  });

  testWidgets('profile editor saves notification and send-text triggers', (
    tester,
  ) async {
    final initialProfile = TerminalProfile(
      id: 'default',
      name: 'Local Shell',
      shell: '/bin/zsh',
      triggers: const [TerminalProfileTrigger(pattern: 'ERROR')],
    );

    TerminalProfile? savedProfile;
    await _pumpEditorHarness(
      tester,
      initialValue: initialProfile,
      onSaved: (value) => savedProfile = value,
    );

    expect(
      tester
          .widget<TextFormField>(
            _findByKey(const Key('profile-editor-triggers')),
          )
          .controller!
          .text,
      'ERROR => notify',
    );

    await tester.enterText(
      _findByKey(const Key('profile-editor-triggers')),
      'WARN[0-9]+ => notify\nPassword: => send: secret\\n',
    );
    await _ensureVisible(tester, _findByKey(const Key('profile-editor-save')));
    await tester.tap(_findByKey(const Key('profile-editor-save')));
    await tester.pumpAndSettle();

    expect(savedProfile, isNotNull);
    expect(savedProfile!.triggers, const [
      TerminalProfileTrigger(pattern: 'WARN[0-9]+'),
      TerminalProfileTrigger(
        pattern: 'Password:',
        action: TerminalProfileTriggerAction.sendText,
        value: 'secret\n',
      ),
    ]);
  });

  testWidgets('profile editor saves automatic profile switching rules', (
    tester,
  ) async {
    final initialProfile = TerminalProfile(
      id: 'prod',
      name: 'Production',
      shell: '/bin/zsh',
      switchRules: const [
        TerminalProfileSwitchRule(
          kind: TerminalProfileSwitchRuleKind.hostname,
          pattern: '*.prod.example.com',
        ),
      ],
    );

    TerminalProfile? savedProfile;
    await _pumpEditorHarness(
      tester,
      initialValue: initialProfile,
      onSaved: (value) => savedProfile = value,
    );

    expect(
      tester
          .widget<TextFormField>(
            _findByKey(const Key('profile-editor-switch-rules')),
          )
          .controller!
          .text,
      'host: *.prod.example.com',
    );

    await tester.enterText(
      _findByKey(const Key('profile-editor-switch-rules')),
      'user: root\ndir: /srv/app',
    );
    await _ensureVisible(tester, _findByKey(const Key('profile-editor-save')));
    await tester.tap(_findByKey(const Key('profile-editor-save')));
    await tester.pumpAndSettle();

    expect(savedProfile, isNotNull);
    expect(savedProfile!.switchRules, const [
      TerminalProfileSwitchRule(
        kind: TerminalProfileSwitchRuleKind.username,
        pattern: 'root',
      ),
      TerminalProfileSwitchRule(
        kind: TerminalProfileSwitchRuleKind.directory,
        pattern: '/srv/app',
      ),
    ]);
  });

  testWidgets('profile editor blocks metadata collections above limits', (
    tester,
  ) async {
    TerminalProfile? savedProfile;
    await _pumpEditorHarness(
      tester,
      initialValue: TerminalProfile(
        id: 'default',
        name: 'Local Shell',
        shell: '/bin/zsh',
      ),
      onSaved: (value) => savedProfile = value,
    );

    await tester.enterText(
      _findByKey(const Key('profile-editor-tags')),
      [
        for (var index = 0; index < maxTerminalProfileTags + 1; index += 1)
          'tag-$index',
      ].join(', '),
    );
    await tester.enterText(
      _findByKey(const Key('profile-editor-triggers')),
      [
        for (var index = 0; index < maxTerminalProfileTriggers + 1; index += 1)
          'TRIGGER_$index => notify',
      ].join('\n'),
    );
    await tester.enterText(
      _findByKey(const Key('profile-editor-switch-rules')),
      [
        for (
          var index = 0;
          index < maxTerminalProfileSwitchRules + 1;
          index += 1
        )
          'host: host-$index.example.com',
      ].join('\n'),
    );

    await _ensureVisible(tester, _findByKey(const Key('profile-editor-save')));
    await tester.tap(_findByKey(const Key('profile-editor-save')));
    await tester.pumpAndSettle();

    expect(savedProfile, isNull);
    expect(
      find.text(
        'Use $maxTerminalProfileTags tags or fewer.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Use $maxTerminalProfileTriggers triggers or fewer.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Use $maxTerminalProfileSwitchRules switching rules or fewer.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'profile editor blocks launch and font collections above limits',
    (tester) async {
      TerminalProfile? savedProfile;
      await _pumpEditorHarness(
        tester,
        initialValue: TerminalProfile(
          id: 'default',
          name: 'Local Shell',
          shell: '/bin/zsh',
          args: [
            for (var index = 0; index < maxTerminalLaunchArgs + 1; index += 1)
              'arg-$index',
          ],
          appearance: terminal.TerminalDisplayConfig(
            font: terminal.TerminalFontConfig(
              fallback: [
                for (
                  var index = 0;
                  index < maxTerminalFontFallbackFamilies + 1;
                  index += 1
                )
                  'Font $index',
              ],
            ),
          ),
        ),
        onSaved: (value) => savedProfile = value,
      );

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-save')),
      );
      await tester.tap(_findByKey(const Key('profile-editor-save')));
      await tester.pumpAndSettle();

      expect(savedProfile, isNull);
      expect(
        find.text(
          'Use $maxTerminalLaunchArgs arguments or fewer.',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Use $maxTerminalFontFallbackFamilies fallback fonts or fewer.',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('profile editor blocks invalid values and duplicate env keys', (
    tester,
  ) async {
    TerminalProfile? savedProfile;
    await _pumpEditorHarness(
      tester,
      initialValue: TerminalProfile(
        id: 'default',
        name: 'Local Shell',
        shell: '/bin/zsh',
      ),
      onSaved: (value) => savedProfile = value,
    );

    await _ensureVisible(
      tester,
      _findByKey(const Key('profile-editor-add-env')),
    );
    await tester.tap(_findByKey(const Key('profile-editor-add-env')));
    await tester.pump();
    await _ensureVisible(
      tester,
      _findByKey(const Key('profile-editor-add-env')),
    );
    await tester.tap(_findByKey(const Key('profile-editor-add-env')));
    await tester.pump();
    await _ensureVisible(
      tester,
      _findByKey(const Key('profile-editor-env-key-0')),
    );
    await tester.enterText(
      _findByKey(const Key('profile-editor-env-key-0')),
      'TERM',
    );
    await _ensureVisible(
      tester,
      _findByKey(const Key('profile-editor-env-key-1')),
    );
    await tester.enterText(
      _findByKey(const Key('profile-editor-env-key-1')),
      'TERM',
    );

    await tester.enterText(_findByKey(const Key('profile-editor-name')), '');
    await tester.enterText(_findByKey(const Key('profile-editor-shell')), '');
    await _ensureVisible(
      tester,
      _findByKey(const Key('profile-editor-scrollback')),
    );
    await tester.enterText(
      _findByKey(const Key('profile-editor-scrollback')),
      '0',
    );
    await _ensureVisible(
      tester,
      _findByKey(const Key('profile-editor-font-size')),
    );
    await tester.enterText(
      _findByKey(const Key('profile-editor-font-size')),
      '0',
    );
    await _ensureVisible(
      tester,
      _findByKey(const Key('profile-editor-font-line-height')),
    );
    await tester.enterText(
      _findByKey(const Key('profile-editor-font-line-height')),
      '-1',
    );
    await _ensureVisible(
      tester,
      _findByKey(const Key('profile-editor-color-foreground')),
    );
    await tester.enterText(
      _findByKey(const Key('profile-editor-color-foreground')),
      'red',
    );

    await _ensureVisible(tester, _findByKey(const Key('profile-editor-save')));
    await tester.tap(_findByKey(const Key('profile-editor-save')));
    await tester.pumpAndSettle();

    expect(savedProfile, isNull);
    expect(find.text('Name is required', skipOffstage: false), findsOneWidget);
    expect(find.text('Shell is required', skipOffstage: false), findsOneWidget);
    expect(
      find.text(
        'Scrollback lines must be a positive integer',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.text('Font size must be greater than 0', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Line height must be greater than 0', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Use #RRGGBB or leave empty.', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Key must be unique', skipOffstage: false),
      findsNWidgets(2),
    );
    expect(_findByKey(const Key('profile-editor-dialog')), findsOneWidget);
  });

  testWidgets('profile editor rejects non-finite typography values', (
    tester,
  ) async {
    TerminalProfile? savedProfile;
    await _pumpEditorHarness(
      tester,
      initialValue: TerminalProfile(
        id: 'default',
        name: 'Local Shell',
        shell: '/bin/zsh',
      ),
      onSaved: (value) => savedProfile = value,
    );

    await _ensureVisible(
      tester,
      _findByKey(const Key('profile-editor-font-size')),
    );
    await tester.enterText(
      _findByKey(const Key('profile-editor-font-size')),
      'NaN',
    );
    await _ensureVisible(
      tester,
      _findByKey(const Key('profile-editor-font-line-height')),
    );
    await tester.enterText(
      _findByKey(const Key('profile-editor-font-line-height')),
      'Infinity',
    );

    await _ensureVisible(tester, _findByKey(const Key('profile-editor-save')));
    await tester.tap(_findByKey(const Key('profile-editor-save')));
    await tester.pumpAndSettle();

    expect(savedProfile, isNull);
    expect(find.text('Font size must be greater than 0'), findsOneWidget);
    expect(find.text('Line height must be greater than 0'), findsOneWidget);
    expect(_findByKey(const Key('profile-editor-dialog')), findsOneWidget);
  });

  testWidgets('profile editor rejects excessive scrollback retention', (
    tester,
  ) async {
    TerminalProfile? savedProfile;
    await _pumpEditorHarness(
      tester,
      initialValue: TerminalProfile(
        id: 'default',
        name: 'Local Shell',
        shell: '/bin/zsh',
      ),
      onSaved: (value) => savedProfile = value,
    );

    await _ensureVisible(
      tester,
      _findByKey(const Key('profile-editor-scrollback')),
    );
    await tester.enterText(
      _findByKey(const Key('profile-editor-scrollback')),
      '${terminal.maxTerminalScrollbackLines + 1}',
    );
    await _ensureVisible(tester, _findByKey(const Key('profile-editor-save')));
    await tester.tap(_findByKey(const Key('profile-editor-save')));
    await tester.pumpAndSettle();

    expect(savedProfile, isNull);
    expect(
      find.text(
        'Scrollback lines must be ${terminal.maxTerminalScrollbackLines} or less',
      ),
      findsOneWidget,
    );
    expect(_findByKey(const Key('profile-editor-dialog')), findsOneWidget);
  });

  testWidgets('profile editor confirms before discarding unsaved changes', (
    tester,
  ) async {
    TerminalProfile? savedProfile;
    await _pumpEditorHarness(
      tester,
      initialValue: TerminalProfile(
        id: 'default',
        name: 'Local Shell',
        shell: '/bin/zsh',
      ),
      onSaved: (value) => savedProfile = value,
    );

    await tester.enterText(
      _findByKey(const Key('profile-editor-name')),
      'Edited Shell',
    );
    await tester.tap(find.byTooltip('Close profile editor'));
    await tester.pumpAndSettle();

    expect(
      _findByKey(const Key('profile-editor-discard-dialog')),
      findsOneWidget,
    );

    await tester.tap(_findByKey(const Key('profile-editor-discard-cancel')));
    await tester.pumpAndSettle();

    expect(_findByKey(const Key('profile-editor-dialog')), findsOneWidget);
    expect(savedProfile, isNull);

    await tester.tap(_findByKey(const Key('profile-editor-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(_findByKey(const Key('profile-editor-discard-confirm')));
    await tester.pumpAndSettle();

    expect(_findByKey(const Key('profile-editor-dialog')), findsNothing);
    expect(savedProfile, isNull);
  });

  testWidgets(
    'profile editor color picker uses palette controls and resets the color field',
    (tester) async {
      TerminalProfile? savedProfile;
      await _pumpEditorHarness(
        tester,
        initialValue: TerminalProfile(
          id: 'default',
          name: 'Local Shell',
          shell: '/bin/zsh',
        ),
        onSaved: (value) => savedProfile = value,
      );

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-swatch-foreground')),
      );
      await tester.tap(
        _findByKey(const Key('profile-editor-swatch-foreground')),
      );
      await tester.pumpAndSettle();
      expect(_findByKey(const Key('color-picker-dialog')), findsOneWidget);
      expect(_findByKey(const Key('color-picker-palette')), findsOneWidget);
      expect(_findByKey(const Key('color-picker-hue-slider')), findsOneWidget);
      expect(_findByKey(const Key('color-picker-red')), findsNothing);
      expect(_findByKey(const Key('color-picker-green')), findsNothing);
      expect(_findByKey(const Key('color-picker-blue')), findsNothing);
      expect(
        tester.getSize(_findByKey(const Key('color-picker-palette'))).height,
        lessThanOrEqualTo(260),
      );
      expect(
        tester.getRect(_findByKey(const Key('color-picker-hue-slider'))).bottom,
        lessThan(
          tester.getRect(_findByKey(const Key('color-picker-apply'))).top,
        ),
      );

      await tester.enterText(
        _findByKey(const Key('color-picker-hex')),
        '#123456',
      );
      await tester.pumpAndSettle();
      await tester.tap(_findByKey(const Key('color-picker-apply')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextFormField>(
              _findByKey(const Key('profile-editor-color-foreground')),
            )
            .controller!
            .text,
        '#123456',
      );

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-pick-foreground')),
      );
      await tester.tap(_findByKey(const Key('profile-editor-pick-foreground')));
      await tester.pumpAndSettle();
      await tester.enterText(
        _findByKey(const Key('color-picker-hex')),
        '#FFFFFG',
      );
      await tester.pumpAndSettle();
      expect(find.text('Use #RRGGBB or leave empty.'), findsOneWidget);
      await tester.tap(_findByKey(const Key('color-picker-apply')));
      await tester.pumpAndSettle();
      expect(_findByKey(const Key('color-picker-dialog')), findsOneWidget);
      await tester.tap(_findByKey(const Key('color-picker-reset')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextFormField>(
              _findByKey(const Key('profile-editor-color-foreground')),
            )
            .controller!
            .text,
        isEmpty,
      );

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-save')),
      );
      await tester.tap(_findByKey(const Key('profile-editor-save')));
      await tester.pumpAndSettle();

      expect(savedProfile, isNotNull);
      expect(savedProfile!.appearance.colors.foreground, isNull);
    },
  );

  testWidgets('profile editor can return terminal colors to the app theme', (
    tester,
  ) async {
    await _pumpEditorHarness(
      tester,
      initialValue: TerminalProfile(
        id: 'default',
        name: 'Local Shell',
        shell: '/bin/zsh',
      ),
      onSaved: (_) {},
    );

    await _ensureVisible(
      tester,
      _findByKey(const Key('profile-editor-theme-presets')),
    );
    expect(
      _findByKey(const Key('profile-editor-theme-preset-selected-follow-app')),
      findsOneWidget,
    );

    await tester.tap(
      _findByKey(const Key('profile-editor-theme-preset-graphite-night')),
    );
    await tester.pumpAndSettle();
    expect(
      _findByKey(const Key('profile-editor-theme-preset-selected-follow-app')),
      findsNothing,
    );

    await tester.tap(
      _findByKey(const Key('profile-editor-theme-preset-follow-app')),
    );
    await tester.pumpAndSettle();
    expect(
      _findByKey(const Key('profile-editor-theme-preset-selected-follow-app')),
      findsOneWidget,
    );
    for (final fieldKey in _allColorFieldKeys) {
      expect(
        tester
            .widget<TextFormField>(_findByKey(Key(fieldKey)))
            .controller!
            .text,
        isEmpty,
      );
    }
  });

  testWidgets(
    'profile editor renders theme presets and applies a preset to all terminal colors',
    (tester) async {
      final paperSlate = terminalThemePresets.singleWhere(
        (preset) => preset.id == 'paper-slate',
      );
      TerminalProfile? savedProfile;
      await _pumpEditorHarness(
        tester,
        initialValue: TerminalProfile(
          id: 'default',
          name: 'Local Shell',
          shell: '/bin/zsh',
        ),
        onSaved: (value) => savedProfile = value,
      );

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-theme-presets')),
      );
      expect(find.text('Theme presets'), findsOneWidget);
      expect(find.text('Dark').evaluate().length, greaterThanOrEqualTo(3));
      expect(find.text('Light').evaluate().length, greaterThanOrEqualTo(2));
      expect(find.text('Graphite Night'), findsOneWidget);
      expect(find.text('Moss Night'), findsOneWidget);
      expect(find.text('Ember Dusk'), findsOneWidget);
      expect(find.text('Paper Slate'), findsOneWidget);
      expect(find.text('Sage Mist'), findsOneWidget);

      await tester.tap(
        _findByKey(const Key('profile-editor-theme-preset-paper-slate')),
      );
      await tester.pumpAndSettle();

      _expectColorFieldText(
        tester,
        'profile-editor-color-foreground',
        paperSlate.palette.special.foreground!,
      );
      _expectColorFieldText(
        tester,
        'profile-editor-color-background',
        paperSlate.palette.special.background!,
      );
      _expectColorFieldText(
        tester,
        'profile-editor-color-cursor',
        paperSlate.palette.special.cursor!,
      );
      _expectColorFieldText(
        tester,
        'profile-editor-color-selection',
        paperSlate.palette.special.selection!,
      );
      _expectColorFieldText(tester, 'profile-editor-color-tab', '');
      _expectColorFieldText(
        tester,
        'profile-editor-color-normal-red',
        paperSlate.palette.normal.red!,
      );
      _expectColorFieldText(
        tester,
        'profile-editor-color-bright-yellow',
        paperSlate.palette.bright.yellow!,
      );
      expect(
        _findByKey(
          const Key('profile-editor-theme-preset-selected-paper-slate'),
        ),
        findsOneWidget,
      );

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-save')),
      );
      await tester.tap(_findByKey(const Key('profile-editor-save')));
      await tester.pumpAndSettle();

      expect(savedProfile, isNotNull);
      expect(
        savedProfile!.appearance.colors.special.toJson(),
        paperSlate.palette.special.toJson(),
      );
      expect(
        savedProfile!.appearance.colors.normal.toJson(),
        paperSlate.palette.normal.toJson(),
      );
      expect(
        savedProfile!.appearance.colors.bright.toJson(),
        paperSlate.palette.bright.toJson(),
      );
    },
  );

  testWidgets(
    'profile editor clears preset selection after a manual color edit and keeps manual values',
    (tester) async {
      TerminalProfile? savedProfile;
      await _pumpEditorHarness(
        tester,
        initialValue: TerminalProfile(
          id: 'default',
          name: 'Local Shell',
          shell: '/bin/zsh',
        ),
        onSaved: (value) => savedProfile = value,
      );

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-theme-presets')),
      );
      await tester.tap(
        _findByKey(const Key('profile-editor-theme-preset-graphite-night')),
      );
      await tester.pumpAndSettle();

      expect(
        _findByKey(
          const Key('profile-editor-theme-preset-selected-graphite-night'),
        ),
        findsOneWidget,
      );

      await tester.enterText(
        _findByKey(const Key('profile-editor-color-cursor')),
        '#123456',
      );
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-color-normal-green')),
      );
      _expectColorFieldText(
        tester,
        'profile-editor-color-normal-green',
        '#8FB573',
      );
      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-color-selection')),
      );
      await tester.tap(_findByKey(const Key('profile-editor-color-selection')));
      await tester.pumpAndSettle();

      expect(
        _findByKey(
          const Key('profile-editor-theme-preset-selected-graphite-night'),
        ),
        findsNothing,
      );

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-save')),
      );
      await tester.tap(_findByKey(const Key('profile-editor-save')));
      await tester.pumpAndSettle();

      expect(savedProfile, isNotNull);
      expect(savedProfile!.appearance.colors.foreground, '#E6EAF2');
      expect(savedProfile!.appearance.colors.background, '#11141A');
      expect(savedProfile!.appearance.colors.cursor, '#123456');
      expect(savedProfile!.appearance.colors.selection, '#2A3C56');
      expect(savedProfile!.appearance.colors.tab, isNull);
      expect(savedProfile!.appearance.colors.normal.green, '#8FB573');
      expect(savedProfile!.appearance.colors.bright.white, '#F8FBFF');
    },
  );

  testWidgets(
    'profile editor reset only clears one color after applying a preset',
    (tester) async {
      TerminalProfile? savedProfile;
      await _pumpEditorHarness(
        tester,
        initialValue: TerminalProfile(
          id: 'default',
          name: 'Local Shell',
          shell: '/bin/zsh',
        ),
        onSaved: (value) => savedProfile = value,
      );

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-theme-presets')),
      );
      await tester.tap(
        _findByKey(const Key('profile-editor-theme-preset-sage-mist')),
      );
      await tester.pumpAndSettle();

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-reset-foreground')),
      );
      await tester.tap(
        _findByKey(const Key('profile-editor-reset-foreground')),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextFormField>(
              _findByKey(const Key('profile-editor-color-foreground')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextFormField>(
              _findByKey(const Key('profile-editor-color-background')),
            )
            .controller!
            .text,
        '#F1F5EF',
      );
      expect(
        tester
            .widget<TextFormField>(
              _findByKey(const Key('profile-editor-color-cursor')),
            )
            .controller!
            .text,
        '#2F855A',
      );
      _expectColorFieldText(
        tester,
        'profile-editor-color-normal-green',
        '#3F7A57',
      );
      expect(
        tester
            .widget<TextFormField>(
              _findByKey(const Key('profile-editor-color-selection')),
            )
            .controller!
            .text,
        '#CFE3D4',
      );

      await _ensureVisible(
        tester,
        _findByKey(const Key('profile-editor-save')),
      );
      await tester.tap(_findByKey(const Key('profile-editor-save')));
      await tester.pumpAndSettle();

      expect(savedProfile, isNotNull);
      expect(savedProfile!.appearance.colors.foreground, isNull);
      expect(savedProfile!.appearance.colors.background, '#F1F5EF');
      expect(savedProfile!.appearance.colors.cursor, '#2F855A');
      expect(savedProfile!.appearance.colors.selection, '#CFE3D4');
      expect(savedProfile!.appearance.colors.tab, isNull);
      expect(savedProfile!.appearance.colors.normal.green, '#3F7A57');
      expect(savedProfile!.appearance.colors.bright.white, '#FFFFFF');
    },
  );
}

const List<String> _allColorFieldKeys = <String>[
  'profile-editor-color-foreground',
  'profile-editor-color-background',
  'profile-editor-color-cursor',
  'profile-editor-color-selection',
  'profile-editor-color-tab',
  'profile-editor-color-normal-black',
  'profile-editor-color-normal-red',
  'profile-editor-color-normal-green',
  'profile-editor-color-normal-yellow',
  'profile-editor-color-normal-blue',
  'profile-editor-color-normal-magenta',
  'profile-editor-color-normal-cyan',
  'profile-editor-color-normal-white',
  'profile-editor-color-bright-black',
  'profile-editor-color-bright-red',
  'profile-editor-color-bright-green',
  'profile-editor-color-bright-yellow',
  'profile-editor-color-bright-blue',
  'profile-editor-color-bright-magenta',
  'profile-editor-color-bright-cyan',
  'profile-editor-color-bright-white',
];

Future<void> _pumpEditorHarness(
  WidgetTester tester, {
  required TerminalProfile initialValue,
  required ValueChanged<TerminalProfile?> onSaved,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildIanvsTerminalTheme(Brightness.dark),
      darkTheme: buildIanvsTerminalTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  onSaved(
                    await showDialog<TerminalProfile>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) =>
                          ProfileEditorDialog(initialValue: initialValue),
                    ),
                  );
                },
                child: const Text('Open editor'),
              ),
            ),
          );
        },
      ),
    ),
  );

  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

Finder _findByKey(Key key) => find.byKey(key, skipOffstage: false);

Future<void> _ensureVisible(WidgetTester tester, Finder finder) async {
  final targetElements = finder.evaluate().toList();
  if (targetElements.any((element) {
    return element.widget.key == const Key('profile-editor-save');
  })) {
    await tester.pumpAndSettle();
    return;
  }

  for (final section in const [
    'general',
    'startup',
    'terminal',
    'appearance',
    'keys',
    'automation',
    'advanced',
  ]) {
    final sectionRoot = _findByKey(Key('profile-editor-section-$section'));
    final belongsToSection = find
        .descendant(
          of: sectionRoot,
          matching: finder,
          matchRoot: true,
          skipOffstage: false,
        )
        .evaluate()
        .isNotEmpty;
    if (!belongsToSection) {
      continue;
    }
    final navItem = _findByKey(Key('profile-editor-nav-$section'));
    await Scrollable.ensureVisible(
      navItem.evaluate().single,
      duration: Duration.zero,
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(navItem);
    await tester.pumpAndSettle();
    break;
  }

  await Scrollable.ensureVisible(
    targetElements.single,
    duration: Duration.zero,
    alignment: 0.2,
  );
  await tester.pumpAndSettle();

  final saveButton = _findByKey(const Key('profile-editor-save'));
  if (saveButton.evaluate().isEmpty) {
    return;
  }

  final targetCenter = tester.getCenter(finder);
  final footerTop = tester.getTopLeft(saveButton).dy - 12;
  if (targetCenter.dy <= footerTop) {
    return;
  }

  await tester.drag(
    _findByKey(const Key('profile-editor-scroll-view')),
    Offset(0, -(targetCenter.dy - footerTop + 48)),
  );
  await tester.pumpAndSettle();
}

void _expectColorFieldText(
  WidgetTester tester,
  String fieldKey,
  String expected,
) {
  expect(
    tester.widget<TextFormField>(_findByKey(Key(fieldKey))).controller!.text,
    expected,
  );
}

void _expectDescendant(Key parentKey, Key childKey) {
  expect(
    find.descendant(
      of: _findByKey(parentKey),
      matching: _findByKey(childKey),
      skipOffstage: false,
    ),
    findsOneWidget,
  );
}
