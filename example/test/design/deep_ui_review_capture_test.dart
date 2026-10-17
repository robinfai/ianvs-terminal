import 'dart:async';

import 'package:app/features/ai/ai_api_client.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/shortcut_editor.dart';
import 'package:app/features/sftp/sftp_file_actions.dart';
import 'package:app/features/sftp/sftp_side_panel.dart';
import 'package:app/ui/app_ui.dart';
import 'package:app/ui/previews/command_blocks_preview.dart';
import 'package:app/ui/previews/mobile_prd_component_previews.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ai/terminal_ai_stream_test.dart' show ControlledStreamingApi;
import '../ai/terminal_ai_test.dart' show FakeTerminal, MemoryAiStore;
import 'configuration_capture_binding.dart';
import 'ui_review_capture.dart';
import 'visual_capture_fonts.dart';

class _Files implements SftpDirectoryDataSource, SftpFileDataSource {
  _Files(this.scene);
  final String scene;
  final pending = Completer<SftpDirectorySnapshot>();
  @override
  SftpDirectoryLoadOperation startListDirectory(SftpDirectoryRequest request) =>
      SftpDirectoryLoadOperation(
        onCancel: () {},
        future: scene == 'sftp-loading'
            ? pending.future
            : scene == 'sftp-error'
            ? Future.error(
                const SftpDirectoryUnavailableException('连接已中断，请重试。'),
              )
            : Future.value(
                SftpDirectorySnapshot(
                  path: '/',
                  entries: [
                    if (scene != 'sftp-empty')
                      const SftpDirectoryEntry(
                        name: 'deploy.log',
                        kind: SftpDirectoryEntryKind.file,
                      ),
                  ],
                ),
              ),
      );
  @override
  Future<void> downloadFile(SftpFileTransferRequest request) async =>
      throw StateError('No I/O in visual fixture');
  @override
  Future<void> uploadFile(SftpFileTransferRequest request) async =>
      throw StateError('No I/O in visual fixture');
  @override
  Future<void> createDirectory(SftpEntryMutationRequest request) async =>
      throw StateError('No mutation in visual fixture');
  @override
  Future<void> deleteEntry(SftpEntryMutationRequest request) async =>
      throw StateError('No mutation in visual fixture');
}

