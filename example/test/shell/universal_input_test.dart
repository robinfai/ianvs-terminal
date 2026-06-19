import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/universal_input.dart';

void main() {
  group('UniversalInputClassifier', () {
    test('classifies known shell commands as command input', () {
      const classifier = UniversalInputClassifier();

      final result = classifier.classify('git status --short');

      expect(result.kind, UniversalInputKind.command);
      expect(result.source, UniversalInputDecisionSource.commandVocabulary);
      expect(result.isCommand, isTrue);
    });

    test('classifies English task text as natural language', () {
      const classifier = UniversalInputClassifier();

      final result = classifier.classify('explain why the tests are failing');

      expect(result.kind, UniversalInputKind.naturalLanguage);
      expect(result.source, UniversalInputDecisionSource.naturalLanguageScore);
      expect(result.isNaturalLanguage, isTrue);
    });

    test('classifies Chinese task text as natural language', () {
      const classifier = UniversalInputClassifier();

      final result = classifier.classify('帮我列出当前目录里的文件');

      expect(result.kind, UniversalInputKind.naturalLanguage);
      expect(result.source, UniversalInputDecisionSource.cjkNaturalLanguage);
    });

    test('honors explicit terminal and agent modes', () {
      const classifier = UniversalInputClassifier();

      expect(
        classifier
            .classify(
              'explain the current branch',
              mode: UniversalInputMode.terminal,
            )
            .kind,
        UniversalInputKind.command,
      );
      expect(
        classifier.classify('git status', mode: UniversalInputMode.agent).kind,
        UniversalInputKind.naturalLanguage,
      );
    });

    test('uses recent command vocabulary as a command signal', () {
      const classifier = UniversalInputClassifier(commandVocabulary: {'just'});

      final result = classifier.classify('just test');

      expect(result.kind, UniversalInputKind.command);
      expect(result.source, UniversalInputDecisionSource.commandVocabulary);
    });
  });

  group('parseUniversalInputTokens', () {
    test('keeps quoted text together', () {
      expect(parseUniversalInputTokens('explain "git status" output'), [
        'explain',
        '"git status"',
        'output',
      ]);
    });
  });

  group('universalInputCommandSuggestionsForText', () {
    test('maps natural language to local command suggestions', () {
      final suggestions = universalInputCommandSuggestionsForText(
        'show files in this directory',
      );

      expect(
        suggestions.map((suggestion) => suggestion.command),
        contains('ls -la'),
      );
    });
  });
}
