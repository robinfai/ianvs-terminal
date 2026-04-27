import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../terminal/terminal_viewport_colors.dart';
import 'profile_models.dart';

class ProfileEditorDialog extends StatefulWidget {
  const ProfileEditorDialog({super.key, required this.initialValue});

  final TerminalProfile initialValue;

  @override
  State<ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<ProfileEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _argControllers = [];
  final List<_EnvEntryControllers> _envControllers = [];
  final List<TextEditingController> _fallbackControllers = [];
  final _scrollController = ScrollController();

  late final TextEditingController _nameController;
  late final TextEditingController _shellController;
  late final TextEditingController _cwdController;
  late final TextEditingController _scrollbackController;
  late final TextEditingController _fontFamilyController;
  late final TextEditingController _fontSizeController;
  late final TextEditingController _lineHeightController;
  late final TextEditingController _foregroundColorController;
  late final TextEditingController _backgroundColorController;
  late final TextEditingController _cursorColorController;
  late final TextEditingController _selectionColorController;
  late final FocusNode _nameFocusNode;
  late final FocusNode _shellFocusNode;
  late final FocusNode _scrollbackFocusNode;
  late final FocusNode _fontFamilyFocusNode;
  late final FocusNode _fontSizeFocusNode;
  late final FocusNode _lineHeightFocusNode;
  late final FocusNode _foregroundColorFocusNode;
  late final FocusNode _backgroundColorFocusNode;
  late final FocusNode _cursorColorFocusNode;
  late final FocusNode _selectionColorFocusNode;

  late TerminalEmulation _terminalEmulation;
  late TerminalCursorShape _cursorShape;
  late bool _cursorBlink;
  late bool _copyOnSelect;
  late TerminalOptionDragMode _optionDragMode;

  bool _didAttemptSave = false;
  bool _didEdit = false;
  bool _allowClose = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialValue;
    _nameController = _trackedController(text: profile.name);
    _shellController = _trackedController(text: profile.shell);
    _cwdController = _trackedController(text: profile.cwd ?? '');
    _scrollbackController = _trackedController(
      text: profile.scrollbackLines.toString(),
    );
    _fontFamilyController = _trackedController(
      text: profile.appearance.font.family,
    );
    _fontSizeController = _trackedController(
      text: profile.appearance.font.size.toString(),
    );
    _lineHeightController = _trackedController(
      text: profile.appearance.font.lineHeight.toString(),
    );
    _foregroundColorController = _trackedController(
      text: profile.appearance.colors.foreground ?? '',
    );
    _backgroundColorController = _trackedController(
      text: profile.appearance.colors.background ?? '',
    );
    _cursorColorController = _trackedController(
      text: profile.appearance.colors.cursor ?? '',
    );
    _selectionColorController = _trackedController(
      text: profile.appearance.colors.selection ?? '',
    );
    _nameFocusNode = FocusNode(debugLabel: 'profile-editor-name');
    _shellFocusNode = FocusNode(debugLabel: 'profile-editor-shell');
    _scrollbackFocusNode = FocusNode(debugLabel: 'profile-editor-scrollback');
    _fontFamilyFocusNode = FocusNode(debugLabel: 'profile-editor-font-family');
    _fontSizeFocusNode = FocusNode(debugLabel: 'profile-editor-font-size');
    _lineHeightFocusNode = FocusNode(
      debugLabel: 'profile-editor-font-line-height',
    );
    _foregroundColorFocusNode = FocusNode(
      debugLabel: 'profile-editor-color-foreground',
    );
    _backgroundColorFocusNode = FocusNode(
      debugLabel: 'profile-editor-color-background',
    );
    _cursorColorFocusNode = FocusNode(
      debugLabel: 'profile-editor-color-cursor',
    );
    _selectionColorFocusNode = FocusNode(
      debugLabel: 'profile-editor-color-selection',
    );

    for (final arg in profile.launch.args) {
      _argControllers.add(_trackedController(text: arg));
    }
    for (final entry in profile.launch.env.entries) {
      _envControllers.add(_trackedEnvEntry(key: entry.key, value: entry.value));
    }
    for (final fallback in profile.appearance.font.fallback) {
      _fallbackControllers.add(_trackedController(text: fallback));
    }

