import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/fig_completion.dart';

void main() {
  test('tokenizer tracks quoted and escaped token at cursor', () {
    final parsed = parseFigCompletionInput(
      const TextEditingValue(
        text: r'''demo run "alpha beta" file\ name''',
        selection: TextSelection.collapsed(offset: 31),
      ),
    );

    expect(parsed.tokens.map((token) => token.text), <String>[
      'demo',
      'run',
      'alpha beta',
      'file name',
    ]);
    expect(parsed.activeToken.text, 'file name');
    expect(parsed.activeToken.start, 22);
    expect(parsed.activeToken.end, 32);
  });

  test(
    'resolver suggests root commands from specs and PATH executables',
    () async {
      final dir = Directory.systemTemp.createTempSync('ianvs_completion_path_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final tool = File('${dir.path}/ianvs-tool')
        ..writeAsStringSync('#!/bin/sh\n');
      Process.runSync('chmod', <String>['755', tool.path]);
      expect(tool.existsSync(), isTrue);

      final repository = FigCompletionRepository.memory(
        index: const FigCompletionIndex(
          commands: <FigCompletionCommandRef>[
            FigCompletionCommandRef(
              name: 'demo',
              specPath: 'specs/demo.json',
              description: 'Demo command',
            ),
          ],
        ),
        specs: <String, FigCompletionSpec>{'specs/demo.json': _demoSpec()},
      );
      final engine = FigCompletionEngine(repository: repository);

      final result = await engine.complete(
        const TextEditingValue(
          text: 'ia',
          selection: TextSelection.collapsed(offset: 2),
        ),
        context: FigCompletionContext(
          cwd: dir.path,
          environment: <String, String>{'PATH': dir.path},
        ),
      );

      expect(result.suggestions.map((suggestion) => suggestion.name), <String>[
        'ianvs-tool',
      ]);
      expect(
        result.suggestions.single.source,
        FigCompletionSuggestionSource.spec,
      );
    },
  );

  test(
    'resolver handles subcommands options args templates and generators',
    () async {
      final dir = Directory.systemTemp.createTempSync('ianvs_completion_cwd_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/config.json').writeAsStringSync('{}');
      File('${dir.path}/my file.txt').writeAsStringSync('{}');
      Directory('${dir.path}/src').createSync();
      File('${dir.path}/src/main.dart').writeAsStringSync('// main');
      Directory('${dir.path}/src/maps').createSync();
      Directory('${dir.path}/foo').createSync();
      final child = Directory('${dir.path}/child')..createSync();
      File('${dir.path}/bar.txt').writeAsStringSync('bar');

      final repository = FigCompletionRepository.memory(
        index: const FigCompletionIndex(
          commands: <FigCompletionCommandRef>[
            FigCompletionCommandRef(name: 'demo', specPath: 'specs/demo.json'),
          ],
        ),
        specs: <String, FigCompletionSpec>{'specs/demo.json': _demoSpec()},
      );
      final engine = FigCompletionEngine(repository: repository);

      final subcommands = await engine.complete(
        const TextEditingValue(
          text: 'demo r',
          selection: TextSelection.collapsed(offset: 6),
        ),
        context: FigCompletionContext(cwd: dir.path),
      );
      expect(subcommands.suggestions.single.name, 'run');

      final options = await engine.complete(
        const TextEditingValue(
          text: 'demo --',
          selection: TextSelection.collapsed(offset: 7),
        ),
        context: FigCompletionContext(cwd: dir.path),
      );
      expect(
        options.suggestions.map((suggestion) => suggestion.name),
        containsAll(<String>['--config', '--generated']),
      );

      final filepaths = await engine.complete(
        const TextEditingValue(
          text: 'demo --config c',
          selection: TextSelection.collapsed(offset: 15),
        ),
        context: FigCompletionContext(cwd: dir.path),
      );
      final configSuggestion = filepaths.suggestions.singleWhere(
        (suggestion) => suggestion.name == 'config.json',
      );
      expect(configSuggestion.name, 'config.json');
      expect(
        configSuggestion.source,
        FigCompletionSuggestionSource.template,
      );

      final generated = await engine.complete(
        const TextEditingValue(
          text: 'demo --generated ',
          selection: TextSelection.collapsed(offset: 17),
        ),
        context: FigCompletionContext(cwd: dir.path),
      );
      expect(
        generated.suggestions.map((suggestion) => suggestion.name),
        <String>['alpha', 'beta'],
      );
      expect(
        generated.suggestions.first.source,
        FigCompletionSuggestionSource.generator,
      );

      final nestedFilepaths = await engine.complete(
        const TextEditingValue(
          text: 'demo --config src/ma',
          selection: TextSelection.collapsed(offset: 20),
        ),
        context: FigCompletionContext(cwd: dir.path),
      );
      expect(
        nestedFilepaths.suggestions.map((suggestion) => suggestion.name),
        <String>['src/main.dart', 'src/maps/'],
      );

      final dotRelative = await engine.complete(
        const TextEditingValue(
          text: 'demo --config ./fo',
          selection: TextSelection.collapsed(offset: 18),
        ),
        context: FigCompletionContext(cwd: dir.path),
      );
      expect(dotRelative.suggestions.single.name, './foo/');

      final parentRelative = await engine.complete(
        const TextEditingValue(
          text: 'demo --config ../ba',
          selection: TextSelection.collapsed(offset: 19),
        ),
        context: FigCompletionContext(cwd: child.path),
      );
      expect(parentRelative.suggestions.single.name, '../bar.txt');

      final absolute = await engine.complete(
        TextEditingValue(
          text: 'demo --config ${dir.path}/co',
          selection: TextSelection.collapsed(
            offset: 'demo --config ${dir.path}/co'.length,
          ),
        ),
        context: FigCompletionContext(cwd: child.path),
      );
      expect(
        absolute.suggestions.single.name,
        '${dir.path}/config.json',
      );

      final foldersOnly = await engine.complete(
        const TextEditingValue(
          text: 'demo --folder src/ma',
          selection: TextSelection.collapsed(offset: 20),
        ),
        context: FigCompletionContext(cwd: dir.path),
      );
      expect(
        foldersOnly.suggestions.map((suggestion) => suggestion.name),
        <String>['src/maps/'],
      );

      final escapedAcceptanceInput = const TextEditingValue(
        text: 'demo --config my',
        selection: TextSelection.collapsed(offset: 16),
      );
      final escapedAcceptance = await engine.complete(
        escapedAcceptanceInput,
        context: FigCompletionContext(cwd: dir.path),
      );
      final escapedSuggestion = escapedAcceptance.suggestions.singleWhere(
        (suggestion) => suggestion.name == 'my file.txt',
      );
      final escapedAccepted = engine.accept(
        escapedAcceptanceInput,
        escapedAcceptance,
        escapedSuggestion,
      );
      expect(escapedAccepted.text, r'demo --config my\ file.txt');

      final quotedAcceptanceInput = const TextEditingValue(
        text: 'demo --config "my',
        selection: TextSelection.collapsed(offset: 17),
      );
      final quotedAcceptance = await engine.complete(
        quotedAcceptanceInput,
        context: FigCompletionContext(cwd: dir.path),
      );
      final quotedSuggestion = quotedAcceptance.suggestions.singleWhere(
        (suggestion) => suggestion.name == 'my file.txt',
      );
      final quotedAccepted = engine.accept(
        quotedAcceptanceInput,
        quotedAcceptance,
        quotedSuggestion,
      );
      expect(quotedAccepted.text, 'demo --config "my file.txt"');

      final pairFirst = await engine.complete(
        const TextEditingValue(
          text: 'demo --pair a',
          selection: TextSelection.collapsed(offset: 13),
        ),
        context: FigCompletionContext(cwd: dir.path),
      );
      expect(pairFirst.suggestions.single.name, 'alpha');

      final pairSecond = await engine.complete(
        const TextEditingValue(
          text: 'demo --pair alpha t',
          selection: TextSelection.collapsed(offset: 19),
        ),
        context: FigCompletionContext(cwd: dir.path),
      );
      expect(pairSecond.suggestions.single.name, 'two');

      final variadicOption = await engine.complete(
        const TextEditingValue(
          text: 'demo --many red b',
          selection: TextSelection.collapsed(offset: 17),
        ),
        context: FigCompletionContext(cwd: dir.path),
      );
      expect(variadicOption.suggestions.single.name, 'blue');

      final optionalOptionSkipped = await engine.complete(
        const TextEditingValue(
          text: 'demo --format --',
          selection: TextSelection.collapsed(offset: 16),
        ),
        context: FigCompletionContext(cwd: dir.path),
      );
      expect(
        optionalOptionSkipped.suggestions.map((suggestion) => suggestion.name),
        contains('--config'),
      );

      final positionalRequired = await engine.complete(
        const TextEditingValue(
          text: 'demo run w',
          selection: TextSelection.collapsed(offset: 10),
        ),
        context: FigCompletionContext(cwd: dir.path),
      );
      expect(positionalRequired.suggestions.single.name, 'web');

      final positionalOptional = await engine.complete(
        const TextEditingValue(
          text: 'demo run web d',
          selection: TextSelection.collapsed(offset: 14),
        ),
        context: FigCompletionContext(cwd: dir.path),
      );
      expect(positionalOptional.suggestions.single.name, 'debug');

      final positionalVariadic = await engine.complete(
        const TextEditingValue(
          text: 'demo run web debug ta',
          selection: TextSelection.collapsed(offset: 21),
        ),
        context: FigCompletionContext(cwd: dir.path),
      );
      expect(
        positionalVariadic.suggestions.map((suggestion) => suggestion.name),
        <String>['tag-a', 'tag-b'],
      );

      final positionalOptionalSkipped = await engine.complete(
        const TextEditingValue(
          text: 'demo run web --',
          selection: TextSelection.collapsed(offset: 15),
        ),
        context: FigCompletionContext(cwd: dir.path),
      );
      expect(
        positionalOptionalSkipped.suggestions.map(
          (suggestion) => suggestion.name,
        ),
        contains('--watch'),
      );
    },
  );

  test(
    'controller updates cwd and accepts a suggestion into the active token',
    () async {
      final repository = FigCompletionRepository.memory(
        index: const FigCompletionIndex(
          commands: <FigCompletionCommandRef>[
            FigCompletionCommandRef(name: 'demo', specPath: 'specs/demo.json'),
          ],
        ),
        specs: <String, FigCompletionSpec>{'specs/demo.json': _demoSpec()},
      );
      final controller = FigCompletionController(
        engine: FigCompletionEngine(repository: repository),
        initialCwd: '/tmp',
      );
      addTearDown(controller.dispose);

      controller.updateCwd('/var/tmp');
      expect(controller.cwd, '/var/tmp');

      final accepted = await controller.completeOrAccept(
        const TextEditingValue(
          text: 'de',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );

      expect(accepted, isNotNull);
      expect(accepted!.text, 'demo');
      expect(accepted.selection.baseOffset, 4);
      expect(controller.isOpen, isFalse);
    },
  );
}

FigCompletionSpec _demoSpec() {
  return const FigCompletionSpec(
    names: <String>['demo'],
    description: 'Demo command',
    subcommands: <FigCompletionCommand>[
      FigCompletionCommand(
        names: <String>['run'],
        description: 'Run target',
        options: <FigCompletionOption>[
          FigCompletionOption(names: <String>['--watch']),
        ],
        args: <FigCompletionArg>[
          FigCompletionArg(
            name: 'target',
            suggestions: <FigCompletionSuggestion>[
              FigCompletionSuggestion(name: 'web'),
              FigCompletionSuggestion(name: 'native'),
            ],
          ),
          FigCompletionArg(
            name: 'mode',
            isOptional: true,
            suggestions: <FigCompletionSuggestion>[
              FigCompletionSuggestion(name: 'debug'),
              FigCompletionSuggestion(name: 'release'),
            ],
          ),
          FigCompletionArg(
            name: 'tag',
            isVariadic: true,
            suggestions: <FigCompletionSuggestion>[
              FigCompletionSuggestion(name: 'tag-a'),
              FigCompletionSuggestion(name: 'tag-b'),
            ],
          ),
        ],
      ),
    ],
    options: <FigCompletionOption>[
      FigCompletionOption(names: <String>['-v', '--verbose']),
      FigCompletionOption(
        names: <String>['--config'],
        args: <FigCompletionArg>[
          FigCompletionArg(name: 'file', templates: <String>['filepaths']),
        ],
      ),
      FigCompletionOption(
        names: <String>['--folder'],
        args: <FigCompletionArg>[
          FigCompletionArg(name: 'dir', templates: <String>['folders']),
        ],
      ),
      FigCompletionOption(
        names: <String>['--generated'],
        args: <FigCompletionArg>[
          FigCompletionArg(
            name: 'value',
            generators: <FigCompletionGenerator>[
              FigCompletionGenerator(script: "printf 'alpha\\nbeta\\n'"),
            ],
          ),
        ],
      ),
      FigCompletionOption(
        names: <String>['--pair'],
        args: <FigCompletionArg>[
          FigCompletionArg(
            name: 'left',
            suggestions: <FigCompletionSuggestion>[
              FigCompletionSuggestion(name: 'alpha'),
              FigCompletionSuggestion(name: 'beta'),
            ],
          ),
          FigCompletionArg(
            name: 'right',
            suggestions: <FigCompletionSuggestion>[
              FigCompletionSuggestion(name: 'one'),
              FigCompletionSuggestion(name: 'two'),
            ],
          ),
        ],
      ),
      FigCompletionOption(
        names: <String>['--many'],
        args: <FigCompletionArg>[
          FigCompletionArg(
            name: 'item',
            isVariadic: true,
            suggestions: <FigCompletionSuggestion>[
              FigCompletionSuggestion(name: 'blue'),
              FigCompletionSuggestion(name: 'red'),
            ],
          ),
        ],
      ),
      FigCompletionOption(
        names: <String>['--format'],
        args: <FigCompletionArg>[
          FigCompletionArg(
            name: 'format',
            isOptional: true,
            suggestions: <FigCompletionSuggestion>[
              FigCompletionSuggestion(name: 'json'),
              FigCompletionSuggestion(name: 'yaml'),
            ],
          ),
        ],
      ),
    ],
  );
}
