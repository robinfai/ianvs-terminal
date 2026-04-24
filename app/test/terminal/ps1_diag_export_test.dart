import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/reference_demo.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal/render_terminal_viewport.dart';
import 'package:app/features/terminal/terminal_painter_models.dart';
import 'package:app/ffi/flutterm_core.dart';

import '../support/fake_core_bindings.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_profile_repository.dart';

const String _configuredOutDir = String.fromEnvironment(
  'PS1_DIAG_OUT_DIR',
  defaultValue: '',
);
const String _configuredReference = String.fromEnvironment(
  'PS1_DIAG_REFERENCE',
  defaultValue: '',
);

void main() {
  testWidgets('ps1 diag export writes configured artifacts', (tester) async {
    final directory = _configuredOutDir.isEmpty
        ? Directory.systemTemp.createTempSync('ps1_diag_export_config_')
        : Directory(_configuredOutDir);
    final reference = _configuredReference.isEmpty
        ? null
        : File(_configuredReference);

    _configureDiagnosticView(tester);
    await _exportPs1Diagnostics(
      tester,
      outDir: directory,
      reference: reference,
    );

    expect(File('${directory.path}/ps1-current.png').existsSync(), isTrue);
    expect(
      File('${directory.path}/shell-surface-current.png').existsSync(),
      isTrue,
    );
    expect(File('${directory.path}/ps1-metrics.json').existsSync(), isTrue);
    if (reference != null) {
      expect(
        File('${directory.path}/ps1-comparison.json').existsSync(),
        isTrue,
      );
    }
  });

  testWidgets('ps1 diag export writes png and metrics json', (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'ps1_diag_export_basic_',
    );

    _configureDiagnosticView(tester);
    await _exportPs1Diagnostics(tester, outDir: directory);

    final promptFile = File('${directory.path}/ps1-current.png');
    final shellFile = File('${directory.path}/shell-surface-current.png');
    final metricsFile = File('${directory.path}/ps1-metrics.json');

    expect(promptFile.existsSync(), isTrue);
    expect(shellFile.existsSync(), isTrue);
    expect(metricsFile.existsSync(), isTrue);
    expect(promptFile.lengthSync(), greaterThan(0));
    expect(shellFile.lengthSync(), greaterThan(0));

    final metrics =
        jsonDecode(metricsFile.readAsStringSync()) as Map<String, dynamic>;
    expect(
      metrics.keys,
      containsAll(<String>[
        'devicePixelRatio',
        'cellSize',
        'rowTextMetrics',
        'promptBoundsLogical',
        'promptBoundsDevice',
        'cursorRect',
        'cells',
        'backgroundSpans',
      ]),
    );
    expect((metrics['cells'] as List<dynamic>), isNotEmpty);
    expect((metrics['backgroundSpans'] as List<dynamic>), isNotEmpty);
  });

  testWidgets('ps1 diag export keeps prompt inset and dark shell surface', (
    tester,
  ) async {
    _configureDiagnosticView(tester);
    final shellExport = await _captureFixtureShellExport(tester);

    try {
      const innerCanvasColor = Color(0xFF050608);
      final devicePixelRatio =
          shellExport.metrics['devicePixelRatio'] as double;
      int scale(double logicalValue) =>
          (logicalValue * devicePixelRatio).round();

      final innerCanvasPixel = await _readPixelColor(
        tester,
        shellExport.shellSurfaceImage,
        x: shellExport.shellSurfaceImage.width - scale(44),
        y: shellExport.shellSurfaceImage.height ~/ 2,
      );
      expect(innerCanvasPixel.toARGB32(), innerCanvasColor.toARGB32());

      final leftInsetPixel = await _readPixelColor(
        tester,
        shellExport.shellSurfaceImage,
        x: scale(16),
        y: scale(28),
      );
      expect(leftInsetPixel.toARGB32(), innerCanvasColor.toARGB32());

      final topInsetPixel = await _readPixelColor(
        tester,
        shellExport.shellSurfaceImage,
        x: scale(120),
        y: scale(10),
      );
      expect(topInsetPixel.toARGB32(), innerCanvasColor.toARGB32());

      final outerRightPixel = await _readPixelColor(
        tester,
        shellExport.shellSurfaceImage,
        x: shellExport.shellSurfaceImage.width - scale(12),
        y: shellExport.shellSurfaceImage.height ~/ 2,
      );
      expect(outerRightPixel.toARGB32(), innerCanvasColor.toARGB32());

      final promptPixel = await _readPixelColor(
        tester,
        shellExport.shellSurfaceImage,
        x: scale(120),
        y: scale(28),
      );
      expect(promptPixel.toARGB32(), isNot(innerCanvasColor.toARGB32()));
    } finally {
      shellExport.promptImage.dispose();
      shellExport.shellSurfaceImage.dispose();
    }
  });

  testWidgets('ps1 diag export writes diff when reference size matches', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'ps1_diag_export_diff_',
    );

    _configureDiagnosticView(tester);
    await _exportPs1Diagnostics(tester, outDir: directory);

    final referenceFile = File('${directory.path}/reference.png');
    referenceFile.writeAsBytesSync(
      File('${directory.path}/ps1-current.png').readAsBytesSync(),
    );

    await _exportPs1Diagnostics(
      tester,
      outDir: directory,
      reference: referenceFile,
    );

    final comparison =
        jsonDecode(
              File('${directory.path}/ps1-comparison.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(comparison['status'], 'ok');
    expect(File('${directory.path}/ps1-diff.png').existsSync(), isTrue);
    expect(
      File('${directory.path}/ps1-side-by-side.png').existsSync(),
      isFalse,
    );
  });

  testWidgets('ps1 diag export reports size mismatch without rescaling', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'ps1_diag_export_mismatch_',
    );
    final referenceFile = File('${directory.path}/reference-small.png');

    _configureDiagnosticView(tester);
    await _writeImage(
      tester,
      await _solidColorImage(
        tester,
        width: 16,
        height: 16,
        color: const Color(0xFF111827),
      ),
      referenceFile,
    );
    await _exportPs1Diagnostics(
      tester,
      outDir: directory,
      reference: referenceFile,
    );

    final comparison =
        jsonDecode(
              File('${directory.path}/ps1-comparison.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(comparison['status'], 'size_mismatch');
    expect(File('${directory.path}/ps1-diff.png').existsSync(), isFalse);
    expect(File('${directory.path}/ps1-side-by-side.png').existsSync(), isTrue);
  });
}

