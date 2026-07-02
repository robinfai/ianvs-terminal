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
      const infinite = LocalTerminalPaneVisualPolicy(
        dividerThickness: double.infinity,
      );
      const nonFinite = LocalTerminalPaneVisualPolicy(
        dividerThickness: double.nan,
      );

      expect(visible.hasVisibleDivider, isTrue);
      expect(hidden.hasVisibleDivider, isFalse);
      expect(infinite.hasVisibleDivider, isFalse);
      expect(nonFinite.hasVisibleDivider, isFalse);
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
      const unsupported = LocalTerminalLayoutTemplate(
        id: 'three-pane',
        name: 'Three Pane',
        paneCount: 3,
        localOnly: true,
      );

      expect(local.canApply, isTrue);
      expect(remote.canApply, isFalse);
      expect(unsupported.canApply, isFalse);
    });

    test('json decoding defaults non-finite numeric fields', () {
      final scheme = LocalTerminalColorScheme.fromJson({
        'background': double.infinity,
      });
      final template = LocalTerminalLayoutTemplate.fromJson({
        'paneCount': double.nan,
        'localOnly': true,
      });

      expect(scheme.background, 0x000000);
      expect(template.paneCount, 0);
      expect(template.canApply, isFalse);
    });

    test('layout template pane count accepts zero but rejects negatives', () {
      final disabled = LocalTerminalLayoutTemplate.fromJson({
        'paneCount': 0,
        'localOnly': true,
      });
      final negative = LocalTerminalLayoutTemplate.fromJson({
        'paneCount': -2,
        'localOnly': true,
      });
      final fractional = LocalTerminalLayoutTemplate.fromJson({
        'paneCount': 1.5,
        'localOnly': true,
      });

      expect(disabled.paneCount, 0);
      expect(disabled.canApply, isFalse);
      expect(negative.paneCount, 0);
      expect(negative.canApply, isFalse);
      expect(fractional.paneCount, 0);
      expect(fractional.canApply, isFalse);
    });

    test(
      'visual preset and template ids trim whitespace and reject blanks',
      () {
        final preset = LocalTerminalThemePreset.fromJson({
          'id': ' baseline ',
          'name': ' Baseline ',
        });
        final blankPreset = LocalTerminalThemePreset.fromJson({
          'id': '   ',
          'name': 'Blank',
        });
        final template = LocalTerminalLayoutTemplate.fromJson({
          'id': ' two-pane ',
          'name': ' Two Pane ',
          'paneCount': 2,
          'localOnly': true,
        });
        final blankTemplate = LocalTerminalLayoutTemplate.fromJson({
          'id': '   ',
          'name': 'Blank',
          'paneCount': 2,
          'localOnly': true,
        });

        expect(preset.id, 'baseline');
        expect(preset.name, 'Baseline');
        expect(preset.isUsable, isTrue);
        expect(blankPreset.isUsable, isFalse);
        expect(template.id, 'two-pane');
        expect(template.name, 'Two Pane');
        expect(template.canApply, isTrue);
        expect(blankTemplate.canApply, isFalse);
      },
    );

    test('visual preset and template JSON normalizes labels', () {
      const preset = LocalTerminalThemePreset(
        id: ' baseline ',
        name: ' Baseline ',
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
      const template = LocalTerminalLayoutTemplate(
        id: ' two-pane ',
        name: ' Two Pane ',
        paneCount: 2,
        localOnly: true,
      );

      expect(preset.toJson()['id'], 'baseline');
      expect(preset.toJson()['name'], 'Baseline');
      expect(template.toJson()['id'], 'two-pane');
      expect(template.toJson()['name'], 'Two Pane');
    });

    test('json decoding defaults out-of-range color fields', () {
      final scheme = LocalTerminalColorScheme.fromJson({
        'background': -1,
        'foreground': 0x1ffffffff,
        'cursor': 0xffffff,
      });
      final fractional = LocalTerminalColorScheme.fromJson({'background': 1.5});

      expect(scheme.background, 0x000000);
      expect(scheme.foreground, 0xffffff);
      expect(scheme.cursor, 0xffffff);
      expect(fractional.background, 0x000000);
    });

    test('color scheme JSON normalizes out-of-range direct colors', () {
      const scheme = LocalTerminalColorScheme(
        background: -1,
        foreground: 0x1ffffffff,
        cursor: 0xffffff,
        selection: -1,
        splitDivider: 0x222222,
        inactivePaneOverlay: 0x1ffffffff,
      );

      final json = scheme.toJson();

      expect(json['background'], 0x000000);
      expect(json['foreground'], 0xffffff);
      expect(json['cursor'], 0xffffff);
      expect(json['selection'], 0x333333);
      expect(json['splitDivider'], 0x222222);
      expect(json['inactivePaneOverlay'], 0x11000000);
    });

    test('json decoding accepts common hex color strings', () {
      final scheme = LocalTerminalColorScheme.fromJson({
        'background': '#050608',
        'foreground': '0xeeeeee',
        'cursor': '#ff00ff',
        'inactivePaneOverlay': '0x33000000',
        'selection': '#bad-color',
      });

      expect(scheme.background, 0x050608);
      expect(scheme.foreground, 0xeeeeee);
      expect(scheme.cursor, 0xff00ff);
      expect(scheme.inactivePaneOverlay, 0x33000000);
      expect(scheme.selection, 0x333333);
    });

    test('advanced visual policy flags renderer-risk options', () {
      const safe = LocalTerminalAdvancedVisualPolicy();
      const risky = LocalTerminalAdvancedVisualPolicy(blurEnabled: true);
      const transparent = LocalTerminalAdvancedVisualPolicy(opacity: 0.8);
      const overOpaque = LocalTerminalAdvancedVisualPolicy(opacity: 1.2);
      const nonFinite = LocalTerminalAdvancedVisualPolicy(opacity: double.nan);

      expect(safe.touchesRendererRisk, isFalse);
      expect(risky.touchesRendererRisk, isTrue);
      expect(transparent.touchesRendererRisk, isTrue);
      expect(overOpaque.touchesRendererRisk, isTrue);
      expect(nonFinite.touchesRendererRisk, isTrue);
    });

    test('theme preset can be encoded and decoded for import export', () {
      final decoded = LocalTerminalThemePreset.decode(_preset().encode());

      expect(decoded.id, 'baseline');
      expect(decoded.dark.background, 0x000000);
      expect(decoded.light.background, 0xffffff);
    });

    test('theme preset decode rejects non-object json roots', () {
      expect(
        () => LocalTerminalThemePreset.decode('[]'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Theme preset JSON must be an object.',
          ),
        ),
      );
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
