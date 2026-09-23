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
    final documents = <String>{
      'README.md',
      'ARCHITECTURE.md',
      'design-qa.md',
      'backend/README.md',
      'example/README.md',
      'packages/ianvs_pty/README.md',
      'packages/ianvs_terminal/README.md',
      'packages/ianvs_terminal_core/README.md',
      'tools/ssh_boundary_lab/README.md',
      'tools/zmodem_e2e/README.md',
      'tools/recording_bench/README.md',
      ...Directory('docs')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.md'))
          .map((file) => file.path),
    };
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

  test('docs contain current documentation instead of execution archives', () {
    for (final directory in <String>[
      'audits',
      'evidence',
      'reviews',
      'design',
      'retros',
      'terminal-graphics-debug',
      'ai',
      'superpowers',
    ]) {
      expect(Directory('docs/$directory').existsSync(), isFalse);
    }
    final generatedFiles = Directory('docs')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              RegExp(r'\.(log|trace|py|dart|ts|zip|mp4)$').hasMatch(file.path),
        )
        .map((file) => file.path);
    expect(generatedFiles, isEmpty);
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

    expect(
      matrix,
      contains(
        '| Area | Capability | Parse | State | Frame | Runtime | UI | '
        'Test layer | Current test / boundary |',
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
    expect(matrix, contains('resize_replay_skipped_truncated_count'));
    expect(knownIssues, contains('DIAGNOSTIC_EVENT_V1.md'));
    expect(manual, contains('Never record a missing prerequisite as `pass`'));
  });

  test('current testing guide points to interaction regressions', () {
    final guide = File('docs/TESTING.md').readAsStringSync();
    final pasteTests = File(
      'example/test/shell/shell_screen_phase4_test.dart',
    ).readAsStringSync();
    final searchTests = File(
      'example/test/widget_test.dart',
    ).readAsStringSync();

    expect(guide, contains('test/shell/shell_screen_phase4_test.dart'));
    expect(guide, contains('test/widget_test.dart'));
    expect(
      pasteTests,
      contains('OSC 52 prompt identifies inactive split pane'),
    );
    expect(
      pasteTests,
      contains('OSC 52 paste read labels empty clipboard preview'),
    );
    expect(
      pasteTests,
      contains('native paste confirms multiline text before sending'),
    );
    expect(
      pasteTests,
      contains('command-v read-only paste does not read clipboard'),
    );
    expect(
      searchTests,
      contains('shell search closes on Escape without terminal input'),
    );
    expect(
      searchTests,
      contains('shell search overlay stays inside active split pane'),
    );
  });

  test('terminal verification script runs docs contract tests', () {
    final script = File('tools/verify_flutter_terminal.sh').readAsStringSync();

    expect(script, contains('dart test test/docs_contract_test.dart'));
  });

  test('terminal verification script uses portable source scans', () {
    final script = File('tools/verify_flutter_terminal.sh').readAsStringSync();

    expect(
      script,
      isNot(contains(RegExp(r'(^|[|;&()\s])rg(?=\s)', multiLine: true))),
    );
    expect(script, contains('persistence_repository_composition.dart'));
    expect(
      script,
      contains('title: context.l10n.defaultsAppearance'),
      reason: 'the settings entry gate must follow the localized source',
    );
    expect(script, isNot(contains('grep -RFn -- "Defaults & appearance"')));
  });

  test('terminal verification scopes the vendored Clippy allowance', () {
    final script = File('tools/verify_flutter_terminal.sh').readAsStringSync();
    final vendorBlock = script.indexOf(r'cd "$VENDORED_TERMINAL_CORE_DIR"');
    final allowance = script.indexOf('-A clippy::uninlined_format_args');
    final nextBlock = script.indexOf(r'cd "$VENDORED_ZMODEM_DIR"');

    expect(vendorBlock, lessThan(allowance));
    expect(allowance, lessThan(nextBlock));
    expect('-A clippy::uninlined_format_args'.allMatches(script), hasLength(1));
  });

  test(
    'terminal verification script automatically discovers example tests',
    () {
      final script = File(
        'tools/verify_flutter_terminal.sh',
      ).readAsStringSync();

      expect(script, contains("find test -type f -name '*_test.dart'"));
      expect(script, contains(r'flutter test "${EXAMPLE_CI_TEST_TARGETS[@]}"'));
      expect(
        script,
        contains("! -path 'test/benchmarks/cat_log_benchmark_test.dart'"),
      );
      expect(
        script,
        isNot(contains('VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS')),
      );
      expect(script, contains('Every self-contained test'));
    },
  );

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
    expect(script, contains('Contents/MacOS/Trail'));
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
        helper.writeAsStringSync('''
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