    _terminalEmulation = profile.terminalEmulation;
    _cursorShape = profile.appearance.cursor.shape;
    _cursorBlink = profile.appearance.cursor.blink;
    _copyOnSelect = profile.interaction.copyOnSelect;
    _optionDragMode = profile.interaction.optionDragMode;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _disposeControllers([
      _nameController,
      _shellController,
      _cwdController,
      _scrollbackController,
      _fontFamilyController,
      _fontSizeController,
      _lineHeightController,
      _foregroundColorController,
      _backgroundColorController,
      _cursorColorController,
      _selectionColorController,
    ]);
    _disposeControllers(_argControllers);
    _disposeControllers(_fallbackControllers);
    _disposeFocusNodes([
      _nameFocusNode,
      _shellFocusNode,
      _scrollbackFocusNode,
      _fontFamilyFocusNode,
      _fontSizeFocusNode,
      _lineHeightFocusNode,
      _foregroundColorFocusNode,
      _backgroundColorFocusNode,
      _cursorColorFocusNode,
      _selectionColorFocusNode,
    ]);
    for (final entry in _envControllers) {
      entry.dispose();
    }
    super.dispose();
  }

  void _disposeControllers(List<TextEditingController> controllers) {
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  void _disposeFocusNodes(List<FocusNode> focusNodes) {
    for (final focusNode in focusNodes) {
      focusNode.dispose();
    }
  }

  TextEditingController _trackedController({String text = ''}) {
    final controller = TextEditingController(text: text);
    controller.addListener(_markDirtyFromListener);
    return controller;
  }

  _EnvEntryControllers _trackedEnvEntry({String key = '', String value = ''}) {
    return _EnvEntryControllers(
      keyController: _trackedController(text: key),
      valueController: _trackedController(text: value),
      keyFocusNode: FocusNode(debugLabel: 'profile-editor-env-key'),
    );
  }

  void _markDirtyFromListener() {
    if (_didEdit || !mounted) {
      return;
    }
    setState(() {
      _didEdit = true;
    });
  }

  void _addArg([String initialValue = '']) {
    setState(() {
      _didEdit = true;
      _argControllers.add(_trackedController(text: initialValue));
    });
  }

  void _removeArg(int index) {
    setState(() {
      _didEdit = true;
      final controller = _argControllers.removeAt(index);
      controller.dispose();
    });
  }

  void _moveArg(int from, int to) {
    if (to < 0 || to >= _argControllers.length) {
      return;
    }
    setState(() {
      _didEdit = true;
      final controller = _argControllers.removeAt(from);
      _argControllers.insert(to, controller);
    });
  }

  void _addEnv({String key = '', String value = ''}) {
    setState(() {
      _didEdit = true;
      _envControllers.add(_trackedEnvEntry(key: key, value: value));
    });
  }

  void _removeEnv(int index) {
    setState(() {
      _didEdit = true;
      final entry = _envControllers.removeAt(index);
      entry.dispose();
    });
  }

  void _addFallback([String initialValue = '']) {
    setState(() {
      _didEdit = true;
      _fallbackControllers.add(_trackedController(text: initialValue));
    });
  }

  void _removeFallback(int index) {
    setState(() {
      _didEdit = true;
      final controller = _fallbackControllers.removeAt(index);
      controller.dispose();
    });
  }

  void _moveFallback(int from, int to) {
    if (to < 0 || to >= _fallbackControllers.length) {
      return;
    }
    setState(() {
      _didEdit = true;
      final controller = _fallbackControllers.removeAt(from);
      _fallbackControllers.insert(to, controller);
    });
  }

  String? _requiredFieldError(String value, String label) {
    if (value.trim().isEmpty) {
      return '$label is required';
    }
    return null;
  }

  String? _positiveIntegerError(String value, String label) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '$label is required';
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed < 1) {
      return '$label must be a positive integer';
    }
    return null;
  }

  String? _positiveDoubleError(String value, String label) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '$label is required';
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null || parsed <= 0) {
      return '$label must be greater than 0';
    }
    return null;
  }

  String? _colorError(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(trimmed)) {
      return 'Use #RRGGBB or leave blank';
    }
    return null;
  }

  String? _envKeyError(int index) {
    final trimmed = _envControllers[index].keyController.text.trim();
    if (trimmed.isEmpty) {
      return 'Key is required';
    }
    final duplicateCount = _envControllers
        .map((entry) => entry.keyController.text.trim())
        .where((key) => key == trimmed)
        .length;
    if (duplicateCount > 1) {
      return 'Key must be unique';
    }
    return null;
  }

  String? _normalizedOptionalHex(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed.toUpperCase();
  }

  Color? _previewColorFor(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      return terminalViewportColorFromHex(trimmed);
    } on FormatException {
      return null;
    }
  }

  List<String> _nonEmptyEntries(List<TextEditingController> controllers) {
    return [
      for (final controller in controllers)
        if (controller.text.trim().isNotEmpty) controller.text,
    ];
  }

  Map<String, String> _envEntries() {
    final env = <String, String>{};
    for (final entry in _envControllers) {
      final key = entry.keyController.text.trim();
      if (key.isEmpty) {
        continue;
      }
      env[key] = entry.valueController.text;
    }
    return env;
  }

  Future<void> _save() async {
    setState(() {
      _didAttemptSave = true;
    });
    if (!(_formKey.currentState?.validate() ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_focusFirstInvalidField());
        }
      });
      return;
    }

    final updated = widget.initialValue.copyWith(
      name: _nameController.text.trim(),
      shell: _shellController.text.trim(),
      args: _nonEmptyEntries(_argControllers),
      env: _envEntries(),
      cwd: _cwdController.text.trim().isEmpty
          ? null
          : _cwdController.text.trim(),
      terminalEmulation: _terminalEmulation,
      scrollbackLines: int.parse(_scrollbackController.text.trim()),
      appearance: widget.initialValue.appearance.copyWith(
        font: widget.initialValue.appearance.font.copyWith(
          family: _fontFamilyController.text.trim(),
          fallback: _nonEmptyEntries(
            _fallbackControllers,
          ).map((value) => value.trim()).toList(),
          size: double.parse(_fontSizeController.text.trim()),
          lineHeight: double.parse(_lineHeightController.text.trim()),
        ),
        colors: widget.initialValue.appearance.colors.copyWith(
          foreground: _normalizedOptionalHex(_foregroundColorController.text),
          background: _normalizedOptionalHex(_backgroundColorController.text),
          cursor: _normalizedOptionalHex(_cursorColorController.text),
          selection: _normalizedOptionalHex(_selectionColorController.text),
        ),
        cursor: widget.initialValue.appearance.cursor.copyWith(
          shape: _cursorShape,
          blink: _cursorBlink,
        ),
      ),
      interaction: widget.initialValue.interaction.copyWith(
        copyOnSelect: _copyOnSelect,
        optionDragMode: _optionDragMode,
      ),
    );
    await _closeWithResult(updated);
  }

  Future<void> _closeWithResult(TerminalProfile? result) async {
    final shouldClose = await _confirmDiscardIfNeeded(
      ignoreDirtyState: result != null,
    );
    if (!shouldClose || !mounted) {
      return;
    }
    setState(() {
      _allowClose = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    });
  }

  Future<bool> _confirmDiscardIfNeeded({bool ignoreDirtyState = false}) async {
    if (_allowClose || ignoreDirtyState || !_didEdit) {
      return true;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('profile-editor-discard-dialog'),
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved profile changes. Close the editor and lose them?',
        ),
        actions: [
          TextButton(
            key: const Key('profile-editor-discard-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            key: const Key('profile-editor-discard-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _focusFirstInvalidField() async {
    final focusNode = _firstInvalidFocusNode();
    if (focusNode == null) {
      return;
    }
    focusNode.requestFocus();
    final context = focusNode.context;
    if (context != null) {
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
    }
  }

  FocusNode? _firstInvalidFocusNode() {
    if (_requiredFieldError(_nameController.text, 'Name') != null) {
      return _nameFocusNode;
    }
    if (_requiredFieldError(_shellController.text, 'Shell') != null) {
      return _shellFocusNode;
    }
    for (final entry in _envControllers) {
      if (_envKeyError(_envControllers.indexOf(entry)) != null) {
        return entry.keyFocusNode;
      }
    }
    if (_positiveIntegerError(_scrollbackController.text, 'Scrollback lines') !=
        null) {
      return _scrollbackFocusNode;
    }
    if (_requiredFieldError(_fontFamilyController.text, 'Font family') !=
        null) {
      return _fontFamilyFocusNode;
    }
    if (_positiveDoubleError(_fontSizeController.text, 'Font size') != null) {
      return _fontSizeFocusNode;
    }
    if (_positiveDoubleError(_lineHeightController.text, 'Line height') !=
        null) {
      return _lineHeightFocusNode;
    }
    if (_colorError(_foregroundColorController.text) != null) {
      return _foregroundColorFocusNode;
    }
    if (_colorError(_backgroundColorController.text) != null) {
      return _backgroundColorFocusNode;
    }
    if (_colorError(_cursorColorController.text) != null) {
      return _cursorColorFocusNode;
    }
    if (_colorError(_selectionColorController.text) != null) {
      return _selectionColorFocusNode;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(screenSize.width - 48, 720.0);
    final dialogHeight = math.min(screenSize.height - 48, 760.0);

    return PopScope<TerminalProfile?>(
      canPop: _allowClose || !_didEdit,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _allowClose) {
          return;
        }
        unawaited(_closeWithResult(null));
      },
      child: Dialog(
        key: const Key('profile-editor-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Edit profile',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Changes apply to new sessions only. Existing tabs keep the profile snapshot they started with.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Theme.of(context).hintColor),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close profile editor',
                      onPressed: () => unawaited(_closeWithResult(null)),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Form(
                  key: _formKey,
                  autovalidateMode: _didAttemptSave
                      ? AutovalidateMode.always
                      : AutovalidateMode.disabled,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProfileEditorSection(
                          title: 'Basic',
                          description:
                              'Name the profile and choose which local program it launches.',
                          children: [
                            TextFormField(
                              key: const Key('profile-editor-name'),
                              controller: _nameController,
                              focusNode: _nameFocusNode,
                              decoration: const InputDecoration(
                                labelText: 'Name',
                              ),
                              validator: (value) =>
                                  _requiredFieldError(value ?? '', 'Name'),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const Key('profile-editor-shell'),
                              controller: _shellController,
                              focusNode: _shellFocusNode,
                              decoration: const InputDecoration(
                                labelText: 'Shell / Program',
                              ),
                              validator: (value) =>
                                  _requiredFieldError(value ?? '', 'Shell'),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const Key('profile-editor-cwd'),
                              controller: _cwdController,
                              decoration: const InputDecoration(
                                labelText: 'Working directory',
                                helperText:
                                    'Leave empty to use the default working directory.',
                              ),
                            ),
                          ],
                        ),
                        _ProfileEditorSection(
                          title: 'Launch',
                          description:
                              'Manage launch arguments and environment variables.',
                          children: [
                            _buildStringListEditor(
                              title: 'Arguments',
                              addKey: const Key('profile-editor-add-arg'),
                              addLabel: 'Add arg',
                              emptyLabel: 'No launch arguments',
                              controllers: _argControllers,
                              fieldKeyPrefix: 'profile-editor-arg',
                              onAdd: _addArg,
                              onRemove: _removeArg,
                              onMoveUp: (index) => _moveArg(index, index - 1),
                              onMoveDown: (index) => _moveArg(index, index + 1),
                            ),
                            const SizedBox(height: 16),
                            _buildEnvEditor(),
                          ],
                        ),
                        _ProfileEditorSection(
                          title: 'Terminal',
                          description:
                              'Pick terminal emulation and scrollback retention.',
                          children: [
                            DropdownButtonFormField<TerminalEmulation>(
                              key: const Key('profile-editor-emulation'),
                              initialValue: _terminalEmulation,
                              decoration: const InputDecoration(
                                labelText: 'Emulation',
                              ),
                              items: TerminalEmulation.values
                                  .map(
                                    (value) =>
                                        DropdownMenuItem<TerminalEmulation>(
                                          value: value,
                                          child: Text(
                                            terminalEmulationLabel(value),
                                          ),
                                        ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setState(() {
                                  _didEdit = true;
                                  _terminalEmulation = value;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const Key('profile-editor-scrollback'),
                              controller: _scrollbackController,
                              focusNode: _scrollbackFocusNode,
                              decoration: const InputDecoration(
                                labelText: 'Scrollback lines',
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: (value) => _positiveIntegerError(
                                value ?? '',
                                'Scrollback lines',
                              ),
                            ),
                          ],
                        ),
                        _ProfileEditorSection(
                          title: 'Appearance',
                          description:
                              'Choose font, color overrides, and cursor behavior.',
                          children: [
                            TextFormField(
                              key: const Key('profile-editor-font-family'),
                              controller: _fontFamilyController,
                              focusNode: _fontFamilyFocusNode,
                              decoration: const InputDecoration(
                                labelText: 'Font family',
                              ),
                              validator: (value) => _requiredFieldError(
                                value ?? '',
                                'Font family',
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildStringListEditor(
                              title: 'Fallback fonts',
                              addKey: const Key('profile-editor-add-fallback'),
                              addLabel: 'Add fallback',
                              emptyLabel: 'No fallback fonts',
                              controllers: _fallbackControllers,
                              fieldKeyPrefix: 'profile-editor-fallback',
                              onAdd: _addFallback,
                              onRemove: _removeFallback,
                              onMoveUp: (index) =>
                                  _moveFallback(index, index - 1),
                              onMoveDown: (index) =>
                                  _moveFallback(index, index + 1),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    key: const Key('profile-editor-font-size'),
                                    controller: _fontSizeController,
                                    focusNode: _fontSizeFocusNode,
                                    decoration: const InputDecoration(
                                      labelText: 'Font size',
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    validator: (value) => _positiveDoubleError(
                                      value ?? '',
                                      'Font size',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    key: const Key(
                                      'profile-editor-font-line-height',
                                    ),
                                    controller: _lineHeightController,
                                    focusNode: _lineHeightFocusNode,
                                    decoration: const InputDecoration(
                                      labelText: 'Line height',
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    validator: (value) => _positiveDoubleError(
                                      value ?? '',
                                      'Line height',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildColorField(
                              label: 'Foreground',
                              controller: _foregroundColorController,
                              focusNode: _foregroundColorFocusNode,
                              inputKey: const Key(
                                'profile-editor-color-foreground',
                              ),
                              pickKey: const Key(
                                'profile-editor-pick-foreground',
                              ),
                              resetKey: const Key(
                                'profile-editor-reset-foreground',
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildColorField(
                              label: 'Background',
                              controller: _backgroundColorController,
                              focusNode: _backgroundColorFocusNode,
                              inputKey: const Key(
                                'profile-editor-color-background',
                              ),
                              pickKey: const Key(
                                'profile-editor-pick-background',
                              ),
                              resetKey: const Key(
                                'profile-editor-reset-background',
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildColorField(
                              label: 'Cursor color',
                              controller: _cursorColorController,
                              focusNode: _cursorColorFocusNode,
                              inputKey: const Key(
                                'profile-editor-color-cursor',
                              ),
                              pickKey: const Key('profile-editor-pick-cursor'),
                              resetKey: const Key(
                                'profile-editor-reset-cursor',
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildColorField(
                              label: 'Selection color',
                              controller: _selectionColorController,
                              focusNode: _selectionColorFocusNode,
                              inputKey: const Key(
                                'profile-editor-color-selection',
                              ),
                              pickKey: const Key(
                                'profile-editor-pick-selection',
                              ),
                              resetKey: const Key(
                                'profile-editor-reset-selection',
                              ),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<TerminalCursorShape>(
                              key: const Key('profile-editor-cursor-shape'),
                              initialValue: _cursorShape,
                              decoration: const InputDecoration(
                                labelText: 'Cursor shape',
                              ),
                              items: TerminalCursorShape.values
                                  .map(
                                    (value) =>
                                        DropdownMenuItem<TerminalCursorShape>(
                                          value: value,
                                          child: Text(
                                            terminalCursorShapeLabel(value),
                                          ),
                                        ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setState(() {
                                  _didEdit = true;
                                  _cursorShape = value;
                                });
                              },
                            ),
                            SwitchListTile.adaptive(
                              key: const Key('profile-editor-cursor-blink'),
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Blink cursor'),
                              value: _cursorBlink,
                              onChanged: (value) {
                                setState(() {
                                  _didEdit = true;
                                  _cursorBlink = value;
                                });
                              },
                            ),
                          ],
                        ),
                        _ProfileEditorSection(
                          title: 'Interaction',
                          description:
                              'Choose selection defaults for newly opened sessions.',
                          children: [
                            SwitchListTile.adaptive(
                              key: const Key('profile-editor-copy-on-select'),
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Copy on select'),
                              value: _copyOnSelect,
                              onChanged: (value) {
                                setState(() {
                                  _didEdit = true;
                                  _copyOnSelect = value;
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Option-drag mode',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            RadioGroup<TerminalOptionDragMode>(
                              groupValue: _optionDragMode,
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setState(() {
                                  _didEdit = true;
                                  _optionDragMode = value;
                                });
                              },
                              child: Column(
                                children: [
                                  for (final mode
                                      in TerminalOptionDragMode.values)
                                    RadioListTile<TerminalOptionDragMode>(
                                      key: Key(
                                        'profile-editor-option-drag-${mode.name}',
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                      value: mode,
                                      title: Text(
                                        terminalOptionDragModeLabel(mode),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Existing sessions do not hot-update after profile edits.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    TextButton(
                      key: const Key('profile-editor-cancel'),
                      onPressed: () => unawaited(_closeWithResult(null)),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const Key('profile-editor-save'),
                      onPressed: () => unawaited(_save()),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStringListEditor({
    required String title,
    required Key addKey,
    required String addLabel,
    required String emptyLabel,
    required List<TextEditingController> controllers,
    required String fieldKeyPrefix,
    required VoidCallback onAdd,
    required void Function(int index) onRemove,
    required void Function(int index) onMoveUp,
    required void Function(int index) onMoveDown,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              key: addKey,
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(addLabel),
            ),
          ],
        ),
        if (controllers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              emptyLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
        for (var index = 0; index < controllers.length; index += 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: Key('$fieldKeyPrefix-$index'),
                    controller: controllers[index],
                    decoration: InputDecoration(
                      labelText: '$title ${index + 1}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: Key('$fieldKeyPrefix-$index-up'),
                  tooltip: 'Move up',
                  onPressed: index == 0 ? null : () => onMoveUp(index),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  key: Key('$fieldKeyPrefix-$index-down'),
                  tooltip: 'Move down',
                  onPressed: index == controllers.length - 1
                      ? null
                      : () => onMoveDown(index),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  key: Key('$fieldKeyPrefix-$index-remove'),
                  tooltip: 'Remove',
                  onPressed: () => onRemove(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEnvEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Environment variables',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              key: const Key('profile-editor-add-env'),
              onPressed: _addEnv,
              icon: const Icon(Icons.add),
              label: const Text('Add variable'),
            ),
          ],
        ),
        if (_envControllers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'No environment variables',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
        for (var index = 0; index < _envControllers.length; index += 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: Key('profile-editor-env-key-$index'),
                    controller: _envControllers[index].keyController,
                    focusNode: _envControllers[index].keyFocusNode,
                    decoration: const InputDecoration(labelText: 'Key'),
                    onChanged: (_) => setState(() {}),
                    validator: (_) => _envKeyError(index),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: Key('profile-editor-env-value-$index'),
                    controller: _envControllers[index].valueController,
                    decoration: const InputDecoration(labelText: 'Value'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: Key('profile-editor-env-remove-$index'),
                  tooltip: 'Remove variable',
                  onPressed: () => _removeEnv(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildColorField({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required Key inputKey,
    required Key pickKey,
    required Key resetKey,
  }) {
    final previewColor = _previewColorFor(controller.text);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            key: inputKey,
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              labelText: label,
              helperText: 'Use #RRGGBB or leave empty',
            ),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
            ],
            onChanged: (_) => setState(() {}),
            validator: (value) => _colorError(value ?? ''),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: previewColor ?? Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: pickKey,
              onPressed: () => unawaited(_pickColor(controller)),
              child: const Text('Pick'),
            ),
            TextButton(
              key: resetKey,
              onPressed: () {
                controller.clear();
                setState(() {});
              },
              child: const Text('Reset'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickColor(TextEditingController controller) async {
    final initialHex = _colorError(controller.text) == null
        ? _normalizedOptionalHex(controller.text)
        : null;
    final result = await showDialog<_ColorPickerResult>(
      context: context,
      builder: (dialogContext) => _ColorPickerDialog(initialHex: initialHex),
    );
    if (result == null || !result.applied) {
      return;
    }
    controller.text = result.hexValue ?? '';
    setState(() {});
  }
}

class _ProfileEditorSection extends StatelessWidget {
  const _ProfileEditorSection({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _EnvEntryControllers {
  _EnvEntryControllers({
    required this.keyController,
    required this.valueController,
    required this.keyFocusNode,
  });

  final TextEditingController keyController;
  final TextEditingController valueController;
  final FocusNode keyFocusNode;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
    keyFocusNode.dispose();
  }
}

class _ColorPickerResult {
  const _ColorPickerResult({required this.applied, this.hexValue});

  final bool applied;
  final String? hexValue;
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initialHex});

  final String? initialHex;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late final TextEditingController _hexController;
  late Color _workingColor;
  late bool _inheritsDefault;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    final initialColor = terminalViewportColorFromHex(widget.initialHex);
    _inheritsDefault = widget.initialHex == null;
    _workingColor = initialColor ?? const Color(0xFFFFFFFF);
    _hexController = TextEditingController(
      text: widget.initialHex ?? terminalViewportHexFromColor(_workingColor),
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _setChannel({required int red, required int green, required int blue}) {
    setState(() {
      _inheritsDefault = false;
      _workingColor = Color.fromARGB(255, red, green, blue);
      _hexController.text = terminalViewportHexFromColor(_workingColor);
      _hexError = null;
    });
  }

  void _handleHexChanged(String value) {
    final normalized = value.trim().toUpperCase();
    if (normalized.isEmpty) {
      setState(() {
        _hexError = null;
      });
      return;
    }
    if (!RegExp(r'^#[0-9A-F]{6}$').hasMatch(normalized)) {
      setState(() {
        _hexError = 'Use #RRGGBB';
      });
      return;
    }
    setState(() {
      _inheritsDefault = false;
      _workingColor = terminalViewportColorFromHex(normalized)!;
      _hexError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final previewHex = terminalViewportHexFromColor(_workingColor);
    final applyEnabled =
        _inheritsDefault ||
        (_hexController.text.trim().isNotEmpty && _hexError == null);
    final red = _colorChannel(_workingColor.r);
    final green = _colorChannel(_workingColor.g);
    final blue = _colorChannel(_workingColor.b);
    return AlertDialog(
      key: const Key('color-picker-dialog'),
      title: const Text('Pick color'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    key: const Key('color-picker-preview'),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _inheritsDefault
                          ? Colors.transparent
                          : _workingColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _inheritsDefault
                          ? 'Inheriting default terminal color'
                          : 'Current color $previewHex',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('color-picker-hex'),
                controller: _hexController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Hex',
                  helperText: 'Use #RRGGBB',
                  errorText: _hexError,
                ),
                onChanged: _handleHexChanged,
              ),
              const SizedBox(height: 12),
              Text('Red $red'),
              Slider(
                key: const Key('color-picker-red'),
                value: red.toDouble(),
                max: 255,
                onChanged: (value) =>
                    _setChannel(red: value.round(), green: green, blue: blue),
              ),
              Text('Green $green'),
              Slider(
                key: const Key('color-picker-green'),
                value: green.toDouble(),
                max: 255,
                onChanged: (value) =>
                    _setChannel(red: red, green: value.round(), blue: blue),
              ),
              Text('Blue $blue'),
              Slider(
                key: const Key('color-picker-blue'),
                value: blue.toDouble(),
                max: 255,
                onChanged: (value) =>
                    _setChannel(red: red, green: green, blue: value.round()),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('color-picker-reset'),
          onPressed: () {
            Navigator.of(
              context,
            ).pop(const _ColorPickerResult(applied: true, hexValue: null));
          },
          child: const Text('Reset to default'),
        ),
        TextButton(
          key: const Key('color-picker-cancel'),
          onPressed: () {
            Navigator.of(context).pop(const _ColorPickerResult(applied: false));
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('color-picker-apply'),
          onPressed: applyEnabled
              ? () {
                  Navigator.of(context).pop(
                    _ColorPickerResult(
                      applied: true,
                      hexValue: _inheritsDefault
                          ? null
                          : terminalViewportHexFromColor(_workingColor),
                    ),
                  );
                }
              : null,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

int _colorChannel(double component) {
  return (component * 255).round().clamp(0, 255);
}
