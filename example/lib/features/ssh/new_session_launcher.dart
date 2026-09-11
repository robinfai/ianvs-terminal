import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';
import '../profiles/profile_models.dart';
import '../terminal/terminal.dart' as terminal;
import 'ssh_private_key_material.dart';
import 'ssh_profile_import_service.dart';

typedef SshPrivateKeySelection = ({String path, String contents});
typedef SshPrivateKeyPicker = Future<SshPrivateKeySelection?> Function();

InputDecoration _iconlessSshInputDecoration(
  BuildContext context, {
  String? hintText,
  Widget? suffixIcon,
}) {
  final palette = context.appTheme;
  // InputDecoration's minimum constraint sizes the outer widget, not the
  // painted container. A narrow, invisible prefix applies the same adaptive
  // height as real icons without changing the normal text inset.
  return InputDecoration(
    hintText: hintText,
    prefixIcon: const SizedBox.shrink(),
    prefixIconConstraints: BoxConstraints(
      minWidth: palette.spacing.xs,
      minHeight: context.adaptiveControlHeight(palette.controls.regular),
    ),
    suffixIcon: suffixIcon,
  );
}

Future<SshPrivateKeySelection?> pickSshPrivateKeyFile() async {
  final file = await openFile(confirmButtonText: 'Select key');
  if (file == null) {
    return null;
  }
  if (await file.length() > maximumSshPrivateKeyBytes) {
    throw const FormatException('Private key files must be 64 KiB or smaller.');
  }
  final contents = validateSshPrivateKeyContents(await file.readAsString());
  return (path: file.path.isEmpty ? file.name : file.path, contents: contents);
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

final class NewSessionSelection {
  const NewSessionSelection({
    required this.profile,
    this.saveProfile = false,
    this.openSession = true,
  });

  final TerminalProfile profile;
  final bool saveProfile;
  final bool openSession;
}

final class SshProfileEditorResult {
  const SshProfileEditorResult({
    required this.profile,
    required this.saveProfile,
    this.clearSecrets = const {},
  });

  final TerminalProfile profile;
  final bool saveProfile;
  final Set<ProfileSecretField> clearSecrets;
}

class NewSessionLauncher extends StatefulWidget {
  const NewSessionLauncher({
    super.key,
    required this.profiles,
    required this.importOpenSshProfiles,
    this.customSshProfilesEnabled = true,
    this.localSessionsEnabled = true,
    this.initialConnectionType = terminal.TerminalConnectionType.local,
  });

  final List<TerminalProfile> profiles;
  final Future<SshProfileImportSnapshot> Function() importOpenSshProfiles;
  final bool customSshProfilesEnabled;
  final bool localSessionsEnabled;
  final terminal.TerminalConnectionType initialConnectionType;

  @override
  State<NewSessionLauncher> createState() => _NewSessionLauncherState();
}

class _NewSessionLauncherState extends State<NewSessionLauncher> {
  late terminal.TerminalConnectionType _type;
  Future<SshProfileImportSnapshot>? _importedProfiles;

  @override
  void initState() {
    super.initState();
    _type = widget.localSessionsEnabled
        ? widget.initialConnectionType
        : terminal.TerminalConnectionType.ssh;
    if (_type == terminal.TerminalConnectionType.ssh) {
      _importedProfiles = widget.importOpenSshProfiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + keyboardInset),
      child: Material(
        key: const Key('new-session-launcher'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 720),
            child: Padding(
              padding: EdgeInsets.all(palette.spacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.localSessionsEnabled
                              ? context.l10n.newTerminalTab
                              : context.l10n.newSshTab,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: context.l10n.close,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Text(
                    widget.localSessionsEnabled
                        ? context.l10n.chooseLocalShellOrSsh
                        : context.l10n.chooseSavedSshOrCreate,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: palette.textSubtle),
                  ),
                  if (widget.localSessionsEnabled) ...[
                    SizedBox(height: palette.spacing.lg),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<terminal.TerminalConnectionType>(
                        key: const Key('new-session-type'),
                        segments: [
                          ButtonSegment(
                            value: terminal.TerminalConnectionType.local,
                            icon: const Icon(Icons.terminal_rounded),
                            label: Text(context.l10n.localShell),
                          ),
                          ButtonSegment(
                            value: terminal.TerminalConnectionType.ssh,
                            icon: const Icon(Icons.dns_outlined),
                            label: Text(context.l10n.sshSession),
                          ),
                        ],
                        selected: {_type},
                        onSelectionChanged: (selection) {
                          setState(() {
                            _type = selection.single;
                            if (_type == terminal.TerminalConnectionType.ssh) {
                              _importedProfiles ??= widget
                                  .importOpenSshProfiles();
                            }
                          });
                        },
                      ),
                    ),
                  ],
                  SizedBox(height: palette.spacing.lg),
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: _type == terminal.TerminalConnectionType.local
                          ? _LocalProfileList(
                              key: const ValueKey('local-sessions'),
                              profiles: widget.profiles
                                  .where((profile) => !profile.isSsh)
                                  .toList(growable: false),
                            )
                          : _SshProfileList(
                              key: const ValueKey('ssh-sessions'),
                              savedProfiles: widget.profiles
                                  .where(
                                    (profile) =>
                                        widget.customSshProfilesEnabled &&
                                        profile.isSsh,
                                  )
                                  .toList(growable: false),
                              importedProfiles: _importedProfiles ??= widget
                                  .importOpenSshProfiles(),
                              onRetryImport: () {
                                setState(() {
                                  _importedProfiles = widget
                                      .importOpenSshProfiles();
                                });
                              },
                              onCreateCustom: _createCustomSshProfile,
                              customSshProfilesEnabled:
                                  widget.customSshProfilesEnabled,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createCustomSshProfile() async {
    final result = await showCreateSshProfileDialog(
      context,
      saveProfileAvailable: widget.customSshProfilesEnabled,
    );
    if (!mounted || result == null) {
      return;
    }
    Navigator.of(context).pop(
      NewSessionSelection(
        profile: result.profile,
        saveProfile: result.saveProfile,
      ),
    );
  }
}

Future<SshProfileEditorResult?> showCreateSshProfileDialog(
  BuildContext context, {
  bool saveProfileAvailable = true,
}) {
  return showDialog<SshProfileEditorResult>(
    context: context,
    useSafeArea: !context.usesMobileNavigation,
    builder: (context) => SshProfileEditorDialog(
      initialValue: defaultTerminalProfile().copyWith(
        id: 'ssh-${DateTime.now().microsecondsSinceEpoch}',
        name: context.usesMobileNavigation ? '' : context.l10n.sshSession,
        connection: terminal.TerminalConnectionConfig.ssh(
          host: '',
          user: '',
          auth: context.usesMobileNavigation
              ? terminal.TerminalSshAuthMethod.password
              : terminal.TerminalSshAuthMethod.auto,
          hostKeyPolicy: terminal.TerminalSshHostKeyPolicy.acceptNew,
        ),
      ),
      allowSaveChoice: true,
      saveProfileAvailable: saveProfileAvailable,
    ),
  );
}

class _LocalProfileList extends StatelessWidget {
  const _LocalProfileList({super.key, required this.profiles});

  final List<TerminalProfile> profiles;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      itemCount: profiles.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final profile = profiles[index];
        return ListTile(
          key: Key('new-local-session-${profile.id}'),
          leading: const Icon(Icons.terminal_rounded),
          title: Text(profile.name),
          subtitle: Text(
            '${profile.shell} • ${terminalEmulationLabel(profile.terminalEmulation)}',
          ),
          trailing: const Icon(Icons.arrow_forward_rounded),
          onTap: () =>
              Navigator.of(context).pop(NewSessionSelection(profile: profile)),
        );
      },
    );
  }
}

class _SshProfileList extends StatefulWidget {
  const _SshProfileList({
    super.key,
    required this.savedProfiles,
    required this.importedProfiles,
    required this.onRetryImport,
    required this.onCreateCustom,
    required this.customSshProfilesEnabled,
  });

  final List<TerminalProfile> savedProfiles;
  final Future<SshProfileImportSnapshot> importedProfiles;
  final VoidCallback onRetryImport;
  final VoidCallback onCreateCustom;
  final bool customSshProfilesEnabled;

  @override
  State<_SshProfileList> createState() => _SshProfileListState();
}

class _SshProfileListState extends State<_SshProfileList> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(TerminalProfile profile) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    final connection = profile.connection;
    return profile.name.toLowerCase().contains(query) ||
        connection.host.toLowerCase().contains(query) ||
        connection.user.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final savedProfiles = widget.savedProfiles.where(_matches).toList();
    return ListView(
      shrinkWrap: true,
      children: [
        FilledButton.icon(
          key: const Key('new-custom-ssh-session'),
          onPressed: widget.onCreateCustom,
          icon: const Icon(Icons.add_rounded),
          label: Text(
            widget.customSshProfilesEnabled
                ? context.l10n.newSshConnectionLower
                : context.l10n.newOneTimeSshConnection,
          ),
        ),
        const SizedBox(height: 10),
        if (!widget.customSshProfilesEnabled) ...[
          ListTile(
            key: const Key('custom-ssh-requires-remote-api'),
            leading: const Icon(Icons.lock_clock_outlined),
            title: Text(context.l10n.connectionWillNotBeSaved),
            subtitle: Text(context.l10n.remoteDataRequiredToSaveSsh),
          ),
          const SizedBox(height: 10),
        ],
        Semantics(
          label: context.l10n.searchSshProfiles,
          textField: true,
          child: TextField(
            key: const Key('ssh-profile-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: context.l10n.searchByNameHostUser,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.l10n.clearSearch,
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        if (savedProfiles.isNotEmpty) ...[
          _SectionLabel(context.l10n.savedSshProfiles),
          for (final profile in savedProfiles)
            _SshProfileTile(
              profile: profile,
              imported: false,
              canImport: false,
            ),
        ],
        _SectionLabel(context.l10n.fromOpenSshConfig),
        FutureBuilder<SshProfileImportSnapshot>(
          future: widget.importedProfiles,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final imported = snapshot.requireData;
            if (imported.error != null) {
              return ListTile(
                leading: const Icon(Icons.warning_amber_rounded),
                title: Text(context.l10n.openSshProfilesUnavailable),
                subtitle: Text(imported.error!),
                trailing: TextButton(
                  onPressed: widget.onRetryImport,
                  child: Text(context.l10n.retry),
                ),
              );
            }
            if (imported.profiles.isEmpty) {
              return ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(context.l10n.noConcreteSshHosts),
                subtitle: Text(imported.sourcePath),
              );
            }
            final filteredProfiles = imported.profiles
                .where(_matches)
                .toList(growable: false);
            if (filteredProfiles.isEmpty && _search.text.trim().isNotEmpty) {
              return ListTile(
                leading: const Icon(Icons.search_off_rounded),
                title: Text(context.l10n.noMatchingSshProfiles),
                subtitle: Text(context.l10n.tryDifferentNameHostUser),
              );
            }
            return Column(
              children: [
                for (final profile in filteredProfiles)
                  _SshProfileTile(
                    profile: profile,
                    imported: true,
                    canImport: widget.customSshProfilesEnabled,
                  ),
                if (imported.warnings.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: Text(
                      '${imported.warnings.length} SSH config warning${imported.warnings.length == 1 ? '' : 's'}',
                    ),
                    subtitle: Text(imported.warnings.first),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SshProfileTile extends StatelessWidget {
  const _SshProfileTile({
    required this.profile,
    required this.imported,
    required this.canImport,
  });

  final TerminalProfile profile;
  final bool imported;
  final bool canImport;

  @override
  Widget build(BuildContext context) {
    final connection = profile.connection;
    return ListTile(
      key: Key('new-ssh-session-${profile.id}'),
      leading: Icon(imported ? Icons.description_outlined : Icons.dns_outlined),
      title: Text(profile.name),
      subtitle: Text(
        '${connection.user}@${connection.host}:${connection.port}'
        '${imported ? ' • OpenSSH config' : ''}',
      ),
      trailing: imported
          ? PopupMenuButton<_ImportedSshProfileAction>(
              key: Key('new-ssh-session-${profile.id}-actions'),
              tooltip: context.l10n.moreActionsFor(profile.name),
              position: PopupMenuPosition.under,
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (action) => _selectImportedAction(context, action),
              itemBuilder: (context) => [
                PopupMenuItem(
                  key: Key('new-ssh-session-${profile.id}-connect'),
                  value: _ImportedSshProfileAction.connect,
                  child: Text(context.l10n.connect),
                ),
                PopupMenuItem(
                  key: Key('new-ssh-session-${profile.id}-import'),
                  value: _ImportedSshProfileAction.import,
                  enabled: canImport,
                  child: Text(context.l10n.importAction),
                ),
              ],
            )
          : const Icon(Icons.arrow_forward_rounded),
      onTap: () => _completeSelection(context),
    );
  }

  void _selectImportedAction(
    BuildContext context,
    _ImportedSshProfileAction action,
  ) {
    switch (action) {
      case _ImportedSshProfileAction.connect:
        _completeSelection(context);
      case _ImportedSshProfileAction.import:
        _completeSelection(context, saveProfile: true, openSession: false);
    }
  }

  void _completeSelection(
    BuildContext context, {
    bool saveProfile = false,
    bool openSession = true,
  }) {
    Navigator.of(context).pop(
      NewSessionSelection(
        profile: profile,
        saveProfile: saveProfile,
        openSession: openSession,
      ),
    );
  }
}

enum _ImportedSshProfileAction { connect, import }

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        palette.spacing.sm,
        palette.spacing.lg,
        palette.spacing.sm,
        palette.spacing.xs,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: palette.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class SshProfileEditorDialog extends StatefulWidget {
  const SshProfileEditorDialog({
    super.key,
    required this.initialValue,
    this.allowSaveChoice = false,
    this.saveProfileAvailable = true,
    this.saveWhenPristine = true,
    this.privateKeyPicker,
  });

  final TerminalProfile initialValue;
  final bool allowSaveChoice;
  final bool saveProfileAvailable;
  final bool saveWhenPristine;
  final SshPrivateKeyPicker? privateKeyPicker;

  @override
  State<SshProfileEditorDialog> createState() => _SshProfileEditorDialogState();
}

class _SshProfileEditorDialogState extends State<SshProfileEditorDialog>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _privateKeyFieldKey = GlobalKey<FormFieldState<List<String>>>();
  final _scrollController = ScrollController();
  final _advancedController = ExpansibleController();
  final _nameFocus = FocusNode(debugLabel: 'ssh-profile-name');
  final _hostFocus = FocusNode();
  final _userFocus = FocusNode();
  final _portFocus = FocusNode(debugLabel: 'ssh-port');
  final _passwordFocus = FocusNode();
  final _privateKeysFocus = FocusNode();
  final _connectTimeoutFocus = FocusNode(debugLabel: 'ssh-connect-timeout');
  final _keepaliveFocus = FocusNode(debugLabel: 'ssh-keepalive');
  final _keepaliveCountFocus = FocusNode(debugLabel: 'ssh-keepalive-count');
  final _proxyJumpFocus = FocusNode(debugLabel: 'ssh-proxy-jump');
  final _portForwardsFocus = FocusNode(debugLabel: 'ssh-port-forwards');
  final _x11TargetFocus = FocusNode(debugLabel: 'ssh-x11-target');
  final _x11CookieFocus = FocusNode(debugLabel: 'ssh-x11-cookie');
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _user;
  late final TextEditingController _port;
  late final TextEditingController _password;
  late final TextEditingController _privateKeyPassphrase;
  late final TextEditingController _knownHostsFile;
  late final TextEditingController _connectTimeout;
  late final TextEditingController _keepalive;
  late final TextEditingController _keepaliveCount;
  late final TextEditingController _proxyCommand;
  late final TextEditingController _proxyJump;
  late final TextEditingController _portForwards;
  late final TextEditingController _agentSocket;
  late final TextEditingController _x11Target;
  late final TextEditingController _x11Cookie;
  late terminal.TerminalSshAuthMethod _auth;
  late terminal.TerminalSshHostKeyPolicy _hostKeyPolicy;
  late bool _agentForwarding;
  late bool _x11Forwarding;
  late List<String> _privateKeyValues;
  String? _privateKeyPath;
  String? _privateKeySelectionError;
  bool _selectingPrivateKey = false;
  bool _clearPassword = false;
  bool _clearPrivateKeys = false;
  bool _clearPrivateKeyPassphrase = false;
  bool _clearX11AuthCookie = false;
  late bool _saveProfile;
  bool _showAdvanced = false;
  bool _showValidationErrors = false;
  bool _obscurePassword = true;
  bool _obscurePrivateKeyPassphrase = true;
  bool _obscureX11Cookie = true;

  @override
  void initState() {
    super.initState();
    _saveProfile = widget.saveProfileAvailable;
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_handlePrimaryFocusChanged);
    final connection = widget.initialValue.connection;
    _name = TextEditingController(text: widget.initialValue.name);
    _host = TextEditingController(text: connection.host);
    _user = TextEditingController(text: connection.user);
    _port = TextEditingController(text: connection.port.toString());
    _password = TextEditingController(text: connection.password ?? '');
    _privateKeyValues = List<String>.of(connection.privateKeys);
    _privateKeyPath =
        connection.privateKeys.length == 1 &&
            !looksLikeSshPrivateKeyContents(connection.privateKeys.single)
        ? connection.privateKeys.single
        : null;
    _privateKeyPassphrase = TextEditingController(
      text: connection.privateKeyPassphrase ?? '',
    );
    _knownHostsFile = TextEditingController(
      text: connection.knownHostsFile ?? '',
    );
    _connectTimeout = TextEditingController(
      text: connection.connectTimeoutSeconds.toString(),
    );
    _keepalive = TextEditingController(
      text: connection.keepaliveSeconds.toString(),
    );
    _keepaliveCount = TextEditingController(
      text: connection.keepaliveCountMax.toString(),
    );
    _proxyCommand = TextEditingController(text: connection.proxyCommand ?? '');
    _proxyJump = TextEditingController(text: connection.proxyJump ?? '');
    _portForwards = TextEditingController(
      text: formatSshPortForwards(connection.portForwards),
    );
    _agentSocket = TextEditingController(text: connection.agentSocket ?? '');
    _x11Target = TextEditingController(
      text: connection.x11TargetHost == null || connection.x11TargetPort == 0
          ? ''
          : '${connection.x11TargetHost}:${connection.x11TargetPort}',
    );
    _x11Cookie = TextEditingController(text: connection.x11AuthCookie ?? '');
    _auth = connection.auth;
    _hostKeyPolicy = connection.hostKeyPolicy;
    _agentForwarding = connection.agentForwarding;
    _x11Forwarding = connection.x11Forwarding;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_handlePrimaryFocusChanged);
    _scrollController.dispose();
    _nameFocus.dispose();
    _hostFocus.dispose();
    _userFocus.dispose();
    _portFocus.dispose();
    _passwordFocus.dispose();
    _privateKeysFocus.dispose();
    _connectTimeoutFocus.dispose();
    _keepaliveFocus.dispose();
    _keepaliveCountFocus.dispose();
    _proxyJumpFocus.dispose();
    _portForwardsFocus.dispose();
    _x11TargetFocus.dispose();
    _x11CookieFocus.dispose();
    for (final controller in <TextEditingController>[
      _name,
      _host,
      _user,
      _port,
      _password,
      _privateKeyPassphrase,
      _knownHostsFile,
      _connectTimeout,
      _keepalive,
      _keepaliveCount,
      _proxyCommand,
      _proxyJump,
      _portForwards,
      _agentSocket,
      _x11Target,
      _x11Cookie,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _scheduleFocusedFieldReveal();
  }

  void _handlePrimaryFocusChanged() {
    _scheduleFocusedFieldReveal();
  }

  void _scheduleFocusedFieldReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (MediaQuery.viewInsetsOf(context).bottom <= 0) {
        return;
      }
      final focus = FocusManager.instance.primaryFocus;
      final focusContext = focus?.context;
      final renderObject = focusContext?.findRenderObject();
      if (focus == null ||
          !focus.hasFocus ||
          focusContext == null ||
          renderObject == null ||
          !renderObject.attached) {
        return;
      }
      final enclosingForm = focusContext.findAncestorWidgetOfExactType<Form>();
      if (enclosingForm?.key != _formKey) {
        return;
      }
      unawaited(
        Scrollable.ensureVisible(
          focusContext,
          alignment: 0.2,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return _buildThemedDialog(context);
  }

  Widget _buildThemedDialog(BuildContext context) {
    final palette = context.appTheme;
    final mobile = context.usesMobileNavigation;
    final mediaSize = MediaQuery.sizeOf(context);
    final width = mediaSize.width;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardVisible = keyboardInset > 0;
    final availableWidth = width - (width < 640 ? 24 : 64);
    final dialogWidth = availableWidth.clamp(0.0, 720.0);
    final compactKeyboardLayout =
        keyboardVisible && (width < 640 || mediaSize.height < width);
    final largeTextLayout =
        MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.3;
    final scrollsSaveChoice =
        context.usesTouchControlDensity ||
        compactKeyboardLayout ||
        largeTextLayout;
    final contentPadding = mobile
        ? EdgeInsets.zero
        : compactKeyboardLayout
        ? EdgeInsets.all(palette.spacing.sm)
        : const EdgeInsets.all(20);
    final showsPassword =
        _auth == terminal.TerminalSshAuthMethod.auto ||
        _auth == terminal.TerminalSshAuthMethod.password;
    final showsPrivateKeys =
        _auth == terminal.TerminalSshAuthMethod.auto ||
        _auth == terminal.TerminalSshAuthMethod.publicKey;
    final compactPrivateKeyAction = largeTextLayout || width < 520;
    Widget nameField() => AppConfigurationField(
      label: context.l10n.sessionName,
      child: Semantics(
        label: context.l10n.sessionName,
        textField: true,
        child: TextFormField(
          key: const Key('ssh-profile-name'),
          controller: _name,
          focusNode: _nameFocus,
          decoration: InputDecoration(
            hintText: context.l10n.exampleProduction,
            prefixIcon: const Icon(Icons.label_outline_rounded),
          ),
          validator: mobile ? null : _required,
        ),
      ),
    );
    Widget portControl() => Semantics(
      label: context.l10n.port,
      textField: true,
      child: TextFormField(
        key: const Key('ssh-port'),
        controller: _port,
        focusNode: _portFocus,
        keyboardType: TextInputType.number,
        decoration: _iconlessSshInputDecoration(context, hintText: '22'),
        validator: (value) => _boundedInteger(value, 1, 65535),
      ),
    );
    Widget saveChoice() => CheckboxListTile(
      key: const Key('ssh-save-profile'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: _saveProfile,
      title: Text(context.l10n.saveThisSshSession),
      subtitle: Text(
        widget.saveProfileAvailable
            ? context.l10n.secretsEncryptedDescription
            : context.l10n.remoteServiceRequiredToSaveProfile,
      ),
      onChanged: widget.saveProfileAvailable
          ? (value) => setState(() => _saveProfile = value ?? true)
          : null,
    );
    Widget mobileSubmit() => SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: const Key('ssh-connect'),
        onPressed:
            widget.allowSaveChoice || widget.saveWhenPristine || _hasChanges
            ? _submit
            : null,
        child: Text(
          widget.allowSaveChoice ? context.l10n.connect : context.l10n.save,
        ),
      ),
    );
    return Dialog(
      insetPadding: mobile
          ? EdgeInsets.zero
          : EdgeInsets.all(width < 640 ? 12 : 32),
      shape: mobile ? const RoundedRectangleBorder() : null,
      backgroundColor: mobile ? palette.panel : null,
      child: SafeArea(
        top: mobile,
        bottom: mobile,
        left: mobile,
        right: mobile,
        child: SizedBox(
          width: mobile ? width : dialogWidth,
          height: mobile ? mediaSize.height : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: mobile ? double.infinity : 700,
            ),
            child: Padding(
              padding: contentPadding,
              child: Form(
                key: _formKey,
                onChanged: () => setState(() {}),
                autovalidateMode: _showValidationErrors
                    ? AutovalidateMode.always
                    : AutovalidateMode.disabled,
                child: Column(
                  mainAxisSize: mobile || compactKeyboardLayout
                      ? MainAxisSize.max
                      : MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (mobile)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            IconButton(
                              key: const Key('ssh-mobile-back'),
                              tooltip: context.l10n.cancel,
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.chevron_left_rounded),
                            ),
                            Expanded(
                              child: Text(
                                context.l10n.sshConnection,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(width: kMinInteractiveDimension),
                          ],
                        ),
                      ),
                    if (!mobile && !compactKeyboardLayout) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.sshConnection,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                SizedBox(height: palette.spacing.xs),
                                Text(
                                  _name.text.trim().isEmpty
                                      ? context.l10n.connectOnceOrSaveProfile
                                      : _name.text.trim(),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: palette.textSubtle),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: context.l10n.cancel,
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      SizedBox(height: palette.spacing.lg),
                      const Divider(height: 1),
                    ],
                    SizedBox(
                      height: mobile || compactKeyboardLayout
                          ? 0
                          : palette.spacing.xl,
                    ),
                    Flexible(
                      fit: mobile || compactKeyboardLayout
                          ? FlexFit.tight
                          : FlexFit.loose,
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: !mobile,
                        trackVisibility: !mobile,
                        thickness: 5,
                        radius: const Radius.circular(3),
                        child: SingleChildScrollView(
                          key: const Key('ssh-profile-form-scroll'),
                          controller: _scrollController,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: mobile
                              ? const EdgeInsets.fromLTRB(16, 20, 16, 20)
                              : EdgeInsets.only(
                                  right: palette.spacing.md,
                                  bottom: palette.spacing.lg,
                                ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!mobile) ...[
                                AppSectionHeader(
                                  title: context.l10n.connection,
                                ),
                                SizedBox(height: palette.spacing.lg),
                              ],
                              if (!mobile) ...[
                                nameField(),
                                SizedBox(height: palette.spacing.lg),
                              ],
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final stacked =
                                      mobile || constraints.maxWidth < 560;
                                  Widget hostField() => AppConfigurationField(
                                    label: context.l10n.host,
                                    child: Semantics(
                                      label: context.l10n.host,
                                      textField: true,
                                      child: TextFormField(
                                        key: const Key('ssh-host'),
                                        controller: _host,
                                        focusNode: _hostFocus,
                                        keyboardType: TextInputType.url,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        textInputAction: TextInputAction.next,
                                        decoration: InputDecoration(
                                          hintText: context.l10n.hostnameOrIp,
                                          prefixIcon: mobile
                                              ? null
                                              : const Icon(Icons.dns_outlined),
                                        ),
                                        validator: _required,
                                      ),
                                    ),
                                  );
                                  Widget userControl() => Semantics(
                                    label: context.l10n.user,
                                    textField: true,
                                    child: TextFormField(
                                      key: const Key('ssh-user'),
                                      controller: _user,
                                      focusNode: _userFocus,
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      textInputAction: TextInputAction.next,
                                      decoration: _iconlessSshInputDecoration(
                                        context,
                                        hintText: context.l10n.remoteUser,
                                      ),
                                      validator: _required,
                                    ),
                                  );
                                  if (stacked) {
                                    return Column(
                                      children: [
                                        hostField(),
                                        SizedBox(height: palette.spacing.md),
                                        AppConfigurationField(
                                          label: context.l10n.user,
                                          child: userControl(),
                                        ),
                                        if (!mobile) ...[
                                          SizedBox(height: palette.spacing.md),
                                          AppConfigurationField(
                                            label: context.l10n.port,
                                            child: portControl(),
                                          ),
                                        ],
                                      ],
                                    );
                                  }
                                  return Column(
                                    children: [
                                      hostField(),
                                      SizedBox(height: palette.spacing.md),
                                      AppConfigurationField(
                                        label: context.l10n.user,
                                        child: Row(
                                          children: [
                                            Expanded(child: userControl()),
                                            const SizedBox(width: 20),
                                            Text(
                                              context.l10n.port,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodyMedium,
                                            ),
                                            const SizedBox(width: 20),
                                            SizedBox(
                                              width: 110,
                                              child: portControl(),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              SizedBox(
                                height: mobile ? 12 : palette.spacing.xl,
                              ),
                              if (!mobile) ...[
                                AppSectionHeader(
                                  title: context.l10n.authentication,
                                ),
                                SizedBox(height: palette.spacing.lg),
                              ],
                              AppConfigurationField(
                                label: mobile
                                    ? context.l10n.authentication
                                    : context.l10n.method,
                                child: Semantics(
                                  label: context.l10n.authenticationMethod,
                                  button: true,
                                  child:
                                      AppDropdownFormField<
                                        terminal.TerminalSshAuthMethod
                                      >(
                                        key: const Key('ssh-auth-method'),
                                        isExpanded: true,
                                        initialValue: _auth,
                                        decoration: _iconlessSshInputDecoration(
                                          context,
                                        ),
                                        items: [
                                          DropdownMenuItem(
                                            value: terminal
                                                .TerminalSshAuthMethod
                                                .auto,
                                            child: Text(
                                              context
                                                  .l10n
                                                  .automaticKeysThenPassword,
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: terminal
                                                .TerminalSshAuthMethod
                                                .publicKey,
                                            child: Text(
                                              context.l10n.privateKey,
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: terminal
                                                .TerminalSshAuthMethod
                                                .password,
                                            child: Text(context.l10n.password),
                                          ),
                                          DropdownMenuItem(
                                            value: terminal
                                                .TerminalSshAuthMethod
                                                .keyboardInteractive,
                                            child: Text(
                                              context
                                                  .l10n
                                                  .keyboardInteractiveOtp,
                                            ),
                                          ),
                                        ],
                                        onChanged: (value) => setState(() {
                                          _auth =
                                              value ??
                                              terminal
                                                  .TerminalSshAuthMethod
                                                  .auto;
                                        }),
                                      ),
                                ),
                              ),
                              if (showsPassword) ...[
                                SizedBox(
                                  height: mobile ? 12 : palette.spacing.lg,
                                ),
                                AppConfigurationField(
                                  label:
                                      _auth ==
                                          terminal
                                              .TerminalSshAuthMethod
                                              .password
                                      ? context.l10n.password
                                      : context.l10n.passwordFallback,
                                  helper:
                                      _auth ==
                                          terminal.TerminalSshAuthMethod.auto
                                      ? context.l10n.passwordFallbackHelp
                                      : null,
                                  child: Semantics(
                                    label: context.l10n.password,
                                    textField: true,
                                    obscured: _obscurePassword,
                                    child: TextFormField(
                                      key: const Key('ssh-password'),
                                      controller: _password,
                                      focusNode: _passwordFocus,
                                      obscureText: _obscurePassword,
                                      enableSuggestions: false,
                                      autocorrect: false,
                                      decoration: InputDecoration(
                                        prefixIcon: mobile
                                            ? null
                                            : const Icon(
                                                Icons.password_rounded,
                                              ),
                                        suffixIcon: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _SecretVisibilityButton(
                                              key: const Key(
                                                'ssh-password-visibility',
                                              ),
                                              obscured: _obscurePassword,
                                              label: context.l10n.password,
                                              onPressed: () => setState(() {
                                                _obscurePassword =
                                                    !_obscurePassword;
                                              }),
                                            ),
                                            if (!mobile ||
                                                (widget
                                                        .initialValue
                                                        .connection
                                                        .password
                                                        ?.isNotEmpty ??
                                                    false))
                                              IconButton(
                                                key: const Key(
                                                  'ssh-clear-password',
                                                ),
                                                tooltip: context
                                                    .l10n
                                                    .forgetSavedPassword,
                                                padding: EdgeInsets.zero,
                                                constraints: BoxConstraints(
                                                  minWidth:
                                                      palette.controls.regular,
                                                  minHeight:
                                                      palette.controls.regular,
                                                ),
                                                iconSize: 18,
                                                onPressed: () => setState(() {
                                                  _password.clear();
                                                  _clearPassword = true;
                                                }),
                                                icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      validator:
                                          _auth ==
                                              terminal
                                                  .TerminalSshAuthMethod
                                                  .password
                                          ? _required
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                              if (showsPrivateKeys) ...[
                                SizedBox(height: palette.spacing.lg),
                                AppConfigurationField(
                                  label: context.l10n.privateKey,
                                  helper: context.l10n.privateKeyDescription,
                                  child: FormField<List<String>>(
                                    key: _privateKeyFieldKey,
                                    initialValue: _privateKeyValues,
                                    validator: (value) =>
                                        _auth ==
                                                terminal
                                                    .TerminalSshAuthMethod
                                                    .publicKey &&
                                            (value == null || value.isEmpty)
                                        ? 'Select a private key file'
                                        : null,
                                    builder: (field) => Semantics(
                                      label: context.l10n.privateKeyFile,
                                      value: _privateKeyDisplayValue,
                                      child: InputDecorator(
                                        key: const Key('ssh-private-keys'),
                                        decoration: InputDecoration(
                                          // The row's actions already provide
                                          // the adaptive control height.
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                              ),
                                          prefixIcon: const Icon(
                                            Icons.key_rounded,
                                          ),
                                          errorText:
                                              _privateKeySelectionError ??
                                              field.errorText,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _privateKeyDisplayValue,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: _privateKeyValues.isEmpty
                                                    ? Theme.of(context)
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                            color: palette
                                                                .textSubtle,
                                                          )
                                                    : null,
                                              ),
                                            ),
                                            SizedBox(width: palette.spacing.sm),
                                            if (compactPrivateKeyAction)
                                              IconButton(
                                                key: const Key(
                                                  'ssh-select-private-key',
                                                ),
                                                focusNode: _privateKeysFocus,
                                                tooltip:
                                                    _privateKeyValues.isEmpty
                                                    ? context.l10n.select
                                                    : context.l10n.replace,
                                                padding: EdgeInsets.zero,
                                                constraints: BoxConstraints(
                                                  minWidth:
                                                      palette.controls.regular,
                                                  minHeight:
                                                      palette.controls.regular,
                                                ),
                                                iconSize: 18,
                                                onPressed: _selectingPrivateKey
                                                    ? null
                                                    : _pickPrivateKey,
                                                icon: _selectingPrivateKey
                                                    ? const SizedBox.square(
                                                        dimension: 16,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                            ),
                                                      )
                                                    : const Icon(
                                                        Icons
                                                            .folder_open_rounded,
                                                      ),
                                              )
                                            else
                                              TextButton.icon(
                                                key: const Key(
                                                  'ssh-select-private-key',
                                                ),
                                                focusNode: _privateKeysFocus,
                                                style: TextButton.styleFrom(
                                                  minimumSize: Size(
                                                    0,
                                                    palette.controls.regular,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                      ),
                                                  iconSize: 18,
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                                onPressed: _selectingPrivateKey
                                                    ? null
                                                    : _pickPrivateKey,
                                                icon: _selectingPrivateKey
                                                    ? const SizedBox.square(
                                                        dimension: 16,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                            ),
                                                      )
                                                    : const Icon(
                                                        Icons
                                                            .folder_open_rounded,
                                                      ),
                                                label: Text(
                                                  _privateKeyValues.isEmpty
                                                      ? context.l10n.select
                                                      : context.l10n.replace,
                                                ),
                                              ),
                                            if (_privateKeyValues.isNotEmpty)
                                              IconButton(
                                                key: const Key(
                                                  'ssh-clear-private-key',
                                                ),
                                                tooltip: context
                                                    .l10n
                                                    .forgetSavedPrivateKey,
                                                padding: EdgeInsets.zero,
                                                constraints: BoxConstraints(
                                                  minWidth:
                                                      palette.controls.regular,
                                                  minHeight:
                                                      palette.controls.regular,
                                                ),
                                                iconSize: 18,
                                                onPressed: _forgetPrivateKey,
                                                icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: palette.spacing.lg),
                                AppConfigurationField(
                                  label: context.l10n.privateKeyPassphrase,
                                  helper: context.l10n.privateKeyPassphraseHelp,
                                  child: Semantics(
                                    label: context.l10n.privateKeyPassphrase,
                                    textField: true,
                                    obscured: _obscurePrivateKeyPassphrase,
                                    child: TextFormField(
                                      key: const Key('ssh-key-passphrase'),
                                      controller: _privateKeyPassphrase,
                                      obscureText: _obscurePrivateKeyPassphrase,
                                      enableSuggestions: false,
                                      autocorrect: false,
                                      decoration: _iconlessSshInputDecoration(
                                        context,
                                        suffixIcon: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _SecretVisibilityButton(
                                              key: const Key(
                                                'ssh-key-passphrase-visibility',
                                              ),
                                              obscured:
                                                  _obscurePrivateKeyPassphrase,
                                              label: context
                                                  .l10n
                                                  .privateKeyPassphrase,
                                              onPressed: () => setState(() {
                                                _obscurePrivateKeyPassphrase =
                                                    !_obscurePrivateKeyPassphrase;
                                              }),
                                            ),
                                            IconButton(
                                              key: const Key(
                                                'ssh-clear-key-passphrase',
                                              ),
                                              tooltip: context
                                                  .l10n
                                                  .forgetSavedKeyPassphrase,
                                              padding: EdgeInsets.zero,
                                              constraints: BoxConstraints(
                                                minWidth:
                                                    palette.controls.regular,
                                                minHeight:
                                                    palette.controls.regular,
                                              ),
                                              iconSize: 18,
                                              onPressed: () => setState(() {
                                                _privateKeyPassphrase.clear();
                                                _clearPrivateKeyPassphrase =
                                                    true;
                                              }),
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              if (_auth ==
                                  terminal
                                      .TerminalSshAuthMethod
                                      .keyboardInteractive) ...[
                                SizedBox(height: palette.spacing.lg),
                                AppPanel(
                                  tone: AppPanelTone.selected,
                                  padding: EdgeInsets.all(palette.spacing.lg),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.chat_bubble_outline_rounded,
                                        size: 18,
                                        color: palette.accent,
                                      ),
                                      SizedBox(width: palette.spacing.md),
                                      Expanded(
                                        child: Text(
                                          context.l10n.keyboardInteractiveHelp,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              SizedBox(height: palette.spacing.lg),
                              ExpansionTile(
                                key: const Key('ssh-more-settings'),
                                shape: mobile
                                    ? RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          palette.radius.md,
                                        ),
                                        side: BorderSide(color: palette.border),
                                      )
                                    : null,
                                collapsedShape: mobile
                                    ? RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          palette.radius.md,
                                        ),
                                        side: BorderSide(color: palette.border),
                                      )
                                    : null,
                                controller: _advancedController,
                                initiallyExpanded: _showAdvanced,
                                onExpansionChanged: (value) =>
                                    _showAdvanced = value,
                                title: Wrap(
                                  key: const Key('ssh-more-settings-toggle'),
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 12,
                                  children: [
                                    Text(
                                      mobile
                                          ? context
                                                .l10n
                                                .mobileMoreConnectionSettings
                                          : context
                                                .l10n
                                                .hostVerificationAdvanced,
                                    ),
                                    if (mobile)
                                      Text(
                                        '${context.l10n.port} ${_port.text.trim()}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: palette.textSubtle,
                                            ),
                                      ),
                                  ],
                                ),
                                subtitle: mobile
                                    ? null
                                    : Text(
                                        context
                                            .l10n
                                            .hostVerificationAdvancedDescription,
                                      ),
                                tilePadding: mobile
                                    ? const EdgeInsets.symmetric(horizontal: 12)
                                    : EdgeInsets.zero,
                                childrenPadding: mobile
                                    ? const EdgeInsets.all(12)
                                    : EdgeInsets.zero,
                                children: [
                                  if (mobile) ...[
                                    nameField(),
                                    const SizedBox(height: 12),
                                    AppConfigurationField(
                                      label: context.l10n.port,
                                      child: portControl(),
                                    ),
                                    if (widget.allowSaveChoice) ...[
                                      const SizedBox(height: 12),
                                      saveChoice(),
                                    ],
                                    const SizedBox(height: 20),
                                  ],
                                  AppConfigurationField(
                                    label: context.l10n.hostKeyPolicy,
                                    child:
                                        AppDropdownFormField<
                                          terminal.TerminalSshHostKeyPolicy
                                        >(
                                          key: const Key('ssh-host-key-policy'),
                                          isExpanded: true,
                                          initialValue: _hostKeyPolicy,
                                          decoration:
                                              _iconlessSshInputDecoration(
                                                context,
                                              ),
                                          items: [
                                            DropdownMenuItem(
                                              value: terminal
                                                  .TerminalSshHostKeyPolicy
                                                  .acceptNew,
                                              child: Text(
                                                context
                                                    .l10n
                                                    .acceptNewHostsRecommended,
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: terminal
                                                  .TerminalSshHostKeyPolicy
                                                  .strict,
                                              child: Text(
                                                context.l10n.askBeforeTrusting,
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: terminal
                                                  .TerminalSshHostKeyPolicy
                                                  .insecure,
                                              child: Text(
                                                context.l10n.doNotVerifyUnsafe,
                                              ),
                                            ),
                                          ],
                                          onChanged: (value) => setState(() {
                                            _hostKeyPolicy =
                                                value ??
                                                terminal
                                                    .TerminalSshHostKeyPolicy
                                                    .acceptNew;
                                          }),
                                        ),
                                  ),
                                  SizedBox(height: palette.spacing.md),
                                  AppConfigurationField(
                                    label: context.l10n.knownHostsFileOptional,
                                    child: TextFormField(
                                      key: const Key('ssh-known-hosts-file'),
                                      controller: _knownHostsFile,
                                      decoration: _iconlessSshInputDecoration(
                                        context,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: palette.spacing.md),
                                  _SshConnectionTimingFields(
                                    connectTimeout: _connectTimeout,
                                    keepalive: _keepalive,
                                    keepaliveCount: _keepaliveCount,
                                    connectTimeoutFocus: _connectTimeoutFocus,
                                    keepaliveFocus: _keepaliveFocus,
                                    keepaliveCountFocus: _keepaliveCountFocus,
                                    validator: _boundedInteger,
                                  ),
                                  SizedBox(height: palette.spacing.md),
                                  AppConfigurationField(
                                    label: context.l10n.proxyCommandOptional,
                                    child: TextFormField(
                                      key: const Key('ssh-proxy-command'),
                                      controller: _proxyCommand,
                                      decoration: _iconlessSshInputDecoration(
                                        context,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: palette.spacing.md),
                                  AppConfigurationField(
                                    label: context.l10n.proxyJumpOptional,
                                    helper: context.l10n.proxyJumpHelp,
                                    child: TextFormField(
                                      key: const Key('ssh-proxy-jump'),
                                      controller: _proxyJump,
                                      focusNode: _proxyJumpFocus,
                                      decoration: _iconlessSshInputDecoration(
                                        context,
                                      ),
                                      validator: (value) {
                                        if ((value ?? '').trim().isEmpty) {
                                          return null;
                                        }
                                        try {
                                          parseSshProxyJumpProfiles(
                                            value ?? '',
                                          );
                                          return null;
                                        } on FormatException catch (error) {
                                          return error.message;
                                        }
                                      },
                                    ),
                                  ),
                                  SizedBox(height: palette.spacing.md),
                                  AppConfigurationField(
                                    label: context.l10n.portForwards,
                                    helper: context.l10n.portForwardsHelp,
                                    child: TextFormField(
                                      key: const Key('ssh-port-forwards'),
                                      controller: _portForwards,
                                      focusNode: _portForwardsFocus,
                                      minLines: 2,
                                      maxLines: 5,
                                      decoration: _iconlessSshInputDecoration(
                                        context,
                                      ),
                                      validator: (value) {
                                        try {
                                          parseSshPortForwards(value ?? '');
                                          return null;
                                        } on FormatException catch (error) {
                                          return error.message;
                                        }
                                      },
                                    ),
                                  ),
                                  SwitchListTile(
                                    key: const Key('ssh-agent-forwarding'),
                                    contentPadding: EdgeInsets.zero,
                                    value: _agentForwarding,
                                    title: Text(context.l10n.forwardSshAgent),
                                    subtitle: Text(
                                      context.l10n.agentSocketHelp,
                                    ),
                                    onChanged: (value) => setState(
                                      () => _agentForwarding = value,
                                    ),
                                  ),
                                  if (_agentForwarding)
                                    AppConfigurationField(
                                      label: context.l10n.agentSocketOptional,
                                      child: TextFormField(
                                        key: const Key('ssh-agent-socket'),
                                        controller: _agentSocket,
                                        decoration: _iconlessSshInputDecoration(
                                          context,
                                        ),
                                      ),
                                    ),
                                  SwitchListTile(
                                    key: const Key('ssh-x11-forwarding'),
                                    contentPadding: EdgeInsets.zero,
                                    value: _x11Forwarding,
                                    title: Text(context.l10n.forwardX11),
                                    subtitle: Text(
                                      context.l10n.x11ForwardingHelp,
                                    ),
                                    onChanged: (value) =>
                                        setState(() => _x11Forwarding = value),
                                  ),
                                  if (_x11Forwarding) ...[
                                    AppConfigurationField(
                                      label: context.l10n.localX11Target,
                                      child: TextFormField(
                                        key: const Key('ssh-x11-target'),
                                        controller: _x11Target,
                                        focusNode: _x11TargetFocus,
                                        decoration: _iconlessSshInputDecoration(
                                          context,
                                        ),
                                        validator: (value) {
                                          if (!_x11Forwarding) {
                                            return null;
                                          }
                                          if ((value ?? '').trim().isEmpty) {
                                            return null;
                                          }
                                          try {
                                            parseSshForwardEndpoint(
                                              value ?? '',
                                            );
                                            return null;
                                          } on FormatException catch (error) {
                                            return error.message;
                                          }
                                        },
                                      ),
                                    ),
                                    SizedBox(height: palette.spacing.md),
                                    AppConfigurationField(
                                      label:
                                          context.l10n.x11AuthenticationCookie,
                                      helper: context.l10n.x11CookieRequired,
                                      child: TextFormField(
                                        key: const Key('ssh-x11-cookie'),
                                        controller: _x11Cookie,
                                        focusNode: _x11CookieFocus,
                                        obscureText: _obscureX11Cookie,
                                        enableSuggestions: false,
                                        autocorrect: false,
                                        decoration: _iconlessSshInputDecoration(
                                          context,
                                          suffixIcon: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _SecretVisibilityButton(
                                                key: const Key(
                                                  'ssh-x11-cookie-visibility',
                                                ),
                                                obscured: _obscureX11Cookie,
                                                label: context
                                                    .l10n
                                                    .x11AuthenticationCookie,
                                                onPressed: () => setState(() {
                                                  _obscureX11Cookie =
                                                      !_obscureX11Cookie;
                                                }),
                                              ),
                                              IconButton(
                                                key: const Key(
                                                  'ssh-clear-x11-cookie',
                                                ),
                                                tooltip: context
                                                    .l10n
                                                    .forgetSavedX11Cookie,
                                                padding: EdgeInsets.zero,
                                                constraints: BoxConstraints(
                                                  minWidth:
                                                      palette.controls.regular,
                                                  minHeight:
                                                      palette.controls.regular,
                                                ),
                                                iconSize: 18,
                                                onPressed: () => setState(() {
                                                  _x11Cookie.clear();
                                                  _clearX11AuthCookie = true;
                                                }),
                                                icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        validator: (value) {
                                          if (!_x11Forwarding) {
                                            return null;
                                          }
                                          final cookie = (value ?? '').trim();
                                          if (!RegExp(
                                            r'^[0-9A-Fa-f]{32}$',
                                          ).hasMatch(cookie)) {
                                            return 'Enter exactly 32 hexadecimal characters';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (!mobile &&
                                  widget.allowSaveChoice &&
                                  scrollsSaveChoice) ...[
                                SizedBox(height: palette.spacing.lg),
                                const Divider(),
                                saveChoice(),
                              ],
                              if (mobile) ...[
                                if (_name.text.trim().isEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    context.l10n.mobileHostAsName,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                                const SizedBox(height: 24),
                                mobileSubmit(),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!mobile) ...[
                      SizedBox(
                        height: compactKeyboardLayout
                            ? palette.spacing.sm
                            : palette.spacing.lg,
                      ),
                      const Divider(height: 1),
                      SizedBox(height: palette.spacing.md),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final actions = Wrap(
                            alignment: WrapAlignment.end,
                            spacing: palette.spacing.sm,
                            runSpacing: palette.spacing.sm,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text(context.l10n.cancel),
                              ),
                              FilledButton.icon(
                                key: const Key('ssh-connect'),
                                onPressed:
                                    widget.allowSaveChoice ||
                                        widget.saveWhenPristine ||
                                        _hasChanges
                                    ? _submit
                                    : null,
                                icon: const Icon(Icons.login_rounded),
                                label: Text(
                                  widget.allowSaveChoice
                                      ? context.l10n.connect
                                      : context.l10n.save,
                                ),
                              ),
                            ],
                          );
                          final saveChoice = CheckboxListTile(
                            key: const Key('ssh-save-profile'),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _saveProfile,
                            title: Text(context.l10n.saveThisSshSession),
                            subtitle: Text(
                              widget.saveProfileAvailable
                                  ? context.l10n.secretsEncryptedDescription
                                  : context
                                        .l10n
                                        .remoteServiceRequiredToSaveProfile,
                            ),
                            onChanged: widget.saveProfileAvailable
                                ? (value) => setState(
                                    () => _saveProfile = value ?? true,
                                  )
                                : null,
                          );
                          if (widget.allowSaveChoice &&
                              !scrollsSaveChoice &&
                              constraints.maxWidth >= 620) {
                            return Row(
                              children: [
                                Expanded(child: saveChoice),
                                SizedBox(width: palette.spacing.lg),
                                SizedBox(width: 220, child: actions),
                              ],
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.allowSaveChoice &&
                                  !scrollsSaveChoice) ...[
                                saveChoice,
                                SizedBox(height: palette.spacing.sm),
                              ],
                              Align(
                                alignment: Alignment.centerRight,
                                child: actions,
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty
        ? context.l10n.requiredField
        : null;
  }

  String? _boundedInteger(String? value, int minimum, int maximum) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < minimum || parsed > maximum) {
      return context.l10n.enterRange(minimum, maximum);
    }
    return null;
  }

  String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String get _privateKeyDisplayValue {
    final path = _privateKeyPath;
    if (path != null && path.isNotEmpty) {
      return path;
    }
    if (_privateKeyValues.isNotEmpty) {
      return _privateKeyValues.length == 1
          ? 'Saved private key'
          : '${_privateKeyValues.length} saved private keys';
    }
    return 'No private key selected';
  }

  Future<void> _pickPrivateKey() async {
    setState(() {
      _selectingPrivateKey = true;
      _privateKeySelectionError = null;
    });
    try {
      final selection =
          await (widget.privateKeyPicker ?? pickSshPrivateKeyFile)();
      if (!mounted || selection == null) {
        return;
      }
      final contents = validateSshPrivateKeyContents(selection.contents);
      setState(() {
        _privateKeyPath = selection.path;
        _privateKeyValues = <String>[contents];
        _privateKeySelectionError = null;
        _clearPrivateKeys = false;
      });
      _privateKeyFieldKey.currentState?.didChange(_privateKeyValues);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _privateKeySelectionError = switch (error) {
          FormatException(:final message) => message,
          _ => 'The selected private key could not be read.',
        };
      });
    } finally {
      if (mounted) {
        setState(() => _selectingPrivateKey = false);
      }
    }
  }

  void _forgetPrivateKey() {
    setState(() {
      _privateKeyPath = null;
      _privateKeyValues = const <String>[];
      _privateKeySelectionError = null;
      _clearPrivateKeys = true;
    });
    _privateKeyFieldKey.currentState?.didChange(_privateKeyValues);
  }

  bool get _hasChanges {
    final initial = widget.initialValue;
    final connection = initial.connection;
    return _name.text != initial.name ||
        _host.text != connection.host ||
        _user.text != connection.user ||
        _port.text != connection.port.toString() ||
        _password.text != (connection.password ?? '') ||
        !_sameStrings(_privateKeyValues, connection.privateKeys) ||
        _privateKeyPassphrase.text != (connection.privateKeyPassphrase ?? '') ||
        _knownHostsFile.text != (connection.knownHostsFile ?? '') ||
        _connectTimeout.text != connection.connectTimeoutSeconds.toString() ||
        _keepalive.text != connection.keepaliveSeconds.toString() ||
        _keepaliveCount.text != connection.keepaliveCountMax.toString() ||
        _proxyCommand.text != (connection.proxyCommand ?? '') ||
        _proxyJump.text != (connection.proxyJump ?? '') ||
        _portForwards.text != formatSshPortForwards(connection.portForwards) ||
        _agentSocket.text != (connection.agentSocket ?? '') ||
        _x11Target.text !=
            (connection.x11TargetHost == null || connection.x11TargetPort == 0
                ? ''
                : '${connection.x11TargetHost}:${connection.x11TargetPort}') ||
        _x11Cookie.text != (connection.x11AuthCookie ?? '') ||
        _auth != connection.auth ||
        _hostKeyPolicy != connection.hostKeyPolicy ||
        _agentForwarding != connection.agentForwarding ||
        _x11Forwarding != connection.x11Forwarding ||
        _clearPassword ||
        _clearPrivateKeys ||
        _clearPrivateKeyPassphrase ||
        _clearX11AuthCookie;
  }

  ({FocusNode node, bool advanced})? _firstInvalidField() {
    if (!context.usesMobileNavigation && _required(_name.text) != null) {
      return (node: _nameFocus, advanced: false);
    }
    if (_required(_host.text) != null) {
      return (node: _hostFocus, advanced: false);
    }
    if (_required(_user.text) != null) {
      return (node: _userFocus, advanced: false);
    }
    if (_boundedInteger(_port.text, 1, 65535) != null) {
      return (node: _portFocus, advanced: context.usesMobileNavigation);
    }
    if (_auth == terminal.TerminalSshAuthMethod.password &&
        _required(_password.text) != null) {
      return (node: _passwordFocus, advanced: false);
    }
    if (_auth == terminal.TerminalSshAuthMethod.publicKey &&
        _privateKeyValues.isEmpty) {
      return (node: _privateKeysFocus, advanced: false);
    }
    if (_boundedInteger(_connectTimeout.text, 1, 120) != null) {
      return (node: _connectTimeoutFocus, advanced: true);
    }
    if (_boundedInteger(_keepalive.text, 0, 86400) != null) {
      return (node: _keepaliveFocus, advanced: true);
    }
    if (_boundedInteger(_keepaliveCount.text, 1, 100) != null) {
      return (node: _keepaliveCountFocus, advanced: true);
    }
    if (_hasProxyJumpError) {
      return (node: _proxyJumpFocus, advanced: true);
    }
    if (_hasPortForwardsError) {
      return (node: _portForwardsFocus, advanced: true);
    }
    if (_x11Forwarding && _hasX11TargetError) {
      return (node: _x11TargetFocus, advanced: true);
    }
    if (_x11Forwarding &&
        !RegExp(r'^[0-9A-Fa-f]{32}$').hasMatch(_x11Cookie.text.trim())) {
      return (node: _x11CookieFocus, advanced: true);
    }
    return null;
  }

  bool get _hasProxyJumpError {
    final value = _proxyJump.text.trim();
    if (value.isEmpty) {
      return false;
    }
    try {
      parseSshProxyJumpProfiles(value);
      return false;
    } on FormatException {
      return true;
    }
  }

  bool get _hasPortForwardsError {
    try {
      parseSshPortForwards(_portForwards.text);
      return false;
    } on FormatException {
      return true;
    }
  }

  bool get _hasX11TargetError {
    final value = _x11Target.text.trim();
    if (value.isEmpty) {
      return false;
    }
    try {
      parseSshForwardEndpoint(value);
      return false;
    } on FormatException {
      return true;
    }
  }

  void _focusInvalidField(({FocusNode node, bool advanced}) target) {
    if (target.advanced && !_advancedController.isExpanded) {
      _advancedController.expand();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      target.node.requestFocus();
      final fieldContext = target.node.context;
      if (fieldContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            fieldContext,
            alignment: 0.25,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    });
  }

  void _submit() {
    final formIsValid = _formKey.currentState?.validate() ?? false;
    final invalidField = _firstInvalidField();
    if (!formIsValid || invalidField != null) {
      setState(() {
        _showValidationErrors = true;
        _showAdvanced = invalidField?.advanced ?? _showAdvanced;
      });
      if (invalidField != null) {
        _focusInvalidField(invalidField);
      }
      return;
    }
    final includesPassword =
        _auth == terminal.TerminalSshAuthMethod.auto ||
        _auth == terminal.TerminalSshAuthMethod.password;
    final includesPrivateKeys =
        _auth == terminal.TerminalSshAuthMethod.auto ||
        _auth == terminal.TerminalSshAuthMethod.publicKey;
    final x11Target = _x11Forwarding
        ? _optional(_x11Target.text) == null
              ? null
              : parseSshForwardEndpoint(_x11Target.text)
        : null;
    final proxyJump = _optional(_proxyJump.text);
    final initialProxyJump = widget.initialValue.connection.proxyJump?.trim();
    final proxyJumpProfiles = proxyJump == null
        ? const <terminal.TerminalSshJumpConfig>[]
        : proxyJump == initialProxyJump
        ? widget.initialValue.connection.proxyJumpProfiles
        : parseSshProxyJumpProfiles(proxyJump);
    final connection = terminal.TerminalConnectionConfig.ssh(
      host: _host.text.trim(),
      user: _user.text.trim(),
      port: int.parse(_port.text.trim()),
      auth: _auth,
      password: includesPassword ? _optional(_password.text) : null,
      privateKeys: includesPrivateKeys ? _privateKeyValues : const [],
      privateKeyPassphrase: includesPrivateKeys
          ? _optional(_privateKeyPassphrase.text)
          : null,
      hostKeyPolicy: _hostKeyPolicy,
      knownHostsFile: _optional(_knownHostsFile.text),
      connectTimeoutSeconds: int.parse(_connectTimeout.text.trim()),
      keepaliveSeconds: int.parse(_keepalive.text.trim()),
      keepaliveCountMax: int.parse(_keepaliveCount.text.trim()),
      proxyCommand: _optional(_proxyCommand.text),
      proxyJump: proxyJump,
      proxyJumpProfiles: proxyJumpProfiles,
      portForwards: parseSshPortForwards(_portForwards.text),
      agentForwarding: _agentForwarding,
      agentSocket: _optional(_agentSocket.text),
      x11Forwarding: _x11Forwarding,
      x11TargetHost: x11Target?.host,
      x11TargetPort: x11Target?.port ?? 0,
      x11AuthCookie: _x11Forwarding ? _optional(_x11Cookie.text) : null,
    );
    Navigator.of(context).pop(
      SshProfileEditorResult(
        profile: widget.initialValue.copyWith(
          name: context.usesMobileNavigation && _name.text.trim().isEmpty
              ? _host.text.trim()
              : _name.text.trim(),
          connection: connection,
        ),
        saveProfile:
            widget.allowSaveChoice &&
            widget.saveProfileAvailable &&
            _saveProfile,
        clearSecrets: <ProfileSecretField>{
          if (_clearPassword ||
              (_auth != widget.initialValue.connection.auth &&
                  !includesPassword))
            ProfileSecretField.password,
          if (_clearPrivateKeyPassphrase ||
              (_auth != widget.initialValue.connection.auth &&
                  !includesPrivateKeys))
            ProfileSecretField.privateKeyPassphrase,
          if (_clearPrivateKeys ||
              (_auth != widget.initialValue.connection.auth &&
                  !includesPrivateKeys))
            ProfileSecretField.privateKeys,
          if (_clearX11AuthCookie ||
              (widget.initialValue.connection.x11Forwarding && !_x11Forwarding))
            ProfileSecretField.x11AuthCookie,
        },
      ),
    );
  }
}

class _SshConnectionTimingFields extends StatelessWidget {
  const _SshConnectionTimingFields({
    required this.connectTimeout,
    required this.keepalive,
    required this.keepaliveCount,
    required this.connectTimeoutFocus,
    required this.keepaliveFocus,
    required this.keepaliveCountFocus,
    required this.validator,
  });

  final TextEditingController connectTimeout;
  final TextEditingController keepalive;
  final TextEditingController keepaliveCount;
  final FocusNode connectTimeoutFocus;
  final FocusNode keepaliveFocus;
  final FocusNode keepaliveCountFocus;
  final String? Function(String?, int, int) validator;

  @override
  Widget build(BuildContext context) {
    final gap = context.appTheme.spacing.md;
    final fields = <Widget>[
      AppConfigurationField(
        label: context.l10n.connectTimeoutSeconds,
        child: TextFormField(
          key: const Key('ssh-connect-timeout'),
          controller: connectTimeout,
          focusNode: connectTimeoutFocus,
          keyboardType: TextInputType.number,
          decoration: _iconlessSshInputDecoration(context),
          validator: (value) => validator(value, 1, 120),
        ),
      ),
      AppConfigurationField(
        label: context.l10n.keepaliveSeconds,
        child: TextFormField(
          key: const Key('ssh-keepalive-seconds'),
          controller: keepalive,
          focusNode: keepaliveFocus,
          keyboardType: TextInputType.number,
          decoration: _iconlessSshInputDecoration(context),
          validator: (value) => validator(value, 0, 86400),
        ),
      ),
      AppConfigurationField(
        label: context.l10n.keepaliveRetries,
        child: TextFormField(
          key: const Key('ssh-keepalive-count'),
          controller: keepaliveCount,
          focusNode: keepaliveCountFocus,
          keyboardType: TextInputType.number,
          decoration: _iconlessSshInputDecoration(context),
          validator: (value) => validator(value, 1, 100),
        ),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            children: [
              for (var index = 0; index < fields.length; index++) ...[
                fields[index],
                if (index + 1 < fields.length) SizedBox(height: gap),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var index = 0; index < fields.length; index++) ...[
              Expanded(child: fields[index]),
              if (index + 1 < fields.length) SizedBox(width: gap),
            ],
          ],
        );
      },
    );
  }
}

class _SecretVisibilityButton extends StatelessWidget {
  const _SecretVisibilityButton({
    super.key,
    required this.obscured,
    required this.label,
    required this.onPressed,
  });

  final bool obscured;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final controlSize = context.appTheme.controls.regular;
    return IconButton(
      tooltip: obscured ? 'Show $label' : 'Hide $label',
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: controlSize,
        minHeight: controlSize,
      ),
      iconSize: 18,
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
    );
  }
}

({String host, int port}) parseSshForwardEndpoint(String raw) {
  final value = raw.trim();
  final bracketed = value.startsWith('[');
  final separator = bracketed
      ? value.lastIndexOf(']:')
      : value.lastIndexOf(':');
  final portOffset = bracketed ? 2 : 1;
  if (separator <= 0 || separator + portOffset >= value.length) {
    throw const FormatException('Use host:port or [IPv6]:port');
  }
  final host = bracketed
      ? value.substring(1, separator)
      : value.substring(0, separator);
  final portText = value.substring(separator + portOffset);
  final port = int.tryParse(portText);
  if (host.trim().isEmpty || port == null || port < 1 || port > 65535) {
    throw const FormatException('Use a valid host and port from 1–65535');
  }
  return (host: host, port: port);
}

List<terminal.TerminalSshJumpConfig> parseSshProxyJumpProfiles(String raw) {
  final hops = raw.split(',');
  if (hops.length > 128) {
    throw const FormatException('ProxyJump supports at most 128 hops');
  }
  final profiles = <terminal.TerminalSshJumpConfig>[];
  for (var index = 0; index < hops.length; index += 1) {
    final value = hops[index].trim();
    final label = 'Hop ${index + 1}';
    if (value.isEmpty) {
      throw FormatException('$label: enter [user@]host[:port]');
    }
    if (value.contains(RegExp(r'[\s/?#]')) ||
        value.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
      throw FormatException(
        '$label: use [user@]host[:port] without spaces, paths, or query text',
      );
    }

    final separator = value.lastIndexOf('@');
    if (separator != value.indexOf('@')) {
      throw FormatException('$label: include at most one @ separator');
    }
    final user = separator < 0 ? '' : value.substring(0, separator);
    final endpoint = separator < 0 ? value : value.substring(separator + 1);
    if (separator >= 0 &&
        (user.isEmpty || user.contains(':') || user.contains('%'))) {
      throw FormatException(
        '$label: enter a username before @; embedded passwords are not allowed',
      );
    }
    if (endpoint.isEmpty) {
      throw FormatException('$label: host is required after @');
    }

    late final String host;
    var port = 22;
    if (endpoint.startsWith('[')) {
      final closing = endpoint.indexOf(']');
      if (closing < 2) {
        throw FormatException('$label: use [IPv6] or [IPv6]:port');
      }
      host = endpoint.substring(1, closing);
      final remainder = endpoint.substring(closing + 1);
      if (remainder.isNotEmpty) {
        if (!remainder.startsWith(':') || remainder.length == 1) {
          throw FormatException('$label: use [IPv6] or [IPv6]:port');
        }
        port = int.tryParse(remainder.substring(1)) ?? 0;
      }
      final uri = Uri.tryParse('ssh://[$host]');
      if (uri == null || uri.host.isEmpty || !host.contains(':')) {
        throw FormatException('$label: enter a valid bracketed IPv6 address');
      }
    } else {
      final colonCount = ':'.allMatches(endpoint).length;
      if (colonCount > 1) {
        throw FormatException('$label: wrap IPv6 addresses in brackets');
      }
      if (colonCount == 1) {
        final colon = endpoint.lastIndexOf(':');
        host = endpoint.substring(0, colon);
        port = int.tryParse(endpoint.substring(colon + 1)) ?? 0;
      } else {
        host = endpoint;
      }
      if (host.isEmpty ||
          !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(host) ||
          host.startsWith('-')) {
        throw FormatException(
          '$label: host aliases may use letters, numbers, dots, underscores, and hyphens',
        );
      }
    }
    if (port < 1 || port > 65535) {
      throw FormatException('$label: port must be from 1–65535');
    }
    profiles.add(
      terminal.TerminalSshJumpConfig(
        host: host,
        user: user,
        port: port,
        auth: terminal.TerminalSshAuthMethod.auto,
        hostKeyPolicy: terminal.TerminalSshHostKeyPolicy.acceptNew,
      ),
    );
  }
  return List<terminal.TerminalSshJumpConfig>.unmodifiable(profiles);
}

List<terminal.TerminalSshPortForwardConfig> parseSshPortForwards(String raw) {
  final forwards = <terminal.TerminalSshPortForwardConfig>[];
  final lines = raw.split(RegExp(r'[\r\n]+'));
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index].trim();
    if (line.isEmpty) {
      continue;
    }
    final parts = line.split(RegExp(r'\s+'));
    final token = parts.first.toUpperCase();
    final type = switch (token) {
      'L' => terminal.TerminalSshPortForwardType.local,
      'R' => terminal.TerminalSshPortForwardType.remote,
      'D' => terminal.TerminalSshPortForwardType.dynamic,
      _ => throw FormatException('Line ${index + 1}: start with L, R, or D'),
    };
    final expectedParts = type == terminal.TerminalSshPortForwardType.dynamic
        ? 2
        : 3;
    if (parts.length != expectedParts) {
      throw FormatException(
        'Line ${index + 1}: expected $expectedParts fields',
      );
    }
    try {
      final bind = parseSshForwardEndpoint(parts[1]);
      final target = type == terminal.TerminalSshPortForwardType.dynamic
          ? null
          : parseSshForwardEndpoint(parts[2]);
      forwards.add(
        terminal.TerminalSshPortForwardConfig(
          type: type,
          bindHost: bind.host,
          bindPort: bind.port,
          targetHost: target?.host ?? '',
          targetPort: target?.port ?? 0,
        ),
      );
    } on FormatException catch (error) {
      throw FormatException('Line ${index + 1}: ${error.message}');
    }
  }
  return List.unmodifiable(forwards);
}

String formatSshPortForwards(
  List<terminal.TerminalSshPortForwardConfig> forwards,
) {
  String endpoint(String host, int port) =>
      '${host.contains(':') ? '[$host]' : host}:$port';
  return forwards
      .map((forward) {
        final kind = switch (forward.type) {
          terminal.TerminalSshPortForwardType.local => 'L',
          terminal.TerminalSshPortForwardType.remote => 'R',
          terminal.TerminalSshPortForwardType.dynamic => 'D',
        };
        final bind = endpoint(forward.bindHost, forward.bindPort);
        if (forward.type == terminal.TerminalSshPortForwardType.dynamic) {
          return '$kind $bind';
        }
        return '$kind $bind ${endpoint(forward.targetHost, forward.targetPort)}';
      })
      .join('\n');
}
