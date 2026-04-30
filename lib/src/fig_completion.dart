import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum FigCompletionSuggestionSource { spec, template, generator }

class FigCompletionCommandRef {
  const FigCompletionCommandRef({
    required this.name,
    required this.specPath,
    this.aliases = const <String>[],
    this.description = '',
  });

  factory FigCompletionCommandRef.fromJson(Object? json) {
    final map = _objectMap(json);
    return FigCompletionCommandRef(
      name: _stringOrNull(map?['name']) ?? '',
      specPath: _stringOrNull(map?['spec']) ?? '',
      aliases: _stringList(map?['aliases']),
      description: _stringOrNull(map?['description']) ?? '',
    );
  }

  final String name;
  final String specPath;
  final List<String> aliases;
  final String description;
}

class FigCompletionIndex {
  const FigCompletionIndex({this.commands = const <FigCompletionCommandRef>[]});

  factory FigCompletionIndex.fromJson(Object? json) {
    final map = _objectMap(json);
    return FigCompletionIndex(
      commands: _objectList(
        map?['commands'],
      ).map(FigCompletionCommandRef.fromJson).toList(growable: false),
    );
  }

  final List<FigCompletionCommandRef> commands;
}

class FigCompletionSuggestion {
  const FigCompletionSuggestion({
    required this.name,
    this.insertValue,
    this.description = '',
    this.source = FigCompletionSuggestionSource.spec,
  });

  factory FigCompletionSuggestion.fromJson(Object? json) {
    if (json is String) {
      return FigCompletionSuggestion(name: json);
    }
    final map = _objectMap(json);
    return FigCompletionSuggestion(
      name: _stringOrNull(map?['name']) ?? '',
      insertValue: _stringOrNull(map?['insertValue']),
      description: _stringOrNull(map?['description']) ?? '',
    );
  }

  final String name;
  final String? insertValue;
  final String description;
  final FigCompletionSuggestionSource source;

  String get replacement => insertValue ?? name;

  FigCompletionSuggestion copyWith({
    FigCompletionSuggestionSource? source,
    String? name,
    String? insertValue,
    String? description,
  }) {
    return FigCompletionSuggestion(
      name: name ?? this.name,
      insertValue: insertValue ?? this.insertValue,
      description: description ?? this.description,
      source: source ?? this.source,
    );
  }
}

class FigCompletionGenerator {
  const FigCompletionGenerator({required this.script, this.splitOn = '\n'});

  factory FigCompletionGenerator.fromJson(Object? json) {
    final map = _objectMap(json);
    return FigCompletionGenerator(
      script: _stringOrNull(map?['script']) ?? '',
      splitOn: _stringOrNull(map?['splitOn']) ?? '\n',
    );
  }

  final String script;
  final String splitOn;
}

class FigCompletionArg {
  const FigCompletionArg({
    required this.name,
    this.description = '',
    this.suggestions = const <FigCompletionSuggestion>[],
    this.templates = const <String>[],
    this.generators = const <FigCompletionGenerator>[],
    this.isOptional = false,
    this.isVariadic = false,
  });

  factory FigCompletionArg.fromJson(Object? json) {
    final map = _objectMap(json);
    return FigCompletionArg(
      name: _stringOrNull(map?['name']) ?? '',
      description: _stringOrNull(map?['description']) ?? '',
      suggestions: _objectList(
        map?['suggestions'],
      ).map(FigCompletionSuggestion.fromJson).toList(growable: false),
      templates: _stringList(map?['templates']),
      generators: _objectList(
        map?['generators'],
      ).map(FigCompletionGenerator.fromJson).toList(growable: false),
      isOptional: map?['isOptional'] == true,
      isVariadic: map?['isVariadic'] == true,
    );
  }

  final String name;
  final String description;
  final List<FigCompletionSuggestion> suggestions;
  final List<String> templates;
  final List<FigCompletionGenerator> generators;
  final bool isOptional;
  final bool isVariadic;
}

class FigCompletionOption {
  const FigCompletionOption({
    required this.names,
    this.description = '',
    this.args = const <FigCompletionArg>[],
  });

