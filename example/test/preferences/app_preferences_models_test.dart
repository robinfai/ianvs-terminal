import 'dart:convert';

import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'platform preference clears the override and follows the receiving platform',
    () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final appearance = const TerminalAppAppearance(
        preferredTerminalMode: TerminalViewMode.normal,
        themeMode: TerminalThemeMode.dark,
      ).copyWith(resetPreferredTerminalMode: true);
      expect(appearance.preferredTerminalModeOverride, isNull);
      expect(appearance.toJson(), isNot(contains('preferredTerminalMode')));
      final loaded = TerminalAppAppearance.fromJson(appearance.toJson());
      expect(loaded.themeMode, TerminalThemeMode.dark);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(loaded.preferredTerminalMode, TerminalViewMode.normal);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(loaded.preferredTerminalMode, TerminalViewMode.blocks);
      final explicit = loaded.copyWith(
        preferredTerminalMode: TerminalViewMode.blocks,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(explicit.preferredTerminalModeOverride, TerminalViewMode.blocks);
      expect(explicit.preferredTerminalMode, TerminalViewMode.blocks);
    },
  );

  test('mobile defaults to Blocks without persisting an implicit choice', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      final appearance = TerminalAppAppearance.fromJson({});
      expect(appearance.preferredTerminalMode, TerminalViewMode.blocks);
      final saved = appearance
          .copyWith(themeMode: TerminalThemeMode.dark)
          .toJson();
      expect(saved.containsKey('preferredTerminalMode'), isFalse);
      expect(
        TerminalAppAppearance.fromJson(saved).preferredTerminalMode,
        TerminalViewMode.blocks,
      );
      final explicit = appearance.copyWith(
        preferredTerminalMode: TerminalViewMode.normal,
      );
      expect(
        TerminalAppAppearance.fromJson(explicit.toJson()).preferredTerminalMode,
        TerminalViewMode.normal,
      );
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(
      const TerminalAppAppearance().preferredTerminalMode,
      TerminalViewMode.normal,
    );
  });
  test('preferred terminal mode roundtrips and unknown values keep Normal', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final preferences = const TerminalAppPreferencesDocument().copyWith(
      appearance: const TerminalAppAppearance(
        preferredTerminalMode: TerminalViewMode.blocks,
      ),
    );
    final decoded = TerminalAppPreferencesDocument.fromJson(
      jsonDecode(preferences.encode()) as Map<String, Object?>,
    );
    expect(decoded.appearance.preferredTerminalMode, TerminalViewMode.blocks);
    expect(
      TerminalAppAppearance.fromJson({}).preferredTerminalMode,
      TerminalViewMode.normal,
    );
    expect(
      TerminalAppAppearance.fromJson({
        'preferredTerminalMode': 'future',
      }).preferredTerminalMode,
      TerminalViewMode.normal,
    );
  });
  test('app preferences copyWith and toJson normalize schema versions', () {
    final copied = const TerminalAppPreferencesDocument().copyWith(
      schemaVersion: -1,
    );
    const direct = TerminalAppPreferencesDocument(schemaVersion: 0);

    expect(
      copied.schemaVersion,
      TerminalAppPreferencesDocument.currentSchemaVersion,
    );
    expect(
      direct.toJson()['schemaVersion'],
      TerminalAppPreferencesDocument.currentSchemaVersion,
    );
  });

  test('app defaults copyWith normalizes default profile ids', () {
    final trimmed = const TerminalAppDefaults().copyWith(
      defaultProfileId: ' ssh ',
    );
    final blank = const TerminalAppDefaults(
      defaultProfileId: 'ssh',
    ).copyWith(defaultProfileId: '   ');

    expect(trimmed.defaultProfileId, 'ssh');
    expect(blank.defaultProfileId, isNull);
  });

  test('app defaults toJson normalizes invalid direct default profile ids', () {
    const defaults = TerminalAppDefaults(defaultProfileId: '   ');

    expect(defaults.toJson()['defaultProfileId'], isNull);
  });

  test('app appearance copyWith normalizes terminal viewport padding', () {
    final appearance = const TerminalAppAppearance(
      terminalViewportPadding: 16,
    ).copyWith(terminalViewportPadding: double.nan);

    expect(
      appearance.terminalViewportPadding,
      TerminalAppAppearance.defaultTerminalViewportPadding,
    );
  });

  test('app appearance language mode defaults and roundtrips through json', () {
    expect(
      const TerminalAppAppearance().languageMode,
      TerminalLanguageMode.system,
    );

    const appearance = TerminalAppAppearance(
      languageMode: TerminalLanguageMode.simplifiedChinese,
    );
    final decoded = TerminalAppAppearance.fromJson(appearance.toJson());

    expect(decoded.languageMode, TerminalLanguageMode.simplifiedChinese);
    expect(
      TerminalAppAppearance.fromJson(const {'languageMode': 'en'}).languageMode,
      TerminalLanguageMode.english,
    );
  });

  test('app appearance toJson normalizes invalid direct padding', () {
    const appearance = TerminalAppAppearance(
      terminalViewportPadding: double.infinity,
    );

    final json = appearance.toJson();

    expect(
      json['terminalViewportPadding'],
      TerminalAppAppearance.defaultTerminalViewportPadding,
    );
    expect(() => jsonEncode(json), returnsNormally);
  });

  test('app appearance normalizes finite padding into supported range', () {
    expect(
      TerminalAppAppearance.normalizeTerminalViewportPadding(96),
      TerminalAppAppearance.maxTerminalViewportPadding,
    );
    expect(
      TerminalAppAppearance.normalizeTerminalViewportPadding(-4),
      TerminalAppAppearance.minTerminalViewportPadding,
    );
    expect(TerminalAppAppearance.normalizeTerminalViewportPadding('20'), 20);
  });
}
