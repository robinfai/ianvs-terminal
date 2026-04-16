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

enum _ShellLauncherAction { newTab, copy, paste }

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  final Map<String, SelectionController> _selectionControllers = {};
  bool _isLauncherOpen = false;

  TerminalProfile? _defaultProfileFor(
    List<TerminalProfile> profiles,
    String? defaultProfileId,
  ) {
    if (profiles.isEmpty) {
      return null;
    }
    for (final profile in profiles) {
      if (profile.id == defaultProfileId) {
        return profile;
      }
    }
    return profiles.first;
  }

  Future<void> _copySelection(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController,
  ) async {
    final text = selectionController.textForFrame(
      sessionController.viewportFor(sessionId).frame,
    );
    if (text.isEmpty) {
      return;
    }
    await ClipboardBridge.copy(text);
  }

  Future<void> _pasteToSession(String sessionId) async {
    final text = await ClipboardBridge.paste();
    if (text.isEmpty) {
      return;
    }
    ref
        .read(terminalCoreClientProvider)
        .sendInput(sessionId, Uint8List.fromList(utf8.encode(text)));
  }

  Future<void> _openTopActionsLauncher(
    BuildContext context,
    SessionController sessionController,
    List<TerminalProfile> profiles,
    String? defaultProfileId,
  ) async {
    final defaultProfile = _defaultProfileFor(profiles, defaultProfileId);
    if (_isLauncherOpen || defaultProfile == null) {
      return;
    }

    setState(() {
      _isLauncherOpen = true;
    });

    final hasActiveSession =
        ref.read(sessionControllerProvider).activeSessionId != null;
    final action = await showDialog<_ShellLauncherAction>(
      context: context,
      barrierDismissible: true,
      requestFocus: true,
      builder: (dialogContext) {
        Widget actionTile({
          required IconData icon,
          required String title,
          required String subtitle,
          required _ShellLauncherAction value,
          required bool enabled,
        }) {
          return ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            enabled: enabled,
            onTap: enabled
                ? () => Navigator.of(dialogContext).pop(value)
                : null,
          );
        }

        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Top actions',
                          style: Theme.of(dialogContext).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close actions',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  actionTile(
                    icon: Icons.add_box_outlined,
                    title: 'New tab',
                    subtitle: 'Open your default shell profile.',
                    value: _ShellLauncherAction.newTab,
                    enabled: true,
                  ),
                  actionTile(
                    icon: Icons.copy_rounded,
                    title: 'Copy selection',
                    subtitle: 'Copy the current terminal selection.',
                    value: _ShellLauncherAction.copy,
                    enabled: hasActiveSession,
                  ),
                  actionTile(
                    icon: Icons.content_paste_rounded,
                    title: 'Paste clipboard',
                    subtitle: 'Send clipboard text to the active shell.',
                    value: _ShellLauncherAction.paste,
                    enabled: hasActiveSession,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _isLauncherOpen = false;
    });

    final currentState = ref.read(sessionControllerProvider);
    final currentSessionId = currentState.activeSessionId;
    switch (action) {
      case _ShellLauncherAction.newTab:
        sessionController.createSession(defaultProfile);
        return;
      case _ShellLauncherAction.copy:
        if (currentSessionId == null) {
          return;
        }
        final selectionController = _selectionControllers[currentSessionId];
        if (selectionController == null) {
          return;
        }
        await _copySelection(
          sessionController,
          currentSessionId,
          selectionController,
        );
        return;
      case _ShellLauncherAction.paste:
        if (currentSessionId == null) {
          return;
        }
        await _pasteToSession(currentSessionId);
        return;
      case null:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(sessionControllerProvider);
    final sessionController = ref.read(sessionControllerProvider.notifier);
    final activeSessionId = sessionState.activeSessionId;
    final defaultProfile = _defaultProfileFor(
      sessionState.profiles,
      sessionState.defaultProfileId,
    );
    final activeSelectionController = activeSessionId == null
        ? null
        : _selectionControllers.putIfAbsent(
            activeSessionId,
            SelectionController.new,
          );

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
                      child: _ShellPanel(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const _ShellSectionLabel('Workspace'),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Shell workspace',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            color: const Color(0xFF111827),
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _sessionSummary(sessionState.tabs.length),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: const Color(0xFF4B5563),
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Active session',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: const Color(0xFF6B7280),
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              FilledButton.tonalIcon(
                                onPressed: defaultProfile == null
                                    ? null
                                    : () => _openTopActionsLauncher(
                                        context,
                                        sessionController,
                                        sessionState.profiles,
                                        sessionState.defaultProfileId,
                                      ),
                                icon: const Icon(Icons.apps_rounded),
                                label: const Text('Actions'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (sessionState.tabs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _ShellPanel(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  const _ShellSectionLabel('Session tabs'),
                                  const Spacer(),
                                  Text(
                                    '${sessionState.tabs.length} open',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: const Color(0xFF6B7280),
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 40,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    for (final tab in sessionState.tabs)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: InputChip(
                                          selected:
                                              tab.sessionId == activeSessionId,
                                          showCheckmark: false,
                                          backgroundColor: const Color(
                                            0xFFF3F4F6,
                                          ),
                                          selectedColor: const Color(
                                            0xFFE5E7EB,
                                          ),
                                          label: Text(tab.title),
                                          labelStyle: TextStyle(
                                            color:
                                                tab.sessionId == activeSessionId
                                                ? const Color(0xFF111827)
                                                : const Color(0xFF4B5563),
                                            fontWeight:
                                                tab.sessionId == activeSessionId
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                          onPressed: () => sessionController
                                              .activateSession(tab.sessionId),
                                          onDeleted: () => sessionController
                                              .closeSession(tab.sessionId),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: activeSessionId == null
                          ? Center(
                              child: _ShellPanel(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const _ShellSectionLabel(
                                        'Ready when you are',
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Create a shell to get started',
                                      ),
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
                                ),
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
                                    activeSelectionController!;
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
                                          onPressed: () => _copySelection(
                                            sessionController,
                                            activeSessionId,
                                            selectionController,
                                          ),
                                          child: const Text('Copy'),
                                        ),
                                        const SizedBox(width: 8),
                                        FilledButton.tonal(
                                          onPressed: () =>
                                              _pasteToSession(activeSessionId),
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
              onPressed: defaultProfile == null
                  ? null
                  : () => sessionController.createSession(defaultProfile),
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

class _ShellPanel extends StatelessWidget {
  const _ShellPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}

class _ShellSectionLabel extends StatelessWidget {
  const _ShellSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: const Color(0xFF6B7280),
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
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
