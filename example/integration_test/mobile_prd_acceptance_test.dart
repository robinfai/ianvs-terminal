// Run only in the isolated work.ianvs.trail.mobileprd application. The fixture
// supplies a disposable SSH host; no saved Profile, AI key or layout is read.
import 'dart:convert';
import 'dart:io';

import 'package:app/app.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/macos_integration_test_lifecycle.dart';
import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_local_terminal_config_repository.dart';
import '../test/support/memory_profile_repository.dart';
import '../test/support/no_io_local_session_recording_repository.dart';
import '../test/support/no_io_local_terminal_layout_repository.dart';

final class _MemoryAiStore implements AiConfigurationStore {
  _MemoryAiStore(this.value);
  AiConfiguration? value;

  @override
  Future<AiConfiguration?> read() async => value;

  @override
  Future<void> write(AiConfiguration? configuration) async {
    value = configuration;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('PRD isolated native SSH failure, diagnosis and approval', (
    tester,
  ) async {
    ensureMacosIntegrationTestFramesEnabled(tester.binding);
    const definition = String.fromEnvironment('TRAIL_MOBILE_PRD_FIXTURE');
    if (definition.isEmpty) {
      fail('Build with tools/mobile_prd/build_ios_fixture.sh and its fixture.');
    }
    final fixture = (jsonDecode(definition) as Map).cast<String, Object?>();
    final evidenceBase = Uri.parse(fixture['evidenceBaseUrl']! as String);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    addTearDown(client.close);
    Future<Map<String, Object?>> request(
      String path, [
      Map<String, Object?>? body,
    ]) async {
      final response = await tester.runAsync(() async {
        final outgoing = body == null
            ? await client.getUrl(evidenceBase.resolve(path))
            : await client.postUrl(evidenceBase.resolve(path));
        if (body != null) {
          outgoing.headers.contentType = ContentType.json;
          outgoing.write(jsonEncode(body));
        }
        final incoming = await outgoing.close().timeout(
          const Duration(seconds: 30),
        );
        final text = await utf8.decoder.bind(incoming).join();
        if (incoming.statusCode != 200) {
          throw StateError('Fixture endpoint $path: ${incoming.statusCode}');
        }
        return (jsonDecode(text) as Map).cast<String, Object?>();
      });
      return response!;
    }

    Future<void> event(String name, Map<String, Object?> fields) async {
      await request('/events', {'event': name, ...fields});
    }

    Future<void> capture(String name) async {
      await tester.pump(const Duration(milliseconds: 400));
      final view = tester.view;
      final context = tester.element(find.byType(ShellScreen));
      await request('/checkpoint', {
        'name': name,
        'metadata': {
          'run_id': fixture['runId'],
          'capture_method': 'native_screenshot',
          'input_method': 'Flutter EditableText client; not native IME',
          'viewport_width': view.physicalSize.width / view.devicePixelRatio,
          'viewport_height': view.physicalSize.height / view.devicePixelRatio,
          'dpr': view.devicePixelRatio,
          'locale': Localizations.localeOf(context).toLanguageTag(),
          'theme': Theme.of(context).brightness.name,
          'keyboard_inset': MediaQuery.viewInsetsOf(context).bottom,
        },
      });
    }

    final home = await Directory.systemTemp.createTemp('trail-mobile-prd-');
    addTearDown(() => home.delete(recursive: true));
    final ssh = (fixture['ssh']! as Map).cast<String, Object?>();
    final knownHosts = File('${home.path}/known_hosts');
    await knownHosts.writeAsString(
      '[${ssh['host']}]:${ssh['port']} ${fixture['hostPublicKey']}\n',
    );
    final connection = TerminalConnectionConfig.fromJson({
      ...ssh,
      'hostKeyPolicy': 'strict',
      'knownHostsFile': knownHosts.path,
      'privateKeys': <String>[],
      'agentForwarding': false,
    });
    if (!connection.isSsh ||
        connection.auth != TerminalSshAuthMethod.password) {
      fail('The PRD harness requires the disposable password SSH fixture.');
    }
    final settings = AiSettingsController(
      _MemoryAiStore(
        AiConfiguration(
          endpoint: fixture['modelBaseUrl']! as String,
          apiKey: 'trail-local-mock',
          model: 'trail-mock',
        ),
      ),
    );
    await settings.loaded;
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(NativePtyBackend.load()),
        aiSettingsProvider.overrideWithValue(settings),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(
              profiles: [
                TerminalProfile(
                  id: 'mobile-prd-fixture',
                  name: 'dev-box · PRD fixture',
                  shell: '',
                  connection: connection,
                ),
              ],
            ),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          MemoryLocalTerminalConfigRepository(
            const LocalTerminalConfigDocument(
              defaultProfileId: 'mobile-prd-fixture',
              appearance: TerminalAppAppearance(
                preferredTerminalMode: TerminalViewMode.blocks,
              ),
            ),
          ),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          noIoLocalTerminalLayoutRepository(),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          noIoLocalSessionRecordingRepository(),
        ),
        shellAnimationsEnabledProvider.overrideWithValue(false),
        shellNotificationSenderProvider.overrideWithValue(
          ({required title, body, identifier, expiresAfterMs}) async {},
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final tab in container.read(sessionControllerProvider).tabs) {
        for (final pane in tab.effectivePanes) {
          await container
              .read(sessionControllerProvider.notifier)
              .closeSession(pane.sessionId);
        }
      }
      container.dispose();
      settings.dispose();
    });
    Future<void> until(bool Function() ready, String label) async {
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (!ready()) {
        if (DateTime.now().isAfter(deadline)) {
          await capture('failure-timeout');
          fail('Timed out waiting for $label');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> click(Finder finder) async {
      await until(() => finder.evaluate().isNotEmpty, 'visible control');
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 300));
    }

    // This drives the production editor, but is deliberately not IME evidence.
    Future<void> enter(Finder finder, String text) async {
      await click(finder);
      tester
          .state<EditableTextState>(
            find.descendant(of: finder, matching: find.byType(EditableText)),
          )
          .updateEditingValue(
            TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length),
            ),
          );
      await tester.pump(const Duration(milliseconds: 300));
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const IanvsTerminalApp(),
      ),
    );
    await until(
      () => container.read(sessionControllerProvider).activeSessionId != null,
      'isolated SSH session',
    );
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    final runtime = container.read(terminalRuntimeControllerProvider);
    await until(
      () =>
          runtime.composerRequest(
            sessionId,
            'composer.state',
            const {},
          )?['state'] ==
          'ready',
      'native SSH shell negotiation',
    );
    await until(
      () => find.byKey(const Key('composer-editor')).evaluate().isNotEmpty,
      'Blocks composer',
    );
    await capture('initial-blocks');
    final before = await request('/state');
    await enter(find.byKey(const Key('composer-editor')), 'trail-fixture fail');
    final composer = tester
        .widget<TerminalComposerView>(find.byType(TerminalComposerView))
        .controller;
    composer.dismissCompletions();
    await tester.pump();
    await click(find.byKey(const Key('composer-primary-action')));
    List<Map<String, Object?>> blocks() =>
        ((runtime.commandBlocks(sessionId)?['blocks'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
    Map<String, Object?>? failedBlock() => blocks()
        .where((block) => block['command'] == 'trail-fixture fail')
        .firstOrNull;
    await until(
      () => failedBlock()?['exitCode'] != null,
      'native failure exit',
    );
    expect(failedBlock()!['exitCode'], 2);
    FocusManager.instance.primaryFocus?.unfocus();
    await capture('failed-block');
    final failedId = failedBlock()!['id']! as String;
    final block = find.byKey(ValueKey('command-block-$failedId'));
    await tester.ensureVisible(block);
    // The same fixture can capture B and C. B uses the old menu; C can expose
    // the direct action. Neither branch invokes the AI controller directly.
    final direct = find.byKey(ValueKey('block-ai-diagnose-$failedId'));
    if (direct.evaluate().isNotEmpty) {
      await click(direct);
    } else {
      await click(
        find
            .descendant(
              of: block,
              matching: find.byType(PopupMenuButton<String>),
            )
            .first,
      );
      await click(
        find.byWidgetPredicate(
          (widget) => widget is PopupMenuItem<String> && widget.value == 'ai',
        ),
      );
    }
    await capture('diagnostic-draft');
    final attached = await request('/state');
    expect(attached['model_requests'], before['model_requests']);
    expect(attached['execution_count'], before['execution_count']);
    expect(failedBlock()!['id'], failedId);
    await event('diagnosis_prepares_only', {
      'model_requests_unchanged': true,
      'fixture_executions_unchanged': true,
      'source_block_unchanged': true,
    });
    await enter(find.byKey(const Key('ai-prompt')), '诊断这个失败并提出修复命令');
    await click(find.byKey(const Key('ai-send')));
    await until(
      () => tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .controller
          .canApprove,
      'proposal awaiting manual review',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await capture('proposal-compact');
    final review = find.byKey(const Key('ai-review-action'));
    if (review.evaluate().isNotEmpty) await click(review);
    await capture('proposal-full-review');
    expect(
      (await request('/state'))['execution_count'],
      before['execution_count'],
    );
    await click(find.byKey(const Key('ai-approve')));
    await until(
      () => blocks().any(
        (block) =>
            block['command'] == 'trail-fixture repair' &&
            block['exitCode'] == 0,
      ),
      'native repair receipt',
    );
    final after = await request('/state');
    expect(after['execution_count'], (before['execution_count']! as int) + 1);
    await event('approved_native_result', {
      'execution_delta': 1,
      'native_exit_code': 0,
      'model_kind': 'deterministic_fixture',
    });
    await capture('execution-result');
    await event('run_finished', {
      'result': 'passed',
      'scope': 'isolated native SSH deterministic smoke; not full PRD gate',
    });
  });
}
