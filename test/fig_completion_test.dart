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
      Directory('${dir.path}/src').createSync();

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
      expect(filepaths.suggestions.single.name, 'config.json');
      expect(
        filepaths.suggestions.single.source,
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
        args: <FigCompletionArg>[
          FigCompletionArg(
            name: 'target',
            suggestions: <FigCompletionSuggestion>[
              FigCompletionSuggestion(name: 'web'),
              FigCompletionSuggestion(name: 'native'),
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
    ],
  );
}