  factory FigCompletionOption.fromJson(Object? json) {
    final map = _objectMap(json);
    return FigCompletionOption(
      names: _stringList(map?['name']),
      description: _stringOrNull(map?['description']) ?? '',
      args: _objectList(
        map?['args'],
      ).map(FigCompletionArg.fromJson).toList(growable: false),
    );
  }

  final List<String> names;
  final String description;
  final List<FigCompletionArg> args;
}

class FigCompletionCommand {
  const FigCompletionCommand({
    required this.names,
    this.description = '',
    this.subcommands = const <FigCompletionCommand>[],
    this.options = const <FigCompletionOption>[],
    this.args = const <FigCompletionArg>[],
  });

  factory FigCompletionCommand.fromJson(Object? json) {
    final map = _objectMap(json);
    return FigCompletionCommand(
      names: _stringList(map?['name']),
      description: _stringOrNull(map?['description']) ?? '',
      subcommands: _objectList(
        map?['subcommands'],
      ).map(FigCompletionCommand.fromJson).toList(growable: false),
      options: _objectList(
        map?['options'],
      ).map(FigCompletionOption.fromJson).toList(growable: false),
      args: _objectList(
        map?['args'],
      ).map(FigCompletionArg.fromJson).toList(growable: false),
    );
  }

  final List<String> names;
  final String description;
  final List<FigCompletionCommand> subcommands;
  final List<FigCompletionOption> options;
  final List<FigCompletionArg> args;
}

class FigCompletionSpec extends FigCompletionCommand {
  const FigCompletionSpec({
    required super.names,
    super.description,
    super.subcommands,
    super.options,
    super.args,
  });

  factory FigCompletionSpec.fromJson(Object? json) {
    final command = FigCompletionCommand.fromJson(json);
    return FigCompletionSpec(
      names: command.names,
      description: command.description,
      subcommands: command.subcommands,
      options: command.options,
      args: command.args,
    );
  }
}

class FigCompletionRepository {
  FigCompletionRepository._({
    FigCompletionIndex? index,
    Map<String, FigCompletionSpec>? specs,
    AssetBundle? bundle,
    String assetRoot = 'assets/fig_specs',
  }) : _index = index,
       _specs = specs ?? <String, FigCompletionSpec>{},
       _bundle = bundle,
       _assetRoot = assetRoot;

  factory FigCompletionRepository.memory({
    required FigCompletionIndex index,
    required Map<String, FigCompletionSpec> specs,
  }) {
    return FigCompletionRepository._(index: index, specs: specs);
  }

  factory FigCompletionRepository.assets({
    AssetBundle? bundle,
    String assetRoot = 'assets/fig_specs',
  }) {
    return FigCompletionRepository._(
      bundle: bundle ?? rootBundle,
      assetRoot: assetRoot,
    );
  }

  factory FigCompletionRepository.empty() {
    return FigCompletionRepository.memory(
      index: const FigCompletionIndex(),
      specs: const <String, FigCompletionSpec>{},
    );
  }

  FigCompletionIndex? _index;
  final Map<String, FigCompletionSpec> _specs;
  final AssetBundle? _bundle;
  final String _assetRoot;
  Future<void>? _loadFuture;

  Future<FigCompletionIndex> index() async {
    await _ensureLoaded();
    return _index ?? const FigCompletionIndex();
  }

  Future<FigCompletionSpec?> specForCommand(String command) async {
    await _ensureLoaded();
    final ref = (_index ?? const FigCompletionIndex()).commands.where((entry) {
      return entry.name == command || entry.aliases.contains(command);
    }).firstOrNull;
    if (ref == null) {
      return null;
    }
    return specForPath(ref.specPath);
  }

