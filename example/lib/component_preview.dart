import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/generated/app_localizations.dart';
import 'ui/components/app_action_button.dart';
import 'ui/components/app_compact_radio_tile.dart';
import 'ui/components/app_confirmation.dart';
import 'ui/components/app_dialog_scaffold.dart';
import 'ui/components/app_dropdown_form_field.dart';
import 'ui/components/app_empty_state.dart';
import 'ui/components/app_menu.dart';
import 'ui/components/app_notifications.dart';
import 'ui/components/app_selection_controls.dart';
import 'ui/components/app_status.dart';
import 'ui/components/app_text_form_field.dart';
import 'ui/foundation/app_motion.dart';
import 'ui/foundation/app_theme.dart';
import 'ui/foundation/app_theme_tokens.dart';

/// Isolated entry point: no app bootstrap, account, native PTY or network calls.
void main() => runApp(const ComponentPreview());

class ComponentPreview extends StatefulWidget {
  const ComponentPreview({super.key});
  @override
  State<ComponentPreview> createState() => _ComponentPreviewState();
}

class _ComponentPreviewState extends State<ComponentPreview> {
  ThemeMode _mode = ThemeMode.system;
  bool _phone = false;
  bool _contrast = false;
  bool _reduceMotion = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final phone = _phone || bounds.maxWidth < 600;
      final platform = phone ? TargetPlatform.iOS : TargetPlatform.macOS;
      return MaterialApp(
        title: 'Ianvs · Foundation Preview',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        themeMode: _mode,
        theme: buildIanvsTerminalTheme(
          Brightness.light,
          platform: platform,
          highContrast: _contrast,
        ),
        darkTheme: buildIanvsTerminalTheme(
          Brightness.dark,
          platform: platform,
          highContrast: _contrast,
        ),
        highContrastTheme: buildIanvsTerminalTheme(
          Brightness.light,
          platform: platform,
          highContrast: true,
        ),
        highContrastDarkTheme: buildIanvsTerminalTheme(
          Brightness.dark,
          platform: platform,
          highContrast: true,
        ),
        themeAnimationDuration: _reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 150),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations:
                _reduceMotion || MediaQuery.disableAnimationsOf(context),
            highContrast: _contrast || MediaQuery.highContrastOf(context),
          ),
          child: AppNotificationHost(child: child!),
        ),
        home: Scaffold(
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _phone ? 430 : 1180),
                child: _PreviewContents(
                  mode: _mode,
                  phone: _phone,
                  contrast: _contrast,
                  reduceMotion: _reduceMotion,
                  onMode: (value) => setState(() => _mode = value),
                  onPhone: (value) => setState(() => _phone = value),
                  onContrast: (value) => setState(() => _contrast = value),
                  onReduceMotion: (value) =>
                      setState(() => _reduceMotion = value),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _PreviewContents extends StatefulWidget {
  const _PreviewContents({
    required this.mode,
    required this.phone,
    required this.contrast,
    required this.reduceMotion,
    required this.onMode,
    required this.onPhone,
    required this.onContrast,
    required this.onReduceMotion,
  });
  final ThemeMode mode;
  final bool phone;
  final bool contrast;
  final bool reduceMotion;
  final ValueChanged<ThemeMode> onMode;
  final ValueChanged<bool> onPhone;
  final ValueChanged<bool> onContrast;
  final ValueChanged<bool> onReduceMotion;
  @override
  State<_PreviewContents> createState() => _PreviewContentsState();
}

class _PreviewContentsState extends State<_PreviewContents> {
  final _form = GlobalKey<FormState>();
  String? _environment = 'Development';
  String _segment = 'Sessions';
  String? _radio = 'Ask each time';
  bool _switch = true;
  bool _check = true;
  bool _pinned = false;
  String _event = 'Ready. All data in this preview is fictional.';
  int _row = 0;

  void _record(String value) {
    if (mounted) setState(() => _event = value);
  }

  List<AppMenuEntry> get _entries => [
    AppMenuEntry(
      label: 'New session…',
      icon: Icons.add_rounded,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
      onSelected: () => _record('New session requested'),
    ),
    AppMenuEntry(
      label: 'Split terminal',
      icon: Icons.vertical_split_outlined,
      children: [
        AppMenuEntry(
          label: 'Side by side',
          onSelected: () => _record('Split: side by side'),
        ),
        AppMenuEntry(
          label: 'Top and bottom',
          onSelected: () => _record('Split: top and bottom'),
        ),
        const AppMenuEntry(label: 'Move to window', enabled: false),
      ],
    ),
    const AppMenuEntry.divider(),
    AppMenuEntry(
      label: 'Pin session',
      selected: _pinned,
      onSelected: () {
        setState(() => _pinned = !_pinned);
        _record(_pinned ? 'Session pinned' : 'Session unpinned');
      },
    ),
    const AppMenuEntry(label: 'Reconnect', enabled: false),
    const AppMenuEntry.divider(),
    AppMenuEntry(
      label: 'Close session…',
      destructive: true,
      onSelected: _confirm,
    ),
  ];

  Future<void> _confirm() async {
    final result = await showAppConfirmation(
      context,
      title: 'Close this session?',
      message: 'The demo session will close. No real process will be affected.',
      confirmLabel: 'Close session',
      cancelLabel: 'Keep session',
      destructive: true,
    );
    _record(result ? 'Demo session closed' : 'Close cancelled');
  }

  Widget _section(
    String index,
    String title,
    String detail,
    List<Widget> children,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$index / $title',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(detail, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: Material(
            color: context.appTheme.panel,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: context.appTheme.border),
              borderRadius: BorderRadius.circular(context.appTheme.radius.lg),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _gap() => const SizedBox(height: 16);

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
          _record('New session requested'),
    },
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const Icon(Icons.terminal_rounded),
            const SizedBox(width: 10),
            Text(
              'IANVS',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              'FOUNDATION / 01',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        const SizedBox(height: 36),
        Text(
          'Familiar by design.',
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          'Cupertino rhythm. Ianvs clarity.\nReal Flutter components, with Material interaction foundations.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppSegmentedControl<ThemeMode>(
              value: widget.mode,
              onChanged: widget.onMode,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
            ),
            FilterChip(
              label: const Text('Phone layout'),
              selected: widget.phone,
              onSelected: widget.onPhone,
            ),
            FilterChip(
              label: const Text('High contrast'),
              selected: widget.contrast,
              onSelected: widget.onContrast,
            ),
            FilterChip(
              label: const Text('Reduce motion'),
              selected: widget.reduceMotion,
              onSelected: widget.onReduceMotion,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Semantics(
          liveRegion: true,
          child: Text(
            _event,
            key: const Key('preview-event'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 32),
        _section(
          '01',
          'Actions',
          'Hover, press and Tab through the controls. Loading prevents duplicate actions.',
          [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                AppActionButton(
                  label: 'New session',
                  icon: Icons.add_rounded,
                  onPressed: () => _record('New session requested'),
                ),
                AppActionButton(
                  label: 'Duplicate',
                  tone: AppActionTone.secondary,
                  onPressed: () => _record('Session duplicated'),
                ),
                AppActionButton(
                  label: 'Learn more',
                  tone: AppActionTone.ghost,
                  onPressed: () => _record('Help opened'),
                ),
                AppActionButton(
                  label: 'Close',
                  tone: AppActionTone.danger,
                  onPressed: _confirm,
                ),
                const AppActionButton(label: 'Unavailable'),
                const AppActionButton(label: 'Connecting', loading: true),
                AppActionButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Refresh sessions',
                  onPressed: () => _record('Sessions refreshed'),
                ),
              ],
            ),
          ],
        ),
        _section(
          '02',
          'Inputs & selection',
          'Validation stays inline. Password visibility retains editing state.',
          [
            Form(
              key: _form,
              child: Column(
                children: [
                  AppTextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Session name',
                      hintText: 'e.g. Development',
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter a session name.'
                        : null,
                  ),
                  _gap(),
                  const AppTextFormField(
                    password: true,
                    revealLabel: 'Show demo password',
                    concealLabel: 'Hide demo password',
                    decoration: InputDecoration(
                      labelText: 'Demo password',
                      helperText:
                          'Use fictional text only. Nothing is sent or stored.',
                    ),
                  ),
                  _gap(),
                  AppDropdownFormField<String>(
                    key: const Key('environment-select'),
                    initialValue: _environment,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Environment'),
                    items: const [
                      DropdownMenuItem(
                        value: 'Development',
                        child: Text('Development'),
                      ),
                      DropdownMenuItem(
                        value: 'Staging',
                        child: Text('Staging'),
                      ),
                      DropdownMenuItem(
                        value: 'Production',
                        enabled: false,
                        child: Text('Production · unavailable'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _environment = value);
                      _record('Environment: $value');
                    },
                  ),
                  _gap(),
                  const AppTextFormField(
                    enabled: false,
                    initialValue: 'Managed by your workspace',
                    decoration: InputDecoration(labelText: 'Unavailable field'),
                  ),
                  _gap(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppActionButton(
                      label: 'Validate',
                      onPressed: () {
                        _record(
                          _form.currentState!.validate()
                              ? 'Form is valid'
                              : 'Check the session name',
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        _section(
          '03',
          'Menus, down to the details',
          'Desktop: arrows, Enter and Esc. Phone: tap to drill down. Right-click or long-press the session row.',
          [
            AppMenuButton(
              label: 'Session actions',
              tooltip: 'Session actions',
              entries: _entries,
            ),
            _gap(),
            AppMenuButton(
              tooltip: 'Development session actions',
              entries: _entries,
              contextChild: const ListTile(
                leading: Icon(Icons.terminal_rounded),
                title: Text('Development'),
                subtitle: Text('demo@localhost · fictional'),
              ),
            ),
            _gap(),
            Align(
              alignment: Alignment.centerRight,
              child: AppMenuButton(
                label: 'Edge test',
                tooltip: 'Edge test',
                entries: _entries,
              ),
            ),
          ],
        ),
        _section(
          '04',
          'Preferences & navigation',
          'Selection uses a check, thumb position or weight as well as color.',
          [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Keep session alive'),
              trailing: AppSwitch(
                value: _switch,
                label: 'Keep session alive',
                onChanged: (value) => setState(() => _switch = value),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Restore open sessions'),
              controlAffinity: ListTileControlAffinity.leading,
              value: _check,
              onChanged: (value) => setState(() => _check = value!),
            ),
            const CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Managed preference'),
              value: false,
              onChanged: null,
            ),
            RadioGroup<String>(
              groupValue: _radio,
              onChanged: (value) => setState(() => _radio = value),
              child: const Column(
                children: [
                  AppCompactRadioTile(
                    value: 'Ask each time',
                    title: Text('Ask each time'),
                  ),
                  AppCompactRadioTile(
                    value: 'Use saved choice',
                    title: Text('Use saved choice'),
                  ),
                  AppCompactRadioTile(
                    value: 'Managed choice',
                    title: Text('Managed choice'),
                    enabled: false,
                  ),
                ],
              ),
            ),
            _gap(),
            AppSegmentedControl<String>(
              value: _segment,
              onChanged: (value) => setState(() => _segment = value),
              segments: const [
                ButtonSegment(value: 'Sessions', label: Text('Sessions')),
                ButtonSegment(value: 'History', label: Text('History')),
              ],
            ),
            _gap(),
            for (var i = 0; i < 2; i++)
              ListTile(
                selected: _row == i,
                leading: Icon(
                  i == 0 ? Icons.terminal_rounded : Icons.history_rounded,
                ),
                title: Text(i == 0 ? 'Development' : 'Staging'),
                trailing: _row == i ? const Icon(Icons.check_rounded) : null,
                onTap: () => setState(() => _row = i),
              ),
          ],
        ),
        _section(
          '05',
          'Dialogs & feedback',
          'Cancel is the default destructive choice. Notices do not interrupt editing.',
          [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                AppActionButton(
                  label: 'Confirm close…',
                  tone: AppActionTone.secondary,
                  onPressed: _confirm,
                ),
                AppActionButton(
                  label: 'Edit session…',
                  tone: AppActionTone.secondary,
                  onPressed: () => showDialog<void>(
                    context: context,
                    animationStyle: appDialogAnimation(context),
                    builder: (context) => AppDialogScaffold(
                      title: 'Edit demo session',
                      width: 480,
                      onClose: () => Navigator.of(context).pop(),
                      body: const SingleChildScrollView(
                        child: AppTextFormField(
                          initialValue: 'Development',
                          decoration: InputDecoration(labelText: 'Name'),
                        ),
                      ),
                      footer: Align(
                        alignment: Alignment.centerRight,
                        child: AppActionButton(
                          label: 'Done',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  ),
                ),
                AppActionButton(
                  label: 'Show notice',
                  tone: AppActionTone.ghost,
                  onPressed: () => AppNotifications.show(
                    context,
                    const SnackBar(
                      content: Text('Demo settings saved.'),
                      showCloseIcon: true,
                    ),
                  ),
                ),
              ],
            ),
            _gap(),
            const AppStatus(
              message: 'Connecting to the demo session…',
              loading: true,
            ),
            _gap(),
            AppStatus(
              message: 'Demo connection interrupted.',
              error: true,
              action: TextButton(
                onPressed: () => _record('Demo reconnect requested'),
                child: const Text('Retry'),
              ),
            ),
            _gap(),
            const AppStatus(message: 'All changes saved.'),
            _gap(),
            Center(
              child: AppEmptyState(
                title: 'A clear starting point',
                message: 'Create a session to make this space yours.',
                action: AppActionButton(
                  label: 'New session',
                  onPressed: () => _record('New session requested'),
                ),
              ),
            ),
          ],
        ),
        Text(
          'Preview only · No accounts, credentials or servers connected.\nFlutter Web preview does not replace iOS / macOS device acceptance.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 32),
      ],
    ),
  );
}
