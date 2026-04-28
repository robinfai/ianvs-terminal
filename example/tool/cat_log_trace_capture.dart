import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutterm_pty/flutterm_pty.dart';

const double _devicePixelRatio = 2.0;
const double _logicalWidth = 1280;
const double _logicalHeight = 720;
const int _viewportRows = 40;
const int _viewportCols = 142;
const Duration _pollPause = Duration(milliseconds: 1);
const int _defaultTimeoutSeconds = 20;

Future<void> main(List<String> args) async {
  final options = _BenchmarkArgs.parse(args);
  final outDir = Directory(options.outDir);
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final fixtureFile = File(
    options.fixturePath ?? '${outDir.path}/cat-log-benchmark.fixture.log',
  );
  if (!fixtureFile.existsSync()) {
    fixtureFile.writeAsStringSync(_buildFixtureText());
  }

  final backend = NativePtyBackend.load();
  final sessionId = backend.createSession(_sessionConfigJson(fixtureFile));
  final traceFrames = <Map<String, Object?>>[];
  final timeout = Stopwatch()..start();
  final timeoutLimit = Duration(seconds: options.timeoutSeconds);
  var seenExit = false;
  var emptyPollsAfterExit = 0;
  var timedOut = false;
  Map<String, Object?> sessionDebugStats = const <String, Object?>{};

  try {
    backend.resizeSession(
      sessionId,
      cols: _viewportCols,
      rows: _viewportRows,
      pixelWidth: (_logicalWidth * _devicePixelRatio).round(),
      pixelHeight: (_logicalHeight * _devicePixelRatio).round(),
    );

    while (!seenExit || emptyPollsAfterExit < 3) {
      if (timeout.elapsed > timeoutLimit) {
        stderr.writeln(
          'cat log trace capture timed out after ${timeoutLimit.inSeconds}s',
        );
        timedOut = true;
        break;
      }

      final rawFrame = backend.takeFrameDiffJson(sessionId);
      if (rawFrame != null && rawFrame.isNotEmpty) {
        emptyPollsAfterExit = 0;
        final frameJson = (jsonDecode(rawFrame) as Map).cast<String, Object?>();
        final rawDebugStats = backend.takeFrameDebugStatsJson(sessionId);
        final debugStats = rawDebugStats == null || rawDebugStats.isEmpty
            ? const <String, Object?>{}
            : (jsonDecode(rawDebugStats) as Map).cast<String, Object?>();
        final rows = (frameJson['rows'] as List<dynamic>? ?? const []).length;
        final dirtyRanges =
            (frameJson['dirty_ranges'] as List<dynamic>? ?? const []).length;
        final traceFrame = <String, Object?>{
          'jsonBytes': utf8.encode(rawFrame).length,
          'rowCount': rows,
          'dirtyRangeCount': dirtyRanges,
          'frameKind': frameJson['frame_kind'] ?? 'snapshot',
          'viewportRowShift': frameJson['viewport_row_shift'] ?? 0,
          'rowsScanned': (debugStats['rows_scanned'] as num?)?.toInt() ?? 0,
          'rowsEmitted': (debugStats['rows_emitted'] as num?)?.toInt() ?? rows,
          'frameBuildMicros':
              (debugStats['frame_build_micros'] as num?)?.toInt() ?? 0,
          'stateLockWaitMicros':
              (debugStats['state_lock_wait_micros'] as num?)?.toInt() ?? 0,
          'frameExtractMicros':
              (debugStats['frame_extract_micros'] as num?)?.toInt() ?? 0,
          'jsonEncodeMicros':
              (debugStats['json_encode_micros'] as num?)?.toInt() ?? 0,
          'fullRepaint': debugStats['full_repaint'] as bool? ?? false,
          'snapshotFallbackReason':
              debugStats['snapshot_fallback_reason'] as String?,
        };
        if (options.includeRawFrames) {
          traceFrame['raw'] = rawFrame;
          traceFrame['rawDebugStats'] = rawDebugStats;
          traceFrame['debugStats'] = debugStats;
        }
        traceFrames.add(traceFrame);
      } else if (seenExit) {
        emptyPollsAfterExit += 1;
      }

      final events = backend.pollEvents(sessionId);
      for (final event in events) {
        if (event.kind == 'exit') {
          seenExit = true;
        }
      }

      if (rawFrame == null || rawFrame.isEmpty) {
        await Future<void>.delayed(_pollPause);
      }
    }
  } finally {
    final rawSessionDebugStats = backend.takeSessionDebugStatsJson(sessionId);
    if (rawSessionDebugStats != null && rawSessionDebugStats.isNotEmpty) {
      sessionDebugStats = (jsonDecode(rawSessionDebugStats) as Map)
          .cast<String, Object?>();
    }
    backend.closeSession(sessionId);
  }

  _writeTrace(
    outDir: outDir,
    fixtureFile: fixtureFile,
    traceFrames: traceFrames,
    includeRawFrames: options.includeRawFrames,
    timedOut: timedOut,
    elapsedMillis: timeout.elapsedMilliseconds,
    timeoutSeconds: options.timeoutSeconds,
    sessionDebugStats: sessionDebugStats,
  );
  if (timedOut) {
    exitCode = 1;
  }
}