void _configureDiagnosticView(WidgetTester tester) {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = const Size(2400, 1600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _exportPs1Diagnostics(
  WidgetTester tester, {
  required Directory outDir,
  File? reference,
}) async {
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }
  _deleteIfExists(File('${outDir.path}/ps1-current.png'));
  _deleteIfExists(File('${outDir.path}/shell-surface-current.png'));
  _deleteIfExists(File('${outDir.path}/ps1-metrics.json'));
  _deleteIfExists(File('${outDir.path}/ps1-comparison.json'));
  _deleteIfExists(File('${outDir.path}/ps1-diff.png'));
  _deleteIfExists(File('${outDir.path}/ps1-side-by-side.png'));

  final shellExport = await _captureFixtureShellExport(tester);
  try {
    await _writeImage(
      tester,
      shellExport.promptImage,
      File('${outDir.path}/ps1-current.png'),
    );
    File('${outDir.path}/ps1-metrics.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(shellExport.metrics),
    );
    try {
      await _writeImage(
        tester,
        shellExport.shellSurfaceImage,
        File('${outDir.path}/shell-surface-current.png'),
      );
    } finally {
      shellExport.shellSurfaceImage.dispose();
    }

    if (reference != null) {
      await _writeComparisonArtifacts(
        tester: tester,
        currentPromptImage: shellExport.promptImage,
        reference: reference,
        outDir: outDir,
      );
    }
  } finally {
    shellExport.promptImage.dispose();
  }
}

Future<_ShellExport> _captureFixtureShellExport(WidgetTester tester) {
  return _captureShellExport(
    tester,
    coreClient: TerminalCoreClient(
      _FrameSeededCoreBindings(_frameDiffToJson(referenceDemoPs1Frame)),
    ),
  );
}

Future<_ShellExport> _captureShellExport(
  WidgetTester tester, {
  required TerminalCoreClient coreClient,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(coreClient),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: ThemeMode.dark,
        home: const ShellScreen(),
      ),
    ),
  );
  await tester.pump();
  await _waitForPromptReady(tester);

  final container = ProviderScope.containerOf(
    tester.element(find.byType(ShellScreen)),
  );
  final renderObject = tester.allRenderObjects
      .whereType<RenderTerminalViewport>()
      .last;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('shell-terminal-surface')),
  );
  final devicePixelRatio = tester.view.devicePixelRatio;
  final cursorRect = renderObject.debugCursorRect!;
  final promptRow = (cursorRect.top / renderObject.debugCellSize.height)
      .round();
  final promptBoundsLogical = Rect.fromLTWH(
    0,
    cursorRect.top,
    cursorRect.left,
    renderObject.debugCellSize.height,
  );
  final promptBoundsDevice = _rectToDevice(
    promptBoundsLogical,
    devicePixelRatio,
  );
  final shellSurfaceImage = await _runUiAsync(
    tester,
    () => boundary.toImage(pixelRatio: devicePixelRatio),
  );
  try {
    final promptImage = await _cropImage(
      tester,
      shellSurfaceImage,
      promptBoundsDevice,
    );
    final metrics = <String, dynamic>{
      'captureMode': 'fixture',
      'devicePixelRatio': devicePixelRatio,
      'cellSize': _sizeToJson(renderObject.debugCellSize),
      'rowTextMetrics': _rowTextMetricsToJson(renderObject.debugRowTextMetrics),
      'promptBoundsLogical': _rectToJson(promptBoundsLogical),
      'promptBoundsDevice': _rectToJson(promptBoundsDevice),
      'cursorRect': _rectToJson(cursorRect),
      'promptRow': promptRow,
      'cells': renderObject
          .debugResolvedCellsForRow(promptRow)
          .map<Map<String, dynamic>>(
            (cell) => <String, dynamic>{
              'column': cell.column,
              'text': cell.text,
              'glyphClass': cell.glyphClass.name,
              'glyphBaseline': cell.glyphBaseline,
              'baselineY': cell.baselineY,
              'drawOffset': _offsetToJson(cell.drawOffset),
              'placementRect': _rectToJson(cell.placementRect),
            },
          )
          .toList(),
      'backgroundSpans': renderObject
          .debugBackgroundSpansForRow(promptRow)
          .map<Map<String, dynamic>>(
            (span) => <String, dynamic>{
              'startColumn': span.startColumn,
              'endColumn': span.endColumn,
              'background': _colorToHex(span.background),
              'rect': _rectToJson(span.rect),
            },
          )
          .toList(),
    };
    return _ShellExport(
      promptImage: promptImage,
      shellSurfaceImage: shellSurfaceImage,
      metrics: metrics,
    );
  } finally {
    final tabs = List.of(container.read(sessionControllerProvider).tabs);
    final notifier = container.read(sessionControllerProvider.notifier);
    for (final tab in tabs) {
      notifier.closeSession(tab.sessionId);
    }
  }
}

