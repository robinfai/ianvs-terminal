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

List<String> _normalizedTagsFromText(String text) {
  final tags = <String>[];
  final seen = <String>{};
  for (final rawTag in text.split(',')) {
    final tag = rawTag.trim();
    if (tag.isEmpty) {
      continue;
    }
    if (!seen.add(tag.toLowerCase())) {
      continue;
    }
    tags.add(tag);
  }
  return tags;
}

List<TerminalProfileTrigger> _triggersFromText(String text) {
  final triggers = <TerminalProfileTrigger>[];
  final lines = text.split('\n');
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index].trim();
    if (line.isEmpty) {
      continue;
    }
    final separator = line.indexOf('=>');
    final pattern = (separator == -1 ? line : line.substring(0, separator))
        .trim();
    final actionText = separator == -1
        ? 'notify'
        : line.substring(separator + 2).trim();
    if (pattern.isEmpty) {
      throw FormatException('Line ${index + 1}: trigger regex is required.');
    }
    try {
      RegExp(pattern);
    } on FormatException {
      throw FormatException('Line ${index + 1}: invalid trigger regex.');
    }
    if (actionText.isEmpty || actionText.toLowerCase() == 'notify') {
      triggers.add(TerminalProfileTrigger(pattern: pattern));
      continue;
    }
    final normalizedAction = actionText.toLowerCase();
    if (normalizedAction.startsWith('send:')) {
      final value = _unescapeTriggerValue(actionText.substring(5).trimLeft());
      if (value.isEmpty) {
        throw FormatException('Line ${index + 1}: send text is required.');
      }
      triggers.add(
        TerminalProfileTrigger(
          pattern: pattern,
          action: TerminalProfileTriggerAction.sendText,
          value: value,
        ),
      );
      continue;
    }
    throw FormatException(
      'Line ${index + 1}: use notify or send: response text.',
    );
  }
  return triggers;
}

String? _triggerLinesError(String text) {
  try {
    _triggersFromText(text);
    return null;
  } on FormatException catch (error) {
    return error.message;
  }
}

String _triggerLineFor(TerminalProfileTrigger trigger) {
  return switch (trigger.action) {
    TerminalProfileTriggerAction.notify => '${trigger.pattern} => notify',
    TerminalProfileTriggerAction.sendText =>
      '${trigger.pattern} => send: ${_escapeTriggerValue(trigger.value ?? '')}',
  };
}

List<TerminalProfileSwitchRule> _switchRulesFromText(String text) {
  final rules = <TerminalProfileSwitchRule>[];
  final lines = text.split('\n');
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index].trim();
    if (line.isEmpty) {
      continue;
    }
    final separator = line.indexOf(':');
    if (separator == -1) {
      throw FormatException(
        'Line ${index + 1}: use host:, user:, or dir: before the pattern.',
      );
    }
    final kind = _switchRuleKindFromText(line.substring(0, separator));
    final pattern = line.substring(separator + 1).trim();
    if (kind == null) {
      throw FormatException(
        'Line ${index + 1}: use host, user, or dir as the rule type.',
      );
    }
    if (pattern.isEmpty) {
      throw FormatException('Line ${index + 1}: pattern is required.');
    }
    rules.add(TerminalProfileSwitchRule(kind: kind, pattern: pattern));
  }
  return rules;
}

String? _switchRuleLinesError(String text) {
  try {
    _switchRulesFromText(text);
    return null;
  } on FormatException catch (error) {
    return error.message;
  }
}

TerminalProfileSwitchRuleKind? _switchRuleKindFromText(String value) {
  return switch (value.trim().toLowerCase()) {
    'host' || 'hostname' => TerminalProfileSwitchRuleKind.hostname,
    'user' || 'username' => TerminalProfileSwitchRuleKind.username,
    'dir' || 'directory' || 'cwd' => TerminalProfileSwitchRuleKind.directory,
    _ => null,
  };
}

