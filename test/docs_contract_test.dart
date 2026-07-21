import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('execution target manifest matches repository evidence', () {
    final manifest =
        jsonDecode(
              File('docs/CURRENT_EXECUTION_TARGETS.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final lanes = (manifest['lanes'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final currentTarget = manifest['current_target'] as String;
    final activeLanes = lanes
        .where((lane) => lane['status'] == 'active')
        .toList(growable: false);

    expect(manifest['schema_version'], 1);
    expect(activeLanes, hasLength(1));
    expect(activeLanes.single['id'], currentTarget);

    const allowedStatuses = <String>{
      'achieved',
      'active',
      'blocked',
      'deferred',
    };
    for (final lane in lanes) {
      final id = lane['id'] as String;
      final status = lane['status'] as String;
      expect(allowedStatuses, contains(status), reason: 'lane $id status');
      expect((lane['goal'] as String).trim(), isNotEmpty, reason: 'lane $id');

      final evidence = (lane['evidence'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(evidence, isNotEmpty, reason: 'lane $id evidence');
      for (final item in evidence) {
        final path = item['path'] as String;
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'lane $id evidence: $path');
        final content = file.readAsStringSync();
        for (final token in _stringList(item['contains'])) {
          expect(content, contains(token), reason: '$path requires $token');
        }
        for (final token in _stringList(item['not_contains'])) {
          expect(
            content,
            isNot(contains(token)),
            reason: '$path must not contain $token',
          );
        }
      }

      final commands = _stringList(lane['verification_commands']);
      if (status != 'deferred') {
        expect(commands, isNotEmpty, reason: 'lane $id verification');
      }
      if (status == 'active') {
        expect(
          _stringList(lane['exit_criteria']),
          isNotEmpty,
          reason: 'lane $id exit criteria',
        );
      }
      if (status == 'blocked') {
        expect(
          _stringList(lane['blockers']),
          isNotEmpty,
          reason: 'lane $id blockers',
        );
      }
      if (status == 'deferred') {
        expect(
          (lane['reason'] as String).trim(),
          isNotEmpty,
          reason: 'lane $id deferral reason',
        );
      }
    }

    final roadmap = File('docs/ROADMAP.md').readAsStringSync();
    expect(roadmap, contains('CURRENT_EXECUTION_TARGETS.json'));
    expect(roadmap, contains('**`$currentTarget`**'));
  });

  test('authoritative documentation links resolve', () {
    const documents = <String>[
      'README.md',
      'ARCHITECTURE.md',
      'docs/README.md',
      'docs/ACCEPTANCE.md',
      'docs/ARCHITECTURE.md',
      'docs/CURRENT_EXECUTION_TARGET.md',
      'docs/compatibility/CAPABILITY_MATRIX.md',
      'docs/compatibility/KNOWN_ISSUES.md',
      'docs/compatibility/MANUAL_VERIFICATION.md',
      'docs/compatibility/TEST_ASSET_INVENTORY.md',
      'docs/KNOWN_ISSUES.md',
      'docs/ROADMAP.md',
      'docs/TESTING.md',
      'docs/tasks/README.md',
      'docs/tasks/verification-gates/'
          'T-298-current-execution-target-contract.md',
      'docs/tasks/verification-gates/T-302-compatibility-baseline.md',
    ];
    final failures = <String>[];

    for (final document in documents) {
      final source = File(document);
      expect(source.existsSync(), isTrue, reason: document);
      final content = source.readAsStringSync();
      for (final match in _markdownLinkPattern.allMatches(content)) {
        final rawTarget = match.group(1)!;
        final target = rawTarget.startsWith('<') && rawTarget.endsWith('>')
            ? rawTarget.substring(1, rawTarget.length - 1)
            : rawTarget;
        if (_isExternalOrAnchorLink(target)) {
          continue;
        }
        final path = Uri.decodeComponent(
          target.split('#').first.split('?').first,
        );
        if (path.isEmpty) {
          continue;
        }
        final resolved = source.absolute.parent.uri.resolve(path).toFilePath();
        if (FileSystemEntity.typeSync(resolved) ==
            FileSystemEntityType.notFound) {
          failures.add('$document -> $target');
        }
      }
    }

    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('compatibility baseline keeps six-layer evidence explicit', () {
    final matrix = File(
      'docs/compatibility/CAPABILITY_MATRIX.md',
    ).readAsStringSync();
    final inventory = File(
      'docs/compatibility/TEST_ASSET_INVENTORY.md',
    ).readAsStringSync();
    final knownIssues = File(
      'docs/compatibility/KNOWN_ISSUES.md',
    ).readAsStringSync();
    final manual = File(
      'docs/compatibility/MANUAL_VERIFICATION.md',
    ).readAsStringSync();
    final task = File(
      'docs/tasks/verification-gates/T-302-compatibility-baseline.md',
    ).readAsStringSync();

    expect(
      matrix,
      contains(
        '| Area | Capability | Parse | State | Frame | Runtime | UI | '
        'Verified | Evidence |',
      ),
    );
    for (final area in <String>[
      '| Basics |',
      '| Input |',
      '| OSC |',
      '| Graphics |',
      '| Shell integration |',
    ]) {
      expect(matrix, contains(area));
    }
    expect(matrix, contains('Unknown'));
    expect(matrix, contains('resize_replay_micros'));
    expect(matrix, contains('real PTY shell starts, accepts input'));
    expect(matrix, contains('real PTY alternate-screen TUI starts, resizes'));
    expect(matrix, contains('UnicodeVersion changes visible columns'));

    expect(inventory, contains('native/core/tests/'));
    expect(inventory, contains('example/integration_test/'));
    expect(inventory, contains('tools/vttest_gui_nightly.sh'));
    expect(knownIssues, contains('resize_replay_skipped_truncated_count'));
    expect(manual, contains('Never record a missing prerequisite as `pass`'));
    for (final command in <String>[
      'make bootstrap',
      'make analyze',
      'make test',
      'make verify',
    ]) {
      expect(task, contains(command));
    }
    expect(task, contains('Do not perform the Iteration 02'));
    expect(task, contains('Do not implement Iteration 03'));
  });

  test('OSC capability plan uses automated OSC52 UI evidence first', () {
    final plan = File('docs/OSC_CAPABILITY_PLAN.md').readAsStringSync();

    expect(
      plan,
      isNot(
        contains(
          'Manual acceptance must include a visible clipboard-copy and '
          'paste-request flow.',
        ),
      ),
    );
    expect(
      plan,
      contains(
        'cd example && flutter test test/shell/shell_screen_phase4_test.dart '
        '--plain-name "OSC 52"',
      ),
    );
    expect(
      plan,
      contains('OSC 52 blocked copy shows visible status and feedback'),
    );
    expect(plan, contains('OSC 52 ask policy prompts before paste read'));
    expect(plan, contains('Desktop smoke remains supplemental'));
    expect(plan, isNot(contains('Computer acceptance confirms')));
  });

  test('terminal verification script runs docs contract tests', () {
    final script = File('tools/verify_flutter_terminal.sh').readAsStringSync();

    expect(script, contains('dart test test/docs_contract_test.dart'));
  });

  test('terminal verification script always runs the Shell widget suite', () {
    final script = File('tools/verify_flutter_terminal.sh').readAsStringSync();

    expect(script, contains('test/widget_test.dart'));
    expect(
      script,
      isNot(contains('VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS')),
    );
    expect(script, isNot(contains('Skipping example/test/widget_test.dart')));
  });

  test('vttest GUI gate serializes the PTY-heavy VT220 suite', () {
    final script = File('tools/vttest_gui_nightly.sh').readAsStringSync();

    expect(script, contains('cargo test vt220 -- --test-threads=1'));
  });

  test('release real PTY gate owns a bounded app process group', () {
    final script = File(
      'tools/run_release_real_pty_refresh_gate.sh',
    ).readAsStringSync();
    final runner = File(
      'tools/run_process_group_with_timeout.py',
    ).readAsStringSync();
    final processControl = '$script\n$runner';

    expect(script, contains('IANVS_RELEASE_REFRESH_GATE_TIMEOUT_SECONDS'));
    expect(script, contains('Contents/MacOS/Ianvs Terminal'));
    expect(
      processControl,
      anyOf(contains('os.setsid()'), contains('start_new_session=True')),
    );
    expect(
      processControl,
      anyOf(contains('kill -TERM'), contains('signal.SIGTERM')),
    );
    expect(
      processControl,
      anyOf(contains('kill -KILL'), contains('signal.SIGKILL')),
    );
    expect(script, isNot(contains('open -W')));
    expect(script, contains('runner_status='));
    final stdoutReplay = script.indexOf("sed -n '1,260p'");
    final runnerFailureCheck = script.indexOf('if (( runner_status != 0 ))');
    expect(stdoutReplay, greaterThanOrEqualTo(0));
    expect(runnerFailureCheck, greaterThan(stdoutReplay));
  });

  test(
    'release process runner kills helpers after the group leader exits',
    () async {
      if (Platform.isWindows) {
        return;
      }
      final directory = Directory.systemTemp.createTempSync(
        'ianvs-process-group-test-',
      );
      final helper = File('${directory.path}/leader.py');
      final childPidFile = File('${directory.path}/child.pid');
      final stdoutLog = File('${directory.path}/stdout.log');
      final stderrLog = File('${directory.path}/stderr.log');
      int? childPid;
      try {
        helper.writeAsStringSync(r'''
import os
import signal
import subprocess
import sys
import time

child = subprocess.Popen([
    sys.executable,
    "-c",
    "import os,signal,sys,time; "
    "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
    "open(sys.argv[1], 'w').write(str(os.getpid())); "
    "time.sleep(30)",
    sys.argv[1],
])

def exit_on_term(_signum, _frame):
    raise SystemExit(0)

signal.signal(signal.SIGTERM, exit_on_term)
while not os.path.exists(sys.argv[1]):
    time.sleep(0.01)
time.sleep(30)
''');

        final result = await Process.run('python3', <String>[
          'tools/run_process_group_with_timeout.py',
          '1',
          stdoutLog.path,
          stderrLog.path,
          'python3',
          helper.path,
          childPidFile.path,
        ]);

        expect(result.exitCode, 124, reason: '${result.stderr}');
        expect(childPidFile.existsSync(), isTrue);
        childPid = int.parse(childPidFile.readAsStringSync());
        var childAlive = true;
        for (var attempt = 0; attempt < 50 && childAlive; attempt += 1) {
          final probe = await Process.run('ps', <String>[
            '-p',
            '$childPid',
            '-o',
            'pid=',
          ]);
          childAlive = (probe.stdout as String).trim().isNotEmpty;
          if (childAlive) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        }
        expect(childAlive, isFalse);
      } finally {
        if (childPid != null) {
          Process.killPid(childPid, ProcessSignal.sigkill);
        }
        directory.deleteSync(recursive: true);
      }
    },
  );

  test('real-flow audit records automated paste-safety closure', () {
    final audit = File(
      'docs/audits/ianvs-terminal-real-flow-2026-06-03/AUDIT.md',
    ).readAsStringSync();

    expect(audit, isNot(contains('missing current-run paste-safety capture')));
    expect(audit, contains('Automated Paste-Safety Closure'));
    expect(
      audit,
      contains(
        'cd example && flutter test test/shell/shell_screen_phase4_test.dart '
        '--plain-name "paste"',
      ),
    );
    expect(
      audit,
      contains('paste clipboard confirms multiline text before sending'),
    );
    expect(
      audit,
      contains('command-v read-only paste does not read clipboard'),
    );
  });

  test('real-flow audit records automated search close proof', () {
    final audit = File(
      'docs/audits/ianvs-terminal-real-flow-2026-06-03/AUDIT.md',
    ).readAsStringSync();

    expect(
      audit,
      isNot(
        contains(
          'keyboard escape/close behavior still needs manual or automated proof',
        ),
      ),
    );
    expect(audit, contains('Automated Search Closure Proof'));
    expect(
      audit,
      contains(
        'cd example && flutter test test/widget_test.dart '
        '--plain-name "shell search closes on Escape without terminal input"',
      ),
    );
    expect(
      audit,
      contains('shell search closes on Escape without terminal input'),
    );
  });

  test('comprehensive evaluation records automated split-search proof', () {
    final evaluation = File(
      'docs/audits/ianvs-terminal-comprehensive-evaluation-2026-06-03/'
      'EVALUATION.md',
    ).readAsStringSync();

    expect(
      evaluation,
      isNot(contains('split-pane overlay placement needs more proof')),
    );
    expect(evaluation, contains('split-pane overlay placement is automated'));
    expect(
      evaluation,
      contains('shell search overlay stays inside active split pane'),
    );
  });
}

final RegExp _markdownLinkPattern = RegExp(
  r'!?\[[^\]]*\]\((<[^>]+>|[^)\s]+)(?:\s+"[^"]*")?\)',
);

List<String> _stringList(Object? value) {
  if (value == null) {
    return const <String>[];
  }
  return (value as List<dynamic>).cast<String>();
}

bool _isExternalOrAnchorLink(String target) {
  if (target.startsWith('#')) {
    return true;
  }
  final uri = Uri.tryParse(target);
  return uri != null && uri.hasScheme;
}