Future<void> _waitForPromptReady(WidgetTester tester) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 32));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 32));
    });
    await tester.pump();

    final renderObjects = tester.allRenderObjects
        .whereType<RenderTerminalViewport>();
    if (renderObjects.isEmpty) {
      continue;
    }
    final renderObject = renderObjects.last;
    final cursorRect = renderObject.debugCursorRect;
    if (cursorRect == null || cursorRect.left <= 0) {
      continue;
    }
    final promptRow = (cursorRect.top / renderObject.debugCellSize.height)
        .round();
    if (renderObject.debugResolvedCellsForRow(promptRow).isNotEmpty) {
      return;
    }
  }
  throw StateError('Timed out waiting for a shell prompt to render.');
}

Future<void> _writeComparisonArtifacts({
  required WidgetTester tester,
  required ui.Image currentPromptImage,
  required File reference,
  required Directory outDir,
}) async {
  final referenceImage = await _decodePng(tester, reference);
  try {
    final comparisonFile = File('${outDir.path}/ps1-comparison.json');
    if (currentPromptImage.width != referenceImage.width ||
        currentPromptImage.height != referenceImage.height) {
      final sideBySide = await _composeSideBySide(
        tester,
        currentPromptImage,
        referenceImage,
      );
      try {
        await _writeImage(
          tester,
          sideBySide,
          File('${outDir.path}/ps1-side-by-side.png'),
        );
      } finally {
        sideBySide.dispose();
      }
      comparisonFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
          'status': 'size_mismatch',
          'currentSize': <String, int>{
            'width': currentPromptImage.width,
            'height': currentPromptImage.height,
          },
          'referenceSize': <String, int>{
            'width': referenceImage.width,
            'height': referenceImage.height,
          },
        }),
      );
      return;
    }

    final comparison = await _buildDiffReport(
      tester,
      currentPromptImage,
      referenceImage,
    );
    try {
      await _writeImage(
        tester,
        comparison.diffImage,
        File('${outDir.path}/ps1-diff.png'),
      );
    } finally {
      comparison.diffImage.dispose();
    }
    comparisonFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(comparison.report),
    );
  } finally {
    referenceImage.dispose();
  }
}

