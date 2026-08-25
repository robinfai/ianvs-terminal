import 'dart:io';

import 'package:app/features/profiles/profile_editor.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _surfaceSize = Size(1440, 1024);

Future<ByteData> _readFont(String path) async {
  final bytes = await File(path).readAsBytes();
  return ByteData.sublistView(Uint8List.fromList(bytes));
}

Future<void> _loadVisualFonts() async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final text = FontLoader('ProfileCaptureSans')
    ..addFont(_readFont('/System/Library/Fonts/STHeiti Medium.ttc'));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(
      _readFont(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    );
  await Future.wait([text.load(), materialIcons.load()]);
}

Future<void> _pumpProfileEditor(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _surfaceSize;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final baseTheme = buildIanvsTerminalTheme(
    Brightness.light,
    platform: TargetPlatform.macOS,
  );
  const captureFont = 'ProfileCaptureSans';
  final inputDecorationTheme = baseTheme.inputDecorationTheme;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(fontFamily: captureFont),
        primaryTextTheme: baseTheme.primaryTextTheme.apply(
          fontFamily: captureFont,
        ),
        inputDecorationTheme: inputDecorationTheme.copyWith(
          labelStyle: inputDecorationTheme.labelStyle?.copyWith(
            fontFamily: captureFont,
          ),
          floatingLabelStyle: inputDecorationTheme.floatingLabelStyle?.copyWith(
            fontFamily: captureFont,
          ),
          helperStyle: inputDecorationTheme.helperStyle?.copyWith(
            fontFamily: captureFont,
          ),
          hintStyle: inputDecorationTheme.hintStyle?.copyWith(
            fontFamily: captureFont,
          ),
          errorStyle: inputDecorationTheme.errorStyle?.copyWith(
            fontFamily: captureFont,
          ),
        ),
      ),
      home: Scaffold(
        body: ProfileEditorDialog(initialValue: defaultTerminalProfile()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _captureTab(
  WidgetTester tester, {
  required String tabKey,
  required String goldenName,
}) async {
  await _pumpProfileEditor(tester);
  if (tabKey != 'general') {
    await tester.tap(
      find.byKey(Key('profile-editor-nav-$tabKey'), skipOffstage: false),
    );
    await tester.pumpAndSettle();
  }
  await expectLater(
    find.byKey(const Key('profile-editor-dialog')),
    matchesGoldenFile(
      '../../../docs/design/profile-tabs/current/$goldenName.png',
    ),
  );
}

void main() {
  if (!Platform.isMacOS) {
    test('profile tab visual captures require macOS fonts', () {}, skip: true);
    return;
  }

  setUpAll(_loadVisualFonts);

  testWidgets('captures General profile tab', (tester) async {
    await _captureTab(tester, tabKey: 'general', goldenName: '01-general');
  });

  testWidgets('captures Startup profile tab', (tester) async {
    await _captureTab(tester, tabKey: 'startup', goldenName: '02-startup');
  });

  testWidgets('captures Terminal profile tab', (tester) async {
    await _captureTab(tester, tabKey: 'terminal', goldenName: '03-terminal');
  });

  testWidgets('captures Appearance profile tab', (tester) async {
    await _captureTab(
      tester,
      tabKey: 'appearance',
      goldenName: '04-appearance',
    );
  });

  testWidgets('captures Keys profile tab', (tester) async {
    await _captureTab(tester, tabKey: 'keys', goldenName: '05-keys');
  });

  testWidgets('captures Automation profile tab', (tester) async {
    await _captureTab(
      tester,
      tabKey: 'automation',
      goldenName: '06-automation',
    );
  });

  testWidgets('captures Advanced profile tab', (tester) async {
    await _captureTab(tester, tabKey: 'advanced', goldenName: '07-advanced');
  });
}
