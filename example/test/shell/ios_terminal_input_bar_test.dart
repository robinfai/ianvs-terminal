import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/shell/ios_terminal_input_bar.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  if (const bool.fromEnvironment('CAPTURE_IOS_KEYBOARD')) {
    setUpAll(_loadCaptureFonts);
  }
  testWidgets('primary keys send terminal input and retain keyboard focus', (
    tester,
  ) async {
    final sent = <List<int>>[];
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var dismissed = false;
    await _pump(
      tester,
      onSend: sent.add,
      focus: focus,
      onDismiss: () => dismissed = true,
    );
    focus.requestFocus();
    await tester.pump();
    expect(find.byKey(const Key('ios-terminal-text-size')), findsNothing);
    expect(find.byKey(const Key('ios-terminal-extra-keys')), findsNothing);
    for (final entry in <String, List<int>>{
      'Escape': [27],
      'Tab': [9],
      'Control C': [3],
      'Control R': [18],
      'Control L': [12],
      'Move cursor left': [27, 91, 68],
      'Next command': [27, 91, 66],
      'Previous command': [27, 91, 65],
      'Move cursor right': [27, 91, 67],
    }.entries) {
      final key = _key(entry.key);
      await tester.ensureVisible(key);
      await tester.pumpAndSettle();
      expect(key.hitTestable(), findsOneWidget);
      await tester.tap(key);
      await tester.pump();
      expect(sent.last, entry.value);
      expect(focus.hasFocus, isTrue);
    }
    await tester.tap(find.byKey(const Key('ios-terminal-dismiss-keyboard')));
    expect(dismissed, isTrue);
  });

  testWidgets('groups send complete chords without leaving modifiers active', (
    tester,
  ) async {
    final sent = <List<int>>[];
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _pump(tester, onSend: sent.add, focus: focus);
    focus.requestFocus();
    await tester.pump();
    await tester.tap(find.byKey(const Key('ios-terminal-more')));
    await tester.pumpAndSettle();
    final groups = <String, Map<String, List<int>>>{
      'editing': {
        'Control A': [1],
        'Control E': [5],
        'Control U': [21],
        'Control K': [11],
        'Control W': [23],
        'Control Y': [25],
      },
      'control': {
        'Control D': [4],
        'Control Z': [26],
        'Control G': [7],
        'Control B': [2],
        'Control O': [15],
        'Control X': [24],
      },
      'navigation': {
        'Home': [27, 91, 72],
        'End': [27, 91, 70],
        'Page up': [27, 91, 53, 126],
        'Page down': [27, 91, 54, 126],
        'Delete': [27, 91, 51, 126],
        'Shift Tab': [27, 91, 90],
        'Alt B': [27, 98],
        'Alt F': [27, 102],
      },
      'symbols': {
        for (final symbol in ['/', '|', r'\', r'$', '`', '{', '}', '<', '>'])
          symbol: symbol.codeUnits,
      },
    };
    for (final group in groups.entries) {
      await _selectGroup(tester, group.key);
      expect(focus.hasFocus, isTrue);
      for (final entry in group.value.entries) {
        await tester.ensureVisible(_key(entry.key));
        await tester.pumpAndSettle();
        await tester.tap(_key(entry.key));
        await tester.pump();
        expect(sent.last, entry.value);
        expect(focus.hasFocus, isTrue);
      }
    }
    await tester.tap(find.byKey(const Key('ios-terminal-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ios-terminal-extra-keys')), findsNothing);
    await tester.tap(_key('Tab'));
    expect(sent.last, [9]);
  });

  for (final brightness in Brightness.values) {
    for (final surface in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(844, 390),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '${brightness.name} $surface ${scale}x keeps all groups in one row',
          (tester) async {
            await _pump(
              tester,
              brightness: brightness,
              size: surface,
              scale: scale,
            );
            final bar = find.byType(IosTerminalInputBar);
            final more = find.byKey(const Key('ios-terminal-more'));
            final dismiss = find.byKey(
              const Key('ios-terminal-dismiss-keyboard'),
            );
            for (final finder in [more, dismiss]) {
              expect(finder.hitTestable(), findsOneWidget);
              expect(tester.getSize(finder).width, greaterThanOrEqualTo(44));
              expect(tester.getSize(finder).height, greaterThanOrEqualTo(44));
            }
            final barHeight = tester.getSize(bar).height;
            expect(barHeight, tester.getSize(more).height + 8);
            if (scale == 1) expect(barHeight, 52);
            for (final key in ['Move cursor left', 'Move cursor right']) {
              await tester.ensureVisible(_key(key));
              await tester.pumpAndSettle();
              expect(_key(key).hitTestable(), findsOneWidget);
              expect(tester.getCenter(_key(key)).dy, tester.getCenter(more).dy);
            }
            await tester.ensureVisible(_key('Escape'));
            await tester.pumpAndSettle();
            if (surface.width == 390 && scale == 1) {
              await _capture(tester, '${brightness.name}-collapsed');
            }
            await tester.tap(more);
            await tester.pumpAndSettle();
            for (final group in [
              'editing',
              'control',
              'navigation',
              'symbols',
            ]) {
              await _selectGroup(tester, group);
              expect(tester.getSize(bar).height, barHeight);
              expect(
                find.byKey(const Key('ios-terminal-primary-list')),
                findsNothing,
              );
              expect(more.hitTestable(), findsOneWidget);
              expect(dismiss.hitTestable(), findsOneWidget);
              expect(tester.takeException(), isNull);
            }
            if (surface.width == 390 && scale == 1) {
              await _selectGroup(tester, 'editing');
              await _capture(tester, '${brightness.name}-expanded');
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('VoiceOver announces shortcut meaning and expansion state once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    expect(find.bySemanticsLabel('Control C · 中断'), findsOneWidget);
    expect(find.bySemanticsLabel('Control R · 搜索命令历史'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const Key('ios-terminal-more'))),
      matchesSemantics(
        label: '更多终端按键',
        isButton: true,
        hasTapAction: true,
        hasExpandedState: true,
      ),
    );
    await tester.tap(find.byKey(const Key('ios-terminal-more')));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const Key('ios-terminal-more'))),
      matchesSemantics(
        label: '收起扩展按键',
        isButton: true,
        hasTapAction: true,
        hasExpandedState: true,
        isExpanded: true,
      ),
    );
    semantics.dispose();
  });
}

Finder _key(String label) => find.byKey(Key('ios-terminal-key-$label'));

Future<void> _selectGroup(WidgetTester tester, String group) async {
  await tester.tap(find.byKey(const Key('ios-terminal-key-group')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('ios-terminal-group-$group')));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
  double scale = 1,
  ValueChanged<List<int>>? onSend,
  FocusNode? focus,
  VoidCallback? onDismiss,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final theme = buildIanvsTerminalTheme(
    brightness,
    platform: TargetPlatform.iOS,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: const bool.fromEnvironment('CAPTURE_IOS_KEYBOARD')
          ? theme.copyWith(
              textTheme: theme.textTheme.apply(
                fontFamily: 'KeyboardCaptureSans',
                fontFamilyFallback: ['KeyboardCaptureChinese'],
              ),
            )
          : theme,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              Expanded(
                child: focus == null
                    ? const SizedBox()
                    : TextField(focusNode: focus),
              ),
              RepaintBoundary(
                key: const Key('keyboard-capture'),
                child: IosTerminalInputBar(
                  palette: AppThemeTokens.of(context),
                  keyboardVisible: true,
                  onSendBytes: onSend ?? (_) {},
                  onDismissKeyboard: onDismiss ?? () {},
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_IOS_KEYBOARD')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('keyboard-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory = Directory('/private/tmp/ianvs-keyboard-review');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> _loadCaptureFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  for (final font in <String, String>{
    'KeyboardCaptureSans': '/System/Library/Fonts/SFNS.ttf',
    'KeyboardCaptureChinese': '/System/Library/Fonts/STHeiti Light.ttc',
    'MaterialIcons':
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    final loader = FontLoader(font.key)
      ..addFont(File(font.value).readAsBytes().then(ByteData.sublistView));
    await loader.load();
  }
}