void _writeTrace({
  required Directory outDir,
  required File fixtureFile,
  required List<Map<String, Object?>> traceFrames,
  required bool includeRawFrames,
  required bool timedOut,
  required int elapsedMillis,
  required int timeoutSeconds,
  required Map<String, Object?> sessionDebugStats,
}) {
  final traceFile = File('${outDir.path}/cat-log-benchmark.trace.json');
  traceFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'fixturePath': fixtureFile.path,
      'fixtureBytes': fixtureFile.existsSync() ? fixtureFile.lengthSync() : 0,
      'includeRawFrames': includeRawFrames,
      'timedOut': timedOut,
      'elapsedMillis': elapsedMillis,
      'timeoutSeconds': timeoutSeconds,
      'viewport': <String, Object?>{
        'logicalWidth': _logicalWidth,
        'logicalHeight': _logicalHeight,
        'devicePixelRatio': _devicePixelRatio,
        'rows': _viewportRows,
        'cols': _viewportCols,
        'pixelWidth': (_logicalWidth * _devicePixelRatio).round(),
        'pixelHeight': (_logicalHeight * _devicePixelRatio).round(),
      },
      'summary': <String, Object?>{
        'frameCount': traceFrames.length,
        'snapshotFrames': traceFrames
            .where((frame) => frame['frameKind'] == 'snapshot')
            .length,
        'deltaFrames': traceFrames
            .where((frame) => frame['frameKind'] == 'delta')
            .length,
        'shiftedFrames': traceFrames
            .where((frame) => (frame['viewportRowShift'] as int? ?? 0) != 0)
            .length,
        'rowsScanned': traceFrames.fold<int>(
          0,
          (sum, frame) => sum + ((frame['rowsScanned'] as int?) ?? 0),
        ),
        'rowsEmitted': traceFrames.fold<int>(
          0,
          (sum, frame) => sum + ((frame['rowsEmitted'] as int?) ?? 0),
        ),
        'totalJsonBytes': traceFrames.fold<int>(
          0,
          (sum, frame) => sum + (frame['jsonBytes'] as int),
        ),
        'sessionDebugStats': sessionDebugStats,
      },
      'frames': traceFrames,
    }),
  );
}

String _sessionConfigJson(File fixtureFile) {
  return jsonEncode(<String, Object?>{
    'id': 'cat-log-benchmark',
    'name': 'cat-log-benchmark',
    'launch': <String, Object?>{
      'program': '/bin/sh',
      'args': <String>[
        '-lc',
        'sleep 0.06; exec /bin/cat ${_shellQuote(fixtureFile.path)}',
      ],
      'env': const <String, String>{},
      'cwd': Directory.current.path,
    },
    'terminal': <String, Object?>{
      'emulation': 'xterm256',
      'scrollbackLines': 120000,
    },
    'appearance': <String, Object?>{
      'font': <String, Object?>{
        'family': 'JetBrainsMono Nerd Font',
        'fallback': const <String>[
          'Symbols Nerd Font Mono',
          '.AppleSymbolsFallback',
          'SF Pro Text',
        ],
        'size': 14,
        'lineHeight': 1.28,
      },
      'colors': const <String, Object?>{},
      'cursor': <String, Object?>{'shape': 'block', 'blink': true},
    },
    'interaction': const <String, Object?>{
      'copyOnSelect': false,
      'optionDragMode': 'block_selection',
    },
  });
}

