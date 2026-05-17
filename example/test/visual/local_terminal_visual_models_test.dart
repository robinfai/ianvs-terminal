import 'package:app/features/visual/local_terminal_visual_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal visual models', () {
    test('theme preset returns paired light and dark schemes', () {
      final preset = _preset();

      expect(preset.schemeForBrightness(darkMode: true).background, 0x000000);
      expect(preset.schemeForBrightness(darkMode: false).background, 0xffffff);
    });

    test('pane visual policy exposes visible divider state', () {
      const visible = LocalTerminalPaneVisualPolicy(dividerThickness: 1);
      const hidden = LocalTerminalPaneVisualPolicy(dividerThickness: 0);

      expect(visible.hasVisibleDivider, isTrue);
      expect(hidden.hasVisibleDivider, isFalse);
    });

    test('layout templates remain local only', () {
      const local = LocalTerminalLayoutTemplate(
        id: 'two-pane',
        name: 'Two Pane',
        paneCount: 2,
        localOnly: true,
      );
      const remote = LocalTerminalLayoutTemplate(
        id: 'remote',
        name: 'Remote',
        paneCount: 2,
        localOnly: false,
      );

      expect(local.canApply, isTrue);
      expect(remote.canApply, isFalse);
    });

    test('advanced visual policy flags renderer-risk options', () {
      const safe = LocalTerminalAdvancedVisualPolicy();
      const risky = LocalTerminalAdvancedVisualPolicy(blurEnabled: true);

      expect(safe.touchesRendererRisk, isFalse);
      expect(risky.touchesRendererRisk, isTrue);
    });

    test('theme preset can be encoded and decoded for import export', () {
      final decoded = LocalTerminalThemePreset.decode(_preset().encode());

      expect(decoded.id, 'baseline');
      expect(decoded.dark.background, 0x000000);
      expect(decoded.light.background, 0xffffff);
    });

    test('profile theme override matches profile id', () {
      const override = LocalTerminalProfileThemeOverride(
        profileId: 'dev',
        themePresetId: 'baseline',
      );

      expect(override.appliesTo('dev'), isTrue);
      expect(override.appliesTo('prod'), isFalse);
    });

    test('command pane and timestamp policies are optional', () {
      const timestamps = LocalTerminalCommandTimestampPolicy(enabled: true);
      const pane = LocalTerminalCommandPanePolicy(
        enabled: true,
        defaultVisible: true,
      );

      expect(timestamps.enabled, isTrue);
      expect(pane.canShow, isTrue);
    });

    test('scrollback export and graphics policies gate advanced storage', () {
      const exportPolicy = LocalTerminalScrollbackExportPolicy();
      const graphics = LocalTerminalGraphicsStoragePolicy(
        enabled: true,
        maxBytes: 10,
      );

      expect(
        exportPolicy.canExport(LocalTerminalExportFormat.plainText),
        isTrue,
      );
      expect(graphics.acceptsImage(bytes: 9), isTrue);
      expect(graphics.acceptsImage(bytes: 11), isFalse);
    });
  });
}

LocalTerminalThemePreset _preset() {
  return const LocalTerminalThemePreset(
    id: 'baseline',
    name: 'Baseline',
    dark: LocalTerminalColorScheme(
      background: 0x000000,
      foreground: 0xffffff,
      cursor: 0xffffff,
      selection: 0x333333,
      splitDivider: 0x222222,
      inactivePaneOverlay: 0x11000000,
    ),
    light: LocalTerminalColorScheme(
      background: 0xffffff,
      foreground: 0x000000,
      cursor: 0x000000,
      selection: 0xdddddd,
      splitDivider: 0xcccccc,
      inactivePaneOverlay: 0x11000000,
    ),
  );
}
