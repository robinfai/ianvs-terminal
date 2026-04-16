import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../profiles/profile_editor.dart';
import '../profiles/profile_models.dart';
import '../sessions/session_controller.dart';
import '../terminal/clipboard_bridge.dart';
import '../terminal/selection_controller.dart';
import '../terminal/terminal_input_controller.dart';
import '../terminal/terminal_viewport.dart';

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  final Map<String, SelectionController> _selectionControllers = {};

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(sessionControllerProvider);
    final sessionController = ref.read(sessionControllerProvider.notifier);
    final activeSessionId = sessionState.activeSessionId;

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            profiles: sessionState.profiles,
            defaultProfileId: sessionState.defaultProfileId,
            onCreateSession: sessionController.createSession,
            onEditProfile: (profile) async {
              final result = await showDialog<TerminalProfile>(
                context: context,
                builder: (context) =>
                    ProfileEditorDialog(initialValue: profile),
              );
              if (result != null) {
                await sessionController.saveProfile(result);
              }
            },
            onSetDefault: sessionController.setDefaultProfile,
          ),
          Expanded(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFE7E1D4), Color(0xFFF7F4EA)],
                ),
              ),
              child: Column(
                children: [
                  if (activeSessionId != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Shell workspace',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: const Color(0xFF111827),
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _sessionSummary(sessionState.tabs.length),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: const Color(0xFF4B5563)),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Active session',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: const Color(0xFF6B7280),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      children: [
                        for (final tab in sessionState.tabs)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InputChip(
                              selected: tab.sessionId == activeSessionId,
                              label: Text(tab.title),
                              onPressed: () => sessionController
                                  .activateSession(tab.sessionId),
                              onDeleted: () =>
                                  sessionController.closeSession(tab.sessionId),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: activeSessionId == null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Create a shell to get started'),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Reopen your default profile in one step.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: const Color(0xFF4B5563),
                                        ),
                                  ),
                                ],
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) {
                                    sessionController.resizeActiveSession(
                                      Size(
                                        constraints.maxWidth,
                                        constraints.maxHeight,
                                      ),
                                      MediaQuery.devicePixelRatioOf(context),
                                    );
                                  }
                                });

                                final selectionController =
                                    _selectionControllers.putIfAbsent(
                                      activeSessionId,
                                      SelectionController.new,
                                    );
                                final inputController = TerminalInputController(
                                  sessionId: activeSessionId,
                                  coreClient: ref.read(
                                    terminalCoreClientProvider,
                                  ),
                                  readSelection: () =>
                                      selectionController.textForFrame(
                                        sessionController
                                            .viewportFor(activeSessionId)
                                            .frame,
                                      ),
                                  copySelection: (text) =>
                                      ClipboardBridge.copy(text),
                                  readClipboard: ClipboardBridge.paste,
                                );

                                return Column(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: DecoratedBox(
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF111827),
                                          ),
                                          child: TerminalViewport(
                                            controller: sessionController
                                                .viewportFor(activeSessionId),
                                            selectionController:
                                                selectionController,
                                            inputController: inputController,
                                            onScrollLines: (delta) {
                                              ref
                                                  .read(
                                                    terminalCoreClientProvider,
                                                  )
                                                  .scrollViewport(
                                                    activeSessionId,
                                                    delta,
                                                  );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        FilledButton.tonal(
                                          onPressed: () async {
                                            final text = selectionController
                                                .textForFrame(
                                                  sessionController
                                                      .viewportFor(
                                                        activeSessionId,
                                                      )
                                                      .frame,
                                                );
                                            if (text.isEmpty) {
                                              return;
                                            }
                                            await ClipboardBridge.copy(text);
                                          },
                                          child: const Text('Copy'),
                                        ),
                                        const SizedBox(width: 8),
                                        FilledButton.tonal(
                                          onPressed: () async {
                                            final text =
                                                await ClipboardBridge.paste();
                                            if (text.isEmpty) {
                                              return;
                                            }
                                            ref
                                                .read(
                                                  terminalCoreClientProvider,
                                                )
                                                .sendInput(
                                                  activeSessionId,
                                                  Uint8List.fromList(
                                                    utf8.encode(text),
                                                  ),
                                                );
                                          },
                                          child: const Text('Paste'),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: sessionState.profiles.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => sessionController.createSession(
                sessionState.profiles.firstWhere(
                  (profile) => profile.id == sessionState.defaultProfileId,
                  orElse: () => sessionState.profiles.first,
                ),
              ),
              label: const Text('New Tab'),
              icon: const Icon(Icons.add),
            ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.profiles,
    required this.defaultProfileId,
    required this.onCreateSession,
    required this.onEditProfile,
    required this.onSetDefault,
  });

  final List<TerminalProfile> profiles;
  final String? defaultProfileId;
  final ValueChanged<TerminalProfile> onCreateSession;
  final ValueChanged<TerminalProfile> onEditProfile;
  final ValueChanged<String> onSetDefault;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF1F2937)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'flutterm',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFFFDE68A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Profiles',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFF9FAFB),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: profiles.length,
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      return Card(
                        color: const Color(0xFF374151),
                        child: ListTile(
                          title: Text(
                            profile.name,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            profile.shell,
                            style: const TextStyle(color: Color(0xFFD1D5DB)),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') {
                                onEditProfile(profile);
                              } else if (value == 'default') {
                                onSetDefault(profile.id);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              const PopupMenuItem(
                                value: 'default',
                                child: Text('Set as default'),
                              ),
                            ],
                          ),
                          leading: Icon(
                            profile.id == defaultProfileId
                                ? Icons.star
                                : Icons.terminal,
                            color: profile.id == defaultProfileId
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFF93C5FD),
                          ),
                          onTap: () => onCreateSession(profile),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _sessionSummary(int count) {
  if (count == 1) {
    return '1 active session';
  }
  return '$count active sessions';
}
