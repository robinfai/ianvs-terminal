import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/app_ui.dart';
import 'profile_models.dart';
import 'utils/hex_color_utils.dart';
import 'widgets/color_picker_palette.dart';
import 'widgets/color_setting_row.dart';
import 'widgets/settings_section.dart';
import 'widgets/toggle_setting_row.dart';

const _hexColorErrorText = 'Use #RRGGBB or leave empty.';

class ProfileEditorDialog extends StatefulWidget {
  const ProfileEditorDialog({super.key, required this.initialValue});

  final TerminalProfile initialValue;

  @override
  State<ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<ProfileEditorDialog> {
  static const double _controlHeight = 48;
  static const double _dropdownItemHeight = 48;
  static const String _foregroundColorFieldKey = 'foreground';
  static const String _backgroundColorFieldKey = 'background';
  static const String _cursorColorFieldKey = 'cursor';
  static const String _selectionColorFieldKey = 'selection';

  final _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _argControllers = [];
  final List<_EnvEntryControllers> _envControllers = [];
  final List<TextEditingController> _fallbackControllers = [];
  final _scrollController = ScrollController();
  final Map<String, String?> _colorErrors = <String, String?>{
    _foregroundColorFieldKey: null,
    _backgroundColorFieldKey: null,
    _cursorColorFieldKey: null,
    _selectionColorFieldKey: null,
  };

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

  bool get _hasColorErrors => _colorErrors.values.any((error) => error != null);

  String? _validateOptionalHexColor(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return isValidOptionalHexColor(trimmed) ? null : _hexColorErrorText;
  }

  void _handleColorChanged(String fieldKey, String value) {
    setState(() {
      if (_didAttemptSave || _colorErrors[fieldKey] != null) {
        _colorErrors[fieldKey] = _validateOptionalHexColor(value);
      }
    });
  }

  void _normalizeColorField(String fieldKey, TextEditingController controller) {
    final trimmed = controller.text.trim();
    String nextText = trimmed;
    String? nextError;
    var didChangeText = false;

    if (trimmed.isEmpty) {
      nextText = '';
      nextError = null;
    } else {
      try {
        nextText = normalizeHexColor(trimmed);
        nextError = null;
      } on FormatException {
        nextError = _hexColorErrorText;
      }
    }

    if (controller.text != nextText) {
      didChangeText = true;
      controller.value = controller.value.copyWith(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
        composing: TextRange.empty,
      );
    }

    if (_colorErrors[fieldKey] != nextError || didChangeText) {
      setState(() {
        _colorErrors[fieldKey] = nextError;
      });
    }
  }

  bool _validateAllColorFields() {
    _normalizeColorField(_foregroundColorFieldKey, _foregroundColorController);
    _normalizeColorField(_backgroundColorFieldKey, _backgroundColorController);
    _normalizeColorField(_cursorColorFieldKey, _cursorColorController);
    _normalizeColorField(_selectionColorFieldKey, _selectionColorController);
    return !_hasColorErrors;
  }

  void _resetColorField(String fieldKey, TextEditingController controller) {
    controller.clear();
    setState(() {
      _colorErrors[fieldKey] = null;
    });
  }

  void _applyPickedColor(
    String fieldKey,
    TextEditingController controller,
    String? value,
  ) {
    controller.text = value ?? '';
    _normalizeColorField(fieldKey, controller);
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
    final colorsValid = _validateAllColorFields();
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!colorsValid || !formValid) {
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
          foreground: _foregroundColorController.text.trim().isEmpty
              ? null
              : normalizeHexColor(_foregroundColorController.text),
          background: _backgroundColorController.text.trim().isEmpty
              ? null
              : normalizeHexColor(_backgroundColorController.text),
          cursor: _cursorColorController.text.trim().isEmpty
              ? null
              : normalizeHexColor(_cursorColorController.text),
          selection: _selectionColorController.text.trim().isEmpty
              ? null
              : normalizeHexColor(_selectionColorController.text),
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
      builder: (dialogContext) => AppDialogScaffold(
        key: const Key('profile-editor-discard-dialog'),
        title: 'Discard changes?',
        subtitle:
            'You have unsaved profile changes. Close the editor and lose them?',
        body: const SizedBox.shrink(),
        footer: Wrap(
          spacing: dialogContext.appTheme.spacing.sm,
          runSpacing: dialogContext.appTheme.spacing.sm,
          alignment: WrapAlignment.end,
          children: [
            AppActionButton(
              buttonKey: const Key('profile-editor-discard-cancel'),
              tone: AppActionTone.secondary,
              label: 'Keep editing',
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            AppActionButton(
              buttonKey: const Key('profile-editor-discard-confirm'),
              tone: AppActionTone.danger,
              icon: Icons.delete_outline,
              label: 'Discard changes',
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
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
    if (_validateOptionalHexColor(_foregroundColorController.text) != null) {
      return _foregroundColorFocusNode;
    }
    if (_validateOptionalHexColor(_backgroundColorController.text) != null) {
      return _backgroundColorFocusNode;
    }
    if (_validateOptionalHexColor(_cursorColorController.text) != null) {
      return _cursorColorFocusNode;
    }
    if (_validateOptionalHexColor(_selectionColorController.text) != null) {
      return _selectionColorFocusNode;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(screenSize.width - 32, 900.0);
    final dialogHeight = math.min(screenSize.height - 32, 860.0);

    return PopScope<TerminalProfile?>(
      canPop: _allowClose || !_didEdit,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _allowClose) {
          return;
        }
        unawaited(_closeWithResult(null));
      },
      child: AppDialogScaffold(
        key: const Key('profile-editor-dialog'),
        title: 'Edit profile',
        subtitle:
            'Changes apply to new sessions only. Existing tabs keep the profile snapshot they started with.',
        onClose: () => unawaited(_closeWithResult(null)),
        closeTooltip: 'Close profile editor',
        width: dialogWidth,
        height: dialogHeight,
        expandBody: true,
        bodyPadding: EdgeInsets.fromLTRB(
          theme.spacing.xl,
          theme.spacing.xl,
          theme.spacing.xl,
          theme.spacing.lg,
        ),
        body: Form(
          key: _formKey,
          autovalidateMode: _didAttemptSave
              ? AutovalidateMode.always
              : AutovalidateMode.disabled,
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Padding(
              padding: EdgeInsets.only(right: theme.spacing.xl + 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsSection(
                    title: 'Basic',
                    description:
                        'Name the profile and choose which local program it launches.',
                    children: [
                      TextFormField(
                        key: const Key('profile-editor-name'),
                        controller: _nameController,
                        focusNode: _nameFocusNode,
                        decoration: const InputDecoration(labelText: 'Name'),
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
                  SettingsSection(
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
                  SettingsSection(
                    title: 'Terminal',
                    description:
                        'Pick terminal emulation and scrollback retention.',
                    children: [
                      DropdownButtonFormField<TerminalEmulation>(
                        key: const Key('profile-editor-emulation'),
                        initialValue: _terminalEmulation,
                        isExpanded: true,
                        iconSize: 18,
                        itemHeight: _dropdownItemHeight,
                        menuMaxHeight: 240,
                        borderRadius: BorderRadius.circular(theme.radius.md),
                        decoration: InputDecoration(
                          labelText: 'Emulation',
                          constraints: const BoxConstraints(
                            minHeight: _controlHeight,
                          ),
                        ),
                        items: TerminalEmulation.values
                            .map(
                              (value) => DropdownMenuItem<TerminalEmulation>(
                                value: value,
                                child: Text(terminalEmulationLabel(value)),
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
                  SettingsSection(
                    title: 'Typography',
                    description:
                        'Choose font family, fallback stack, and type sizing.',
                    children: [
                      TextFormField(
                        key: const Key('profile-editor-font-family'),
                        controller: _fontFamilyController,
                        focusNode: _fontFamilyFocusNode,
                        decoration: const InputDecoration(
                          labelText: 'Font family',
                        ),
                        validator: (value) =>
                            _requiredFieldError(value ?? '', 'Font family'),
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
                        onMoveUp: (index) => _moveFallback(index, index - 1),
                        onMoveDown: (index) => _moveFallback(index, index + 1),
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
                              key: const Key('profile-editor-font-line-height'),
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
                    ],
                  ),
                  SettingsSection(
                    title: 'Colors',
                    description:
                        'Override terminal colors for newly opened sessions.',
                    children: [
                      _buildColorField(
                        fieldKey: _foregroundColorFieldKey,
                        label: 'Foreground',
                        controller: _foregroundColorController,
                        focusNode: _foregroundColorFocusNode,
                        inputKey: const Key('profile-editor-color-foreground'),
                        swatchKey: const Key(
                          'profile-editor-swatch-foreground',
                        ),
                        pickKey: const Key('profile-editor-pick-foreground'),
                        resetKey: const Key('profile-editor-reset-foreground'),
                      ),
                      const SizedBox(height: 12),
                      _buildColorField(
                        fieldKey: _backgroundColorFieldKey,
                        label: 'Background',
                        controller: _backgroundColorController,
                        focusNode: _backgroundColorFocusNode,
                        inputKey: const Key('profile-editor-color-background'),
                        swatchKey: const Key(
                          'profile-editor-swatch-background',
                        ),
                        pickKey: const Key('profile-editor-pick-background'),
                        resetKey: const Key('profile-editor-reset-background'),
                      ),
                      const SizedBox(height: 12),
                      _buildColorField(
                        fieldKey: _cursorColorFieldKey,
                        label: 'Cursor color',
                        controller: _cursorColorController,
                        focusNode: _cursorColorFocusNode,
                        inputKey: const Key('profile-editor-color-cursor'),
                        swatchKey: const Key('profile-editor-swatch-cursor'),
                        pickKey: const Key('profile-editor-pick-cursor'),
                        resetKey: const Key('profile-editor-reset-cursor'),
                      ),
                      const SizedBox(height: 12),
                      _buildColorField(
                        fieldKey: _selectionColorFieldKey,
                        label: 'Selection color',
                        controller: _selectionColorController,
                        focusNode: _selectionColorFocusNode,
                        inputKey: const Key('profile-editor-color-selection'),
                        swatchKey: const Key('profile-editor-swatch-selection'),
                        pickKey: const Key('profile-editor-pick-selection'),
                        resetKey: const Key('profile-editor-reset-selection'),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: 'Cursor',
                    description:
                        'Adjust cursor shape and animation for new sessions.',
                    children: [
                      DropdownButtonFormField<TerminalCursorShape>(
                        key: const Key('profile-editor-cursor-shape'),
                        initialValue: _cursorShape,
                        isExpanded: true,
                        iconSize: 18,
                        itemHeight: _dropdownItemHeight,
                        menuMaxHeight: 240,
                        borderRadius: BorderRadius.circular(theme.radius.md),
                        decoration: InputDecoration(
                          labelText: 'Cursor shape',
                          constraints: const BoxConstraints(
                            minHeight: _controlHeight,
                          ),
                        ),
                        items: TerminalCursorShape.values
                            .map(
                              (value) => DropdownMenuItem<TerminalCursorShape>(
                                value: value,
                                child: Text(terminalCursorShapeLabel(value)),
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
                      ToggleSettingRow(
                        key: const Key('profile-editor-cursor-blink'),
                        label: 'Blink cursor',
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
                  SettingsSection(
                    title: 'Interaction',
                    description:
                        'Choose selection defaults for newly opened sessions.',
                    children: [
                      ToggleSettingRow(
                        key: const Key('profile-editor-copy-on-select'),
                        label: 'Copy on select',
                        value: _copyOnSelect,
                        onChanged: (value) {
                          setState(() {
                            _didEdit = true;
                            _copyOnSelect = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Option-drag mode',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildOptionDragModeField(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        footer: Row(
          children: [
            Expanded(
              child: Text(
                'Existing sessions do not hot-update after profile edits.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
              ),
            ),
            SizedBox(width: theme.spacing.lg),
            AppActionButton(
              buttonKey: const Key('profile-editor-cancel'),
              tone: AppActionTone.secondary,
              label: 'Cancel',
              onPressed: () => unawaited(_closeWithResult(null)),
            ),
            SizedBox(width: theme.spacing.sm),
            AppActionButton(
              buttonKey: const Key('profile-editor-save'),
              icon: Icons.save_outlined,
              label: 'Save',
              onPressed: _hasColorErrors ? null : () => unawaited(_save()),
            ),
          ],
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
    final theme = context.appTheme;
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
            AppActionButton(
              buttonKey: addKey,
              tone: AppActionTone.ghost,
              size: AppActionSize.compact,
              icon: Icons.add,
              label: addLabel,
              tooltip: addLabel,
              onPressed: onAdd,
            ),
          ],
        ),
        if (controllers.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: theme.spacing.xs + 1),
            child: Text(
              emptyLabel,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
            ),
          ),
        for (var index = 0; index < controllers.length; index += 1)
          Padding(
            padding: EdgeInsets.only(top: theme.spacing.sm),
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
                SizedBox(width: theme.spacing.sm),
                _buildListActionButton(
                  buttonKey: Key('$fieldKeyPrefix-$index-up'),
                  tooltip: 'Move up',
                  onPressed: index == 0 ? null : () => onMoveUp(index),
                  icon: Icons.arrow_upward,
                ),
                _buildListActionButton(
                  buttonKey: Key('$fieldKeyPrefix-$index-down'),
                  tooltip: 'Move down',
                  onPressed: index == controllers.length - 1
                      ? null
                      : () => onMoveDown(index),
                  icon: Icons.arrow_downward,
                ),
                _buildListActionButton(
                  buttonKey: Key('$fieldKeyPrefix-$index-remove'),
                  tooltip: 'Remove',
                  onPressed: () => onRemove(index),
                  icon: Icons.delete_outline,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEnvEditor() {
    final theme = context.appTheme;
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
            AppActionButton(
              buttonKey: const Key('profile-editor-add-env'),
              tone: AppActionTone.ghost,
              size: AppActionSize.compact,
              icon: Icons.add,
              label: 'Add variable',
              tooltip: 'Add variable',
              onPressed: _addEnv,
            ),
          ],
        ),
        if (_envControllers.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: theme.spacing.xs + 1),
            child: Text(
              'No environment variables',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
            ),
          ),
        for (var index = 0; index < _envControllers.length; index += 1)
          Padding(
            padding: EdgeInsets.only(top: theme.spacing.sm),
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
                SizedBox(width: theme.spacing.md),
                Expanded(
                  child: TextFormField(
                    key: Key('profile-editor-env-value-$index'),
                    controller: _envControllers[index].valueController,
                    decoration: const InputDecoration(labelText: 'Value'),
                  ),
                ),
                SizedBox(width: theme.spacing.sm),
                _buildListActionButton(
                  buttonKey: Key('profile-editor-env-remove-$index'),
                  tooltip: 'Remove variable',
                  onPressed: () => _removeEnv(index),
                  icon: Icons.delete_outline,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildListActionButton({
    required Key buttonKey,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return AppActionButton(
      buttonKey: buttonKey,
      tone: AppActionTone.ghost,
      size: AppActionSize.dense,
      tooltip: tooltip,
      icon: icon,
      onPressed: onPressed,
    );
  }

  Widget _buildColorField({
    required String fieldKey,
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required Key inputKey,
    required Key swatchKey,
    required Key pickKey,
    required Key resetKey,
  }) {
    return ColorSettingRow(
      label: label,
      controller: controller,
      focusNode: focusNode,
      inputKey: inputKey,
      swatchKey: swatchKey,
      pickKey: pickKey,
      resetKey: resetKey,
      errorText: _colorErrors[fieldKey],
      onChanged: (value) => _handleColorChanged(fieldKey, value),
      onBlurNormalize: () => _normalizeColorField(fieldKey, controller),
      onPick: () => unawaited(_pickColor(fieldKey, controller)),
      onReset: () => _resetColorField(fieldKey, controller),
    );
  }

  Widget _buildOptionDragModeField() {
    final modes = TerminalOptionDragMode.values;
    if (modes.length == 1) {
      return Text(
        terminalOptionDragModeLabel(modes.single),
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: context.appTheme.textSubtle),
      );
    }

    return RadioGroup<TerminalOptionDragMode>(
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
          for (final mode in modes)
            RadioListTile<TerminalOptionDragMode>(
              key: Key('profile-editor-option-drag-${mode.name}'),
              dense: true,
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              contentPadding: EdgeInsets.zero,
              value: mode,
              title: Text(terminalOptionDragModeLabel(mode)),
            ),
        ],
      ),
    );
  }

  Future<void> _pickColor(
    String fieldKey,
    TextEditingController controller,
  ) async {
    final initialHex = _validateOptionalHexColor(controller.text) == null
        ? controller.text.trim().isEmpty
              ? null
              : normalizeHexColor(controller.text)
        : null;
    final result = await showDialog<_ColorPickerResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ColorPickerDialog(initialHex: initialHex),
    );
    if (result == null || !result.applied) {
      return;
    }
    _applyPickedColor(fieldKey, controller, result.hexValue);
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
  late HSVColor _workingHsv;
  late bool _inheritsDefault;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    final initialColor = widget.initialHex == null
        ? null
        : parseOptionalHexColor(widget.initialHex!);
    _inheritsDefault = widget.initialHex == null;
    _workingHsv = HSVColor.fromColor(initialColor ?? Colors.white);
    _hexController = TextEditingController(
      text: widget.initialHex ?? hsvColorToHex(_workingHsv),
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _setWorkingHsv(HSVColor color) {
    final normalized = hsvColorToHex(color);
    setState(() {
      _inheritsDefault = false;
      _workingHsv = color.withAlpha(1);
      _setHexText(normalized);
      _hexError = null;
    });
  }

  void _handleHexChanged(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _hexError = null;
      });
      return;
    }

    try {
      final normalized = normalizeHexColor(trimmed);
      setState(() {
        _inheritsDefault = false;
        _workingHsv = hexToHsvColor(normalized);
        _hexError = null;
      });
    } on FormatException {
      setState(() {
        _hexError = _hexColorErrorText;
      });
    }
  }

  void _normalizeHexField() {
    final trimmed = _hexController.text.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _hexError = null;
      });
      return;
    }

    try {
      final normalized = normalizeHexColor(trimmed);
      setState(() {
        _inheritsDefault = false;
        _workingHsv = hexToHsvColor(normalized);
        _setHexText(normalized);
        _hexError = null;
      });
    } on FormatException {
      setState(() {
        _hexError = _hexColorErrorText;
      });
    }
  }

  void _setHexText(String value) {
    if (_hexController.text == value) {
      return;
    }
    _hexController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final previewColor = _workingHsv.toColor();
    final previewHex = hsvColorToHex(_workingHsv);
    final applyEnabled =
        _inheritsDefault ||
        (_hexController.text.trim().isNotEmpty && _hexError == null);
    return AppDialogScaffold(
      key: const Key('color-picker-dialog'),
      title: 'Pick color',
      onClose: () {
        Navigator.of(context).pop(const _ColorPickerResult(applied: false));
      },
      height: 472,
      expandBody: true,
      constraints: const BoxConstraints(maxWidth: 480),
      headerPadding: EdgeInsets.fromLTRB(
        theme.spacing.xl,
        theme.spacing.lg,
        theme.spacing.xl,
        theme.spacing.sm,
      ),
      bodyPadding: EdgeInsets.fromLTRB(
        theme.spacing.xl,
        theme.spacing.md,
        theme.spacing.xl,
        theme.spacing.md,
      ),
      footerPadding: EdgeInsets.fromLTRB(
        theme.spacing.xl,
        theme.spacing.sm,
        theme.spacing.xl,
        theme.spacing.md,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 440;
          final previewCard = DecoratedBox(
            decoration: BoxDecoration(
              color: theme.chrome.withValues(alpha: 0.36),
              borderRadius: BorderRadius.circular(theme.radius.lg),
              border: Border.all(color: theme.border),
            ),
            child: Padding(
              padding: EdgeInsets.all(theme.spacing.sm + 1),
              child: Row(
                children: [
                  Container(
                    key: const Key('color-picker-preview'),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _inheritsDefault ? theme.chrome : previewColor,
                      borderRadius: BorderRadius.circular(theme.radius.md),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: _inheritsDefault
                        ? Icon(
                            Icons.colorize_outlined,
                            size: 16,
                            color: theme.textMuted,
                          )
                        : null,
                  ),
                  SizedBox(width: theme.spacing.md),
                  Expanded(
                    child: Text(
                      _inheritsDefault
                          ? 'Inheriting default terminal color'
                          : 'Current color $previewHex',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );

          final hexField = TextField(
            key: const Key('color-picker-hex'),
            controller: _hexController,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
            ],
            decoration: InputDecoration(
              hintText: '#RRGGBB or empty',
              errorText: _hexError,
            ),
            onChanged: _handleHexChanged,
            onEditingComplete: _normalizeHexField,
            onTapOutside: (_) {
              _normalizeHexField();
              FocusScope.of(context).unfocus();
            },
          );

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (compact) ...[
                  previewCard,
                  SizedBox(height: theme.spacing.sm + 1),
                  Text(
                    'Hex',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: theme.spacing.xs),
                  hexField,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: previewCard),
                      SizedBox(width: theme.spacing.md),
                      SizedBox(
                        width: 156,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hex',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: theme.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            SizedBox(height: theme.spacing.xs),
                            hexField,
                          ],
                        ),
                      ),
                    ],
                  ),
                SizedBox(height: theme.spacing.md),
                Text(
                  'Palette',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: theme.spacing.sm),
                ColorPickerPalette(
                  key: const Key('color-picker-palette'),
                  color: _workingHsv,
                  aspectRatio: 2.4,
                  onChanged: _setWorkingHsv,
                ),
                SizedBox(height: theme.spacing.sm),
                Text(
                  'Hue',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: theme.spacing.xs + 1),
                HueSlider(
                  key: const Key('color-picker-hue-slider'),
                  color: _workingHsv,
                  onChanged: _setWorkingHsv,
                ),
              ],
            ),
          );
        },
      ),
      footer: Wrap(
        alignment: WrapAlignment.end,
        spacing: theme.spacing.sm,
        runSpacing: theme.spacing.sm,
        children: [
          AppActionButton(
            buttonKey: const Key('color-picker-reset'),
            tone: AppActionTone.ghost,
            label: 'Reset to default',
            onPressed: () {
              Navigator.of(
                context,
              ).pop(const _ColorPickerResult(applied: true, hexValue: null));
            },
          ),
          AppActionButton(
            buttonKey: const Key('color-picker-cancel'),
            tone: AppActionTone.secondary,
            label: 'Cancel',
            onPressed: () {
              Navigator.of(
                context,
              ).pop(const _ColorPickerResult(applied: false));
            },
          ),
          AppActionButton(
            buttonKey: const Key('color-picker-apply'),
            icon: Icons.check_rounded,
            label: 'Apply',
            onPressed: applyEnabled
                ? () {
                    Navigator.of(context).pop(
                      _ColorPickerResult(
                        applied: true,
                        hexValue: _inheritsDefault
                            ? null
                            : hsvColorToHex(_workingHsv),
                      ),
                    );
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
