import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/composer/composer_icons.dart';
import 'package:ianvs_terminal/src/composer/composer_theme.dart';
import 'package:ianvs_terminal/src/composer/terminal_composer_controller.dart';

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final increasedContrast in [false, true]) {
      test('paired roles are readable: $brightness / $increasedContrast', () {
        final theme = ComposerTheme.fromTheme(
          ThemeData(
            platform: TargetPlatform.macOS,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff007aff),
              brightness: brightness,
            ),
          ),
          highContrast: increasedContrast,
        );
        final textPairs = <String, (Color, Color)>{
          'command': (theme.foreground, theme.surface),
          'result': (theme.foreground, theme.popover),
          'context': (theme.muted, theme.contextSurface),
          'metadata': (theme.muted, theme.popover),
          'hover': (theme.foreground, theme.hover),
          'selection': (theme.onSelection, theme.selection),
          'primary': (theme.onPrimaryAction, theme.primaryAction),
          'error': (theme.onError, theme.errorSurface),
        };
        for (final entry in textPairs.entries) {
          final ratio = contrast(entry.value.$1, entry.value.$2);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '${entry.key} contrast must remain readable ($ratio:1)',
          );
        }
        expect(contrast(theme.focus, theme.surface), greaterThanOrEqualTo(3));
        if (increasedContrast) {
          expect(
            contrast(theme.border, theme.surface),
            greaterThanOrEqualTo(3),
          );
          expect(
            contrast(theme.divider, theme.popover),
            greaterThanOrEqualTo(3),
          );
          expect(theme.focusWidth, greaterThan(theme.borderWidth));
          expect(theme.shadow.a, 0);
        }
      });
    }
  }

  testWidgets(
    'host override follows contrast changes and preserves text scale',
    (tester) async {
      final host = ThemeData(
        platform: TargetPlatform.macOS,
        fontFamily: 'Host UI Font',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff007aff)),
      );
      final custom = ComposerTheme.fromTheme(host).copyWith(
        border: host.colorScheme.surfaceContainerLow,
        focus: host.colorScheme.surfaceContainerLow,
        commandStyle: ComposerTheme.fromTheme(
          host,
        ).commandStyle.copyWith(fontSize: 18),
      );
      late ComposerTheme resolved;
      late TextScaler scaler;
      Widget app(bool highContrast) => MaterialApp(
        theme: host.copyWith(extensions: [custom]),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            highContrast: highContrast,
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            resolved = ComposerTheme.of(context);
            scaler = MediaQuery.textScalerOf(context);
            return Text('命令 draft', style: resolved.commandStyle);
          },
        ),
      );

      await tester.pumpWidget(app(false));
      expect(resolved.border, custom.border);
      expect(resolved.commandStyle.fontSize, 18);
      expect(resolved.commandStyle.fontFamily, 'monospace');
      expect(resolved.contextStyle.fontFamily, 'Host UI Font');
      expect(scaler.scale(resolved.commandStyle.fontSize!), 36);

      await tester.pumpWidget(app(true));
      expect(resolved.highContrast, isTrue);
      expect(
        contrast(resolved.border, resolved.surface),
        greaterThanOrEqualTo(3),
      );
      expect(
        contrast(resolved.focus, resolved.surface),
        greaterThanOrEqualTo(3),
      );
      expect(resolved.commandStyle.fontSize, 18);
      expect(scaler.scale(resolved.commandStyle.fontSize!), 36);

      await tester.pumpWidget(app(false));
      expect(resolved.highContrast, isFalse);
      expect(resolved.border, custom.border);
    },
  );

  test('touch targets adapt without increasing the command type size', () {
    final desktop = ComposerTheme.fromTheme(
      ThemeData(platform: TargetPlatform.macOS),
    );
    final touch = ComposerTheme.fromTheme(
      ThemeData(platform: TargetPlatform.iOS),
    );
    expect(desktop.controlHeight, 32);
    expect(touch.controlHeight, 44);
    expect(touch.commandStyle.fontSize, desktop.commandStyle.fontSize);
    expect(touch.resultStyle.fontSize, desktop.resultStyle.fontSize);
  });

  test('theme extension interpolates between light and dark host roles', () {
    final light = ComposerTheme.fromTheme(ThemeData.light());
    final dark = ComposerTheme.fromTheme(ThemeData.dark());
    final middle = light.lerp(dark, .5);
    expect(middle.surface, Color.lerp(light.surface, dark.surface, .5));
    expect(
      middle.onPrimaryAction,
      Color.lerp(light.onPrimaryAction, dark.onPrimaryAction, .5),
    );
    expect(middle.commandStyle.fontFamily, 'monospace');
    expect(middle.commandStyle.fontSize, 16);
  });

  test('ownership and result glyphs use the existing vector font family', () {
    final ownership = ComposerOwnership.values
        .map(ComposerIcons.forOwnership)
        .toList();
    expect(ownership.map((icon) => icon.codePoint).toSet(), hasLength(6));
    final kinds = [
      'directory',
      'folder',
      'file',
      'option',
      'alias',
      'script',
      'command',
      'subcommand',
      'argument',
    ];
    for (final icon in [...ownership, ...kinds.map(ComposerIcons.forKind)]) {
      expect(icon.fontFamily, 'MaterialIcons');
    }
    expect(ComposerIcons.automaticSuggestions, isNot(ComposerIcons.directory));
    expect(ComposerIcons.accept, isNot(ComposerIcons.run));
    expect(
      ComposerIcons.forKind('command', riskHint: true),
      ComposerIcons.unknown,
    );
  });
}