String _shellQuote(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

String _buildFixtureText() {
  final buffer = StringBuffer();
  for (var index = 0; index < 6000; index += 1) {
    final level = switch (index % 5) {
      0 => 'INFO',
      1 => 'DEBUG',
      2 => 'WARN',
      3 => 'ERROR',
      _ => 'TRACE',
    };
    final service = switch (index % 4) {
      0 => 'gateway',
      1 => 'timeline',
      2 => 'session',
      _ => 'renderer',
    };
    final userId = 1000 + (index % 97);
    final latencyMs = 4 + (index % 240);
    final payloadBytes = 256 + (index % 8192);
    final minute = (index ~/ 60) % 60;
    final second = index % 60;
    buffer.writeln(
      '2026-04-27T12:${minute.toString().padLeft(2, '0')}:'
      '${second.toString().padLeft(2, '0')}.'
      '${(index % 1000).toString().padLeft(3, '0')}Z '
      'level=$level service=$service request_id=req-${index.toString().padLeft(6, '0')} '
      'user_id=$userId latency_ms=$latencyMs payload_bytes=$payloadBytes '
      'path=/api/v1/logs/${index % 13} message="cat log benchmark line $index" '
      'trace=tr-${(index * 17).toString().padLeft(8, '0')}',
    );
  }
  return buffer.toString();
}

class _BenchmarkArgs {
  const _BenchmarkArgs({
    required this.outDir,
    required this.fixturePath,
    required this.timeoutSeconds,
    required this.includeRawFrames,
  });

  final String outDir;
  final String? fixturePath;
  final int timeoutSeconds;
  final bool includeRawFrames;

  static _BenchmarkArgs parse(List<String> args) {
    String? outDir;
    String? fixturePath;
    var timeoutSeconds = _defaultTimeoutSeconds;
    var includeRawFrames = false;

    for (var index = 0; index < args.length; index += 1) {
      switch (args[index]) {
        case '--out-dir':
          index += 1;
          if (index >= args.length) {
            _usageAndExit('--out-dir requires a value');
          }
          outDir = args[index];
        case '--fixture':
          index += 1;
          if (index >= args.length) {
            _usageAndExit('--fixture requires a value');
          }
          fixturePath = args[index];
        case '--timeout-sec':
          index += 1;
          if (index >= args.length) {
            _usageAndExit('--timeout-sec requires a value');
          }
          timeoutSeconds = int.tryParse(args[index]) ?? _defaultTimeoutSeconds;
        case '--include-raw-frames':
          includeRawFrames = true;
        default:
          _usageAndExit('Unknown argument: ${args[index]}');
      }
    }

    if (outDir == null || outDir.isEmpty) {
      _usageAndExit('--out-dir is required');
    }
    if (!outDir.startsWith('/')) {
      _usageAndExit('--out-dir must be an absolute path');
    }
    if (fixturePath != null &&
        fixturePath.isNotEmpty &&
        !fixturePath.startsWith('/')) {
      _usageAndExit('--fixture must be an absolute path');
    }

    if (timeoutSeconds <= 0) {
      _usageAndExit('--timeout-sec must be greater than 0');
    }

    return _BenchmarkArgs(
      outDir: outDir,
      fixturePath: fixturePath,
      timeoutSeconds: timeoutSeconds,
      includeRawFrames: includeRawFrames,
    );
  }

  static Never _usageAndExit(String message) {
    stderr.writeln(message);
    stderr.writeln(
      'Usage: dart run tool/cat_log_trace_capture.dart '
      '--out-dir /absolute/output/dir '
      '[--fixture /absolute/fixture.log] [--timeout-sec 20] '
      '[--include-raw-frames]',
    );
    exit(64);
  }
}
