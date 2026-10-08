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
      failures.addAll(_unresolvedMarkdownLinks(source));
    }

    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test(
    'docs archive exceptions are closed legacy paths and scoped PRD assets',
    () {
      final inventory = File('test/fixtures/docs_legacy_inventory.txt')
          .readAsLinesSync()
          .where((line) => line.isNotEmpty && !line.startsWith('#'));
      final legacyFiles = inventory.toSet();
      expect(legacyFiles, hasLength(inventory.length));
      expect(legacyFiles, isNotEmpty);
      expect(legacyFiles.every(_isLegacyDocumentationPath), isTrue);

      final entries = Directory('docs').listSync(recursive: true);
      final files = entries
          .whereType<File>()
          .map((file) => file.path.replaceAll(r'\', '/'))
          .toSet();
      final directories = entries
          .whereType<Directory>()
          .map((directory) => directory.path.replaceAll(r'\', '/'))
          .toSet();
      final failures = _documentationArchiveViolations(
        files: files,
        directories: directories,
        legacyFiles: legacyFiles,
      );
      expect(failures, isEmpty, reason: failures.join('\n'));
      expect(
        legacyFiles.difference(files),
        isEmpty,
        reason:
            'The frozen inventory must not be used to delete existing material.',
      );
    },
  );

  group('documentation link gate', () {
    late Directory fixture;
    late File document;

    setUp(() {
      fixture = Directory.systemTemp.createTempSync('ianvs-docs-links-');
      document = File('${fixture.path}/README.md');
      File(
        '${fixture.path}/present.md',
      ).writeAsStringSync('# Existing document');
    });

    tearDown(() => fixture.deleteSync(recursive: true));

    test('ignores fenced Markdown examples but checks rendered links', () {
      document.writeAsStringSync('''
[Before](present.md)
```markdown
![Example](missing-example.png)
[Example log](missing-example.log)
```
[After](present.md)
''');
      expect(_unresolvedMarkdownLinks(document), isEmpty);
    });

    test('still rejects a missing link after a fenced example', () {
      document.writeAsStringSync('''
```markdown
[Placeholder](missing-example.md)
```
[Actual link](missing-document.md)
''');
      expect(_unresolvedMarkdownLinks(document), [
        '${document.path} -> missing-document.md',
      ]);
    });

    test('shorter or different fence markers cannot end a code example', () {
      document.writeAsStringSync('''
````markdown
```
[Still an example](missing-short-fence.md)
~~~
[Still an example](missing-other-fence.md)
````
   ~~~markdown
[Tilde example](missing-tilde-example.md)
   ~~~~
[Actual link](missing-after.md)
''');
      expect(_unresolvedMarkdownLinks(document), [
        '${document.path} -> missing-after.md',
      ]);
    });

    test('a delimiter followed by text does not close the example', () {
      document.writeAsStringSync('''
```markdown
``` trailing text
[Still an example](missing-example.md)
```
[Actual link](missing-after.md)
''');
      expect(_unresolvedMarkdownLinks(document), [
        '${document.path} -> missing-after.md',
      ]);
    });
  });

  group('documentation archive gate', () {
    const legacyFiles = {
      'docs/ai/REFERENCE.md',
      'docs/ai/evidence/old.log',
      'docs/design/previous/screen.png',
    };

    test('allows only the exact frozen legacy paths', () {
      expect(
        _documentationArchiveViolations(
          files: legacyFiles,
          directories: _parentDirectories(legacyFiles),
          legacyFiles: legacyFiles,
        ),
        isEmpty,
      );
      for (final added in [
        'docs/ai/evidence/new.log',
        'docs/ai/NEW_REPORT.md',
        'docs/design/previous/new.png',
      ]) {
        expect(
          _documentationArchiveViolations(
            files: {...legacyFiles, added},
            directories: _parentDirectories(legacyFiles),
            legacyFiles: legacyFiles,
          ),
          [added],
        );
      }
    });

    test('rejects new archive directories even when they are empty', () {
      for (final added in ['docs/audits', 'docs/design/new-review']) {
        expect(
          _documentationArchiveViolations(
            files: legacyFiles,
            directories: {..._parentDirectories(legacyFiles), added},
            legacyFiles: legacyFiles,
          ),
          [added],
        );
      }
    });

    test(
      'allows the PRD validators and evidence inside a case or shared run',
      () {
        const files = {
          ..._mobilePrdScripts,
          '$_mobilePrdRoot/evidence/manifest.json',
          '$_mobilePrdRoot/evidence/S1/S1-T05/run-one/assertions.log',
          '$_mobilePrdRoot/evidence/S2/S2-T01/run-two/after-01.png',
          '$_mobilePrdRoot/evidence/S3/S3-T08/run-three/flow.mp4',
          '$_mobilePrdRoot/evidence/S4/S4-T01/run-four/flow.mov',
          '$_mobilePrdRoot/evidence/shared/run-one/performance.trace',
          '$_mobilePrdRoot/evidence/shared/run-one/events.jsonl',
        };
        expect(
          _documentationArchiveViolations(
            files: files,
            directories: _parentDirectories(files),
            legacyFiles: const {},
          ),
          isEmpty,
        );
      },
    );

    test('the PRD exception does not allow unrelated scripts or archives', () {
      for (final added in [
        'docs/generic-run.log',
        'docs/evidence/new.png',
        'docs/product/another-prd/evidence/S1/S1-T01/run/after.png',
        '${_mobilePrdRoot}0/evidence/S1/S1-T01/run/flow.mp4',
        '$_mobilePrdRoot/scripts/new_helper.py',
        '$_mobilePrdRoot/scripts/validate_evidence.dart',
        '$_mobilePrdRoot/evidence/build.log',
        '$_mobilePrdRoot/evidence/S1/S2-T01/run/after.png',
        '$_mobilePrdRoot/evidence/S1/S1-T01/run/helper.py',
        '$_mobilePrdRoot/evidence/S1/S1-T01/run/bundle.zip',
        '$_mobilePrdRoot/evidence/S1/S1-T01/../escape.log',
        '$_mobilePrdRoot/evidence/shared/run/../escape.log',
      ]) {
        expect(
          _documentationArchiveViolations(
            files: {added},
            directories: const {},
            legacyFiles: const {},
          ),
          [added],
          reason: added,
        );
      }
    });
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

final RegExp _markdownFencePattern = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');

String _markdownOutsideFences(String content) {
  final prose = StringBuffer();
  String? fenceMarker;
  var fenceLength = 0;
  for (final line in const LineSplitter().convert(content)) {
    final match = _markdownFencePattern.firstMatch(line);
    if (fenceMarker != null) {
      if (match != null &&
          match.group(1)!.startsWith(fenceMarker) &&
          match.group(1)!.length >= fenceLength &&
          match.group(2)!.trim().isEmpty) {
        fenceMarker = null;
      }
      prose.writeln();
    } else if (match != null &&
        !(match.group(1)!.startsWith('`') && match.group(2)!.contains('`'))) {
      fenceMarker = match.group(1)![0];
      fenceLength = match.group(1)!.length;
      prose.writeln();
    } else {
      prose.writeln(line);
    }
  }
  return prose.toString();
}

List<String> _unresolvedMarkdownLinks(File source) {
  final failures = <String>[];
  final prose = _markdownOutsideFences(source.readAsStringSync());
  for (final match in _markdownLinkPattern.allMatches(prose)) {
    final rawTarget = match.group(1)!;
    final target = rawTarget.startsWith('<') && rawTarget.endsWith('>')
        ? rawTarget.substring(1, rawTarget.length - 1)
        : rawTarget;
    if (_isExternalOrAnchorLink(target)) continue;
    final path = Uri.decodeComponent(target.split('#').first.split('?').first);
    if (path.isEmpty) continue;
    final resolved = source.absolute.parent.uri.resolve(path).toFilePath();
    if (FileSystemEntity.typeSync(resolved) == FileSystemEntityType.notFound) {
      failures.add('${source.path} -> $target');
    }
  }
  return failures;
}

const _mobilePrdRoot = 'docs/product/mobile-block-ai-v1';
const _mobilePrdScripts = {
  '$_mobilePrdRoot/scripts/validate_evidence.py',
  '$_mobilePrdRoot/scripts/validate_shotlist.py',
  '$_mobilePrdRoot/scripts/test_validate_evidence.py',
  '$_mobilePrdRoot/scripts/test_validate_shotlist.py',
};
const _archiveRoots = {
  'docs/audits',
  'docs/evidence',
  'docs/reviews',
  'docs/design',
  'docs/retros',
  'docs/terminal-graphics-debug',
  'docs/ai',
  'docs/superpowers',
};
final _generatedDocumentationFile = RegExp(
  r'\.(log|trace|py|dart|ts|zip|mp4|mov|webm)$',
);
final _mobilePrdEvidenceFile = RegExp(
  '^$_mobilePrdRoot/evidence/'
  r'(?:S([1-4])/S\1-T[0-9]{2}/[A-Za-z0-9][A-Za-z0-9._-]*|'
  'shared/[A-Za-z0-9][A-Za-z0-9._-]*)/'
  r'[^/]+\.(?:png|json|jsonl|txt|log|trace|mp4|mov|webm)$',
);

bool _isLegacyDocumentationPath(String path) =>
    path.startsWith('docs/ai/') || path.startsWith('docs/design/');

bool _isArchivePath(String path) =>
    _archiveRoots.any((root) => path == root || path.startsWith('$root/'));

bool _isProductEvidencePath(String path) {
  final parts = path.split('/');
  return parts.length >= 4 &&
      parts[0] == 'docs' &&
      parts[1] == 'product' &&
      parts[3] == 'evidence';
}

bool _isMobilePrdEvidenceFile(String path) =>
    path == '$_mobilePrdRoot/evidence/manifest.json' ||
    (!path.split('/').any((part) => part == '.' || part == '..') &&
        _mobilePrdEvidenceFile.hasMatch(path));

Set<String> _parentDirectories(Iterable<String> files) => {
  for (final file in files)
    for (
      var slash = file.lastIndexOf('/');
      slash >= 0;
      slash = file.lastIndexOf('/', slash - 1)
    )
      file.substring(0, slash),
};

List<String> _documentationArchiveViolations({
  required Set<String> files,
  required Set<String> directories,
  required Set<String> legacyFiles,
}) {
  final legacyDirectories = _parentDirectories(legacyFiles);
  final failures = <String>{
    for (final directory in directories)
      if (_isArchivePath(directory) && !legacyDirectories.contains(directory))
        directory,
  };
  for (final path in files) {
    if (legacyFiles.contains(path)) continue;
    if (_isArchivePath(path)) {
      failures.add(path);
    } else if (_isProductEvidencePath(path)) {
      if (!_isMobilePrdEvidenceFile(path)) failures.add(path);
    } else if (_generatedDocumentationFile.hasMatch(path) &&
        !_mobilePrdScripts.contains(path)) {
      failures.add(path);
    }
  }
  return failures.toList()..sort();
}

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