Future<void> _writeImage(WidgetTester tester, ui.Image image, File file) async {
  final byteData = await _runUiAsync(
    tester,
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  if (byteData == null) {
    throw StateError('Failed to encode image bytes for ${file.path}');
  }
  file.writeAsBytesSync(byteData.buffer.asUint8List(), flush: true);
}

Future<ui.Image> _decodePng(WidgetTester tester, File file) async {
  final codec = await _runUiAsync(
    tester,
    () => ui.instantiateImageCodec(file.readAsBytesSync()),
  );
  try {
    final frame = await _runUiAsync(tester, codec.getNextFrame);
    return frame.image;
  } finally {
    codec.dispose();
  }
}

Future<ui.Image> _cropImage(
  WidgetTester tester,
  ui.Image image,
  Rect pixelRect,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final outputSize = Size(pixelRect.width, pixelRect.height);
  canvas.drawImageRect(
    image,
    pixelRect,
    Offset.zero & outputSize,
    Paint()..isAntiAlias = false,
  );
  final picture = recorder.endRecording();
  try {
    return _runUiAsync(
      tester,
      () => picture.toImage(pixelRect.width.round(), pixelRect.height.round()),
    );
  } finally {
    picture.dispose();
  }
}

Future<ui.Image> _composeSideBySide(
  WidgetTester tester,
  ui.Image current,
  ui.Image reference,
) async {
  final width = current.width + reference.width;
  final height = current.height > reference.height
      ? current.height
      : reference.height;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF000000),
  );
  canvas.drawImage(current, Offset.zero, Paint());
  canvas.drawImage(reference, Offset(current.width.toDouble(), 0), Paint());
  final picture = recorder.endRecording();
  try {
    return _runUiAsync(tester, () => picture.toImage(width, height));
  } finally {
    picture.dispose();
  }
}