String _switchRuleLineFor(TerminalProfileSwitchRule rule) {
  final kind = switch (rule.kind) {
    TerminalProfileSwitchRuleKind.hostname => 'host',
    TerminalProfileSwitchRuleKind.username => 'user',
    TerminalProfileSwitchRuleKind.directory => 'dir',
  };
  return '$kind: ${rule.pattern}';
}

String _escapeTriggerValue(String value) {
  return value
      .replaceAll('\\', r'\\')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n');
}

String _unescapeTriggerValue(String value) {
  final buffer = StringBuffer();
  for (var index = 0; index < value.length; index += 1) {
    final character = value[index];
    if (character != '\\' || index == value.length - 1) {
      buffer.write(character);
      continue;
    }
    index += 1;
    final escaped = value[index];
    buffer.write(switch (escaped) {
      'n' => '\n',
      'r' => '\r',
      '\\' => '\\',
      _ => escaped,
    });
  }
  return buffer.toString();
}

class _ColorFieldSpec {
  const _ColorFieldSpec({
    required this.group,
    required this.slot,
    required this.label,
  });

  final String group;
  final String slot;
  final String label;

  String get fieldKey => '$group.$slot';

  String get debugLabel => switch (group) {
    'special' => 'profile-editor-color-$slot',
    _ => 'profile-editor-color-$group-$slot',
  };

  Key get inputKey => switch (group) {
    'special' => Key('profile-editor-color-$slot'),
    _ => Key('profile-editor-color-$group-$slot'),
  };

  Key get swatchKey => switch (group) {
    'special' => Key('profile-editor-swatch-$slot'),
    _ => Key('profile-editor-swatch-$group-$slot'),
  };

  Key get pickKey => switch (group) {
    'special' => Key('profile-editor-pick-$slot'),
    _ => Key('profile-editor-pick-$group-$slot'),
  };

  Key get resetKey => switch (group) {
    'special' => Key('profile-editor-reset-$slot'),
    _ => Key('profile-editor-reset-$group-$slot'),
  };
}

const List<_ColorFieldSpec> _specialColorFieldSpecs = <_ColorFieldSpec>[
  _ColorFieldSpec(group: 'special', slot: 'foreground', label: 'Foreground'),
  _ColorFieldSpec(group: 'special', slot: 'background', label: 'Background'),
  _ColorFieldSpec(group: 'special', slot: 'cursor', label: 'Cursor color'),
  _ColorFieldSpec(
    group: 'special',
    slot: 'selection',
    label: 'Selection color',
  ),
];

const List<_ColorFieldSpec> _normalAnsiColorFieldSpecs = <_ColorFieldSpec>[
  _ColorFieldSpec(group: 'normal', slot: 'black', label: 'Black'),
  _ColorFieldSpec(group: 'normal', slot: 'red', label: 'Red'),
  _ColorFieldSpec(group: 'normal', slot: 'green', label: 'Green'),
  _ColorFieldSpec(group: 'normal', slot: 'yellow', label: 'Yellow'),
  _ColorFieldSpec(group: 'normal', slot: 'blue', label: 'Blue'),
  _ColorFieldSpec(group: 'normal', slot: 'magenta', label: 'Magenta'),
  _ColorFieldSpec(group: 'normal', slot: 'cyan', label: 'Cyan'),
  _ColorFieldSpec(group: 'normal', slot: 'white', label: 'White'),
];

const List<_ColorFieldSpec> _brightAnsiColorFieldSpecs = <_ColorFieldSpec>[
  _ColorFieldSpec(group: 'bright', slot: 'black', label: 'Bright black'),
  _ColorFieldSpec(group: 'bright', slot: 'red', label: 'Bright red'),
  _ColorFieldSpec(group: 'bright', slot: 'green', label: 'Bright green'),
  _ColorFieldSpec(group: 'bright', slot: 'yellow', label: 'Bright yellow'),
  _ColorFieldSpec(group: 'bright', slot: 'blue', label: 'Bright blue'),
  _ColorFieldSpec(group: 'bright', slot: 'magenta', label: 'Bright magenta'),
  _ColorFieldSpec(group: 'bright', slot: 'cyan', label: 'Bright cyan'),
  _ColorFieldSpec(group: 'bright', slot: 'white', label: 'Bright white'),
];