void main() {
  ConfigurationCaptureBinding();
  setUpAll(loadVisualCaptureFonts);
  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    for (final brightness in Brightness.values) {
      for (final landscape in [false, true]) {
        if (platform == TargetPlatform.macOS && landscape) continue;
        for (final scene in [
          'shortcut-capture',
          'shortcut-unsafe',
          'shortcut-conflict',
          'sftp-loading',
          'sftp-empty',
          'sftp-error',
          'sftp-busy',
          'sftp-delete',
          'sftp-create',
          'sftp-create-error',
          'blocks-running',
          'blocks-long',
          'ai-waiting',
          'ai-streaming',
          'ai-loading-proposal',
          'ai-target-changed',
        ]) {
          testWidgets(
            'deep UI ${platform.name} ${brightness.name} $landscape $scene',
            (tester) async {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = platform == TargetPlatform.macOS
                  ? const Size(1280, 900)
                  : landscape
                  ? const Size(874, 402)
                  : const Size(402, 874);
              addTearDown(tester.view.reset);
              final theme = withVisualCaptureFonts(
                buildIanvsTerminalTheme(brightness, platform: platform),
              );
              final boundary = GlobalKey();
              final files = SftpFileActions();
              final busy = Completer<void>();
              const target = SftpSessionTarget(
                sessionId: 'visual',
                profileName: 'Review',
                host: 'review.example.test',
                user: 'review',
                port: 22,
              );
              var config = const LocalTerminalKeybindingsConfig();
              final settings = AiSettingsController(MemoryAiStore());
              await settings.loaded;
              final terminal = FakeTerminal();
              final api = ControlledStreamingApi();
              final ai = TerminalAiController(
                settings: settings,
                terminal: terminal,
                api: api,
              );
              await ai.refreshContext();
              addTearDown(() async {
                await tester.pumpWidget(const SizedBox.shrink());
                if (!busy.isCompleted) busy.complete();
                ai.dispose();
                settings.dispose();
                files.dispose();
              });
              final Widget content;
              if (scene.startsWith('shortcut-')) {
                content = StatefulBuilder(
                  builder: (context, setState) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: ShortcutEditorPanel(
                      config: config,
                      expandList: true,
                      onChanged: (value) => setState(() => config = value),
                    ),
                  ),
                );
              } else if (scene.startsWith('sftp-')) {
                content = SftpSidePanel(
                  target: target,
                  dataSource: _Files(scene),
                  fileActions: files,
                  onClose: () {},
                );
              } else if (scene == 'ai-loading-proposal' ||
                  scene == 'ai-target-changed') {
                content = TerminalAiComponentFixture(
                  component: MobilePrdPreviewComponent.proposalCard,
                  state: scene == 'ai-target-changed'
                      ? MobilePrdPreviewState.targetChanged
                      : MobilePrdPreviewState.loading,
                );
              } else {
                content = TerminalAiWorkspace(
                  controller: ai,
                  compactMobile: platform == TargetPlatform.iOS,
                  onClose: () {},
                );
              }
              await tester.pumpWidget(
                RepaintBoundary(
                  key: boundary,
                  child: scene.startsWith('blocks-')
                      ? CommandBlocksPreview(
                          theme: theme,
                          running: scene == 'blocks-running',
                          longOutput: scene == 'blocks-long',
                        )
                      : MaterialApp(
                          debugShowCheckedModeBanner: false,
                          theme: theme,
                          locale: const Locale('zh'),
                          localizationsDelegates:
                              AppLocalizations.localizationsDelegates,
                          supportedLocales: AppLocalizations.supportedLocales,
                          home: Scaffold(body: content),
                        ),
                ),
              );
              Future<void> frames() async {
                for (var i = 0; i < 10; i++) {
                  await tester.pump(const Duration(milliseconds: 100));
                }
              }

              await frames();
              if (scene.startsWith('shortcut-')) {
                await tester.enterText(
                  find.byKey(const Key('shortcut-editor-filter')),
                  AppLocalizations.of(
                    tester.element(find.byType(ShortcutEditorPanel)),
                  )!.terminalActionName('new_tab'),
                );
                await tester.pump();
                await tester.tap(find.byKey(const Key('shortcut-edit-newTab')));
                await tester.pumpAndSettle();
                expect(
                  find.byKey(const Key('shortcut-capture-dialog')),
                  findsOneWidget,
                );
                if (scene == 'shortcut-unsafe') {
                  await tester.sendKeyEvent(
                    LogicalKeyboardKey.keyN,
                    platform: platform == TargetPlatform.iOS ? 'ios' : 'macos',
                  );
                  await tester.pump();
                  expect(
                    find.byKey(const Key('shortcut-capture-error')),
                    findsOneWidget,
                  );
                } else if (scene == 'shortcut-conflict') {
                  final os = platform == TargetPlatform.iOS ? 'ios' : 'macos';
                  await tester.sendKeyDownEvent(
                    LogicalKeyboardKey.metaLeft,
                    platform: os,
                  );
                  await tester.sendKeyEvent(
                    LogicalKeyboardKey.comma,
                    platform: os,
                  );
                  await tester.sendKeyUpEvent(
                    LogicalKeyboardKey.metaLeft,
                    platform: os,
                  );
                  await tester.pump();
                  await tester.tap(
                    find.byKey(const Key('shortcut-capture-apply')),
                  );
                  await tester.pumpAndSettle();
                  expect(
                    find.byKey(const Key('shortcut-editor-conflict-summary')),
                    findsOneWidget,
                  );
                }
              }
              if (scene == 'sftp-busy') {
                unawaited(
                  files.runRemoteOperation(
                    sessionId: target.operationScopeId,
                    remotePath: '/deploy.log',
                    operation: () => busy.future,
                  ),
                );
                await frames();
                expect(
                  files.isRemotePathBusy(
                    target.operationScopeId,
                    '/deploy.log',
                  ),
                  isTrue,
                );
              }
              if (scene == 'sftp-delete') {
                if (platform == TargetPlatform.iOS) {
                  await tester.tap(
                    find.byKey(const Key('sftp-entry-actions-deploy.log')),
                  );
                } else {
                  await tester.tap(
                    find.text('deploy.log'),
                    buttons: kSecondaryMouseButton,
                  );
                }
                await tester.pumpAndSettle();
                await tester.tap(find.byKey(const Key('sftp-context-delete')));
                await tester.pumpAndSettle();
                expect(
                  find.byKey(const Key('sftp-delete-confirm')),
                  findsOneWidget,
                );
              }
              if (scene.startsWith('sftp-create')) {
                if (platform == TargetPlatform.iOS) {
                  await tester.tap(find.byKey(const Key('sftp-create-folder')));
                } else {
                  await tester.tap(
                    find.text('deploy.log'),
                    buttons: kSecondaryMouseButton,
                  );
                  await tester.pumpAndSettle();
                  await tester.tap(
                    find.byKey(const Key('sftp-context-create-directory')),
                  );
                }
                await tester.pumpAndSettle();
                expect(
                  find.byKey(const Key('sftp-create-directory-name')),
                  findsOneWidget,
                );
                if (scene.endsWith('error')) {
                  await tester.tap(
                    find.byKey(const Key('sftp-create-directory-confirm')),
                  );
                  await tester.pumpAndSettle();
                  expect(
                    tester
                        .widget<TextField>(
                          find.byKey(const Key('sftp-create-directory-name')),
                        )
                        .decoration
                        ?.errorText,
                    isNotEmpty,
                  );
                }
              }
              if (scene == 'ai-waiting' || scene == 'ai-streaming') {
                unawaited(ai.ask('请解释这段部署日志，并指出需要关注的地方。'));
                await frames();
                expect(api.updates, hasLength(1));
                api.updates.single(
                  const AiResponseUpdate(AiResponseStage.waitingForFirstToken),
                );
                if (scene == 'ai-streaming') {
                  api.updates.single(
                    const AiResponseUpdate(
                      AiResponseStage.generating,
                      textDelta: '正在检查部署日志。\n\n依赖安装已经完成，接下来核对服务启动状态与端口监听。',
                    ),
                  );
                }
                await frames();
                expect(terminal.writes, isEmpty);
              }
              await captureUiReview(
                tester,
                boundary,
                '${platform.name}-${brightness.name}-${landscape ? 'landscape' : 'portrait'}-$scene',
              );
              expect(tester.takeException(), isNull);
            },
            variant: TargetPlatformVariant.only(platform),
          );
        }
      }
    }
  }
}
