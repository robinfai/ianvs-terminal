import 'dart:convert';
import 'dart:io';

import 'package:app/features/visual/local_terminal_diagnostics_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  test('diagnostics exporter writes the expected local bundle files', () async {
    final root = await Directory.systemTemp.createTemp(
      'ianvs terminal-diagnostics-exporter-test-',
    );
    addTearDown(() => root.delete(recursive: true));

    final directory = await LocalTerminalDiagnosticsExporter.write(
      directory: root,
      basename: 'diagnostics-user-host-cwd-safe',
      exports: const <TerminalDiagnosticsExport>[
        TerminalDiagnosticsExport(
          manifest: <String, Object?>{
            'schema_version': 'terminal-diagnostics-session-v1',
            'session_id': 1,
            'content_included': false,
          },
          resourceSamples: <Map<String, Object?>>[
            <String, Object?>{'timestamp_micros': 10, 'rss_bytes': 1024},
          ],
          terminalStats: <String, Object?>{
            'session': <String, Object?>{'bytes_read': 4},
          },
          events: <Map<String, Object?>>[
            <String, Object?>{'kind': 'started'},
          ],
          summary: <String, Object?>{
            'conclusion': 'insufficient-evidence',
            'evidence': <String>['valid_resource_samples=1'],
            'attribution_scores': <String, Object?>{'insufficient_evidence': 1},
            'next_steps': <String>['reproduce while active'],
          },
        ),
      ],
    );

    expect(File('${directory.path}/manifest.json').existsSync(), isTrue);
    expect(File('${directory.path}/sessions.json').existsSync(), isTrue);
    expect(
      File('${directory.path}/resource_samples.jsonl').existsSync(),
      isTrue,
    );
    expect(File('${directory.path}/terminal_stats.jsonl').existsSync(), isTrue);
    expect(File('${directory.path}/events.jsonl').existsSync(), isTrue);
    expect(File('${directory.path}/summary.md').existsSync(), isTrue);

    final manifest =
        jsonDecode(File('${directory.path}/manifest.json').readAsStringSync())
            as Map<String, Object?>;
    expect(manifest['schema_version'], 'terminal-diagnostics-bundle-v1');
    expect(manifest['session_count'], 1);
    expect(manifest['privacy'], containsPair('raw_command_included', false));

    final summary = File('${directory.path}/summary.md').readAsStringSync();
    expect(summary, contains('## 结论'));
    expect(summary, contains('## 隐私处理'));
  });

  test('diagnostics exporter does not overwrite an existing bundle', () async {
    final root = await Directory.systemTemp.createTemp(
      'ianvs terminal-diagnostics-exporter-collision-test-',
    );
    addTearDown(() => root.delete(recursive: true));
    final existing = Directory('${root.path}/diagnostics');
    await existing.create(recursive: true);
    await File('${existing.path}/manifest.json').writeAsString('previous');

    final directory = await LocalTerminalDiagnosticsExporter.write(
      directory: root,
      basename: 'diagnostics',
      exports: const <TerminalDiagnosticsExport>[
        TerminalDiagnosticsExport(
          manifest: <String, Object?>{'session_id': 1},
          resourceSamples: <Map<String, Object?>>[],
          terminalStats: <String, Object?>{},
          events: <Map<String, Object?>>[],
          summary: <String, Object?>{'conclusion': 'insufficient-evidence'},
        ),
      ],
    );

    expect(directory.path, '${root.path}/diagnostics-1');
    expect(File('${directory.path}/manifest.json').existsSync(), isTrue);
    expect(
      File('${existing.path}/manifest.json').readAsStringSync(),
      'previous',
    );
  });

  test('diagnostics exporter sanitizes unsafe bundle names', () async {
    final root = await Directory.systemTemp.createTemp(
      'ianvs terminal-diagnostics-exporter-name-test-',
    );
    addTearDown(() => root.delete(recursive: true));

    final directory = await LocalTerminalDiagnosticsExporter.write(
      directory: root,
      basename: '../alice@example.local:/Users/alice/project',
      exports: const <TerminalDiagnosticsExport>[
        TerminalDiagnosticsExport(
          manifest: <String, Object?>{'session_id': 1},
          resourceSamples: <Map<String, Object?>>[],
          terminalStats: <String, Object?>{},
          events: <Map<String, Object?>>[],
          summary: <String, Object?>{'conclusion': 'insufficient-evidence'},
        ),
      ],
    );

    expect(directory.parent.path, root.path);
    expect(directory.path, isNot(contains('/Users/alice')));
    expect(directory.path, isNot(contains('@')));
    expect(directory.path, isNot(contains(':')));
  });

  test('diagnostics exporter rejects parent directory bundle names', () async {
    final root = await Directory.systemTemp.createTemp(
      'ianvs terminal-diagnostics-exporter-dot-name-test-',
    );
    addTearDown(() => root.delete(recursive: true));

    final directory = await LocalTerminalDiagnosticsExporter.write(
      directory: root,
      basename: '..',
      exports: const <TerminalDiagnosticsExport>[
        TerminalDiagnosticsExport(
          manifest: <String, Object?>{'session_id': 1},
          resourceSamples: <Map<String, Object?>>[],
          terminalStats: <String, Object?>{},
          events: <Map<String, Object?>>[],
          summary: <String, Object?>{'conclusion': 'insufficient-evidence'},
        ),
      ],
    );

    final rootPath = await root.resolveSymbolicLinks();
    final directoryPath = await directory.resolveSymbolicLinks();
    expect(directoryPath, startsWith('$rootPath${Platform.pathSeparator}'));
    expect(directory.parent.path, root.path);
  });

  test('diagnostics exporter truncates long bundle names', () async {
    final root = await Directory.systemTemp.createTemp(
      'ianvs terminal-diagnostics-exporter-long-name-test-',
    );
    addTearDown(() => root.delete(recursive: true));

    final directory = await LocalTerminalDiagnosticsExporter.write(
      directory: root,
      basename: 'diagnostics-${List.filled(400, 'a').join()}',
      exports: const <TerminalDiagnosticsExport>[
        TerminalDiagnosticsExport(
          manifest: <String, Object?>{'session_id': 1},
          resourceSamples: <Map<String, Object?>>[],
          terminalStats: <String, Object?>{},
          events: <Map<String, Object?>>[],
          summary: <String, Object?>{'conclusion': 'insufficient-evidence'},
        ),
      ],
    );

    final bundleName = directory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    expect(bundleName.length, lessThanOrEqualTo(120));
    expect(directory.parent.path, root.path);
    expect(File('${directory.path}/manifest.json').existsSync(), isTrue);
  });

  test('diagnostics exporter skips non-string summary list entries', () async {
    final root = await Directory.systemTemp.createTemp(
      'ianvs terminal-diagnostics-exporter-summary-test-',
    );
    addTearDown(() => root.delete(recursive: true));

    final directory = await LocalTerminalDiagnosticsExporter.write(
      directory: root,
      basename: 'summary',
      exports: const <TerminalDiagnosticsExport>[
        TerminalDiagnosticsExport(
          manifest: <String, Object?>{'session_id': 1},
          resourceSamples: <Map<String, Object?>>[],
          terminalStats: <String, Object?>{},
          events: <Map<String, Object?>>[],
          summary: <String, Object?>{
            'conclusion': 'insufficient-evidence',
            'evidence': <Object?>[
              ' valid_resource_samples=1 ',
              <String, Object?>{'raw_command': 'ssh prod'},
              '   ',
            ],
            'next_steps': <Object?>[
              ' reproduce while active ',
              <String, Object?>{'raw_cwd': '/Users/alice/project'},
            ],
          },
        ),
      ],
    );

    final summary = File('${directory.path}/summary.md').readAsStringSync();

    expect(summary, contains('valid_resource_samples=1'));
    expect(summary, contains('reproduce while active'));
    expect(summary, isNot(contains('raw_command')));
    expect(summary, isNot(contains('raw_cwd')));
  });

  test('diagnostics exporter bounds oversized bundle payloads', () async {
    final root = await Directory.systemTemp.createTemp(
      'ianvs terminal-diagnostics-exporter-bounds-test-',
    );
    addTearDown(() => root.delete(recursive: true));

    final directory = await LocalTerminalDiagnosticsExporter.write(
      directory: root,
      basename: 'bounded',
      exports: <TerminalDiagnosticsExport>[
        TerminalDiagnosticsExport(
          manifest: <String, Object?>{'session_id': 1},
          resourceSamples: <Map<String, Object?>>[
            for (var index = 0; index < 65; index += 1)
              <String, Object?>{'timestamp_micros': index},
          ],
          terminalStats: <String, Object?>{
            'session': <String, Object?>{'bytes_read': 4},
          },
          events: <Map<String, Object?>>[
            for (var index = 0; index < 205; index += 1)
              <String, Object?>{'sequence': index},
          ],
          summary: <String, Object?>{
            'conclusion': ' ${'c' * 5000} ',
            'evidence': <Object?>[
              for (var index = 0; index < 24; index += 1)
                ' ${index.toString().padLeft(2, '0')}-${'e' * 700} ',
              <String, Object?>{'raw_command': 'ssh prod'},
            ],
            'next_steps': <Object?>[
              for (var index = 0; index < 24; index += 1)
                ' ${index.toString().padLeft(2, '0')}-${'n' * 700} ',
            ],
            'attribution_scores': <String, Object?>{
              'non_finite': double.nan,
              for (var index = 0; index < 40; index += 1)
                'score-$index': ' ${'s' * 5000} ',
            },
          },
        ),
      ],
    );

    final sessions =
        jsonDecode(File('${directory.path}/sessions.json').readAsStringSync())
            as List<Object?>;
    final session = sessions.single! as Map<String, Object?>;
    final summary = session['summary']! as Map<String, Object?>;
    final evidence = summary['evidence']! as List<Object?>;
    final nextSteps = summary['next_steps']! as List<Object?>;
    final scores = summary['attribution_scores']! as Map<String, Object?>;
    final resourceSamples = File(
      '${directory.path}/resource_samples.jsonl',
    ).readAsLinesSync();
    final events = File('${directory.path}/events.jsonl').readAsLinesSync();
    final markdown = File('${directory.path}/summary.md').readAsStringSync();

    expect(resourceSamples, hasLength(60));
    expect(events, hasLength(200));
    expect((summary['conclusion']! as String), hasLength(4096));
    expect(evidence, hasLength(20));
    expect(evidence.first! as String, hasLength(512));
    expect(nextSteps, hasLength(20));
    expect(nextSteps.first! as String, hasLength(512));
    expect(scores, hasLength(32));
    expect(scores.values.first! as String, hasLength(4096));
    expect(scores.containsKey('non_finite'), isFalse);
    expect(markdown, isNot(contains('raw_command')));
  });

  test('diagnostics exporter scans summary fields past invalids', () async {
    final root = await Directory.systemTemp.createTemp(
      'ianvs terminal-diagnostics-exporter-summary-scan-test-',
    );
    addTearDown(() => root.delete(recursive: true));

    final directory = await LocalTerminalDiagnosticsExporter.write(
      directory: root,
      basename: 'summary-scan',
      exports: <TerminalDiagnosticsExport>[
        TerminalDiagnosticsExport(
          manifest: <String, Object?>{'session_id': 1},
          resourceSamples: const <Map<String, Object?>>[],
          terminalStats: const <String, Object?>{},
          events: const <Map<String, Object?>>[],
          summary: <String, Object?>{
            for (var index = 0; index < 34; index += 1)
              'invalid_$index': double.nan,
            'conclusion': ' recovered ',
            'evidence': <Object?>[
              for (var index = 0; index < 22; index += 1)
                <String, Object?>{'raw_command': 'ssh prod-$index'},
              ' evidence recovered ',
            ],
            'attribution_scores': <Object?, Object?>{
              for (var index = 0; index < 34; index += 1) index: double.nan,
              ' score ': ' useful ',
            },
          },
        ),
      ],
    );

    final sessions =
        jsonDecode(File('${directory.path}/sessions.json').readAsStringSync())
            as List<Object?>;
    final session = sessions.single! as Map<String, Object?>;
    final summary = session['summary']! as Map<String, Object?>;
    final evidence = summary['evidence']! as List<Object?>;
    final scores = summary['attribution_scores']! as Map<String, Object?>;
    final markdown = File('${directory.path}/summary.md').readAsStringSync();

    expect(summary['conclusion'], 'recovered');
    expect(evidence, <String>['evidence recovered']);
    expect(scores, <String, Object?>{'score': 'useful'});
    expect(markdown, contains('evidence recovered'));
    expect(markdown, isNot(contains('raw_command')));
  });
}
