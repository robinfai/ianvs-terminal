import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal_composer/terminal_mode.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../design/configuration_capture_binding.dart';
import '../design/visual_capture_fonts.dart';
import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';
import '../support/no_io_local_terminal_layout_repository.dart';

const _evidence = String.fromEnvironment('MOBILE_BLOCKS_EVIDENCE_DIR');

class _MobileBackend extends FakePtyBackend {
  String owner = 'draft';
  String contextId = 'root';
  final submissions = <String>[];
  @override
  PtyRuntimeCapabilities get runtimeCapabilities =>
      PtyRuntimeCapabilities.fromJson({
        'schema_version': 1,
        'runtime_contract': 'ianvs-runtime-contract-v1',
        'frame_schema_versions': <String>[],
        'recording_schema_versions': <int>[],
        'features': ['session-config.json.v1', 'ssh-session.v1'],
      });

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    if (request['kind'] == 'completion.query') {
      final query = Map<String, Object?>.of(request)..remove('kind');
      return jsonEncode({
        'schemaVersion': 1,
        'query': query,
        'status': 'ok',
        'items': <Object?>[],
      });
    }
    if (request['kind'] == 'completion.local_start') {
      return jsonEncode({'status': 'unsupported_context'});
    }
    if (request['kind'] == 'composer.state') {
      return jsonEncode({
        'state': owner,
        'lease': owner == 'ready' ? 'lease-$contextId' : null,
        'contextId': contextId,
        'transport': 'shell',
        'cwd': '/srv/app',
        'dialect': 'bash',
      });
    }
    if (request['kind'] == 'composer.submit') {
      submissions.add(request['text']! as String);
      return jsonEncode({'outcome': 'accepted'});
    }
    if (request['kind'] == 'terminal.command_blocks') {
      final block = {
        'id': '1',
        'command': 'uname -a',
        'cwd': '/srv/app',
        'exitCode': owner == 'running' ? null : 0,
        'running': owner == 'running',
        'columns': 80,
        'totalLines': 12,
        'matchingLines': 12,
        'lines': [
          for (var i = 0; i < 12; i++)
            {
              'index': i,
              'text': 'cloud · output line ${i + 1}',
              'wrapped': false,
            },
        ],
      };
      return jsonEncode(
        request['id'] == null
            ? {
                'blocks': [block],
              }
            : {'block': block},
      );
    }
    return super.requestSessionJson(sessionId, requestJson);
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<({ProviderContainer container, String id})> _pump(
  WidgetTester tester,
  _MobileBackend backend, {
  TargetPlatform platform = TargetPlatform.iOS,
  Brightness brightness = Brightness.light,
  Size size = const Size(390, 844),
  double scale = 1,
  TerminalViewMode? preference,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    debugDefaultTargetPlatformOverride = null;
    tester.view.reset();
  });
  final profile = TerminalProfile(
    id: 'cloud',
    name: 'Cloud',
    shell: '',
    appearance: const TerminalDisplayConfig(
      font: TerminalFontConfig(family: 'monospace'),
    ),
    connection: const TerminalConnectionConfig.ssh(
      host: 'cloud.test',
      user: 'user',
    ),
  );
  var theme = buildIanvsTerminalTheme(brightness, platform: platform);
  if (_evidence.isNotEmpty) theme = withVisualCaptureFonts(theme);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(backend),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(profiles: [profile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(
            TerminalAppPreferencesDocument(
              appearance: TerminalAppAppearance(
                preferredTerminalMode: preference,
              ),
            ),
          ),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          MemoryLocalTerminalConfigRepository(
            LocalTerminalConfigDocument(
              appearance: TerminalAppAppearance(
                preferredTerminalMode: preference,
              ),
            ),
          ),
        ),
        pasteHistoryRepositoryProvider.overrideWithValue(
          MemoryPasteHistoryRepository(),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          noIoLocalTerminalLayoutRepository(),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          noIoLocalSessionRecordingRepository(),
        ),
      ],
      child: RepaintBoundary(
        key: const Key('mobile-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const ShellScreen(),
        ),
      ),
    ),
  );
  await _settle(tester);
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ShellScreen)),
  );
  if (container.read(sessionControllerProvider).activeSessionId == null) {
    container.read(sessionControllerProvider.notifier).createSession(profile);
    await _settle(tester);
  }
  expect(
    container.read(sessionControllerProvider).activeSessionId,
    isNotNull,
    reason: container.read(sessionControllerProvider).lastError,
  );
  return (
    container: container,
    id: container.read(sessionControllerProvider).activeSessionId!,
  );
}