const List<_ColorFieldSpec> _allColorFieldSpecs = <_ColorFieldSpec>[
  ..._specialColorFieldSpecs,
  ..._normalAnsiColorFieldSpecs,
  ..._brightAnsiColorFieldSpecs,
];

class ProfileEditorDialog extends StatefulWidget {
  const ProfileEditorDialog({
    super.key,
    required this.initialValue,
    this.title = 'Edit profile',
  });

  final TerminalProfile initialValue;
  final String title;

  @override
  State<ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<ProfileEditorDialog> {
  static const double _controlHeight = 48;
  static const double _dropdownItemHeight = 48;

  final _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _argControllers = [];
  final List<_EnvEntryControllers> _envControllers = [];
  final List<TextEditingController> _fallbackControllers = [];
  final _scrollController = ScrollController();
  final Map<String, TextEditingController> _colorControllers =
      <String, TextEditingController>{};
  final Map<String, FocusNode> _colorFocusNodes = <String, FocusNode>{};
  final Map<String, String?> _colorErrors = <String, String?>{
    for (final spec in _allColorFieldSpecs) spec.fieldKey: null,
  };

  late final TextEditingController _nameController;
  late final TextEditingController _tagsController;
  late final TextEditingController _triggersController;
  late final TextEditingController _switchRulesController;
  late final TextEditingController _shellController;
  late final TextEditingController _cwdController;
  late final TextEditingController _scrollbackController;
  late final TextEditingController _fontFamilyController;
  late final TextEditingController _fontSizeController;
  late final TextEditingController _lineHeightController;
  late final FocusNode _nameFocusNode;
  late final FocusNode _triggersFocusNode;
  late final FocusNode _switchRulesFocusNode;
  late final FocusNode _shellFocusNode;
  late final FocusNode _scrollbackFocusNode;
  late final FocusNode _fontFamilyFocusNode;
  late final FocusNode _fontSizeFocusNode;
  late final FocusNode _lineHeightFocusNode;

  late TerminalEmulation _terminalEmulation;
  late bool _shellIntegrationEnabled;
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
    _tagsController = _trackedController(text: profile.tags.join(', '));
    _triggersController = _trackedController(
      text: profile.triggers.map(_triggerLineFor).join('\n'),
    );
    _switchRulesController = _trackedController(
      text: profile.switchRules.map(_switchRuleLineFor).join('\n'),
    );
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
    _nameFocusNode = FocusNode(debugLabel: 'profile-editor-name');
    _triggersFocusNode = FocusNode(debugLabel: 'profile-editor-triggers');
    _switchRulesFocusNode = FocusNode(
      debugLabel: 'profile-editor-switch-rules',
    );
    _shellFocusNode = FocusNode(debugLabel: 'profile-editor-shell');
    _scrollbackFocusNode = FocusNode(debugLabel: 'profile-editor-scrollback');
    _fontFamilyFocusNode = FocusNode(debugLabel: 'profile-editor-font-family');
    _fontSizeFocusNode = FocusNode(debugLabel: 'profile-editor-font-size');
    _lineHeightFocusNode = FocusNode(
      debugLabel: 'profile-editor-font-line-height',
    );
    for (final spec in _allColorFieldSpecs) {
      _colorControllers[spec.fieldKey] = _trackedController(
        text: _colorValueForSpec(profile.appearance.colors, spec) ?? '',
      );
      _colorFocusNodes[spec.fieldKey] = FocusNode(debugLabel: spec.debugLabel);
    }

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
    _shellIntegrationEnabled = profile.sessionConfig.shellIntegration.enabled;
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
      _tagsController,
      _triggersController,
      _switchRulesController,
      _shellController,
      _cwdController,
      _scrollbackController,
      _fontFamilyController,
      _fontSizeController,
      _lineHeightController,
      ..._colorControllers.values,
    ]);
    _disposeControllers(_argControllers);
    _disposeControllers(_fallbackControllers);
    _disposeFocusNodes([
      _nameFocusNode,
      _triggersFocusNode,
      _switchRulesFocusNode,
      _shellFocusNode,
      _scrollbackFocusNode,
      _fontFamilyFocusNode,
      _fontSizeFocusNode,
      _lineHeightFocusNode,
      ..._colorFocusNodes.values,
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

  TextEditingController _colorControllerForSpec(_ColorFieldSpec spec) {
    return _colorControllers[spec.fieldKey]!;
  }

  FocusNode _colorFocusNodeForSpec(_ColorFieldSpec spec) {
    return _colorFocusNodes[spec.fieldKey]!;
  }

  String? _colorValueForSpec(
    TerminalColorPalette palette,
    _ColorFieldSpec spec,
  ) {
    return switch (spec.group) {
      'special' => switch (spec.slot) {
        'foreground' => palette.special.foreground,
        'background' => palette.special.background,
        'cursor' => palette.special.cursor,
        'selection' => palette.special.selection,
        _ => null,
      },
      'normal' => _ansiColorValueForSlot(palette.normal, spec.slot),
      'bright' => _ansiColorValueForSlot(palette.bright, spec.slot),
      _ => null,
    };
  }

  String? _ansiColorValueForSlot(TerminalAnsiColors colors, String slot) {
    return switch (slot) {
      'black' => colors.black,
      'red' => colors.red,
      'green' => colors.green,
      'yellow' => colors.yellow,
      'blue' => colors.blue,
      'magenta' => colors.magenta,
      'cyan' => colors.cyan,
      'white' => colors.white,
      _ => null,
    };
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
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
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
    for (final spec in _allColorFieldSpecs) {
      _normalizeColorField(spec.fieldKey, _colorControllerForSpec(spec));
    }
    return !_hasColorErrors;
  }

  TerminalThemePreset? get _selectedThemePreset {
    final colors = _paletteFromControllerValues();
    for (final preset in terminalThemePresets) {
      if (preset.matchesColors(colors)) {
        return preset;
      }
    }
    return null;
  }

  String? _normalizedColorValueForPreset(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      return normalizeHexColor(trimmed);
    } on FormatException {
      return null;
    }
  }

  void _applyThemePreset(TerminalThemePreset preset) {
    _didEdit = true;
    for (final spec in _allColorFieldSpecs) {
      _setControllerText(
        _colorControllerForSpec(spec),
        _colorValueForSpec(preset.palette, spec) ?? '',
      );
    }

    setState(() {
      for (final spec in _allColorFieldSpecs) {
        _colorErrors[spec.fieldKey] = null;
      }
    });
  }

  TerminalColorPalette _paletteFromControllerValues() {
    String? valueFor(_ColorFieldSpec spec) {
      return _normalizedColorValueForPreset(_colorControllerForSpec(spec).text);
    }

    return TerminalColorPalette(
      special: TerminalSpecialColors(
        foreground: valueFor(_specialColorFieldSpecs[0]),
        background: valueFor(_specialColorFieldSpecs[1]),
        cursor: valueFor(_specialColorFieldSpecs[2]),
        selection: valueFor(_specialColorFieldSpecs[3]),
      ),
      normal: TerminalAnsiColors(
        black: valueFor(_normalAnsiColorFieldSpecs[0]),
        red: valueFor(_normalAnsiColorFieldSpecs[1]),
        green: valueFor(_normalAnsiColorFieldSpecs[2]),
        yellow: valueFor(_normalAnsiColorFieldSpecs[3]),
        blue: valueFor(_normalAnsiColorFieldSpecs[4]),
        magenta: valueFor(_normalAnsiColorFieldSpecs[5]),
        cyan: valueFor(_normalAnsiColorFieldSpecs[6]),
        white: valueFor(_normalAnsiColorFieldSpecs[7]),
      ),
      bright: TerminalAnsiColors(
        black: valueFor(_brightAnsiColorFieldSpecs[0]),
        red: valueFor(_brightAnsiColorFieldSpecs[1]),
        green: valueFor(_brightAnsiColorFieldSpecs[2]),
        yellow: valueFor(_brightAnsiColorFieldSpecs[3]),
        blue: valueFor(_brightAnsiColorFieldSpecs[4]),
        magenta: valueFor(_brightAnsiColorFieldSpecs[5]),
        cyan: valueFor(_brightAnsiColorFieldSpecs[6]),
        white: valueFor(_brightAnsiColorFieldSpecs[7]),
      ),
    );
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.value = controller.value.copyWith(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
      composing: TextRange.empty,
    );
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
      tags: _normalizedTagsFromText(_tagsController.text),
      triggers: _triggersFromText(_triggersController.text),
      switchRules: _switchRulesFromText(_switchRulesController.text),
      shell: _shellController.text.trim(),
      args: _nonEmptyEntries(_argControllers),
      env: _envEntries(),
      cwd: _cwdController.text.trim().isEmpty
          ? null
          : _cwdController.text.trim(),
      sessionConfig: widget.initialValue.sessionConfig.copyWith(
        shellIntegration: widget.initialValue.sessionConfig.shellIntegration
            .copyWith(enabled: _shellIntegrationEnabled),
      ),
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
        colors: TerminalColorPalette(
          special: TerminalSpecialColors(
            foreground: _normalizedColorValueForPreset(
              _colorControllerForSpec(_specialColorFieldSpecs[0]).text,
            ),
            background: _normalizedColorValueForPreset(
              _colorControllerForSpec(_specialColorFieldSpecs[1]).text,
            ),
            cursor: _normalizedColorValueForPreset(
              _colorControllerForSpec(_specialColorFieldSpecs[2]).text,
            ),
            selection: _normalizedColorValueForPreset(
              _colorControllerForSpec(_specialColorFieldSpecs[3]).text,
            ),
          ),
          normal: TerminalAnsiColors(
            black: _normalizedColorValueForPreset(
              _colorControllerForSpec(_normalAnsiColorFieldSpecs[0]).text,
            ),
            red: _normalizedColorValueForPreset(
              _colorControllerForSpec(_normalAnsiColorFieldSpecs[1]).text,
            ),
            green: _normalizedColorValueForPreset(
              _colorControllerForSpec(_normalAnsiColorFieldSpecs[2]).text,
            ),
            yellow: _normalizedColorValueForPreset(
              _colorControllerForSpec(_normalAnsiColorFieldSpecs[3]).text,
            ),
            blue: _normalizedColorValueForPreset(
              _colorControllerForSpec(_normalAnsiColorFieldSpecs[4]).text,
            ),
            magenta: _normalizedColorValueForPreset(
              _colorControllerForSpec(_normalAnsiColorFieldSpecs[5]).text,
            ),
            cyan: _normalizedColorValueForPreset(
              _colorControllerForSpec(_normalAnsiColorFieldSpecs[6]).text,
            ),
            white: _normalizedColorValueForPreset(
              _colorControllerForSpec(_normalAnsiColorFieldSpecs[7]).text,
            ),
          ),
          bright: TerminalAnsiColors(
            black: _normalizedColorValueForPreset(
              _colorControllerForSpec(_brightAnsiColorFieldSpecs[0]).text,
            ),
            red: _normalizedColorValueForPreset(
              _colorControllerForSpec(_brightAnsiColorFieldSpecs[1]).text,
            ),
            green: _normalizedColorValueForPreset(
              _colorControllerForSpec(_brightAnsiColorFieldSpecs[2]).text,
            ),
            yellow: _normalizedColorValueForPreset(
              _colorControllerForSpec(_brightAnsiColorFieldSpecs[3]).text,
            ),
            blue: _normalizedColorValueForPreset(
              _colorControllerForSpec(_brightAnsiColorFieldSpecs[4]).text,
            ),
            magenta: _normalizedColorValueForPreset(
              _colorControllerForSpec(_brightAnsiColorFieldSpecs[5]).text,
            ),
            cyan: _normalizedColorValueForPreset(
              _colorControllerForSpec(_brightAnsiColorFieldSpecs[6]).text,
            ),
            white: _normalizedColorValueForPreset(
              _colorControllerForSpec(_brightAnsiColorFieldSpecs[7]).text,
            ),
          ),
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
    if (_triggerLinesError(_triggersController.text) != null) {
      return _triggersFocusNode;
    }
    if (_switchRuleLinesError(_switchRulesController.text) != null) {
      return _switchRulesFocusNode;
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
    for (final spec in _allColorFieldSpecs) {
      if (_validateOptionalHexColor(_colorControllerForSpec(spec).text) !=
          null) {
        return _colorFocusNodeForSpec(spec);
      }
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
        title: widget.title,
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
                    key: const Key('profile-editor-section-identity'),
                    title: 'Identity',
                    description:
                        'Name and tag the profile before configuring launch behavior.',
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
                        key: const Key('profile-editor-tags'),
                        controller: _tagsController,
                        decoration: const InputDecoration(
                          labelText: 'Tags',
                          helperText: 'Separate tags with commas.',
                        ),
                      ),
                    ],
                  ),
                  SettingsSection(
                    key: const Key('profile-editor-section-startup'),
                    title: 'Startup',
                    description:
                        'Configure the command, working directory, and process environment.',
                    children: [
                      _ProfileFormGroup(
                        key: const Key('profile-editor-group-command'),
                        title: 'Command',
                        children: [
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
                      _ProfileFormGroup(
                        key: const Key('profile-editor-group-launch-data'),
                        title: 'Arguments and environment',
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
                    ],
                  ),
                  SettingsSection(
                    key: const Key('profile-editor-section-automation'),
                    title: 'Automation',
                    description:
                        'Match terminal output, then notify you or type a fixed reply.',
                    children: [
                      _ProfileFormGroup(
                        key: const Key('profile-editor-group-automation-rules'),
                        title: 'Rules',
                        children: [
                          TextFormField(
                            key: const Key('profile-editor-triggers'),
                            controller: _triggersController,
                            focusNode: _triggersFocusNode,
                            minLines: 2,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              labelText: 'Triggers',
                              helperText:
                                  'Examples: ERROR => notify, Password: => send: secret\\n',
                            ),
                            validator: (value) =>
                                _triggerLinesError(value ?? ''),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            key: const Key('profile-editor-switch-rules'),
                            controller: _switchRulesController,
                            focusNode: _switchRulesFocusNode,
                            minLines: 2,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              labelText: 'Automatic profile switching',
                              helperText:
                                  'Change this profile after host, user, or directory changes.',
                            ),
                            validator: (value) =>
                                _switchRuleLinesError(value ?? ''),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SettingsSection(
                    key: const Key('profile-editor-section-session'),
                    title: 'Terminal session',
                    description:
                        'Pick terminal emulation and scrollback retention.',
                    children: [
                      _ProfileFormGroup(
                        key: const Key('profile-editor-group-terminal'),
                        title: 'Emulation',
                        children: [
                          DropdownButtonFormField<TerminalEmulation>(
                            key: const Key('profile-editor-emulation'),
                            initialValue: _terminalEmulation,
                            isExpanded: true,
                            iconSize: 18,
                            itemHeight: _dropdownItemHeight,
                            menuMaxHeight: 240,
                            borderRadius: BorderRadius.circular(
                              theme.radius.md,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Emulation',
                              constraints: const BoxConstraints(
                                minHeight: _controlHeight,
                              ),
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
                      _ProfileFormGroup(
                        key: const Key('profile-editor-group-integration'),
                        title: 'Integration',
                        children: [
                          ToggleSettingRow(
                            key: const Key('profile-editor-shell-integration'),
                            label: 'Shell integration',
                            description:
                                'Enable prompt marks, badges, command navigation, and shell-aware actions.',
                            value: _shellIntegrationEnabled,
                            onChanged: (value) {
                              setState(() {
                                _didEdit = true;
                                _shellIntegrationEnabled = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  SettingsSection(
                    key: const Key('profile-editor-section-appearance'),
                    title: 'Appearance',
                    description:
                        'Control typography, terminal colors, and cursor rendering.',
                    children: [
                      _ProfileFormGroup(
                        key: const Key('profile-editor-group-typography'),
                        title: 'Typography',
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
                        ],
                      ),
                      _ProfileFormGroup(
                        key: const Key('profile-editor-group-colors'),
                        title: 'Colors',
                        children: [
                          _buildThemePresetSection(),
                          const SizedBox(height: 16),
                          _buildColorGroupSection(
                            title: 'Special',
                            description:
                                'Foreground, background, cursor, and selection.',
                            specs: _specialColorFieldSpecs,
                          ),
                          const SizedBox(height: 16),
                          _buildColorGroupSection(
                            title: 'ANSI normal',
                            description: 'Standard ANSI 0-7 terminal colors.',
                            specs: _normalAnsiColorFieldSpecs,
                          ),
                          const SizedBox(height: 16),
                          _buildColorGroupSection(
                            title: 'ANSI bright',
                            description: 'Bright ANSI 8-15 terminal colors.',
                            specs: _brightAnsiColorFieldSpecs,
                          ),
                        ],
                      ),
                      _ProfileFormGroup(
                        key: const Key('profile-editor-group-cursor'),
                        title: 'Cursor',
                        children: [
                          DropdownButtonFormField<TerminalCursorShape>(
                            key: const Key('profile-editor-cursor-shape'),
                            initialValue: _cursorShape,
                            isExpanded: true,
                            iconSize: 18,
                            itemHeight: _dropdownItemHeight,
                            menuMaxHeight: 240,
                            borderRadius: BorderRadius.circular(
                              theme.radius.md,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Cursor shape',
                              constraints: const BoxConstraints(
                                minHeight: _controlHeight,
                              ),
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
                    ],
                  ),
                  SettingsSection(
                    key: const Key('profile-editor-section-interaction'),
                    title: 'Interaction',
                    description:
                        'Choose selection defaults for newly opened sessions.',
                    children: [
                      _ProfileFormGroup(
                        key: const Key('profile-editor-group-selection'),
                        title: 'Selection',
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
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          _buildOptionDragModeField(),
                        ],
                      ),
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

  Widget _buildColorGroupSection({
    required String title,
    required String description,
    required List<_ColorFieldSpec> specs,
  }) {
    final theme = context.appTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: theme.spacing.xs + 1),
        Text(
          description,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
        ),
        for (var index = 0; index < specs.length; index += 1) ...[
          SizedBox(height: theme.spacing.sm + 4),
          _buildColorField(specs[index]),
        ],
      ],
    );
  }

  Widget _buildColorField(_ColorFieldSpec spec) {
    final controller = _colorControllerForSpec(spec);
    return ColorSettingRow(
      label: spec.label,
      controller: controller,
      focusNode: _colorFocusNodeForSpec(spec),
      inputKey: spec.inputKey,
      swatchKey: spec.swatchKey,
      pickKey: spec.pickKey,
      resetKey: spec.resetKey,
      errorText: _colorErrors[spec.fieldKey],
      onChanged: (value) => _handleColorChanged(spec.fieldKey, value),
      onBlurNormalize: () => _normalizeColorField(spec.fieldKey, controller),
      onPick: () => unawaited(_pickColor(spec.fieldKey, controller)),
      onReset: () => _resetColorField(spec.fieldKey, controller),
    );
  }

  Widget _buildThemePresetSection() {
    final theme = context.appTheme;
    final selectedPreset = _selectedThemePreset;

    return Column(
      key: const Key('profile-editor-theme-presets'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Theme presets',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: theme.spacing.xs + 1),
        Text(
          'Apply a curated palette, then fine-tune any color below.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
        ),
        SizedBox(height: theme.spacing.sm + 1),
        Wrap(
          spacing: theme.spacing.sm,
          runSpacing: theme.spacing.sm,
          children: [
            for (final preset in terminalThemePresets)
              _TerminalThemePresetButton(
                key: Key('profile-editor-theme-preset-${preset.id}'),
                preset: preset,
                selected: selectedPreset?.id == preset.id,
                onPressed: () => _applyThemePreset(preset),
              ),
          ],
        ),
      ],
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
            AppCompactRadioTile<TerminalOptionDragMode>(
              tileKey: Key('profile-editor-option-drag-${mode.name}'),
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

class _ProfileFormGroup extends StatelessWidget {
  const _ProfileFormGroup({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: theme.spacing.lg),
      child: AppPanel(
        tone: AppPanelTone.chrome,
        padding: EdgeInsets.all(theme.spacing.lg),
        borderRadius: BorderRadius.circular(theme.radius.lg),
        border: Border(left: BorderSide(color: theme.borderStrong, width: 2)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.labelLarge?.copyWith(
                color: theme.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: theme.spacing.md),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ColorPickerResult {
  const _ColorPickerResult({required this.applied, this.hexValue});

  final bool applied;
  final String? hexValue;
}

class _TerminalThemePresetButton extends StatelessWidget {
  const _TerminalThemePresetButton({
    super.key,
    required this.preset,
    required this.selected,
    required this.onPressed,
  });

  final TerminalThemePreset preset;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final titleStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: theme.textPrimary,
      fontWeight: FontWeight.w700,
    );
    final toneBackground = selected
        ? theme.selected
        : theme.chrome.withValues(alpha: 0.65);
    final toneColor = selected ? theme.textPrimary : theme.textMuted;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Apply ${preset.name} theme preset',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(theme.radius.lg),
          onTap: onPressed,
          child: Ink(
            width: 168,
            padding: EdgeInsets.all(theme.spacing.md),
            decoration: BoxDecoration(
              color: selected ? theme.panelElevated : theme.chrome,
              borderRadius: BorderRadius.circular(theme.radius.lg),
              border: Border.all(
                color: selected ? theme.focusRing : theme.border,
                width: selected ? 1.5 : 1,
              ),
              boxShadow: selected ? theme.elevation.floating : const [],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        preset.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_circle_rounded,
                        key: Key(
                          'profile-editor-theme-preset-selected-${preset.id}',
                        ),
                        size: 16,
                        color: theme.focus,
                      ),
                  ],
                ),
                SizedBox(height: theme.spacing.xs + 1),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: toneBackground,
                    borderRadius: BorderRadius.circular(theme.radius.sm),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: theme.spacing.sm,
                      vertical: theme.spacing.xs + 1,
                    ),
                    child: Text(
                      preset.tone.label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: toneColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: theme.spacing.sm + 1),
                Wrap(
                  spacing: theme.spacing.xs + 1,
                  runSpacing: theme.spacing.xs + 1,
                  children: [
                    for (final colorValue in preset.previewColors)
                      _ThemePresetColorSwatch(colorValue: colorValue),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemePresetColorSwatch extends StatelessWidget {
  const _ThemePresetColorSwatch({required this.colorValue});

  final String colorValue;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: parseOptionalHexColor(colorValue),
        borderRadius: BorderRadius.circular(theme.radius.sm),
        border: Border.all(color: theme.border),
      ),
    );
  }
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
