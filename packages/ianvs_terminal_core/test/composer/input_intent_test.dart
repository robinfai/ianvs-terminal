import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

const shell = InputIntentContext(
  commandNames: {
    'ls',
    'git',
    'find',
    'cat',
    'echo',
    'printf',
    'sudo',
    'codex',
    'rg',
    'npm',
    'docker',
    'kubectl',
    'ssh',
    'cd',
    'df',
    'top',
    'vim',
    'python3',
    'curl',
    'yes',
    'for',
    'pwd',
    'custom-tool',
  },
);

void main() {
  test(
    'initial metadata and temporary unavailability preserve a manual choice',
    () {
      final state = InputIntentState();
      state.update('ls', context: shell);
      state.choice = InputIntentChoice.ai;
      const local = InputIntentContext(
        scope: 'session:root',
        commandNames: {'ls'},
      );
      expect(state.update('ls', context: local).intent, InputIntent.ai);
      expect(state.update('ls', context: shell).intent, InputIntent.ai);
      expect(state.update('ls', context: local).source, 'manual');
      expect(
        state
            .update(
              'ls',
              context: const InputIntentContext(
                scope: 'session:ssh',
                commandNames: {'ls'},
              ),
            )
            .intent,
        InputIntent.command,
      );
      expect(state.choice, InputIntentChoice.automatic);
    },
  );
  group('routing with live shell evidence', () {
    const commands = [
      'ls -l /var/log',
      'git diff --stat',
      'git status',
      'git rebase main',
      'find . -name foo',
      'cat "请帮我.txt"',
      './显示文件',
      'echo why is it failing',
      'sudo explain',
      'codex explain this code',
      'FOO=bar ./script',
      'rg "how do I" README.md',
      'npm run lint',
      'docker ps -a',
      'kubectl describe pod foo',
      'ssh cloud',
      'cd ../src',
      'df',
      'top',
      'vim',
      'python3 script.py',
      'curl -I https://example.org',
      'yes',
      r'for n in 1 2 3; do echo "$n"; done',
      'ls | sort',
      'pwd > /tmp/location',
      'custom-tool --version',
      '/opt/bin/工具 帮助',
      'cat 中文文档.txt',
    ];
    const prompts = [
      '请检查这个端口为什么连接不上',
      '找出最近修改的几个文件',
      '看看上一个命令的输出哪里有问题',
      '这个目录里最大的文件是什么',
      '磁盘满了，应该怎么办',
      '网络一直不通',
      'git status 是什么意思',
      'ls -la 里的权限怎么理解',
      'npm install 报错，怎么处理',
      '为什么 ssh cloud 连接不上',
      '帮我写一条 find 命令',
      'summarize the most recent error',
      'show me the hidden directories',
      'find the biggest files in this folder',
      'how do I stop this process',
      'why is my ssh connection timing out',
      'explain what docker ps does',
      'remove the generated files after checking them',
      'the build failed again',
      'can you inspect /etc/hosts',
      'please explain ls | sort',
      'what does --force mean',
      'check if the database is healthy',
      'write a small script to rename files',
      '? explain this output',
      'in vim save the current file',
    ];
    for (final command in commands) {
      test('command: $command', () {
        expect(
          classifyInputIntent(command, context: shell).intent,
          InputIntent.command,
        );
      });
    }
    for (final prompt in prompts) {
      test('AI: $prompt', () {
        expect(
          classifyInputIntent(prompt, context: shell).intent,
          InputIntent.ai,
        );
      });
    }
  });

  group('unknown input goes to AI across languages and domains', () {
    const inputs = [
      '讲个故事',
      '写首诗',
      '随便聊聊',
      '明天天气怎样',
      '晚饭吃什么',
      '生成一份周计划',
      '早上好',
      '一加一等于几',
      '编一个笑话',
      '翻译这段文字',
      '北京到上海有多远',
      'good morning',
      'translate bonjour',
      'invent a bedtime story',
      'sing a song',
      'plan dinner for six',
      'draft an apology',
      'raconte une histoire',
      'cuéntame un cuento',
      '物語を話して',
      '이야기를 해줘',
      'unknown-tool --version',
      'totally-new-cli status',
      'sl',
      '帮助',
      'tell me a story; use a dragon',
      'translate "hello"',
    ];
    for (final input in inputs) {
      test(input, () {
        expect(
          classifyInputIntent(input, context: shell).intent,
          InputIntent.ai,
        );
      });
    }
  });

  test('unknown names become commands only with current shell evidence', () {
    const custom = InputIntentContext(
      commandNames: {'my-app', '帮助', 'summarize'},
    );
    for (final input in ['my-app --version', '帮助', 'summarize']) {
      expect(classifyInputIntent(input).intent, InputIntent.ai);
      expect(
        classifyInputIntent(input, context: custom).intent,
        InputIntent.command,
      );
      expect(classifyInputIntent(input).intent, InputIntent.ai);
    }
    expect(
      classifyInputIntent('git status 是什么意思', context: shell).intent,
      InputIntent.ai,
    );
  });

  test('shell names may be words, Unicode functions or aliases', () {
    const names = InputIntentContext(
      commandNames: {'help', '解释', 'make', 'git'},
      aliases: {'summarize': 'cat'},
    );
    for (final input in [
      'help --all',
      '解释 --help',
      'summarize report.txt',
      'make build',
    ]) {
      expect(
        classifyInputIntent(input, context: names).intent,
        InputIntent.command,
        reason: input,
      );
    }
    for (final input in ['make me a sandwich', 'git status why does it fail']) {
      expect(
        classifyInputIntent(input, context: names).intent,
        InputIntent.ai,
        reason: input,
      );
    }
  });

  test(
    'failed attempts in navigation history never become command evidence',
    () {
      final controller = TerminalComposerController(
        targetId: 'test',
        provider: (query, _) async => CompletionBatch(query, const []),
      );
      addTearDown(controller.dispose);
      controller.updateHistory(['讲个故事', 'unknown-cli --version']);
      for (final text in ['讲个故事', 'unknown-cli --version']) {
        controller.editor.text = text;
        expect(controller.intentDecision.intent, InputIntent.ai);
      }
      controller.chooseInputIntent(InputIntentChoice.command);
      expect(controller.intentDecision.intent, InputIntent.command);
      controller.editor.clear();
      controller.editor.text = '讲个故事';
      expect(controller.intentDecision.intent, InputIntent.ai);
    },
  );

  test('session evidence is scoped; an SSH node replaces local evidence', () {
    final state = InputIntentState();
    const local = InputIntentContext(
      scope: 'session:root',
      aliases: {'diagnose': 'custom-tool'},
      commandNames: {'summarize'},
    );
    const ssh = InputIntentContext(scope: 'session:ssh:1');
    expect(state.update('diagnose', context: local).source, 'alias');
    state.choice = InputIntentChoice.command;
    expect(state.update('分析一下失败原因', context: local).source, 'manual');
    expect(state.update('分析一下失败原因', context: ssh).intent, InputIntent.ai);
    expect(state.choice, InputIntentChoice.automatic);
    expect(state.update('summarize', context: local).source, 'shell');
    expect(state.update('summarize', context: ssh).intent, InputIntent.ai);
  });

  test('manual override lasts until draft clears; IME cannot flip mode', () {
    final state = InputIntentState();
    expect(state.update('ls', context: shell).intent, InputIntent.command);
    expect(state.update('为什么', composing: true).intent, InputIntent.command);
    expect(state.update('为什么').intent, InputIntent.ai);
    state.choice = InputIntentChoice.command;
    expect(state.update('为什么不行').intent, InputIntent.command);
    state.update('');
    expect(state.choice, InputIntentChoice.automatic);
    expect(state.update('如何退出').intent, InputIntent.ai);
  });

  test('agent follow-up and input ownership precede bare yes command', () {
    final state = InputIntentState();
    expect(state.update('yes', context: shell).intent, InputIntent.command);
    expect(
      state
          .update('yes', context: const InputIntentContext(agentFollowUp: true))
          .intent,
      InputIntent.ai,
    );
    state.choice = InputIntentChoice.command;
    expect(state.update('ls', agentOwnsInput: true).intent, InputIntent.ai);
  });

  test('bounded input handles multiline, emoji and oversized paste', () {
    final state = InputIntentState();
    expect(state.update('解释这个错误 🔥').intent, InputIntent.ai);
    expect(state.update('x' * 65536).source, 'length');
    expect(state.decision.intent, InputIntent.ai);
    expect(
      classifyInputIntent('echo one\necho two', context: shell).intent,
      InputIntent.command,
    );
  });
}
