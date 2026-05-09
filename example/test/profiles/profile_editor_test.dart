import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

import 'package:app/features/profiles/profile_editor.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/ui/app_ui.dart';

void main() {
  testWidgets(
    'profile editor seeds nested terminal fields and saves structured changes',
    (tester) async {
      final initialProfile = TerminalProfile.configured(
        id: 'default',
        name: 'Local Shell',
        sessionConfig: const terminal.TerminalSessionConfig(
          launch: terminal.TerminalLaunchConfig(
            program: '/bin/bash',
            args: ['-lc', 'printf hello'],
            env: {'TERM_PROGRAM': 'flutterm'},
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
              foreground: '#AABBCC',
              background: '#101112',
              cursor: '#778899',
              selection: '#334455',
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
            .widget<TextFormField>(find.byKey(const Key('profile-editor-name')))
            .controller!
            .text,
        'Local Shell',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('profile-editor-shell')),
            )
            .controller!
            .text,
        '/bin/bash',
      );
      expect(find.text('Colors'), findsOneWidget);
      expect(find.text('Cursor'), findsOneWidget);
      expect(find.text('Interaction'), findsOneWidget);
      expect(find.text('VT220'), findsOneWidget);
      expect(find.text('Beam'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('profile-editor-save'))).height,
        40,
      );
      final shellFieldHeight = tester
          .getSize(find.byKey(const Key('profile-editor-shell')))
          .height;
      expect(shellFieldHeight, greaterThanOrEqualTo(48));
      expect(
        tester.getSize(find.byKey(const Key('profile-editor-add-arg'))).height,
        36,
      );

      await tester.enterText(
        find.byKey(const Key('profile-editor-name')),
        'Workspace Shell',
      );
      await tester.enterText(
        find.byKey(const Key('profile-editor-shell')),
        '/bin/fish',
      );
      await tester.enterText(find.byKey(const Key('profile-editor-cwd')), '');

      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-arg-0-down')),
      );
      await tester.tap(find.byKey(const Key('profile-editor-arg-0-down')));
      await tester.pump();
      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-add-arg')),
      );
      await tester.tap(find.byKey(const Key('profile-editor-add-arg')));
      await tester.pump();
      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-arg-2')),
      );
      await tester.enterText(
        find.byKey(const Key('profile-editor-arg-2')),
        '--login',
      );

      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-add-env')),
      );
      await tester.tap(find.byKey(const Key('profile-editor-add-env')));
      await tester.pump();
      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-env-key-1')),
      );
      await tester.enterText(
        find.byKey(const Key('profile-editor-env-key-1')),
        'COLORTERM',
      );
      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-env-value-1')),
      );
      await tester.enterText(
        find.byKey(const Key('profile-editor-env-value-1')),
        'truecolor',
      );

      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-emulation')),
      );
      await tester.tap(find.byKey(const Key('profile-editor-emulation')));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.byKey(const Key('profile-editor-emulation')))
            .height,
        closeTo(shellFieldHeight, 2),
      );
      await tester.tap(find.text('xterm-256color').last);
      await tester.pumpAndSettle();
      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-scrollback')),
      );
      await tester.enterText(
        find.byKey(const Key('profile-editor-scrollback')),
        '12000',
      );

      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-font-family')),
      );
      await tester.enterText(
        find.byKey(const Key('profile-editor-font-family')),
        'JetBrainsMono Nerd Font Mono',
      );
      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-fallback-1-remove')),
      );
      expect(
        tester
            .getSize(find.byKey(const Key('profile-editor-fallback-1-remove')))
            .height,
        32,
      );
      await tester.tap(
        find.byKey(const Key('profile-editor-fallback-1-remove')),
      );
      await tester.pump();
      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-add-fallback')),
      );
      await tester.tap(find.byKey(const Key('profile-editor-add-fallback')));
      await tester.pump();
      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-fallback-1')),
      );
      await tester.enterText(
        find.byKey(const Key('profile-editor-fallback-1')),
        'Menlo',
      );
      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-font-size')),
      );
      await tester.enterText(
        find.byKey(const Key('profile-editor-font-size')),
        '15',
      );
      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-font-line-height')),
      );
      await tester.enterText(
        find.byKey(const Key('profile-editor-font-line-height')),
        '1.6',
      );

      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-color-foreground')),
      );
      expect(
        tester.getSize(
          find.byKey(const Key('profile-editor-swatch-foreground')),
        ),
        const Size(30, 30),
      );
      await tester.enterText(
        find.byKey(const Key('profile-editor-color-foreground')),
        '112233',
      );
      await tester.tap(
        find.byKey(const Key('profile-editor-color-background')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getCenter(find.byKey(const Key('profile-editor-pick-background')))
            .dy,
        closeTo(
          tester
              .getCenter(
                find.byKey(const Key('profile-editor-swatch-background')),
              )
              .dy,
          6,
        ),
      );
      final dialogRect = tester.getRect(
        find.byKey(const Key('profile-editor-dialog')),
      );
      final backgroundSwatchRect = tester.getRect(
        find.byKey(const Key('profile-editor-swatch-background')),
      );
      expect(
        dialogRect.right - backgroundSwatchRect.right,
        greaterThanOrEqualTo(20),
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('profile-editor-color-foreground')),
            )
            .controller!
            .text,
        '#112233',
      );
      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-color-cursor')),
      );
      await tester.enterText(
        find.byKey(const Key('profile-editor-color-cursor')),
        '',
      );
      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-color-selection')),
      );
      await tester.enterText(
        find.byKey(const Key('profile-editor-color-selection')),
        '#445566',
      );

      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-cursor-shape')),
      );
      final cursorShapeRect = tester.getRect(
        find.byKey(const Key('profile-editor-cursor-shape')),
      );
      expect(
        dialogRect.right - cursorShapeRect.right,
        greaterThanOrEqualTo(20),
      );
      await tester.tap(find.byKey(const Key('profile-editor-cursor-shape')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block').last);
      await tester.pumpAndSettle();
      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-cursor-blink')),
      );
      expect(
        tester
            .getSize(find.byKey(const Key('profile-editor-cursor-blink')))
            .height,
        lessThanOrEqualTo(40),
      );
      await tester.tap(find.byKey(const Key('profile-editor-cursor-blink')));
      await tester.pump();

      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-copy-on-select')),
      );
      await tester.tap(find.byKey(const Key('profile-editor-copy-on-select')));
      await tester.pump();
      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-option-drag-blockSelection')),
      );
      await tester.tap(
        find.byKey(const Key('profile-editor-option-drag-blockSelection')),
      );
      await tester.pump();

      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-save')),
      );
      await tester.tap(find.byKey(const Key('profile-editor-save')));
      await tester.pumpAndSettle();

      expect(savedProfile, isNotNull);
      expect(savedProfile!.name, 'Workspace Shell');
      expect(savedProfile!.shell, '/bin/fish');
      expect(savedProfile!.cwd, isNull);
      expect(savedProfile!.args, ['printf hello', '-lc', '--login']);
      expect(savedProfile!.env, {
        'TERM_PROGRAM': 'flutterm',
        'COLORTERM': 'truecolor',
      });
      expect(savedProfile!.terminalEmulation, TerminalEmulation.xterm256);
      expect(savedProfile!.scrollbackLines, 12000);
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
      expect(savedProfile!.appearance.cursor.shape, TerminalCursorShape.block);
      expect(savedProfile!.appearance.cursor.blink, isTrue);
      expect(savedProfile!.interaction.copyOnSelect, isFalse);
      expect(
        savedProfile!.interaction.optionDragMode,
        TerminalOptionDragMode.blockSelection,
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
      find.byKey(const Key('profile-editor-add-env')),
    );
    await tester.tap(find.byKey(const Key('profile-editor-add-env')));
    await tester.pump();
    await _ensureVisible(
      tester,
      find.byKey(const Key('profile-editor-add-env')),
    );
    await tester.tap(find.byKey(const Key('profile-editor-add-env')));
    await tester.pump();
    await _ensureVisible(
      tester,
      find.byKey(const Key('profile-editor-env-key-0')),
    );
    await tester.enterText(
      find.byKey(const Key('profile-editor-env-key-0')),
      'TERM',
    );
    await _ensureVisible(
      tester,
      find.byKey(const Key('profile-editor-env-key-1')),
    );
    await tester.enterText(
      find.byKey(const Key('profile-editor-env-key-1')),
      'TERM',
    );

    await tester.enterText(find.byKey(const Key('profile-editor-name')), '');
    await tester.enterText(find.byKey(const Key('profile-editor-shell')), '');
    await _ensureVisible(
      tester,
      find.byKey(const Key('profile-editor-scrollback')),
    );
    await tester.enterText(
      find.byKey(const Key('profile-editor-scrollback')),
      '0',
    );
    await _ensureVisible(
      tester,
      find.byKey(const Key('profile-editor-font-size')),
    );
    await tester.enterText(
      find.byKey(const Key('profile-editor-font-size')),
      '0',
    );
    await _ensureVisible(
      tester,
      find.byKey(const Key('profile-editor-font-line-height')),
    );
    await tester.enterText(
      find.byKey(const Key('profile-editor-font-line-height')),
      '-1',
    );
    await _ensureVisible(
      tester,
      find.byKey(const Key('profile-editor-color-foreground')),
    );
    await tester.enterText(
      find.byKey(const Key('profile-editor-color-foreground')),
      'red',
    );

    await _ensureVisible(tester, find.byKey(const Key('profile-editor-save')));
    await tester.tap(find.byKey(const Key('profile-editor-save')));
    await tester.pump();

    expect(savedProfile, isNull);
    expect(find.text('Name is required'), findsOneWidget);
    expect(find.text('Shell is required'), findsOneWidget);
    expect(
      find.text('Scrollback lines must be a positive integer'),
      findsOneWidget,
    );
    expect(find.text('Font size must be greater than 0'), findsOneWidget);
    expect(find.text('Line height must be greater than 0'), findsOneWidget);
    expect(find.text('Use #RRGGBB or leave empty.'), findsOneWidget);
    expect(find.text('Key must be unique'), findsNWidgets(2));
    expect(find.byKey(const Key('profile-editor-dialog')), findsOneWidget);
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
      find.byKey(const Key('profile-editor-name')),
      'Edited Shell',
    );
    await tester.tap(find.byTooltip('Close profile editor'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('profile-editor-discard-dialog')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('profile-editor-discard-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-editor-dialog')), findsOneWidget);
    expect(savedProfile, isNull);

    await tester.tap(find.byKey(const Key('profile-editor-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-editor-discard-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-editor-dialog')), findsNothing);
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
        find.byKey(const Key('profile-editor-swatch-foreground')),
      );
      await tester.tap(
        find.byKey(const Key('profile-editor-swatch-foreground')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('color-picker-dialog')), findsOneWidget);
      expect(find.byKey(const Key('color-picker-palette')), findsOneWidget);
      expect(find.byKey(const Key('color-picker-hue-slider')), findsOneWidget);
      expect(find.byKey(const Key('color-picker-red')), findsNothing);
      expect(find.byKey(const Key('color-picker-green')), findsNothing);
      expect(find.byKey(const Key('color-picker-blue')), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('color-picker-palette'))).height,
        lessThanOrEqualTo(260),
      );
      expect(
        tester.getRect(find.byKey(const Key('color-picker-hue-slider'))).bottom,
        lessThan(
          tester.getRect(find.byKey(const Key('color-picker-apply'))).top,
        ),
      );

      await tester.enterText(
        find.byKey(const Key('color-picker-hex')),
        '#123456',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('color-picker-apply')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('profile-editor-color-foreground')),
            )
            .controller!
            .text,
        '#123456',
      );

      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-pick-foreground')),
      );
      await tester.tap(find.byKey(const Key('profile-editor-pick-foreground')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('color-picker-hex')),
        '#FFFFFG',
      );
      await tester.pumpAndSettle();
      expect(find.text('Use #RRGGBB or leave empty.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('color-picker-apply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('color-picker-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('color-picker-reset')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('profile-editor-color-foreground')),
            )
            .controller!
            .text,
        isEmpty,
      );

      await _ensureVisible(
        tester,
        find.byKey(const Key('profile-editor-save')),
      );
      await tester.tap(find.byKey(const Key('profile-editor-save')));
      await tester.pumpAndSettle();

      expect(savedProfile, isNotNull);
      expect(savedProfile!.appearance.colors.foreground, isNull);
    },
  );
}

Future<void> _pumpEditorHarness(
  WidgetTester tester, {
  required TerminalProfile initialValue,
  required ValueChanged<TerminalProfile?> onSaved,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildFluttermTheme(Brightness.dark),
      darkTheme: buildFluttermTheme(Brightness.dark),
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

Future<void> _ensureVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}
