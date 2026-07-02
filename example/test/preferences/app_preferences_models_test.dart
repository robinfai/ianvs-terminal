import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/preferences/app_preferences_models.dart';

void main() {
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