TerminalModeState _mode(ProviderContainer container) => container
    .read(sessionControllerProvider)
    .tabs
    .first
    .activePane
    .terminalMode;

Future<void> _choose(
  WidgetTester tester,
  String id,
  TerminalViewMode mode,
) async {
  await tester.tap(find.byKey(const Key('shell-chrome-menu')));
  await _settle(tester);
  final item = find.byKey(Key('terminal-mode-${mode.name}-$id'));
  await tester.ensureVisible(item);
  await tester.tap(item);
  await _settle(tester);
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (_evidence.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('mobile-capture')),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_evidence).create(recursive: true);
    await File(
      '$_evidence/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  ConfigurationCaptureBinding();
  if (_evidence.isNotEmpty) setUpAll(loadVisualCaptureFonts);
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      '${platform.name} negotiates Blocks and preserves manual Normal',
      (tester) async {
        final backend = _MobileBackend();
        final (:container, :id) = await _pump(
          tester,
          backend,
          platform: platform,
        );
        expect(
          container.read(sessionControllerProvider).preferredTerminalMode,
          TerminalViewMode.blocks,
        );
        expect(_mode(container).mode, TerminalViewMode.normal);
        expect(find.byType(TerminalComposerView), findsNothing);
        await tester.tap(find.byKey(const Key('shell-chrome-menu')));
        await _settle(tester);
        final blocksItem = find.byKey(Key('terminal-mode-blocks-$id'));
        expect(tester.widget<ListTile>(blocksItem).enabled, isFalse);
        // The open sheet must reflect the negotiation result without reopening.
        backend.owner = 'ready';
        await _settle(tester);
        expect(_mode(container).mode, TerminalViewMode.blocks);
        expect(tester.widget<ListTile>(blocksItem).enabled, isTrue);
        final normalItem = find.byKey(Key('terminal-mode-normal-$id'));
        expect(tester.getSize(normalItem).height, greaterThanOrEqualTo(48));
        await _capture(tester, '${platform.name}-menu');
        await tester.tap(normalItem);
        await _settle(tester);
        backend.owner = 'draft';
        await _settle(tester);
        backend.owner = 'ready';
        await _settle(tester);
        expect(_mode(container).mode, TerminalViewMode.normal);
        await _choose(tester, id, TerminalViewMode.blocks);
        await tester.enterText(
          find.byKey(const Key('composer-editor')),
          'echo 移动端',
        );
        expect(backend.writes, isEmpty);
        await _choose(tester, id, TerminalViewMode.normal);
        await _choose(tester, id, TerminalViewMode.blocks);
        final editor = tester.widget<TextField>(
          find.byKey(const Key('composer-editor')),
        );
        expect(editor.controller!.text, 'echo 移动端');
        expect(editor.focusNode!.hasFocus, isTrue);
        await tester.tap(find.byKey(const Key('composer-primary-action')));
        await _settle(tester);
        expect(backend.submissions, ['echo 移动端']);
        expect(backend.writes, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('SSH hop and fullscreen fall back; restore remains manual', (
    tester,
  ) async {
    final backend = _MobileBackend()..owner = 'ready';
    final (:container, :id) = await _pump(tester, backend);
    expect(_mode(container).mode, TerminalViewMode.blocks);
    await tester.enterText(
      find.byKey(const Key('composer-editor')),
      'saved draft',
    );
    backend.owner = 'draft';
    backend.enqueueEvent(
      id,
      PtyEvent(
        kind: 'shell_hook',
        sessionId: id,
        payload: {
          'hook': 'bootstrap.checking',
          'context_id': 'hop',
          'parent_context_id': 'root',
          'context_kind': 'ssh',
          'host_context_id': 'hop',
        },
      ),
    );
    await _settle(tester);
    expect(_mode(container).mode, TerminalViewMode.normal);
    expect(_mode(container).canUseBlocks, isFalse);
    expect(
      tester
          .widget<Badge>(find.byKey(const Key('mobile-terminal-mode-notice')))
          .isLabelVisible,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await _settle(tester);
    expect(
      tester
          .widget<ListTile>(find.byKey(Key('terminal-mode-blocks-$id')))
          .enabled,
      isFalse,
    );
    await _capture(tester, 'ios-fallback');
    backend.contextId = 'hop';
    backend.owner = 'ready';
    await _settle(tester);
    expect(_mode(container).mode, TerminalViewMode.normal);
    expect(_mode(container).notice, TerminalModeNotice.blocksRestored);
    await tester.tap(find.byKey(Key('terminal-mode-blocks-$id')));
    await _settle(tester);
    backend.owner = 'running';
    backend.setFrame(id, {
      'rows': [
        {'index': 0, 'text': 'top — process list'},
      ],
      'viewport_rows': 24,
      'viewport_cols': 80,
      'modes': {'alternate_screen': true},
    });
    await _settle(tester);
    expect(_mode(container).mode, TerminalViewMode.normal);
    expect(
      _mode(container).unavailableReason,
      BlockUnavailableReason.fullScreen,
    );
    expect(find.byType(TerminalComposerView), findsNothing);
    expect(find.byType(TerminalCommandBlocksView), findsNothing);
    expect(
      tester
          .widget<TerminalViewport>(find.byType(TerminalViewport))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    backend.setFrame(id, {
      'rows': <Object?>[],
      'viewport_rows': 24,
      'viewport_cols': 80,
    });
    backend.owner = 'ready';
    await _settle(tester);
    expect(_mode(container).mode, TerminalViewMode.normal);
    expect(_mode(container).canUseBlocks, isTrue);
    await _choose(tester, id, TerminalViewMode.blocks);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('composer-editor')))
          .controller!
          .text,
      'saved draft',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'main-screen application modes fall back without an alternate buffer',
    (tester) async {
      final backend = _MobileBackend()..owner = 'ready';
      final (:container, :id) = await _pump(tester, backend);
      // Prompt editors may use application keys; a prompt alone is not a TUI.
      backend.setFrame(id, {
        'rows': <Object?>[],
        'viewport_rows': 24,
        'viewport_cols': 80,
        'modes': {
          'application_cursor': true,
          'application_keypad': true,
          'hide_cursor': true,
        },
      });
      await _settle(tester);
      expect(_mode(container).mode, TerminalViewMode.blocks);
      backend.owner = 'running';
      // Progress output hiding only its cursor remains a normal command block.
      backend.setFrame(id, {
        'rows': <Object?>[],
        'viewport_rows': 24,
        'viewport_cols': 80,
        'modes': {'hide_cursor': true},
      });
      await _settle(tester);
      expect(_mode(container).mode, TerminalViewMode.blocks);
      // Linux procps top uses DECCKM, DECKPAM and DECTCEM on the main buffer.
      backend.setFrame(id, {
        'rows': [
          {'index': 0, 'text': 'top — load average'},
        ],
        'viewport_rows': 24,
        'viewport_cols': 80,
        'modes': {
          'application_cursor': true,
          'application_keypad': true,
          'hide_cursor': true,
        },
      });
      await _settle(tester);
      expect(_mode(container).mode, TerminalViewMode.normal);
      expect(
        _mode(container).unavailableReason,
        BlockUnavailableReason.fullScreen,
      );
      expect(find.byType(TerminalCommandBlocksView), findsNothing);
      expect(find.byType(TerminalComposerView), findsNothing);
      // An application's input prompt can show its cursor again before exiting.
      backend.setFrame(id, {
        'rows': <Object?>[],
        'viewport_rows': 24,
        'viewport_cols': 80,
      });
      await _settle(tester);
      expect(_mode(container).canUseBlocks, isFalse);
      backend.owner = 'ready';
      await _settle(tester);
      expect(_mode(container).mode, TerminalViewMode.normal);
      expect(_mode(container).notice, TerminalModeNotice.blocksRestored);
      await _choose(tester, id, TerminalViewMode.blocks);
      expect(_mode(container).mode, TerminalViewMode.blocks);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final scene in [
    (
      name: 'phone',
      size: const Size(390, 844),
      keyboard: 300.0,
      scale: 1.0,
      brightness: Brightness.light,
    ),
    (
      name: 'landscape',
      size: const Size(844, 390),
      keyboard: 180.0,
      scale: 1.0,
      brightness: Brightness.light,
    ),
    (
      name: 'large-text-dark',
      size: const Size(360, 800),
      keyboard: 300.0,
      scale: 2.0,
      brightness: Brightness.dark,
    ),
    (
      name: 'landscape-large-text',
      size: const Size(844, 390),
      keyboard: 180.0,
      scale: 2.0,
      brightness: Brightness.dark,
    ),
    (
      name: 'ipad',
      size: const Size(1024, 768),
      keyboard: 280.0,
      scale: 1.0,
      brightness: Brightness.dark,
    ),
  ]) {
    testWidgets('mobile Block input fits ${scene.name} with the keyboard', (
      tester,
    ) async {
      final backend = _MobileBackend()..owner = 'ready';
      final (:container, :id) = await _pump(
        tester,
        backend,
        size: scene.size,
        brightness: scene.brightness,
        scale: scene.scale,
      );
      expect(_mode(container).mode, TerminalViewMode.blocks);
      if (scene.name == 'phone') {
        expect(find.text('末尾 6 / 12 行 · 查看全部'), findsOneWidget);
        await _capture(tester, 'ios-block');
        expect(
          find.byKey(const ValueKey('block-output-scroll-1')),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('block-expand-1')));
        await _settle(tester);
        expect(find.byKey(const Key('block-reader-scroll')), findsOneWidget);
        final readerBack = find.byKey(const Key('block-reader-close'));
        expect(tester.getSize(readerBack).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(readerBack).width, greaterThanOrEqualTo(44));
        final readerActions = find.byKey(const Key('block-reader-actions'));
        expect(tester.getSize(readerActions).height, greaterThanOrEqualTo(44));
        expect(readerActions.hitTestable(), findsOneWidget);
        await _capture(tester, 'ios-reader');
        await tester.tap(find.byKey(const Key('block-reader-close')));
        await _settle(tester);
      }
      await tester.enterText(
        find.byKey(const Key('composer-editor')),
        'echo 移动端',
      );
      tester.view.viewInsets = FakeViewPadding(bottom: scene.keyboard);
      await _settle(tester);
      expect(find.byKey(const Key('ios-terminal-input-bar')), findsNothing);
      expect(tester.takeException(), isNull);
      final run = find.byKey(const Key('composer-primary-action'));
      await tester.ensureVisible(run);
      await _settle(tester);
      expect(run.hitTestable(), findsOneWidget);
      expect(tester.getSize(run).height, greaterThanOrEqualTo(44));
      expect(
        tester.getBottomRight(run).dy,
        lessThanOrEqualTo(scene.size.height - scene.keyboard),
      );
      final surface = tester.getRect(find.byKey(const Key('composer-surface')));
      expect(surface.top, greaterThanOrEqualTo(0));
      expect(
        surface.bottom,
        lessThanOrEqualTo(scene.size.height - scene.keyboard),
        reason: 'The complete input surface must remain above the keyboard.',
      );
      if (scene.name.startsWith('landscape')) {
        final editable = find.descendant(
          of: find.byKey(const Key('composer-editor')),
          matching: find.byType(EditableText),
        );
        expect(
          tester.getRect(editable).center.dy,
          closeTo(tester.getRect(run).center.dy, 2),
          reason: 'Inline command text should align with the action row.',
        );
      }
      if (scene.name.startsWith('landscape') || scene.name == 'ipad') {
        expect(
          find.byKey(const ValueKey('block-expand-1')).hitTestable(),
          findsOneWidget,
          reason: 'Full output remains reachable with the keyboard open.',
        );
        expect(find.text('末尾 6 / 12 行 · 查看全部'), findsOneWidget);
      }
      await _capture(tester, 'ios-${scene.name}-keyboard');
      if (scene.name == 'ipad') {
        tester.view.viewInsets = FakeViewPadding.zero;
        await _settle(tester);
        await _choose(tester, id, TerminalViewMode.normal);
        expect(_mode(container).mode, TerminalViewMode.normal);
        expect(find.byType(TerminalComposerView), findsNothing);
      }
      if (scene.name == 'phone') {
        backend.owner = 'running';
        await _settle(tester);
        expect(find.byKey(const Key('ios-terminal-input-bar')), findsOneWidget);
        await tester.tap(find.byKey(const Key('ios-terminal-key-Control C')));
        expect(backend.writes, contains(orderedEquals([3])));
        backend.writes.clear();
        backend.owner = 'ready';
        await _settle(tester);
        expect(find.byKey(const Key('ios-terminal-input-bar')), findsNothing);
        await tester.tap(find.byKey(const Key('composer-dismiss-keyboard')));
        tester.view.viewInsets = FakeViewPadding.zero;
        await _settle(tester);
        await tester.tap(find.byKey(const Key('mobile-show-keyboard')));
        await _settle(tester);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('composer-editor')))
              .focusNode!
              .hasFocus,
          isTrue,
        );
      }
      expect(backend.writes, isEmpty);
      expect(id, isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('mobile settings save Normal for new sessions only', (
    tester,
  ) async {
    final backend = _MobileBackend()..owner = 'ready';
    final (:container, :id) = await _pump(tester, backend);
    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await _settle(tester);
    final settings = find.byKey(const Key('shell-command-defaults'));
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await _settle(tester);
    await tester.tap(find.byKey(const Key('defaults-section-general')));
    await _settle(tester);
    final choices = find.byKey(const Key('defaults-terminal-mode-options'));
    await tester.ensureVisible(choices);
    await tester.tap(choices);
    await _settle(tester);
    await tester.tap(
      find.byKey(const Key('default-terminal-mode-normal')).last,
    );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('defaults-save')));
    await _settle(tester);
    expect(
      container.read(sessionControllerProvider).preferredTerminalMode,
      TerminalViewMode.normal,
    );
    expect(_mode(container).mode, TerminalViewMode.blocks);
    container
        .read(sessionControllerProvider.notifier)
        .createSession(
          container.read(sessionControllerProvider).profiles.first,
        );
    await _settle(tester);
    final state = container.read(sessionControllerProvider);
    expect(state.activeSessionId, isNot(id));
    expect(
      state.tabs.last.activePane.terminalMode.mode,
      TerminalViewMode.normal,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('explicit Normal preference overrides the mobile default', (
    tester,
  ) async {
    final backend = _MobileBackend()..owner = 'ready';
    final (:container, :id) = await _pump(
      tester,
      backend,
      preference: TerminalViewMode.normal,
    );
    expect(_mode(container).mode, TerminalViewMode.normal);
    expect(_mode(container).canUseBlocks, isTrue);
    await _choose(tester, id, TerminalViewMode.blocks);
    expect(_mode(container).mode, TerminalViewMode.blocks);
    expect(
      container.read(sessionControllerProvider).preferredTerminalMode,
      TerminalViewMode.normal,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
