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

String? _tagsError(String text) {
  if (_normalizedTagsFromText(text).length > maxTerminalProfileTags) {
    return 'Use $maxTerminalProfileTags tags or fewer.';
  }
  return null;
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
      if (triggers.length >= maxTerminalProfileTriggers) {
        throw const FormatException(
          'Use $maxTerminalProfileTriggers triggers or fewer.',
        );
      }
      triggers.add(TerminalProfileTrigger(pattern: pattern));
      continue;
    }
    final normalizedAction = actionText.toLowerCase();
    if (normalizedAction.startsWith('send:')) {
      final value = _unescapeTriggerValue(actionText.substring(5).trimLeft());
      if (value.isEmpty) {
        throw FormatException('Line ${index + 1}: send text is required.');
      }
      if (triggers.length >= maxTerminalProfileTriggers) {
        throw const FormatException(
          'Use $maxTerminalProfileTriggers triggers or fewer.',
        );
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
    if (rules.length >= maxTerminalProfileSwitchRules) {
      throw const FormatException(
        'Use $maxTerminalProfileSwitchRules switching rules or fewer.',
      );
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
      .replaceAll(r'\', r'\\')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n');
}

String _unescapeTriggerValue(String value) {
  final buffer = StringBuffer();
  for (var index = 0; index < value.length; index += 1) {
    final character = value[index];
    if (character != r'\' || index == value.length - 1) {
      buffer.write(character);
      continue;
    }
    index += 1;
    final escaped = value[index];
    buffer.write(switch (escaped) {
      'n' => '\n',
      'r' => '\r',
      r'\' => r'\',
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
  _ColorFieldSpec(group: 'special', slot: 'tab', label: 'Tab color'),
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

enum _ProfileEditorSection {
  general,
  startup,
  terminal,
  appearance,
  keys,
  automation,
  advanced,
}

class _ProfileEditorSectionSpec {
  const _ProfileEditorSectionSpec({
    required this.section,
    required this.label,
    required this.icon,
    this.searchTerms = const <String>[],
  });

  final _ProfileEditorSection section;
  final String label;
  final IconData icon;
  final List<String> searchTerms;
}

const List<_ProfileEditorSectionSpec> _profileEditorSections =
    <_ProfileEditorSectionSpec>[
      _ProfileEditorSectionSpec(
        section: _ProfileEditorSection.general,
        label: 'General',
        icon: Icons.badge_outlined,
        searchTerms: ['name', 'tags', 'identity'],
      ),
      _ProfileEditorSectionSpec(
        section: _ProfileEditorSection.startup,
        label: 'Startup',
        icon: Icons.terminal_outlined,
        searchTerms: [
          'shell',
          'program',
          'working directory',
          'arguments',
          'environment',
          'cwd',
        ],
      ),
      _ProfileEditorSectionSpec(
        section: _ProfileEditorSection.terminal,
        label: 'Terminal',
        icon: Icons.settings_applications_outlined,
        searchTerms: ['emulation', 'scrollback', 'retention'],
      ),
      _ProfileEditorSectionSpec(
        section: _ProfileEditorSection.appearance,
        label: 'Appearance',
        icon: Icons.palette_outlined,
        searchTerms: [
          'font',
          'typography',
          'fallback',
          'theme',
          'colors',
          'ansi',
          'cursor',
        ],
      ),
      _ProfileEditorSectionSpec(
        section: _ProfileEditorSection.keys,
        label: 'Keys',
        icon: Icons.keyboard_outlined,
        searchTerms: ['selection', 'copy on select', 'option drag'],
      ),
      _ProfileEditorSectionSpec(
        section: _ProfileEditorSection.automation,
        label: 'Automation',
        icon: Icons.bolt_outlined,
        searchTerms: [
          'triggers',
          'notify',
          'send text',
          'automatic profile switching',
          'profile switching',
        ],
      ),
      _ProfileEditorSectionSpec(
        section: _ProfileEditorSection.advanced,
        label: 'Advanced',
        icon: Icons.tune_outlined,
        searchTerms: [
          'shell integration',
          'prompt marks',
          'badges',
          'command navigation',
        ],
      ),
    ];

class ProfileEditorDialog extends StatefulWidget {
  const ProfileEditorDialog({
    super.key,
    required this.initialValue,
    this.title,
    this.saveWhenPristine = true,
  });

  final TerminalProfile initialValue;
  final String? title;
  final bool saveWhenPristine;

  @override
  State<ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<ProfileEditorDialog> {
  static const double _dropdownItemHeight = 48;

  final _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _argControllers = [];
  final List<_EnvEntryControllers> _envControllers = [];
  final List<TextEditingController> _fallbackControllers = [];
  final _scrollController = ScrollController();
  final GlobalKey<State<StatefulWidget>> _generalSectionKey = GlobalKey(
    debugLabel: 'profile-editor-section-general-anchor',
  );
  final GlobalKey<State<StatefulWidget>> _startupSectionKey = GlobalKey(
    debugLabel: 'profile-editor-section-startup-anchor',
  );
  final GlobalKey<State<StatefulWidget>> _terminalSectionKey = GlobalKey(
    debugLabel: 'profile-editor-section-terminal-anchor',
  );
  final GlobalKey<State<StatefulWidget>> _appearanceSectionKey = GlobalKey(
    debugLabel: 'profile-editor-section-appearance-anchor',
  );
  final GlobalKey<State<StatefulWidget>> _keysSectionKey = GlobalKey(
    debugLabel: 'profile-editor-section-keys-anchor',
  );
  final GlobalKey<State<StatefulWidget>> _automationSectionKey = GlobalKey(
    debugLabel: 'profile-editor-section-automation-anchor',
  );
  final GlobalKey<State<StatefulWidget>> _advancedSectionKey = GlobalKey(
    debugLabel: 'profile-editor-section-advanced-anchor',
  );
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
  late final TextEditingController _sectionSearchController;
  late final FocusNode _nameFocusNode;
  late final FocusNode _tagsFocusNode;
  late final FocusNode _triggersFocusNode;
  late final FocusNode _switchRulesFocusNode;
  late final FocusNode _shellFocusNode;
  late final FocusNode _scrollbackFocusNode;
  late final FocusNode _fontFamilyFocusNode;
  late final FocusNode _fontSizeFocusNode;
  late final FocusNode _lineHeightFocusNode;
  late final FocusNode _sectionSearchFocusNode;
  late final Map<_ProfileEditorSection, FocusNode> _sectionNavFocusNodes;

  late TerminalEmulation _terminalEmulation;
  late bool _shellIntegrationEnabled;
  late TerminalCursorShape _cursorShape;
  late bool _cursorBlink;
  late bool _copyOnSelect;
  late TerminalOptionDragMode _optionDragMode;

  bool _didAttemptSave = false;
  bool _didEdit = false;
  bool _allowClose = false;
  String _sectionSearchQuery = '';
  _ProfileEditorSection _activeSection = _ProfileEditorSection.general;

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
    _sectionSearchController = TextEditingController();
    _nameFocusNode = FocusNode(debugLabel: 'profile-editor-name');
    _tagsFocusNode = FocusNode(debugLabel: 'profile-editor-tags');
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
    _sectionSearchFocusNode = FocusNode(
      debugLabel: 'profile-editor-section-search',
    );
    _sectionNavFocusNodes = {
      for (final spec in _profileEditorSections)
        spec.section: FocusNode(
          debugLabel: 'profile-editor-nav-${spec.section.name}',
        ),
    };
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
      _sectionSearchController,
      ..._colorControllers.values,
    ]);
    _disposeControllers(_argControllers);
    _disposeControllers(_fallbackControllers);
    _disposeFocusNodes([
      _nameFocusNode,
      _tagsFocusNode,
      _triggersFocusNode,
      _switchRulesFocusNode,
      _shellFocusNode,
      _scrollbackFocusNode,
      _fontFamilyFocusNode,
      _fontSizeFocusNode,
      _lineHeightFocusNode,
      _sectionSearchFocusNode,
      ..._sectionNavFocusNodes.values,
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
        'tab' => palette.special.tab,
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
    if (!mounted) {
      return;
    }
    setState(() {
      _didEdit = _hasAnyDirtySection();
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
      return context.l10n.fieldIsRequired(label);
    }
    return null;
  }

  String? _positiveIntegerError(String value, String label, {int? maximum}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return context.l10n.fieldIsRequired(label);
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed < 1) {
      return context.l10n.fieldMustBePositiveInteger(label);
    }
    if (maximum != null && parsed > maximum) {
      return context.l10n.fieldMustBeAtMost(label, maximum);
    }
    return null;
  }

  String? _positiveDoubleError(String value, String label) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return context.l10n.fieldIsRequired(label);
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      return context.l10n.fieldMustBeGreaterThanZero(label);
    }
    return null;
  }

  String? _envKeyError(int index) {
    if (index == 0) {
      final limitError = _envLimitError();
      if (limitError != null) {
        return limitError;
      }
    }
    final trimmed = _envControllers[index].keyController.text.trim();
    if (trimmed.isEmpty) {
      return context.l10n.environmentKeyRequired;
    }
    final duplicateCount = _envControllers
        .map((entry) => entry.keyController.text.trim())
        .where((key) => key == trimmed)
        .length;
    if (duplicateCount > 1) {
      return context.l10n.environmentKeyUnique;
    }
    return null;
  }

  bool get _hasColorErrors => _colorErrors.values.any((error) => error != null);

  String? _validateOptionalHexColor(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return isValidOptionalHexColor(trimmed)
        ? null
        : context.l10n.hexColorValidation;
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
        nextError = context.l10n.hexColorValidation;
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

  bool get _usesAppThemeColors => _allColorFieldSpecs.every(
    (spec) => _colorControllerForSpec(spec).text.trim().isEmpty,
  );

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

  void _followAppThemeColors() {
    _didEdit = true;
    for (final spec in _allColorFieldSpecs) {
      _setControllerText(_colorControllerForSpec(spec), '');
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
        tab: valueFor(_specialColorFieldSpecs[4]),
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

  String? _stringListLimitError({
    required List<TextEditingController> controllers,
    required int maxEntries,
    required String entryLabel,
  }) {
    return _nonEmptyEntries(controllers).length > maxEntries
        ? 'Use $maxEntries $entryLabel or fewer.'
        : null;
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

  String? _envLimitError() {
    return _envEntries().length > maxTerminalEnvironmentEntries
        ? 'Use $maxTerminalEnvironmentEntries environment variables or fewer.'
        : null;
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
            tab: _normalizedColorValueForPreset(
              _colorControllerForSpec(_specialColorFieldSpecs[4]).text,
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
        title: dialogContext.l10n.discardChangesQuestion,
        subtitle: dialogContext.l10n.discardProfileChangesWarning,
        body: const SizedBox.shrink(),
        footer: Wrap(
          spacing: dialogContext.appTheme.spacing.sm,
          runSpacing: dialogContext.appTheme.spacing.sm,
          alignment: WrapAlignment.end,
          children: [
            AppActionButton(
              buttonKey: const Key('profile-editor-discard-cancel'),
              tone: AppActionTone.secondary,
              label: dialogContext.l10n.keepEditing,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            AppActionButton(
              buttonKey: const Key('profile-editor-discard-confirm'),
              tone: AppActionTone.danger,
              icon: Icons.delete_outline,
              label: dialogContext.l10n.discardChanges,
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
    final section = focusNode == null
        ? _firstInvalidSection()
        : _sectionForFocusNode(focusNode);
    if (section != null && _activeSection != section) {
      setState(() {
        _activeSection = section;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
    if (focusNode == null) {
      return;
    }
    focusNode.requestFocus();
    final context = focusNode.context;
    if (context != null && context.mounted) {
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
    }
  }

  _ProfileEditorSection? _sectionForFocusNode(FocusNode focusNode) {
    if (identical(focusNode, _nameFocusNode) ||
        identical(focusNode, _tagsFocusNode)) {
      return _ProfileEditorSection.general;
    }
    if (identical(focusNode, _shellFocusNode) ||
        _envControllers.any(
          (entry) => identical(focusNode, entry.keyFocusNode),
        )) {
      return _ProfileEditorSection.startup;
    }
    if (identical(focusNode, _scrollbackFocusNode)) {
      return _ProfileEditorSection.terminal;
    }
    if (identical(focusNode, _fontFamilyFocusNode) ||
        identical(focusNode, _fontSizeFocusNode) ||
        identical(focusNode, _lineHeightFocusNode) ||
        _colorFocusNodes.values.any((node) => identical(node, focusNode))) {
      return _ProfileEditorSection.appearance;
    }
    if (identical(focusNode, _triggersFocusNode) ||
        identical(focusNode, _switchRulesFocusNode)) {
      return _ProfileEditorSection.automation;
    }
    return null;
  }

  _ProfileEditorSection? _firstInvalidSection() {
    if (_requiredFieldError(_nameController.text, 'Name') != null ||
        _tagsError(_tagsController.text) != null) {
      return _ProfileEditorSection.general;
    }
    if (_requiredFieldError(_shellController.text, 'Shell') != null ||
        _stringListLimitError(
              controllers: _argControllers,
              maxEntries: maxTerminalLaunchArgs,
              entryLabel: 'arguments',
            ) !=
            null ||
        _envLimitError() != null ||
        _envControllers.indexed.any(
          (entry) => _envKeyError(entry.$1) != null,
        )) {
      return _ProfileEditorSection.startup;
    }
    if (_positiveIntegerError(
          _scrollbackController.text,
          'Scrollback lines',
          maximum: maxTerminalScrollbackLines,
        ) !=
        null) {
      return _ProfileEditorSection.terminal;
    }
    if (_requiredFieldError(_fontFamilyController.text, 'Font family') !=
            null ||
        _stringListLimitError(
              controllers: _fallbackControllers,
              maxEntries: maxTerminalFontFallbackFamilies,
              entryLabel: 'fallback fonts',
            ) !=
            null ||
        _positiveDoubleError(_fontSizeController.text, 'Font size') != null ||
        _positiveDoubleError(_lineHeightController.text, 'Line height') !=
            null ||
        _allColorFieldSpecs.any(
          (spec) =>
              _validateOptionalHexColor(_colorControllerForSpec(spec).text) !=
              null,
        )) {
      return _ProfileEditorSection.appearance;
    }
    if (_triggerLinesError(_triggersController.text) != null ||
        _switchRuleLinesError(_switchRulesController.text) != null) {
      return _ProfileEditorSection.automation;
    }
    return null;
  }

  FocusNode? _firstInvalidFocusNode() {
    if (_requiredFieldError(_nameController.text, 'Name') != null) {
      return _nameFocusNode;
    }
    if (_tagsError(_tagsController.text) != null) {
      return _tagsFocusNode;
    }
    if (_requiredFieldError(_shellController.text, 'Shell') != null) {
      return _shellFocusNode;
    }
    if (_stringListLimitError(
          controllers: _argControllers,
          maxEntries: maxTerminalLaunchArgs,
          entryLabel: 'arguments',
        ) !=
        null) {
      return null;
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
    if (_positiveIntegerError(
          _scrollbackController.text,
          'Scrollback lines',
          maximum: maxTerminalScrollbackLines,
        ) !=
        null) {
      return _scrollbackFocusNode;
    }
    if (_requiredFieldError(_fontFamilyController.text, 'Font family') !=
        null) {
      return _fontFamilyFocusNode;
    }
    if (_stringListLimitError(
          controllers: _fallbackControllers,
          maxEntries: maxTerminalFontFallbackFamilies,
          entryLabel: 'fallback fonts',
        ) !=
        null) {
      return null;
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

  Future<void> _jumpToSection(_ProfileEditorSection section) async {
    setState(() {
      _activeSection = section;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
  }

  List<_ProfileEditorSectionSpec> _matchingSectionSpecs() {
    final normalizedTerms = _sectionSearchQuery
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    if (normalizedTerms.isEmpty) {
      return _profileEditorSections;
    }
    return _profileEditorSections
        .where((spec) {
          final searchable = <String>[
            spec.label,
            context.l10n.profileSectionName(spec.section.name),
            ...spec.searchTerms,
          ].join('\n').toLowerCase();
          return normalizedTerms.every(searchable.contains);
        })
        .toList(growable: false);
  }

  void _updateSectionSearch(String value) {
    setState(() {
      _sectionSearchQuery = value;
      final matchingSections = _matchingSectionSpecs();
      if (matchingSections.isNotEmpty &&
          !matchingSections.any((spec) => spec.section == _activeSection)) {
        _activeSection = matchingSections.first.section;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  bool _stringListsEqual(List<String> left, List<String> right) {
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

  List<String> _controllerTexts(List<TextEditingController> controllers) {
    return [for (final controller in controllers) controller.text];
  }

  List<String> _initialEnvLines() {
    return [
      for (final entry in widget.initialValue.launch.env.entries)
        '${entry.key}=${entry.value}',
    ];
  }

  List<String> _currentEnvLines() {
    return [
      for (final entry in _envControllers)
        '${entry.keyController.text}=${entry.valueController.text}',
    ];
  }

  bool _isSectionDirty(_ProfileEditorSection section) {
    final profile = widget.initialValue;
    return switch (section) {
      _ProfileEditorSection.general =>
        _nameController.text != profile.name ||
            !_stringListsEqual(
              _normalizedTagsFromText(_tagsController.text),
              profile.tags,
            ),
      _ProfileEditorSection.startup =>
        _shellController.text != profile.shell ||
            _cwdController.text != (profile.cwd ?? '') ||
            !_stringListsEqual(
              _controllerTexts(_argControllers),
              profile.args,
            ) ||
            !_stringListsEqual(_currentEnvLines(), _initialEnvLines()),
      _ProfileEditorSection.terminal =>
        _terminalEmulation != profile.terminalEmulation ||
            _scrollbackController.text != profile.scrollbackLines.toString(),
      _ProfileEditorSection.appearance =>
        _fontFamilyController.text != profile.appearance.font.family ||
            !_stringListsEqual(
              _controllerTexts(_fallbackControllers),
              profile.appearance.font.fallback,
            ) ||
            _fontSizeController.text !=
                profile.appearance.font.size.toString() ||
            _lineHeightController.text !=
                profile.appearance.font.lineHeight.toString() ||
            _cursorShape != profile.appearance.cursor.shape ||
            _cursorBlink != profile.appearance.cursor.blink ||
            _allColorFieldSpecs.any(
              (spec) =>
                  _colorControllerForSpec(spec).text !=
                  (_colorValueForSpec(profile.appearance.colors, spec) ?? ''),
            ),
      _ProfileEditorSection.keys =>
        _copyOnSelect != profile.interaction.copyOnSelect ||
            _optionDragMode != profile.interaction.optionDragMode,
      _ProfileEditorSection.automation =>
        _triggersController.text !=
                profile.triggers.map(_triggerLineFor).join('\n') ||
            _switchRulesController.text !=
                profile.switchRules.map(_switchRuleLineFor).join('\n'),
      _ProfileEditorSection.advanced =>
        _shellIntegrationEnabled !=
            profile.sessionConfig.shellIntegration.enabled,
    };
  }

  bool _hasAnyDirtySection() {
    return _profileEditorSections.any((spec) => _isSectionDirty(spec.section));
  }

  int _dirtySectionCount() {
    return _profileEditorSections
        .where((spec) => _isSectionDirty(spec.section))
        .length;
  }

  void _replaceStringListControllers(
    List<TextEditingController> controllers,
    Iterable<String> values,
  ) {
    _disposeControllers(controllers);
    controllers
      ..clear()
      ..addAll(values.map((value) => _trackedController(text: value)));
  }

  void _replaceEnvControllers(Map<String, String> values) {
    for (final entry in _envControllers) {
      entry.dispose();
    }
    _envControllers
      ..clear()
      ..addAll(
        values.entries.map(
          (entry) => _trackedEnvEntry(key: entry.key, value: entry.value),
        ),
      );
  }

  void _resetSection(_ProfileEditorSection section) {
    final profile = widget.initialValue;
    switch (section) {
      case _ProfileEditorSection.general:
        _setControllerText(_nameController, profile.name);
        _setControllerText(_tagsController, profile.tags.join(', '));
      case _ProfileEditorSection.startup:
        _setControllerText(_shellController, profile.shell);
        _setControllerText(_cwdController, profile.cwd ?? '');
        _replaceStringListControllers(_argControllers, profile.args);
        _replaceEnvControllers(profile.launch.env);
      case _ProfileEditorSection.terminal:
        _terminalEmulation = profile.terminalEmulation;
        _setControllerText(
          _scrollbackController,
          profile.scrollbackLines.toString(),
        );
      case _ProfileEditorSection.appearance:
        _setControllerText(
          _fontFamilyController,
          profile.appearance.font.family,
        );
        _replaceStringListControllers(
          _fallbackControllers,
          profile.appearance.font.fallback,
        );
        _setControllerText(
          _fontSizeController,
          profile.appearance.font.size.toString(),
        );
        _setControllerText(
          _lineHeightController,
          profile.appearance.font.lineHeight.toString(),
        );
        for (final spec in _allColorFieldSpecs) {
          _setControllerText(
            _colorControllerForSpec(spec),
            _colorValueForSpec(profile.appearance.colors, spec) ?? '',
          );
          _colorErrors[spec.fieldKey] = null;
        }
        _cursorShape = profile.appearance.cursor.shape;
        _cursorBlink = profile.appearance.cursor.blink;
      case _ProfileEditorSection.keys:
        _copyOnSelect = profile.interaction.copyOnSelect;
        _optionDragMode = profile.interaction.optionDragMode;
      case _ProfileEditorSection.automation:
        _setControllerText(
          _triggersController,
          profile.triggers.map(_triggerLineFor).join('\n'),
        );
        _setControllerText(
          _switchRulesController,
          profile.switchRules.map(_switchRuleLineFor).join('\n'),
        );
      case _ProfileEditorSection.advanced:
        _shellIntegrationEnabled =
            profile.sessionConfig.shellIntegration.enabled;
    }

    setState(() {
      _didEdit = _hasAnyDirtySection();
    });
  }

  Widget _buildSectionNavigation({required bool vertical}) {
    final theme = context.appTheme;
    final matchingSections = _matchingSectionSpecs();
    final dirtySectionCount = _dirtySectionCount();
    final children = [
      for (final (index, spec) in matchingSections.indexed)
        _ProfileEditorSectionNavItem(
          key: Key('profile-editor-nav-${spec.section.name}'),
          spec: spec,
          selected: _activeSection == spec.section,
          dirty: _isSectionDirty(spec.section),
          vertical: vertical,
          focusNode: _sectionNavFocusNodes[spec.section],
          focusOrder: 20 + index.toDouble(),
          onReset: () => _resetSection(spec.section),
          onTap: () => unawaited(_jumpToSection(spec.section)),
        ),
    ];
    final searchHasQuery = _sectionSearchQuery.trim().isNotEmpty;
    final searchField = FocusTraversalOrder(
      order: const NumericFocusOrder(10),
      child: Semantics(
        identifier: 'profile-editor-section-search',
        label: context.l10n.findProfileSetting,
        container: true,
        explicitChildNodes: true,
        child: TextField(
          key: const Key('profile-editor-section-search'),
          controller: _sectionSearchController,
          focusNode: _sectionSearchFocusNode,
          onChanged: _updateSectionSearch,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: context.l10n.findSetting,
            prefixIcon: const Icon(Icons.search_outlined, size: 18),
            suffixIcon: searchHasQuery
                ? IconButton(
                    key: const Key('profile-editor-section-search-clear'),
                    tooltip: context.l10n.clearSettingsSearch,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _sectionSearchController.clear();
                      _updateSectionSearch('');
                    },
                  )
                : null,
            isDense: true,
          ),
        ),
      ),
    );
    final resultSummary = searchHasQuery
        ? Padding(
            padding: EdgeInsets.only(top: theme.spacing.xs),
            child: Text(
              matchingSections.isEmpty
                  ? context.l10n.noSettingsFound
                  : context.l10n.sectionsFound(matchingSections.length),
              key: const Key('profile-editor-section-search-count'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: matchingSections.isEmpty
                    ? theme.warning
                    : theme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        : const SizedBox.shrink();
    final dirtySummary = dirtySectionCount > 0
        ? Padding(
            padding: EdgeInsets.only(top: theme.spacing.xs),
            child: Text(
              context.l10n.modifiedSections(dirtySectionCount),
              key: const Key('profile-editor-dirty-summary'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: theme.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        : const SizedBox.shrink();
    final emptyState = matchingSections.isEmpty
        ? Padding(
            padding: EdgeInsets.only(top: theme.spacing.sm),
            child: Text(
              context.l10n.noProfileSettingsMatch(_sectionSearchQuery.trim()),
              key: const Key('profile-editor-section-search-empty'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: theme.textMuted),
            ),
          )
        : const SizedBox.shrink();

    if (!vertical) {
      return Semantics(
        identifier: 'profile-editor-section-nav',
        label: context.l10n.profileEditorSectionNavigation,
        container: true,
        explicitChildNodes: true,
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: AppPanel(
            key: const Key('profile-editor-section-nav'),
            tone: AppPanelTone.chrome,
            padding: EdgeInsets.all(theme.spacing.sm),
            borderRadius: BorderRadius.circular(theme.radius.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                resultSummary,
                dirtySummary,
                if (matchingSections.isNotEmpty) ...[
                  SizedBox(height: theme.spacing.sm),
                  SingleChildScrollView(
                    key: const Key('profile-editor-section-nav-scroll'),
                    scrollDirection: Axis.horizontal,
                    child: Row(children: children),
                  ),
                ] else
                  emptyState,
              ],
            ),
          ),
        ),
      );
    }

    return Semantics(
      identifier: 'profile-editor-section-nav',
      label: context.l10n.profileEditorSectionNavigation,
      container: true,
      explicitChildNodes: true,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: KeyedSubtree(
          key: const Key('profile-editor-section-nav'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              resultSummary,
              dirtySummary,
              SizedBox(height: theme.spacing.xl),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: matchingSections.isNotEmpty
                        ? children
                        : [emptyState],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final screenSize = MediaQuery.sizeOf(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final dialogWidth = math.min(screenSize.width - 32, 960.0);
    final dialogHeight = math.max(
      0.0,
      math.min(screenSize.height - keyboardInset - 32, 720.0),
    );

    return PopScope<TerminalProfile?>(
      canPop: _allowClose || !_didEdit,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _allowClose) {
          return;
        }
        unawaited(_closeWithResult(null));
      },
      child: Semantics(
        identifier: 'profile-editor-dialog',
        label: context.l10n.profileEditorDialog,
        container: true,
        explicitChildNodes: true,
        child: AppDialogScaffold(
          key: const Key('profile-editor-dialog'),
          title: widget.title ?? context.l10n.editProfile,
          subtitle: context.l10n.profileChangesNewSessionsOnly,
          onClose: () => unawaited(_closeWithResult(null)),
          closeTooltip: context.l10n.closeProfileEditor,
          insetPadding: EdgeInsets.all(theme.spacing.md),
          constraints: const BoxConstraints(maxWidth: 960),
          width: dialogWidth,
          height: dialogHeight,
          expandBody: true,
          titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: theme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
          subtitleTextStyle: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: theme.textSubtle),
          headerPadding: EdgeInsets.only(
            left: theme.spacing.xxl,
            top: theme.spacing.xxl,
            right: theme.spacing.xxl,
            bottom: theme.spacing.xl,
          ),
          bodyPadding: EdgeInsets.zero,
          footerPadding: EdgeInsets.symmetric(
            horizontal: theme.spacing.xxl,
            vertical: theme.spacing.xl,
          ),
          body: Form(
            key: _formKey,
            autovalidateMode: _didAttemptSave
                ? AutovalidateMode.always
                : AutovalidateMode.disabled,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showSideNavigation = constraints.maxWidth >= 680;
                final sideNavigationWidth = constraints.maxWidth >= 860
                    ? 220.0
                    : 184.0;
                final sectionNavigation = _buildSectionNavigation(
                  vertical: showSideNavigation,
                );
                final scrollableSections = Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  radius: Radius.circular(theme.radius.sm),
                  thickness: theme.spacing.xs,
                  child: SingleChildScrollView(
                    key: const Key('profile-editor-scroll-view'),
                    controller: _scrollController,
                    padding: EdgeInsets.only(
                      left: theme.spacing.xxl + theme.spacing.md,
                      top: theme.spacing.xxl,
                      right: theme.spacing.xxl + theme.spacing.md,
                      bottom: theme.spacing.xxl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Offstage(
                          offstage:
                              _activeSection != _ProfileEditorSection.general,
                          child: KeyedSubtree(
                            key: const Key('profile-editor-section-general'),
                            child: KeyedSubtree(
                              key: const Key('profile-editor-section-identity'),
                              child: SettingsSection(
                                anchorKey: _generalSectionKey,
                                title: context.l10n.general,
                                description:
                                    context.l10n.generalProfileDescription,
                                contained: true,
                                children: [
                                  _ProfileLabeledControl(
                                    label: context.l10n.name,
                                    child: TextFormField(
                                      key: const Key('profile-editor-name'),
                                      controller: _nameController,
                                      focusNode: _nameFocusNode,
                                      decoration: _profileFieldDecoration(),
                                      validator: (value) => _requiredFieldError(
                                        value ?? '',
                                        context.l10n.name,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: theme.spacing.xxl),
                                  _ProfileLabeledControl(
                                    label: context.l10n.tags,
                                    helperText: context.l10n.tagsCommaHelp,
                                    child: TextFormField(
                                      key: const Key('profile-editor-tags'),
                                      controller: _tagsController,
                                      focusNode: _tagsFocusNode,
                                      decoration: _profileFieldDecoration(),
                                      validator: (value) =>
                                          _tagsError(value ?? ''),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Offstage(
                          offstage:
                              _activeSection != _ProfileEditorSection.startup,
                          child: KeyedSubtree(
                            key: const Key('profile-editor-section-startup'),
                            child: SettingsSection(
                              anchorKey: _startupSectionKey,
                              title: context.l10n.startup,
                              description:
                                  context.l10n.profileStartupDescription,
                              children: [
                                _ProfileFormGroup(
                                  key: const Key(
                                    'profile-editor-group-command',
                                  ),
                                  title: context.l10n.command,
                                  tone: AppPanelTone.elevated,
                                  children: [
                                    _ProfileLabeledControl(
                                      label: context.l10n.shellProgram,
                                      child: TextFormField(
                                        key: const Key('profile-editor-shell'),
                                        controller: _shellController,
                                        focusNode: _shellFocusNode,
                                        decoration: _profileFieldDecoration(),
                                        validator: (value) =>
                                            _requiredFieldError(
                                              value ?? '',
                                              context.l10n.shell,
                                            ),
                                      ),
                                    ),
                                    SizedBox(height: theme.spacing.xxl),
                                    _ProfileLabeledControl(
                                      label: context.l10n.workingDirectory,
                                      helperText:
                                          context.l10n.workingDirectoryHelp,
                                      child: TextFormField(
                                        key: const Key('profile-editor-cwd'),
                                        controller: _cwdController,
                                        decoration: _profileFieldDecoration(),
                                      ),
                                    ),
                                  ],
                                ),
                                _ProfileFormGroup(
                                  key: const Key(
                                    'profile-editor-group-launch-data',
                                  ),
                                  title: context.l10n.argumentsAndEnvironment,
                                  tone: AppPanelTone.elevated,
                                  children: [
                                    _buildStringListEditor(
                                      title: context.l10n.arguments,
                                      addKey: const Key(
                                        'profile-editor-add-arg',
                                      ),
                                      addLabel: 'Add arg',
                                      emptyLabel: 'No launch arguments',
                                      controllers: _argControllers,
                                      fieldKeyPrefix: 'profile-editor-arg',
                                      compactRows: true,
                                      maxEntries: maxTerminalLaunchArgs,
                                      limitEntryLabel: 'arguments',
                                      onAdd: _addArg,
                                      onRemove: _removeArg,
                                      onMoveUp: (index) =>
                                          _moveArg(index, index - 1),
                                      onMoveDown: (index) =>
                                          _moveArg(index, index + 1),
                                    ),
                                    const SizedBox(height: 16),
                                    _buildEnvEditor(),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        Offstage(
                          offstage:
                              _activeSection != _ProfileEditorSection.terminal,
                          child: KeyedSubtree(
                            key: const Key('profile-editor-section-terminal'),
                            child: KeyedSubtree(
                              key: const Key('profile-editor-section-session'),
                              child: SettingsSection(
                                anchorKey: _terminalSectionKey,
                                title: context.l10n.terminal,
                                description:
                                    context.l10n.terminalProfileDescription,
                                children: [
                                  _ProfileFormGroup(
                                    key: const Key(
                                      'profile-editor-group-terminal',
                                    ),
                                    title: context.l10n.emulation,
                                    tone: AppPanelTone.elevated,
                                    children: [
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 560,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            _ProfileLabeledControl(
                                              label: context.l10n.emulation,
                                              child:
                                                  AppDropdownFormField<
                                                    TerminalEmulation
                                                  >(
                                                    key: const Key(
                                                      'profile-editor-emulation',
                                                    ),
                                                    initialValue:
                                                        _terminalEmulation,
                                                    isExpanded: true,
                                                    iconSize: 18,
                                                    itemHeight:
                                                        _dropdownItemHeight,
                                                    menuMaxHeight: 240,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          theme.radius.md,
                                                        ),
                                                    decoration:
                                                        _profileFieldDecoration(),
                                                    items: TerminalEmulation
                                                        .values
                                                        .map(
                                                          (value) =>
                                                              DropdownMenuItem<
                                                                TerminalEmulation
                                                              >(
                                                                value: value,
                                                                child: Text(
                                                                  terminalEmulationLabel(
                                                                    value,
                                                                  ),
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
                                                        _terminalEmulation =
                                                            value;
                                                      });
                                                    },
                                                  ),
                                            ),
                                            SizedBox(height: theme.spacing.xxl),
                                            _ProfileLabeledControl(
                                              label:
                                                  context.l10n.scrollbackLines,
                                              child: TextFormField(
                                                key: const Key(
                                                  'profile-editor-scrollback',
                                                ),
                                                controller:
                                                    _scrollbackController,
                                                focusNode: _scrollbackFocusNode,
                                                decoration:
                                                    _profileFieldDecoration(),
                                                keyboardType:
                                                    TextInputType.number,
                                                inputFormatters: [
                                                  FilteringTextInputFormatter
                                                      .digitsOnly,
                                                ],
                                                validator: (value) =>
                                                    _positiveIntegerError(
                                                      value ?? '',
                                                      context
                                                          .l10n
                                                          .scrollbackLines,
                                                      maximum:
                                                          maxTerminalScrollbackLines,
                                                    ),
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
                        Offstage(
                          offstage:
                              _activeSection !=
                              _ProfileEditorSection.appearance,
                          child: KeyedSubtree(
                            key: const Key('profile-editor-section-appearance'),
                            child: SettingsSection(
                              anchorKey: _appearanceSectionKey,
                              title: context.l10n.appearance,
                              description:
                                  context.l10n.profileAppearanceDescription,
                              children: [
                                _ProfileFormGroup(
                                  key: const Key(
                                    'profile-editor-group-typography',
                                  ),
                                  title: context.l10n.typography,
                                  tone: AppPanelTone.elevated,
                                  children: [
                                    _ProfileLabeledControl(
                                      label: context.l10n.fontFamily,
                                      child: TextFormField(
                                        key: const Key(
                                          'profile-editor-font-family',
                                        ),
                                        controller: _fontFamilyController,
                                        focusNode: _fontFamilyFocusNode,
                                        decoration: _profileFieldDecoration(),
                                        validator: (value) =>
                                            _requiredFieldError(
                                              value ?? '',
                                              context.l10n.fontFamily,
                                            ),
                                      ),
                                    ),
                                    SizedBox(height: theme.spacing.xxl),
                                    _buildStringListEditor(
                                      title: context.l10n.fallbackFonts,
                                      addKey: const Key(
                                        'profile-editor-add-fallback',
                                      ),
                                      addLabel: 'Add fallback',
                                      emptyLabel: 'No fallback fonts',
                                      controllers: _fallbackControllers,
                                      fieldKeyPrefix: 'profile-editor-fallback',
                                      compactRows: true,
                                      maxEntries:
                                          maxTerminalFontFallbackFamilies,
                                      limitEntryLabel: 'fallback fonts',
                                      onAdd: _addFallback,
                                      onRemove: _removeFallback,
                                      onMoveUp: (index) =>
                                          _moveFallback(index, index - 1),
                                      onMoveDown: (index) =>
                                          _moveFallback(index, index + 1),
                                    ),
                                    SizedBox(height: theme.spacing.xxl),
                                    _ProfileResponsiveFieldPair(
                                      first: _ProfileLabeledControl(
                                        label: context.l10n.fontSize,
                                        child: TextFormField(
                                          key: const Key(
                                            'profile-editor-font-size',
                                          ),
                                          controller: _fontSizeController,
                                          focusNode: _fontSizeFocusNode,
                                          decoration: _profileFieldDecoration(),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          validator: (value) =>
                                              _positiveDoubleError(
                                                value ?? '',
                                                context.l10n.fontSize,
                                              ),
                                        ),
                                      ),
                                      second: _ProfileLabeledControl(
                                        label: context.l10n.lineHeight,
                                        child: TextFormField(
                                          key: const Key(
                                            'profile-editor-font-line-height',
                                          ),
                                          controller: _lineHeightController,
                                          focusNode: _lineHeightFocusNode,
                                          decoration: _profileFieldDecoration(),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          validator: (value) =>
                                              _positiveDoubleError(
                                                value ?? '',
                                                context.l10n.lineHeight,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                _ProfileFormGroup(
                                  key: const Key('profile-editor-group-colors'),
                                  title: context.l10n.colors,
                                  tone: AppPanelTone.elevated,
                                  children: [
                                    _buildThemePresetSection(),
                                    const SizedBox(height: 16),
                                    _buildColorGroupSection(
                                      title: context.l10n.specialColors,
                                      description:
                                          'Foreground, background, cursor, selection, and tab.',
                                      specs: _specialColorFieldSpecs,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildColorGroupSection(
                                      title: context.l10n.ansiNormal,
                                      description:
                                          'Standard ANSI 0-7 terminal colors.',
                                      specs: _normalAnsiColorFieldSpecs,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildColorGroupSection(
                                      title: context.l10n.ansiBright,
                                      description:
                                          'Bright ANSI 8-15 terminal colors.',
                                      specs: _brightAnsiColorFieldSpecs,
                                    ),
                                  ],
                                ),
                                _ProfileFormGroup(
                                  key: const Key('profile-editor-group-cursor'),
                                  title: context.l10n.cursor,
                                  tone: AppPanelTone.elevated,
                                  children: [
                                    _ProfileLabeledControl(
                                      label: context.l10n.cursorShape,
                                      child:
                                          AppDropdownFormField<
                                            TerminalCursorShape
                                          >(
                                            key: const Key(
                                              'profile-editor-cursor-shape',
                                            ),
                                            initialValue: _cursorShape,
                                            isExpanded: true,
                                            iconSize: 18,
                                            itemHeight: _dropdownItemHeight,
                                            menuMaxHeight: 240,
                                            borderRadius: BorderRadius.circular(
                                              theme.radius.md,
                                            ),
                                            decoration:
                                                _profileFieldDecoration(),
                                            items: TerminalCursorShape.values
                                                .map(
                                                  (value) =>
                                                      DropdownMenuItem<
                                                        TerminalCursorShape
                                                      >(
                                                        value: value,
                                                        child: Text(
                                                          terminalCursorShapeLabel(
                                                            value,
                                                          ),
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
                                    ),
                                    SizedBox(height: theme.spacing.xl),
                                    ToggleSettingRow(
                                      key: const Key(
                                        'profile-editor-cursor-blink',
                                      ),
                                      label: context.l10n.blinkCursor,
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
                          ),
                        ),
                        Offstage(
                          offstage:
                              _activeSection != _ProfileEditorSection.keys,
                          child: KeyedSubtree(
                            key: const Key('profile-editor-section-keys'),
                            child: KeyedSubtree(
                              key: const Key(
                                'profile-editor-section-interaction',
                              ),
                              child: SettingsSection(
                                anchorKey: _keysSectionKey,
                                title: context.l10n.keys,
                                description:
                                    context.l10n.keysProfileDescription,
                                children: [
                                  _ProfileFormGroup(
                                    key: const Key(
                                      'profile-editor-group-selection',
                                    ),
                                    title: context.l10n.selection,
                                    children: [
                                      ToggleSettingRow(
                                        key: const Key(
                                          'profile-editor-copy-on-select',
                                        ),
                                        label: context.l10n.copyOnSelect,
                                        value: _copyOnSelect,
                                        onChanged: (value) {
                                          setState(() {
                                            _didEdit = true;
                                            _copyOnSelect = value;
                                          });
                                        },
                                      ),
                                      Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: theme.spacing.lg,
                                        ),
                                        child: Divider(
                                          height: 1,
                                          color: theme.border,
                                        ),
                                      ),
                                      Text(
                                        context.l10n.optionDragMode,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      SizedBox(height: theme.spacing.md),
                                      _buildOptionDragModeField(),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Offstage(
                          offstage:
                              _activeSection !=
                              _ProfileEditorSection.automation,
                          child: KeyedSubtree(
                            key: const Key('profile-editor-section-automation'),
                            child: SettingsSection(
                              anchorKey: _automationSectionKey,
                              title: context.l10n.automation,
                              description:
                                  context.l10n.automationProfileDescription,
                              children: [
                                _ProfileFormGroup(
                                  key: const Key(
                                    'profile-editor-group-automation-rules',
                                  ),
                                  title: context.l10n.rules,
                                  children: [
                                    _ProfileRuleEditor(
                                      fieldKey: const Key(
                                        'profile-editor-triggers',
                                      ),
                                      label: context.l10n.triggers,
                                      helperText: context.l10n.triggerExamples,
                                      controller: _triggersController,
                                      focusNode: _triggersFocusNode,
                                      validator: (value) =>
                                          _triggerLinesError(value ?? ''),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: theme.spacing.xl,
                                      ),
                                      child: Divider(
                                        height: 1,
                                        color: theme.border,
                                      ),
                                    ),
                                    _ProfileRuleEditor(
                                      fieldKey: const Key(
                                        'profile-editor-switch-rules',
                                      ),
                                      label: context
                                          .l10n
                                          .automaticProfileSwitching,
                                      helperText: context
                                          .l10n
                                          .automaticProfileSwitchingHelp,
                                      controller: _switchRulesController,
                                      focusNode: _switchRulesFocusNode,
                                      validator: (value) =>
                                          _switchRuleLinesError(value ?? ''),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        Offstage(
                          offstage:
                              _activeSection != _ProfileEditorSection.advanced,
                          child: KeyedSubtree(
                            key: const Key('profile-editor-section-advanced'),
                            child: SettingsSection(
                              anchorKey: _advancedSectionKey,
                              title: context.l10n.advanced,
                              description:
                                  context.l10n.advancedProfileDescription,
                              children: [
                                _ProfileFormGroup(
                                  key: const Key(
                                    'profile-editor-group-integration',
                                  ),
                                  title: context.l10n.integration,
                                  children: [
                                    ToggleSettingRow(
                                      key: const Key(
                                        'profile-editor-shell-integration',
                                      ),
                                      label: context.l10n.shellIntegration,
                                      description: context
                                          .l10n
                                          .shellIntegrationDescription,
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
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                if (showSideNavigation) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.chrome.withValues(alpha: 0.34),
                          border: Border(
                            right: BorderSide(color: theme.border),
                          ),
                        ),
                        child: SizedBox(
                          width: sideNavigationWidth,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: theme.spacing.xl,
                              vertical: theme.spacing.xxl,
                            ),
                            child: sectionNavigation,
                          ),
                        ),
                      ),
                      Expanded(child: scrollableSections),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        left: theme.spacing.xl,
                        top: theme.spacing.xl,
                        right: theme.spacing.xl,
                      ),
                      child: sectionNavigation,
                    ),
                    Expanded(child: scrollableSections),
                  ],
                );
              },
            ),
          ),
          footer: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppActionButton(
                buttonKey: const Key('profile-editor-cancel'),
                tone: AppActionTone.secondary,
                label: context.l10n.cancel,
                onPressed: () => unawaited(_closeWithResult(null)),
              ),
              SizedBox(width: theme.spacing.sm),
              AppActionButton(
                buttonKey: const Key('profile-editor-save'),
                icon: Icons.save_outlined,
                label: context.l10n.save,
                onPressed:
                    _hasColorErrors || (!_didEdit && !widget.saveWhenPristine)
                    ? null
                    : () => unawaited(_save()),
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
    bool compactRows = false,
    required int maxEntries,
    required String limitEntryLabel,
    required VoidCallback onAdd,
    required void Function(int index) onRemove,
    required void Function(int index) onMoveUp,
    required void Function(int index) onMoveDown,
  }) {
    final theme = context.appTheme;
    final canAdd = controllers.length < maxEntries;
    final rows = <Widget>[];
    for (var index = 0; index < controllers.length; index += 1) {
      rows.add(
        _buildStringListRow(
          title: title,
          controller: controllers[index],
          allControllers: controllers,
          fieldKeyPrefix: fieldKeyPrefix,
          index: index,
          itemCount: controllers.length,
          compact: compactRows,
          maxEntries: maxEntries,
          limitEntryLabel: limitEntryLabel,
          onRemove: onRemove,
          onMoveUp: onMoveUp,
          onMoveDown: onMoveDown,
        ),
      );
      if (compactRows && index != controllers.length - 1) {
        rows.add(Divider(height: 1, color: theme.border));
      }
    }

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
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            AppActionButton(
              buttonKey: addKey,
              tone: AppActionTone.ghost,
              size: AppActionSize.compact,
              icon: Icons.add,
              label: addLabel,
              tooltip: addLabel,
              onPressed: canAdd ? onAdd : null,
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
        if (controllers.isNotEmpty && compactRows)
          Padding(
            padding: EdgeInsets.only(top: theme.spacing.md),
            child: SizedBox(
              width: double.infinity,
              child: AppPanel(
                tone: AppPanelTone.terminal,
                padding: EdgeInsets.zero,
                borderRadius: BorderRadius.circular(theme.radius.md),
                border: Border.all(
                  color: theme.borderStrong.withValues(alpha: 0.72),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(theme.radius.md),
                  child: Column(children: rows),
                ),
              ),
            ),
          )
        else if (controllers.isNotEmpty)
          ...rows,
      ],
    );
  }

  Widget _buildStringListRow({
    required String title,
    required TextEditingController controller,
    required List<TextEditingController> allControllers,
    required String fieldKeyPrefix,
    required int index,
    required int itemCount,
    required bool compact,
    required int maxEntries,
    required String limitEntryLabel,
    required void Function(int index) onRemove,
    required void Function(int index) onMoveUp,
    required void Function(int index) onMoveDown,
  }) {
    final theme = context.appTheme;
    final row = Row(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Semantics(
            textField: true,
            label: '$title ${index + 1}',
            child: TextFormField(
              key: Key('$fieldKeyPrefix-$index'),
              controller: controller,
              decoration: compact
                  ? _integratedRowDecoration(hintText: '$title ${index + 1}')
                  : InputDecoration(labelText: '$title ${index + 1}'),
              validator: (_) => index == 0
                  ? _stringListLimitError(
                      controllers: allControllers,
                      maxEntries: maxEntries,
                      entryLabel: limitEntryLabel,
                    )
                  : null,
            ),
          ),
        ),
        if (compact) ...[
          SizedBox(width: theme.spacing.sm),
          Container(width: 1, height: 24, color: theme.border),
          SizedBox(width: theme.spacing.sm),
        ] else
          SizedBox(width: theme.spacing.sm),
        _buildListActionButton(
          buttonKey: Key('$fieldKeyPrefix-$index-up'),
          tooltip: context.l10n.moveUp,
          onPressed: index == 0 ? null : () => onMoveUp(index),
          icon: Icons.arrow_upward,
        ),
        _buildListActionButton(
          buttonKey: Key('$fieldKeyPrefix-$index-down'),
          tooltip: context.l10n.moveDown,
          onPressed: index == itemCount - 1 ? null : () => onMoveDown(index),
          icon: Icons.arrow_downward,
        ),
        _buildListActionButton(
          buttonKey: Key('$fieldKeyPrefix-$index-remove'),
          tooltip: context.l10n.remove,
          onPressed: () => onRemove(index),
          icon: Icons.delete_outline,
        ),
      ],
    );

    if (compact) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: EdgeInsets.only(right: theme.spacing.sm),
          child: row,
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: theme.spacing.sm),
      child: row,
    );
  }

  InputDecoration _profileFieldDecoration({String? hintText}) {
    final theme = context.appTheme;
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(theme.radius.lg),
      borderSide: BorderSide(color: theme.borderStrong.withValues(alpha: 0.72)),
    );
    return InputDecoration(
      hintText: hintText,
      isDense: false,
      filled: true,
      fillColor: theme.terminalSurface.withValues(alpha: 0.92),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: BorderSide(color: theme.focusRing, width: 1.6),
      ),
      errorBorder: outline.copyWith(
        borderSide: BorderSide(color: theme.danger),
      ),
      focusedErrorBorder: outline.copyWith(
        borderSide: BorderSide(color: theme.danger, width: 1.6),
      ),
      constraints: const BoxConstraints(minHeight: 64),
      contentPadding: EdgeInsets.symmetric(
        horizontal: theme.spacing.xl,
        vertical: theme.spacing.xl,
      ),
    );
  }

  InputDecoration _integratedRowDecoration({required String hintText}) {
    final theme = context.appTheme;
    final focusBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(theme.radius.md),
      borderSide: BorderSide(color: theme.focusRing, width: 1.5),
    );
    return InputDecoration(
      hintText: hintText,
      isDense: false,
      filled: false,
      fillColor: Colors.transparent,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      focusedBorder: focusBorder,
      errorBorder: focusBorder.copyWith(
        borderSide: BorderSide(color: theme.danger),
      ),
      focusedErrorBorder: focusBorder.copyWith(
        borderSide: BorderSide(color: theme.danger, width: 1.5),
      ),
      constraints: const BoxConstraints(minHeight: 48),
      contentPadding: EdgeInsets.symmetric(
        horizontal: theme.spacing.xl,
        vertical: theme.spacing.md,
      ),
    );
  }

  Widget _buildEnvEditor() {
    final theme = context.appTheme;
    final canAdd = _envControllers.length < maxTerminalEnvironmentEntries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.environmentVariables,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            AppActionButton(
              buttonKey: const Key('profile-editor-add-env'),
              tone: AppActionTone.ghost,
              size: AppActionSize.compact,
              icon: Icons.add,
              label: context.l10n.addVariable,
              tooltip: context.l10n.addVariable,
              onPressed: canAdd ? _addEnv : null,
            ),
          ],
        ),
        if (_envControllers.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: theme.spacing.xs + 1),
            child: Text(
              context.l10n.noEnvironmentVariables,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
            ),
          ),
        if (_envControllers.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: theme.spacing.md),
            child: SizedBox(
              width: double.infinity,
              child: AppPanel(
                tone: AppPanelTone.terminal,
                padding: EdgeInsets.zero,
                borderRadius: BorderRadius.circular(theme.radius.md),
                border: Border.all(
                  color: theme.borderStrong.withValues(alpha: 0.72),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        theme.spacing.md,
                        theme.spacing.sm,
                        theme.spacing.sm,
                        theme.spacing.xs,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.l10n.key,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: theme.textMuted),
                            ),
                          ),
                          SizedBox(width: theme.spacing.md),
                          Expanded(
                            child: Text(
                              context.l10n.value,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: theme.textMuted),
                            ),
                          ),
                          SizedBox(
                            width: theme.controls.dense + theme.spacing.sm,
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: theme.border),
                    for (
                      var index = 0;
                      index < _envControllers.length;
                      index += 1
                    ) ...[
                      Padding(
                        padding: EdgeInsets.only(right: theme.spacing.sm),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Semantics(
                                textField: true,
                                label: context.l10n.environmentVariableKey(
                                  index + 1,
                                ),
                                child: TextFormField(
                                  key: Key('profile-editor-env-key-$index'),
                                  controller:
                                      _envControllers[index].keyController,
                                  focusNode:
                                      _envControllers[index].keyFocusNode,
                                  decoration: _integratedRowDecoration(
                                    hintText: context.l10n.variableName,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                  validator: (_) => _envKeyError(index),
                                ),
                              ),
                            ),
                            SizedBox(width: theme.spacing.md),
                            Expanded(
                              child: Semantics(
                                textField: true,
                                label: context.l10n.environmentVariableValue(
                                  index + 1,
                                ),
                                child: TextFormField(
                                  key: Key('profile-editor-env-value-$index'),
                                  controller:
                                      _envControllers[index].valueController,
                                  decoration: _integratedRowDecoration(
                                    hintText: context.l10n.value,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: theme.spacing.sm),
                            _buildListActionButton(
                              buttonKey: Key(
                                'profile-editor-env-remove-$index',
                              ),
                              tooltip: context.l10n.removeVariable,
                              onPressed: () => _removeEnv(index),
                              icon: Icons.delete_outline,
                            ),
                          ],
                        ),
                      ),
                      if (index != _envControllers.length - 1)
                        Divider(height: 1, color: theme.border),
                    ],
                  ],
                ),
              ),
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
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        SizedBox(height: theme.spacing.xs + 1),
        Text(
          description,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
        ),
        for (var index = 0; index < specs.length; index += 1) ...[
          if (index == 0)
            SizedBox(height: theme.spacing.md)
          else
            Padding(
              padding: EdgeInsets.symmetric(vertical: theme.spacing.xs),
              child: Divider(height: 1, color: theme.border),
            ),
          _buildColorField(specs[index]),
        ],
      ],
    );
  }

  Widget _buildColorField(_ColorFieldSpec spec) {
    final controller = _colorControllerForSpec(spec);
    return ColorSettingRow(
      label: context.l10n.profileColorName('${spec.group}_${spec.slot}'),
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
    final colorScheme = Theme.of(context).colorScheme;
    final selectedPreset = _selectedThemePreset;

    return Column(
      key: const Key('profile-editor-theme-presets'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.themePresets,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        SizedBox(height: theme.spacing.xs + 1),
        Text(
          context.l10n.themePresetsDescription,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
        ),
        SizedBox(height: theme.spacing.sm + 1),
        _FollowAppThemeColorChoice(
          key: const Key('profile-editor-theme-preset-follow-app'),
          selected: _usesAppThemeColors,
          previewColors: [
            colorScheme.surfaceContainerLowest,
            colorScheme.onSurface,
            colorScheme.primary,
            colorScheme.secondary,
            colorScheme.tertiary,
            colorScheme.onSurfaceVariant,
          ],
          onPressed: _followAppThemeColors,
        ),
        SizedBox(height: theme.spacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final columnCount = constraints.maxWidth >= 640
                ? 3
                : constraints.maxWidth >= 420
                ? 2
                : 1;
            final cardWidth =
                (constraints.maxWidth - theme.spacing.sm * (columnCount - 1)) /
                columnCount;
            return Wrap(
              spacing: theme.spacing.sm,
              runSpacing: theme.spacing.sm,
              children: [
                for (final preset in terminalThemePresets)
                  SizedBox(
                    width: cardWidth,
                    child: _TerminalThemePresetButton(
                      key: Key('profile-editor-theme-preset-${preset.id}'),
                      preset: preset,
                      selected: selectedPreset?.id == preset.id,
                      onPressed: () => _applyThemePreset(preset),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildOptionDragModeField() {
    final theme = context.appTheme;
    const modes = TerminalOptionDragMode.values;
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
          for (final (index, mode) in modes.indexed) ...[
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 48),
              padding: EdgeInsets.symmetric(
                horizontal: theme.spacing.lg,
                vertical: theme.spacing.xs,
              ),
              decoration: BoxDecoration(
                color: _optionDragMode == mode
                    ? theme.selected.withValues(alpha: 0.48)
                    : theme.chrome,
                borderRadius: BorderRadius.circular(theme.radius.lg),
                border: Border.all(
                  color: _optionDragMode == mode
                      ? theme.focusRing
                      : theme.border,
                  width: _optionDragMode == mode ? 1.5 : 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: AppCompactRadioTile<TerminalOptionDragMode>(
                  tileKey: Key('profile-editor-option-drag-${mode.name}'),
                  value: mode,
                  title: Text(terminalOptionDragModeLabel(mode)),
                ),
              ),
            ),
            if (index != modes.length - 1) SizedBox(height: theme.spacing.sm),
          ],
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
    this.tone = AppPanelTone.overlay,
    required this.children,
  });

  final String title;
  final AppPanelTone tone;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: theme.spacing.xl),
      child: SizedBox(
        width: double.infinity,
        child: AppPanel(
          tone: tone,
          padding: EdgeInsets.all(theme.spacing.xxl + theme.spacing.xs),
          borderRadius: BorderRadius.circular(theme.radius.xl),
          border: Border.all(color: theme.border),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  color: theme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: theme.spacing.xl),
              Divider(height: 1, color: theme.border),
              SizedBox(height: theme.spacing.xxl),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileLabeledControl extends StatelessWidget {
  const _ProfileLabeledControl({
    required this.label,
    this.helperText,
    required this.child,
  });

  final String label;
  final String? helperText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.bodyMedium?.copyWith(
            color: theme.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: theme.spacing.xl),
        Semantics(label: label, child: child),
        if (helperText != null) ...[
          SizedBox(height: theme.spacing.md),
          Text(
            helperText!,
            style: textTheme.bodySmall?.copyWith(color: theme.textSubtle),
          ),
        ],
      ],
    );
  }
}

class _ProfileResponsiveFieldPair extends StatelessWidget {
  const _ProfileResponsiveFieldPair({
    required this.first,
    required this.second,
  });

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              SizedBox(height: theme.spacing.xxl),
              second,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            SizedBox(width: theme.spacing.xxl),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _ProfileRuleEditor extends StatelessWidget {
  const _ProfileRuleEditor({
    required this.fieldKey,
    required this.label,
    required this.helperText,
    required this.controller,
    required this.focusNode,
    required this.validator,
  });

  final Key fieldKey;
  final String label;
  final String helperText;
  final TextEditingController controller;
  final FocusNode focusNode;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.titleSmall?.copyWith(
            color: theme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: theme.spacing.sm),
        Semantics(
          textField: true,
          label: label,
          child: TextFormField(
            key: fieldKey,
            controller: controller,
            focusNode: focusNode,
            minLines: 4,
            maxLines: 6,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
            decoration: const InputDecoration(),
            validator: validator,
            onTapOutside: (_) => focusNode.unfocus(),
          ),
        ),
        SizedBox(height: theme.spacing.sm),
        Text(
          helperText,
          style: textTheme.bodySmall?.copyWith(color: theme.textSubtle),
        ),
      ],
    );
  }
}

class _ProfileEditorSectionNavItem extends StatelessWidget {
  const _ProfileEditorSectionNavItem({
    super.key,
    required this.spec,
    required this.selected,
    required this.dirty,
    required this.vertical,
    required this.focusNode,
    required this.focusOrder,
    required this.onReset,
    required this.onTap,
  });

  final _ProfileEditorSectionSpec spec;
  final bool selected;
  final bool dirty;
  final bool vertical;
  final FocusNode? focusNode;
  final double focusOrder;
  final VoidCallback onReset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final sectionLabel = context.l10n.profileSectionName(spec.section.name);
    final foreground = selected ? theme.textPrimary : theme.textMuted;
    final background = selected
        ? theme.selected.withValues(alpha: 0.86)
        : theme.chrome.withValues(alpha: 0);
    final borderColor = selected
        ? theme.focusRing.withValues(alpha: 0.72)
        : Colors.transparent;
    final content = Row(
      mainAxisSize: vertical ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (vertical) ...[
          Container(
            width: 3,
            height: 26,
            decoration: BoxDecoration(
              color: borderColor,
              borderRadius: BorderRadius.circular(theme.radius.sm),
            ),
          ),
          SizedBox(width: theme.spacing.sm),
        ],
        Icon(spec.icon, size: 18, color: foreground),
        SizedBox(width: theme.spacing.sm),
        Flexible(
          child: Text(
            sectionLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: foreground,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
        if (dirty) ...[
          SizedBox(width: theme.spacing.xs),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: theme.warning,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: theme.spacing.xs),
          AppActionButton(
            buttonKey: Key('profile-editor-reset-${spec.section.name}'),
            tooltip: context.l10n.resetProfileSection(sectionLabel),
            icon: Icons.restore,
            tone: AppActionTone.ghost,
            size: AppActionSize.dense,
            onPressed: onReset,
          ),
        ],
      ],
    );

    return FocusTraversalOrder(
      order: NumericFocusOrder(focusOrder),
      child: Semantics(
        identifier: 'profile-editor-nav-${spec.section.name}',
        button: true,
        selected: selected,
        label: context.l10n.profileSectionSemantics(
          sectionLabel,
          dirty.toString(),
        ),
        onTap: onTap,
        excludeSemantics: true,
        child: Tooltip(
          message: sectionLabel,
          child: Padding(
            padding: EdgeInsets.only(
              right: vertical ? 0 : theme.spacing.xs,
              bottom: vertical ? theme.spacing.sm : 0,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                focusNode: focusNode,
                borderRadius: BorderRadius.circular(theme.radius.lg),
                onTap: onTap,
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  constraints: BoxConstraints(
                    minHeight: context.adaptiveControlHeight(44),
                    minWidth: vertical ? 0 : 118,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: theme.spacing.lg,
                    vertical: vertical
                        ? theme.spacing.xs
                        : theme.spacing.sm + 1,
                  ),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(theme.radius.lg),
                    border: Border.all(color: borderColor),
                  ),
                  child: content,
                ),
              ),
            ),
          ),
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

class _FollowAppThemeColorChoice extends StatelessWidget {
  const _FollowAppThemeColorChoice({
    super.key,
    required this.selected,
    required this.previewColors,
    required this.onPressed,
  });

  final bool selected;
  final List<Color> previewColors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: context.l10n.followApplicationThemeColors,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(theme.radius.lg),
          onTap: onPressed,
          child: Ink(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: theme.spacing.lg,
              vertical: theme.spacing.md,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? theme.selected.withValues(alpha: 0.52)
                  : theme.chrome,
              borderRadius: BorderRadius.circular(theme.radius.lg),
              border: Border.all(
                color: selected ? theme.focusRing : theme.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showPreview = constraints.maxWidth >= 520;
                return Row(
                  children: [
                    Icon(
                      Icons.brightness_auto_rounded,
                      size: 20,
                      color: selected ? theme.focus : theme.textMuted,
                    ),
                    SizedBox(width: theme.spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.followAppTheme,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: theme.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          SizedBox(height: theme.spacing.xs),
                          Text(
                            context.l10n.followAppThemeDescription,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: theme.textSubtle),
                          ),
                        ],
                      ),
                    ),
                    if (showPreview) ...[
                      SizedBox(width: theme.spacing.md),
                      Wrap(
                        spacing: theme.spacing.xs,
                        children: [
                          for (final color in previewColors)
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(
                                  theme.radius.sm,
                                ),
                                border: Border.all(color: theme.borderStrong),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (selected) ...[
                      SizedBox(width: theme.spacing.md),
                      Icon(
                        Icons.check_circle_rounded,
                        key: const Key(
                          'profile-editor-theme-preset-selected-follow-app',
                        ),
                        size: 18,
                        color: theme.focus,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
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
      fontWeight: FontWeight.w600,
    );
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
            width: double.infinity,
            padding: EdgeInsets.all(theme.spacing.md),
            decoration: BoxDecoration(
              color: selected ? theme.panelElevated : theme.chrome,
              borderRadius: BorderRadius.circular(theme.radius.lg),
              border: Border.all(
                color: selected ? theme.focusRing : theme.border,
                width: selected ? 1.5 : 1,
              ),
              boxShadow: const [],
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
                SizedBox(height: theme.spacing.xs),
                Text(
                  preset.tone.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: toneColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: theme.spacing.sm),
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
        _hexError = context.l10n.hexColorValidation;
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
        _hexError = context.l10n.hexColorValidation;
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
      title: context.l10n.pickColor,
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
                          ? context.l10n.inheritingDefaultTerminalColor
                          : context.l10n.currentColorValue(previewHex),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
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
              FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
            ],
            decoration: InputDecoration(
              hintText: context.l10n.hexColorOrEmpty,
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
                    context.l10n.hex,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w600,
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
                              context.l10n.hex,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: theme.textPrimary,
                                    fontWeight: FontWeight.w600,
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
                  context.l10n.palette,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w600,
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
                  context.l10n.hue,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w600,
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
            label: context.l10n.resetToDefault,
            onPressed: () {
              Navigator.of(
                context,
              ).pop(const _ColorPickerResult(applied: true, hexValue: null));
            },
          ),
          AppActionButton(
            buttonKey: const Key('color-picker-cancel'),
            tone: AppActionTone.secondary,
            label: context.l10n.cancel,
            onPressed: () {
              Navigator.of(
                context,
              ).pop(const _ColorPickerResult(applied: false));
            },
          ),
          AppActionButton(
            buttonKey: const Key('color-picker-apply'),
            icon: Icons.check_rounded,
            label: context.l10n.apply,
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
