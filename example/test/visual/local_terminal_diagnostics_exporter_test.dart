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
}
