import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/command_intelligence_service.dart';
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

    test('classifies shell builtins with plain arguments as command input', () {
      const classifier = UniversalInputClassifier();

      final result = classifier.classify('printf RETEST_LOCAL2');

      expect(result.kind, UniversalInputKind.command);
      expect(result.source, UniversalInputDecisionSource.commandVocabulary);
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

    test('honors natural-language denylist entries as command signals', () {
      const classifier = UniversalInputClassifier(
        naturalLanguageDenylist: {'show'},
      );

      final result = classifier.classify('show files');

      expect(result.kind, UniversalInputKind.command);
      expect(
        result.source,
        UniversalInputDecisionSource.naturalLanguageDenylist,
      );
    });

    test('classifies multiline shell input as command input', () {
      const classifier = UniversalInputClassifier();

      final result = classifier.classify('cd example\nflutter test');

      expect(result.kind, UniversalInputKind.command);
      expect(result.source, UniversalInputDecisionSource.multilineCommand);
    });

    test('keeps multiline task text as natural language', () {
      const classifier = UniversalInputClassifier();

      final result = classifier.classify(
        'explain why tests fail\nand suggest a fix',
      );

      expect(result.kind, UniversalInputKind.naturalLanguage);
      expect(result.source, UniversalInputDecisionSource.naturalLanguageScore);
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
    test(
      'does not use local rules for natural-language command generation',
      () {
        final suggestions = universalInputCommandSuggestionsForText(
          'show files in this directory',
        );

        expect(suggestions, isEmpty);
      },
    );
  });

  group('universalInputCommandDraftsForText', () {
    test('returns no local drafts for natural-language text', () {
      expect(universalInputCommandDraftsForText('查找 TODO'), isEmpty);
      expect(universalInputCommandDraftsForText('查看git分支'), isEmpty);
      expect(universalInputCommandDraftsForText('查看当前分支'), isEmpty);
    });

    test('does not locally draft destructive natural-language commands', () {
      final drafts = universalInputCommandDraftsForText('删除 node_modules');

      expect(drafts, isEmpty);
    });
  });

  group('universalInputLocalCorrectionFor', () {
    test('corrects mistyped executables', () {
      final correction = universalInputLocalCorrectionFor(
        const CommandCorrectionRequest(command: 'gti status', exitCode: 127),
      );

      expect(correction?.command, 'git status');
      expect(correction?.ruleId, 'executable-typo');
    });

    test('suggests git push upstream command from output', () {
      final correction = universalInputLocalCorrectionFor(
        const CommandCorrectionRequest(
          command: 'git push',
          exitCode: 128,
          outputTail:
              'fatal: The current branch feature/demo has no upstream branch.\n'
              'git push --set-upstream origin feature/demo',
        ),
      );

      expect(
        correction?.command,
        "git push --set-upstream origin 'feature/demo'",
      );
      expect(correction?.ruleId, 'git-push-upstream');
    });

    test('quotes branch names captured from git output', () {
      final correction = universalInputLocalCorrectionFor(
        const CommandCorrectionRequest(
          command: 'git push',
          exitCode: 128,
          outputTail:
              'fatal: The current branch feature/demo has no upstream branch.\n'
              'git push --set-upstream origin feature/demo;touch/tmp/pwn',
        ),
      );

      expect(
        correction?.command,
        "git push --set-upstream origin 'feature/demo;touch/tmp/pwn'",
      );
      expect(correction?.ruleId, 'git-push-upstream');
    });

    test('quotes recent directory corrections', () {
      final correction = universalInputLocalCorrectionFor(
        const CommandCorrectionRequest(
          command: 'cd prodction',
          exitCode: 1,
          outputTail: 'cd: no such file or directory: prodction',
          recentDirectories: ['/tmp/prodction;'],
        ),
      );

      expect(correction?.command, "cd '/tmp/prodction;'");
      expect(correction?.ruleId, 'cd-path-fuzzy');
    });

    test('suggests executable permission fix for local script', () {
      final correction = universalInputLocalCorrectionFor(
        const CommandCorrectionRequest(
          command: './script.sh',
          exitCode: 126,
          outputTail: 'zsh: permission denied: ./script.sh',
        ),
      );

      expect(correction?.command, 'chmod +x ./script.sh && ./script.sh');
      expect(correction?.riskLevel, CommandRiskLevel.caution);
    });
  });

  group('universal input safety helpers', () {
    test('redacts common secret shapes and limits output tails', () {
      final redacted = redactUniversalInputCommandContext(
        [
          'line one',
          'DEEPSEEK_API_KEY=abc123456789',
          'Authorization: Bearer abcdefghijklmnopqrstuvwxyz',
          'token=my-token',
        ].join('\n'),
        maxLines: 3,
      );

      expect(redacted, isNot(contains('line one')));
      expect(redacted, isNot(contains('abc123456789')));
      expect(redacted, isNot(contains('abcdefghijklmnopqrstuvwxyz')));
      expect(redacted, contains('[REDACTED]'));
    });

    test('classifies command risk levels', () {
      expect(
        universalInputRiskLevelForCommand('rm -rf node_modules'),
        CommandRiskLevel.destructive,
      );
      expect(
        universalInputRiskLevelForCommand('sudo cat /var/log/system.log'),
        CommandRiskLevel.caution,
      );
      expect(
        universalInputRiskLevelForCommand('rg TODO'),
        CommandRiskLevel.safe,
      );
    });
  });

  group('CommandIntelligenceService', () {
    test('returns no command drafts without an API key', () async {
      final service = CommandIntelligenceService(apiKey: null);
      addTearDown(service.close);

      final drafts = await service.draftCommands(
        const CommandDraftRequest(input: '列出文件'),
      );

      expect(drafts, isEmpty);
    });

    test(
      'uses request OpenAI-compatible settings and disables DeepSeek thinking',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final service = CommandIntelligenceService(apiKey: null);
        addTearDown(service.close);
        final baseUrl = 'http://${server.address.address}:${server.port}';

        final handledRequest = server.first.then((request) async {
          expect(request.uri.path, '/chat/completions');
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer profile-key',
          );
          final body =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, Object?>;
          expect(body['model'], 'deepseek-v4-flash');
          expect(body['thinking'], {'type': 'disabled'});
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'commands': [
                        {
                          'command': 'ls -la',
                          'reason': 'List files.',
                          'confidence': 0.9,
                        },
                      ],
                    }),
                  },
                },
              ],
            }),
          );
          await request.response.close();
        });

        final drafts = await service.draftCommands(
          CommandDraftRequest(
            input: '列出文件',
            apiBaseUrl: baseUrl,
            apiKey: 'profile-key',
            apiModel: 'deepseek-v4-flash',
          ),
        );
        await handledRequest;

        expect(drafts.single.command, 'ls -la');
      },
    );

    test(
      'does not send service fallback keys to request override base URLs',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        var handledRequests = 0;
        final subscription = server.listen((request) async {
          handledRequests += 1;
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
        });
        addTearDown(subscription.cancel);
        final service = CommandIntelligenceService(apiKey: 'env-key');
        addTearDown(service.close);
        final baseUrl = 'http://${server.address.address}:${server.port}';

        expect(service.remoteAvailableFor(apiBaseUrl: baseUrl), isFalse);
        final drafts = await service.draftCommands(
          CommandDraftRequest(input: '列出文件', apiBaseUrl: baseUrl),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(drafts, isEmpty);
        expect(handledRequests, 0);
      },
    );

    test('falls back to local corrections without an API key', () async {
      final service = CommandIntelligenceService(apiKey: null);
      addTearDown(service.close);

      final correction = await service.correctCommand(
        const CommandCorrectionRequest(command: 'gti status', exitCode: 127),
      );

      expect(correction?.command, 'git status');
    });
  });
}