Future<_DiffReport> _buildDiffReport(
  WidgetTester tester,
  ui.Image current,
  ui.Image reference,
) async {
  final currentBytes = await _runUiAsync(
    tester,
    () => current.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  final referenceBytes = await _runUiAsync(
    tester,
    () => reference.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  if (currentBytes == null || referenceBytes == null) {
    throw StateError('Failed to decode image bytes for comparison.');
  }

  final currentPixels = currentBytes.buffer.asUint8List();
  final referencePixels = referenceBytes.buffer.asUint8List();
  var differingPixels = 0;
  var maxChannelDelta = 0;
  var totalChannelDelta = 0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  for (var index = 0; index < currentPixels.length; index += 4) {
    final pixelIndex = index ~/ 4;
    final x = pixelIndex % current.width;
    final y = pixelIndex ~/ current.width;
    final deltaR = (currentPixels[index] - referencePixels[index]).abs();
    final deltaG = (currentPixels[index + 1] - referencePixels[index + 1])
        .abs();
    final deltaB = (currentPixels[index + 2] - referencePixels[index + 2])
        .abs();
    final deltaA = (currentPixels[index + 3] - referencePixels[index + 3])
        .abs();
    final pixelDelta = <int>[deltaR, deltaG, deltaB, deltaA].reduce(mathMax);
    if (pixelDelta > 0) {
      differingPixels += 1;
    }
    maxChannelDelta = mathMax(maxChannelDelta, pixelDelta);
    totalChannelDelta += deltaR + deltaG + deltaB + deltaA;
    if (pixelDelta > 0) {
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
        Paint()
          ..color = Color.fromARGB(255, pixelDelta, pixelDelta, pixelDelta),
      );
    }
  }

  final picture = recorder.endRecording();
  final diffImage = await _runUiAsync(
    tester,
    () => picture.toImage(current.width, current.height),
  );
  picture.dispose();
  final totalPixels = current.width * current.height;
  return _DiffReport(
    diffImage: diffImage,
    report: <String, dynamic>{
      'status': 'ok',
      'currentSize': <String, int>{
        'width': current.width,
        'height': current.height,
      },
      'referenceSize': <String, int>{
        'width': reference.width,
        'height': reference.height,
      },
      'pixelCount': totalPixels,
      'differingPixels': differingPixels,
      'differingPixelRatio': totalPixels == 0
          ? 0
          : differingPixels / totalPixels,
      'maxChannelDelta': maxChannelDelta,
      'meanChannelDelta': totalPixels == 0
          ? 0
          : totalChannelDelta / (totalPixels * 4),
    },
  );
}

Future<ui.Image> _solidColorImage(
  WidgetTester tester, {
  required int width,
  required int height,
  required Color color,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  try {
    return _runUiAsync(tester, () => picture.toImage(width, height));
  } finally {
    picture.dispose();
  }
}

void _deleteIfExists(File file) {
  if (file.existsSync()) {
    file.deleteSync();
  }
}

Map<String, dynamic> _sizeToJson(Size size) => <String, dynamic>{
  'width': size.width,
  'height': size.height,
};

Map<String, dynamic> _offsetToJson(Offset offset) => <String, dynamic>{
  'dx': offset.dx,
  'dy': offset.dy,
};

Map<String, dynamic> _rectToJson(Rect rect) => <String, dynamic>{
  'left': rect.left,
  'top': rect.top,
  'right': rect.right,
  'bottom': rect.bottom,
  'width': rect.width,
  'height': rect.height,
};

Map<String, dynamic> _rowTextMetricsToJson(TerminalRowTextMetrics metrics) =>
    <String, dynamic>{
      'alphabeticBaseline': metrics.alphabeticBaseline,
      'ascent': metrics.ascent,
      'descent': metrics.descent,
      'textTopInset': metrics.textTopInset,
      'textHeight': metrics.textHeight,
    };

Rect _rectToDevice(Rect logicalRect, double devicePixelRatio) => Rect.fromLTRB(
  (logicalRect.left * devicePixelRatio).roundToDouble(),
  (logicalRect.top * devicePixelRatio).roundToDouble(),
  (logicalRect.right * devicePixelRatio).roundToDouble(),
  (logicalRect.bottom * devicePixelRatio).roundToDouble(),
);

String _colorToHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}';

Future<Color> _readPixelColor(
  WidgetTester tester,
  ui.Image image, {
  required int x,
  required int y,
}) async {
  final byteData = await _runUiAsync(
    tester,
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  if (byteData == null) {
    throw StateError('Failed to read image bytes.');
  }
  final bytes = byteData.buffer.asUint8List();
  final pixelOffset = ((y * image.width) + x) * 4;
  return Color.fromARGB(
    bytes[pixelOffset + 3],
    bytes[pixelOffset],
    bytes[pixelOffset + 1],
    bytes[pixelOffset + 2],
  );
}

int mathMax(int left, int right) => left > right ? left : right;

Future<T> _runUiAsync<T>(
  WidgetTester tester,
  Future<T> Function() operation,
) async {
  final result = await tester.runAsync(operation);
  return result as T;
}

Map<String, Object?> _frameDiffToJson(TerminalFrameDiff frame) {
  return <String, Object?>{
    'rows': frame.rows
        .map<Map<String, Object?>>(
          (row) => <String, Object?>{
            'index': row.index,
            'text': row.text,
            'wrapped': row.wrapped,
            'style_runs': row.styleRuns
                .map<Map<String, Object?>>(
                  (run) => <String, Object?>{
                    'start': run.start,
                    'end': run.end,
                    'foreground': run.foreground == null
                        ? null
                        : _colorToHex(run.foreground!),
                    'background': run.background == null
                        ? null
                        : _colorToHex(run.background!),
                    'bold': run.bold,
                    'dim': run.dim,
                    'italic': run.italic,
                    'underline': run.underline,
                    'blink': run.blink,
                    'inverse': run.inverse,
                  },
                )
                .toList(),
          },
        )
        .toList(),
    'cursor': <String, Object?>{
      'row': frame.cursor.row,
      'col': frame.cursor.col,
      'visible': frame.cursor.visible,
    },
    'selection': null,
    'viewport_rows': frame.viewportRows,
    'viewport_cols': frame.viewportCols,
    'dirty_ranges': frame.dirtyRanges
        .map<Map<String, Object?>>(
          (range) => <String, Object?>{'start': range.start, 'end': range.end},
        )
        .toList(),
    'scrollback_offset': frame.scrollbackOffset,
    'scrollback_max_offset': frame.scrollbackMaxOffset,
    'modes': <String, Object?>{
      'application_cursor': frame.modes.applicationCursor,
      'application_keypad': frame.modes.applicationKeypad,
      'insert_mode': frame.modes.insertMode,
      'origin_mode': frame.modes.originMode,
      'line_feed_new_line_mode': frame.modes.lineFeedNewLineMode,
      'hide_cursor': frame.modes.hideCursor,
      'bracketed_paste': frame.modes.bracketedPaste,
      'focus_tracking': frame.modes.focusTracking,
      'char_protected': frame.modes.charProtected,
      'mouse_mode': frame.modes.mouseMode,
      'mouse_encoding': frame.modes.mouseEncoding,
    },
    'window_title': frame.windowTitle,
    'window_icon_name': frame.windowIconName,
  };
}

class _FrameSeededCoreBindings extends FakeCoreBindings {
  _FrameSeededCoreBindings(this._frame);

  final Map<String, Object?> _frame;

  @override
  int sessionCreate(ffi.Pointer<Utf8> profileJson) {
    final sessionId = super.sessionCreate(profileJson);
    setFrame(sessionId, _frame);
    return sessionId;
  }
}

class _ShellExport {
  const _ShellExport({
    required this.promptImage,
    required this.shellSurfaceImage,
    required this.metrics,
  });

  final ui.Image promptImage;
  final ui.Image shellSurfaceImage;
  final Map<String, dynamic> metrics;
}

class _DiffReport {
  const _DiffReport({required this.diffImage, required this.report});

  final ui.Image diffImage;
  final Map<String, dynamic> report;
}
