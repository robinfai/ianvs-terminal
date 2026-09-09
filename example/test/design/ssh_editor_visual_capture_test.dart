import 'dart:io';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/ssh/new_session_launcher.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'configuration_capture_binding.dart';

const _outputDirectory =
    '../../../docs/design/'
    'configuration-forms-20260909/final/ssh';

Future<ByteData> _readFont(String path) async {
  final bytes = await File(path).readAsBytes();
  return ByteData.sublistView(Uint8List.fromList(bytes));
}

Future<void> _loadVisualFonts() async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final latin = FontLoader('SshCaptureSans')
    ..addFont(_readFont('/System/Library/Fonts/SFNS.ttf'));
  final cjk = FontLoader('SshCaptureCjk')
    ..addFont(_readFont('/System/Library/Fonts/STHeiti Medium.ttc'));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(
      _readFont(
        '$flutterRoot/bin/cache/artifacts/material_fonts/'
        'MaterialIcons-Regular.otf',
      ),
    );
  await Future.wait([latin.load(), cjk.load(), materialIcons.load()]);
}

void main() {
  ConfigurationCaptureBinding();
  if (!Platform.isMacOS) {
    test('SSH editor visual capture requires macOS fonts', () {}, skip: true);
    return;
  }

  setUpAll(_loadVisualFonts);

  for (final variant in [
    (
      name: 'advanced',
      size: const Size(1100, 900),
      brightness: Brightness.light,
      scale: 1.0,
    ),
    (
      name: 'advanced-compact',
      size: const Size(520, 900),
      brightness: Brightness.light,
      scale: 1.5,
    ),
    (
      name: 'editor',
      size: const Size(1100, 900),
      brightness: Brightness.light,
      scale: 1.0,
    ),
    (
      name: 'dark',
      size: const Size(1100, 900),
      brightness: Brightness.dark,
      scale: 1.0,
    ),
    (
      name: 'compact-scaled',
      size: const Size(390, 844),
      brightness: Brightness.light,
      scale: 1.5,
    ),
  ]) {
    testWidgets('captures SSH editor ${variant.name}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = variant.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final baseTheme = buildIanvsTerminalTheme(
        variant.brightness,
        platform: TargetPlatform.macOS,
      );
      const captureFont = 'SshCaptureSans';
      const captureFallback = <String>['SshCaptureCjk'];
      final profile = defaultTerminalProfile().copyWith(
        id: 'design-capture-ssh',
        name: '生产环境',
        connection: const terminal.TerminalConnectionConfig.ssh(
          host: 'prod.example.com',
          user: 'deploy',
          port: 22,
          auth: terminal.TerminalSshAuthMethod.auto,
          privateKeys: <String>['~/.ssh/id_ed25519'],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(variant.scale)),
            child: child!,
          ),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: baseTheme.copyWith(
            textTheme: baseTheme.textTheme.apply(
              fontFamily: captureFont,
              fontFamilyFallback: captureFallback,
            ),
            primaryTextTheme: baseTheme.primaryTextTheme.apply(
              fontFamily: captureFont,
              fontFamilyFallback: captureFallback,
            ),
          ),
          home: Scaffold(
            body: SshProfileEditorDialog(
              initialValue: profile,
              allowSaveChoice: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (variant.name.startsWith('advanced')) {
        await tester.ensureVisible(find.byType(ExpansionTile));
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('主机验证与高级选项'));
        await tester.pumpAndSettle();
      }

      await expectLater(
        find.byType(SshProfileEditorDialog),
        matchesGoldenFile(
          variant.name.startsWith('advanced')
              ? '../../../docs/design/configuration-forms-20260909/interaction-review/after/ssh-${variant.name}.png'
              : '$_outputDirectory/${variant.name}.png',
        ),
      );
    });
  }
}