  Future<FigCompletionSpec?> specForPath(String specPath) async {
    await _ensureLoaded();
    if (_specs.containsKey(specPath)) {
      return _specs[specPath];
    }
    final bundle = _bundle;
    if (bundle == null) {
      return null;
    }
    try {
      final json = jsonDecode(await bundle.loadString('$_assetRoot/$specPath'));
      final spec = FigCompletionSpec.fromJson(json);
      _specs[specPath] = spec;
      return spec;
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureLoaded() {
    return _loadFuture ??= _loadIndex();
  }

  Future<void> _loadIndex() async {
    if (_index != null) {
      return;
    }
    final bundle = _bundle;
    if (bundle == null) {
      _index = const FigCompletionIndex();
      return;
    }
    try {
      final json = jsonDecode(
        await bundle.loadString('$_assetRoot/index.json'),
      );
      _index = FigCompletionIndex.fromJson(json);
    } catch (_) {
      _index = const FigCompletionIndex();
    }
  }
}

class FigCompletionContext {
  const FigCompletionContext({
    required this.cwd,
    this.environment = const <String, String>{},
  });

  final String cwd;
  final Map<String, String> environment;
}

class FigCompletionInput {
  const FigCompletionInput({
    required this.tokens,
    required this.activeTokenIndex,
    required this.cursorOffset,
  });

  final List<FigCompletionToken> tokens;
  final int activeTokenIndex;
  final int cursorOffset;

  FigCompletionToken get activeToken {
    if (tokens.isEmpty) {
      return FigCompletionToken(
        text: '',
        start: cursorOffset,
        end: cursorOffset,
      );
    }
    return tokens[activeTokenIndex];
  }
}

class FigCompletionToken {
  const FigCompletionToken({
    required this.text,
    required this.start,
    required this.end,
  });

  final String text;
  final int start;
  final int end;
}

class FigCompletionResult {
  const FigCompletionResult({
    required this.suggestions,
    required this.replaceStart,
    required this.replaceEnd,
  });

  final List<FigCompletionSuggestion> suggestions;
  final int replaceStart;
  final int replaceEnd;
}

class FigCompletionEngine {
  FigCompletionEngine({required this.repository});

  final FigCompletionRepository repository;

  Future<FigCompletionResult> complete(
    TextEditingValue value, {
    required FigCompletionContext context,
  }) async {
    final input = parseFigCompletionInput(value);
    final activeToken = input.activeToken;
    final tokens = input.tokens;
    if (tokens.isEmpty || input.activeTokenIndex == 0) {
      return FigCompletionResult(
        suggestions: await _rootSuggestions(activeToken.text, context),
        replaceStart: activeToken.start,
        replaceEnd: activeToken.end,
      );
    }

    final commandName = tokens.first.text;
    final spec = await repository.specForCommand(commandName);
    if (spec == null) {
      return FigCompletionResult(
        suggestions: const <FigCompletionSuggestion>[],
        replaceStart: activeToken.start,
        replaceEnd: activeToken.end,
      );
    }

    final node = _nodeForTokens(spec, tokens, input.activeTokenIndex);
    final previousToken = input.activeTokenIndex > 0
        ? tokens[input.activeTokenIndex - 1]
        : null;
    final optionArg = previousToken == null
        ? null
        : _optionForName(node, previousToken.text)?.args.firstOrNull;
    final suggestions = optionArg != null
        ? await _argSuggestions(optionArg, activeToken.text, context)
        : await _nodeSuggestions(node, activeToken.text, context);

    return FigCompletionResult(
      suggestions: suggestions,
      replaceStart: activeToken.start,
      replaceEnd: activeToken.end,
    );
  }

  TextEditingValue accept(
    TextEditingValue value,
    FigCompletionResult result,
    FigCompletionSuggestion suggestion,
  ) {
    final replacement = suggestion.replacement;
    final nextText = value.text.replaceRange(
      result.replaceStart,
      result.replaceEnd,
      replacement,
    );
    final nextOffset = result.replaceStart + replacement.length;
    return value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
  }

  Future<List<FigCompletionSuggestion>> _rootSuggestions(
    String prefix,
    FigCompletionContext context,
  ) async {
    final index = await repository.index();
    final fromSpecs = index.commands.map((entry) {
      return FigCompletionSuggestion(
        name: entry.name,
        description: entry.description,
      );
    });
    final fromPath = _pathExecutables(context);
    return _matchingSuggestions(<FigCompletionSuggestion>[
      ...fromSpecs,
      ...fromPath,
    ], prefix);
  }

  FigCompletionCommand _nodeForTokens(
    FigCompletionSpec spec,
    List<FigCompletionToken> tokens,
    int activeTokenIndex,
  ) {
    FigCompletionCommand node = spec;
    for (var index = 1; index < activeTokenIndex; index += 1) {
      final token = tokens[index].text;
      final subcommand = _subcommandForName(node, token);
      if (subcommand != null) {
        node = subcommand;
      }
    }
    return node;
  }

  Future<List<FigCompletionSuggestion>> _nodeSuggestions(
    FigCompletionCommand node,
    String prefix,
    FigCompletionContext context,
  ) async {
    if (prefix.startsWith('-')) {
      final suggestions = <FigCompletionSuggestion>[];
      for (final option in node.options) {
        for (final name in option.names) {
          suggestions.add(
            FigCompletionSuggestion(
              name: name,
              description: option.description,
            ),
          );
        }
      }
      return _matchingSuggestions(suggestions, prefix);
    }

    final subcommands = <FigCompletionSuggestion>[
      for (final command in node.subcommands)
        for (final name in command.names)
          FigCompletionSuggestion(name: name, description: command.description),
    ];
    if (subcommands.isNotEmpty) {
      return _matchingSuggestions(subcommands, prefix);
    }
    final arg = node.args.firstOrNull;
    if (arg == null) {
      return const <FigCompletionSuggestion>[];
    }
    return _argSuggestions(arg, prefix, context);
  }

  Future<List<FigCompletionSuggestion>> _argSuggestions(
    FigCompletionArg arg,
    String prefix,
    FigCompletionContext context,
  ) async {
    final suggestions = <FigCompletionSuggestion>[
      for (final suggestion in arg.suggestions)
        suggestion.copyWith(source: FigCompletionSuggestionSource.spec),
      ..._templateSuggestions(arg.templates, prefix, context),
      ...await _generatorSuggestions(arg.generators, context),
    ];
    return _matchingSuggestions(suggestions, prefix);
  }

  FigCompletionCommand? _subcommandForName(
    FigCompletionCommand node,
    String name,
  ) {
    for (final subcommand in node.subcommands) {
      if (subcommand.names.contains(name)) {
        return subcommand;
      }
    }
    return null;
  }

  FigCompletionOption? _optionForName(FigCompletionCommand node, String name) {
    for (final option in node.options) {
      if (option.names.contains(name)) {
        return option;
      }
    }
    return null;
  }
}

class FigCompletionController extends ChangeNotifier {
  FigCompletionController({
    required FigCompletionEngine engine,
    required String initialCwd,
    Map<String, String> environment = const <String, String>{},
  }) : _engine = engine,
       _cwd = initialCwd,
       _environment = environment;

  final FigCompletionEngine _engine;
  final Map<String, String> _environment;
  String _cwd;
  FigCompletionResult? _activeResult;
  int _activeIndex = -1;
  bool _isOpen = false;

  String get cwd => _cwd;
  bool get isOpen => _isOpen;
  int get activeIndex => _activeIndex;
  List<FigCompletionSuggestion> get suggestions =>
      _activeResult?.suggestions ?? const <FigCompletionSuggestion>[];
  FigCompletionSuggestion? get activeSuggestion {
    if (_activeIndex < 0 || _activeIndex >= suggestions.length) {
      return null;
    }
    return suggestions[_activeIndex];
  }

  void updateCwd(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == _cwd) {
      return;
    }
    _cwd = trimmed;
    notifyListeners();
  }

  Future<TextEditingValue?> completeOrAccept(TextEditingValue value) async {
    if (_isOpen) {
      return acceptActive(value);
    }
    final result = await _engine.complete(
      value,
      context: FigCompletionContext(cwd: _cwd, environment: _environment),
    );
    if (result.suggestions.isEmpty) {
      close();
      return null;
    }
    if (result.suggestions.length == 1) {
      close();
      return _engine.accept(value, result, result.suggestions.single);
    }
    _activeResult = result;
    _activeIndex = 0;
    _isOpen = true;
    notifyListeners();
    return null;
  }

  TextEditingValue? acceptActive(TextEditingValue value) {
    final result = _activeResult;
    final suggestion = activeSuggestion;
    if (result == null || suggestion == null) {
      close();
      return null;
    }
    final next = _engine.accept(value, result, suggestion);
    close();
    return next;
  }

  void next() {
    if (!_isOpen || suggestions.isEmpty) {
      return;
    }
    _activeIndex = (_activeIndex + 1) % suggestions.length;
    notifyListeners();
  }

  void previous() {
    if (!_isOpen || suggestions.isEmpty) {
      return;
    }
    _activeIndex = _activeIndex <= 0
        ? suggestions.length - 1
        : _activeIndex - 1;
    notifyListeners();
  }

  void close() {
    if (!_isOpen && _activeResult == null && _activeIndex == -1) {
      return;
    }
    _isOpen = false;
    _activeResult = null;
    _activeIndex = -1;
    notifyListeners();
  }
}

FigCompletionInput parseFigCompletionInput(TextEditingValue value) {
  final text = value.text;
  final cursor = value.selection.isValid
      ? value.selection.extentOffset.clamp(0, text.length).toInt()
      : text.length;
  final tokens = <FigCompletionToken>[];
  final buffer = StringBuffer();
  var tokenStart = -1;
  var quote = '';
  var escaped = false;
  var activeTokenIndex = -1;

  void finishToken(int rawEnd) {
    if (tokenStart < 0) {
      return;
    }
    final token = FigCompletionToken(
      text: buffer.toString(),
      start: tokenStart,
      end: rawEnd,
    );
    tokens.add(token);
    if (cursor >= token.start && cursor <= token.end) {
      activeTokenIndex = tokens.length - 1;
    }
    buffer.clear();
    tokenStart = -1;
  }

  for (var index = 0; index < text.length; index += 1) {
    final char = text[index];
    if (escaped) {
      if (tokenStart < 0) {
        tokenStart = index;
      }
      buffer.write(char);
      escaped = false;
      continue;
    }
    if (char == r'\') {
      if (tokenStart < 0) {
        tokenStart = index;
      }
      escaped = true;
      continue;
    }
    if (quote.isNotEmpty) {
      if (char == quote) {
        quote = '';
      } else {
        buffer.write(char);
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      if (tokenStart < 0) {
        tokenStart = index + 1;
      }
      continue;
    }
    if (_isWhitespace(char)) {
      finishToken(index);
      if (cursor == index + 1) {
        activeTokenIndex = tokens.length;
      }
      continue;
    }
    if (tokenStart < 0) {
      tokenStart = index;
    }
    buffer.write(char);
  }
  finishToken(text.length);

  if (tokens.isEmpty || activeTokenIndex == tokens.length) {
    tokens.add(FigCompletionToken(text: '', start: cursor, end: cursor));
    activeTokenIndex = tokens.length - 1;
  } else if (activeTokenIndex < 0) {
    activeTokenIndex = tokens.length - 1;
  }

  return FigCompletionInput(
    tokens: tokens,
    activeTokenIndex: activeTokenIndex,
    cursorOffset: cursor,
  );
}

bool _isWhitespace(String value) => value.trim().isEmpty;

List<FigCompletionSuggestion> _matchingSuggestions(
  List<FigCompletionSuggestion> suggestions,
  String prefix,
) {
  final normalizedPrefix = prefix.toLowerCase();
  final seen = <String>{};
  final result = <FigCompletionSuggestion>[];
  for (final suggestion in suggestions) {
    if (suggestion.name.isEmpty) {
      continue;
    }
    if (normalizedPrefix.isNotEmpty &&
        !suggestion.name.toLowerCase().startsWith(normalizedPrefix)) {
      continue;
    }
    if (!seen.add(suggestion.name)) {
      continue;
    }
    result.add(suggestion);
  }
  result.sort((left, right) => left.name.compareTo(right.name));
  return result;
}

List<FigCompletionSuggestion> _pathExecutables(FigCompletionContext context) {
  final pathValue = context.environment['PATH'];
  if (pathValue == null || pathValue.isEmpty) {
    return const <FigCompletionSuggestion>[];
  }
  final suggestions = <FigCompletionSuggestion>[];
  for (final segment in pathValue.split(':')) {
    if (segment.isEmpty) {
      continue;
    }
    final dir = Directory(segment);
    if (!dir.existsSync()) {
      continue;
    }
    for (final entry in dir.listSync(followLinks: false)) {
      if (entry is! File) {
        continue;
      }
      final stat = entry.statSync();
      if (stat.mode & 0x49 == 0) {
        continue;
      }
      suggestions.add(FigCompletionSuggestion(name: _basename(entry.path)));
    }
  }
  return suggestions;
}

List<FigCompletionSuggestion> _templateSuggestions(
  List<String> templates,
  String prefix,
  FigCompletionContext context,
) {
  if (!templates.contains('filepaths') && !templates.contains('folders')) {
    return const <FigCompletionSuggestion>[];
  }
  final cwd = Directory(context.cwd);
  if (!cwd.existsSync()) {
    return const <FigCompletionSuggestion>[];
  }
  final foldersOnly =
      templates.contains('folders') && !templates.contains('filepaths');
  final suggestions = <FigCompletionSuggestion>[];
  for (final entry in cwd.listSync(followLinks: false)) {
    final isDirectory = entry is Directory;
    if (foldersOnly && !isDirectory) {
      continue;
    }
    final name = '${_basename(entry.path)}${isDirectory ? '/' : ''}';
    if (prefix.isNotEmpty && !name.startsWith(prefix)) {
      continue;
    }
    suggestions.add(
      FigCompletionSuggestion(
        name: name,
        source: FigCompletionSuggestionSource.template,
      ),
    );
  }
  return suggestions;
}

Future<List<FigCompletionSuggestion>> _generatorSuggestions(
  List<FigCompletionGenerator> generators,
  FigCompletionContext context,
) async {
  final suggestions = <FigCompletionSuggestion>[];
  for (final generator in generators) {
    if (generator.script.trim().isEmpty) {
      continue;
    }
    try {
      final result = await Process.run(
        '/bin/sh',
        <String>['-lc', generator.script],
        workingDirectory: Directory(context.cwd).existsSync()
            ? context.cwd
            : null,
        environment: context.environment.isEmpty ? null : context.environment,
      ).timeout(const Duration(milliseconds: 800));
      if (result.exitCode != 0) {
        continue;
      }
      final output = result.stdout?.toString() ?? '';
      final splitOn = _decodeSplitOn(generator.splitOn);
      for (final part in output.split(splitOn)) {
        final value = part.trim();
        if (value.isEmpty) {
          continue;
        }
        suggestions.add(
          FigCompletionSuggestion(
            name: value,
            source: FigCompletionSuggestionSource.generator,
          ),
        );
      }
    } catch (_) {
      continue;
    }
  }
  return suggestions;
}

String _decodeSplitOn(String value) {
  return value.replaceAll(r'\n', '\n').replaceAll(r'\t', '\t');
}

String _basename(String path) {
  final slash = path.lastIndexOf(Platform.pathSeparator);
  return slash < 0 ? path : path.substring(slash + 1);
}

Map<String, Object?>? _objectMap(Object? value) {
  if (value is Map) {
    return value.map(
      (key, entry) => MapEntry(key.toString(), entry as Object?),
    );
  }
  return null;
}

List<Object?> _objectList(Object? value) {
  if (value is List) {
    return value.cast<Object?>();
  }
  if (value == null) {
    return const <Object?>[];
  }
  return <Object?>[value];
}

List<String> _stringList(Object? value) {
  if (value is String) {
    return <String>[value];
  }
  if (value is List) {
    return value.whereType<String>().toList(growable: false);
  }
  return const <String>[];
}

String? _stringOrNull(Object? value) {
  return value is String ? value : null;
}
