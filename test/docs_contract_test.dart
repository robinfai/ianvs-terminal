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
