import 'dart:io';

import 'package:test/test.dart';

void main() {
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
