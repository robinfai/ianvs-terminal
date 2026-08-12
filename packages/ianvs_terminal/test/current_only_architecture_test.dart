import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final packageRoot = Directory.current.absolute;
  final repositoryRoot = packageRoot.parent.parent;

  test('terminal product exposes only the current runtime contracts', () {
    final production = _scanTerminalProduction(packageRoot);
    expect(
      production.violations,
      isEmpty,
      reason: production.violations.join('\n'),
    );
    expect(
      production.reachable,
      containsAll(<String>{
        'lib/ianvs_terminal.dart',
        'lib/src/config/terminal_config.dart',
        'lib/src/runtime/terminal_runtime_controller.dart',
        'lib/src/runtime/terminal_frame_transport_coordinator.dart',
        'lib/src/runtime/terminal_session_request_transport.dart',
      }),
    );

    final sources = <String, String>{
      'barrel': _read(packageRoot, 'lib/ianvs_terminal.dart'),
      'config': _read(packageRoot, 'lib/src/config/terminal_config.dart'),
      'runtime': _read(
        packageRoot,
        'lib/src/runtime/terminal_runtime_controller.dart',
      ),
      'transport': _read(
        packageRoot,
        'lib/src/runtime/terminal_frame_transport_coordinator.dart',
      ),
      'request': _read(
        packageRoot,
        'lib/src/runtime/terminal_session_request_transport.dart',
      ),
    };

    _requireTokens(sources['transport']!, <String>[
      'PtySessionFramePacketV1Backend',
      'takeFramePacketV1Protobuf',
      'TerminalFramePacketV1Decoder',
    ]);
    _requireTokens(sources['request']!, <String>[
      'PtySessionRequestV1Backend',
      'PtySessionRequestV1(',
      'PtySessionResponseV1.fromJsonString',
    ]);
    _requireTokens(sources['runtime']!, <String>[
      'PtySessionConfigV1Backend',
      'runtimeSignals',
      'beforeSessionCloseOnExitSignal',
      'allowClipboardCopyWithContext',
    ]);

    final forbiddenBySource = <String, List<String>>{
      'barrel': <String>['src/xterm/', 'terminal_wire_compatibility.dart'],
      'config': <String>['fromProfileJson'],
      'runtime': <String>[
        'TerminalFrameWireFormatPreference',
        'Stream<TerminalSessionEvent> get events',
        'get zmodemEvents',
        'get zmodemDeferredWriteFailures',
        'beforeSessionCloseOnExit,',
        'Future<bool> Function()? allowClipboardCopy',
        'Future<bool> Function()? allowClipboardPasteRequest',
      ],
      'transport': <String>[
        'TerminalJsonFrameDecoder',
        'TerminalProtobufFrameDecoder',
        'takeFrameDiffJson',
        'takeFrameDiffProtobuf',
      ],
      'request': <String>[
        'PtySessionJsonRequestBackend',
        'requestSessionJson',
        'supportsSessionRequestV1',
      ],
    };
    for (final entry in forbiddenBySource.entries) {
      _rejectTokens(entry.key, sources[entry.key]!, entry.value);
    }

    for (final path in <String>[
      'lib/src/xterm/terminal_api.dart',
      'lib/src/contracts/terminal_wire_compatibility.dart',
      'lib/src/transport/terminal_json_frame_decoder.dart',
      'lib/src/transport/terminal_protobuf_frame_decoder.dart',
    ]) {
      expect(
        File('${packageRoot.path}/$path').existsSync(),
        isFalse,
        reason: path,
      );
    }
  });

  test(
    'recursive current-only gate catches re-exported aliased helper tear-offs',
    () {
      final fixture = Directory.systemTemp.createTempSync(
        'ianvs_terminal_current_only_gate_',
      );
      addTearDown(() => fixture.deleteSync(recursive: true));
      _writeFixture(
        fixture,
        'lib/ianvs_terminal.dart',
        "export 'src/oddly_named_router.dart';\n",
      );
      _writeFixture(
        fixture,
        'lib/src/oddly_named_router.dart',
        "export 'nested/current_relay.dart';\n",
      );
      _writeFixture(
        fixture,
        'lib/src/nested/current_relay.dart',
        "import '../../support/arbitrary_bridge.dart' as routed;\n"
            'final Object? relay = routed.bridge;\n',
      );
      _writeFixture(
        fixture,
        'lib/support/arbitrary_bridge.dart',
        'Object? requestSessionJson;\n'
            'final Object? bridge = requestSessionJson;\n',
      );
      _writeFixture(
        fixture,
        'lib/src/dormant_unexported_file.dart',
        'Object? takeFrameDiffJson;\n'
            'final Object? dormant = takeFrameDiffJson;\n',
      );

      final report = _scanTerminalProduction(fixture);

      expect(
        report.reachable,
        containsAll(<String>{
          'lib/ianvs_terminal.dart',
          'lib/src/oddly_named_router.dart',
          'lib/src/nested/current_relay.dart',
          'lib/support/arbitrary_bridge.dart',
        }),
      );
      expect(
        report.violations.join('\n'),
        allOf(
          contains('lib/support/arbitrary_bridge.dart'),
          contains('requestSessionJson'),
          contains('lib/src/dormant_unexported_file.dart'),
          contains('takeFrameDiffJson'),
        ),
      );
    },
  );

  test('PTY and C ABI bind current symbols without predecessor routes', () {
    final pty = _read(
      repositoryRoot,
      'packages/ianvs_pty/lib/src/native_pty_backend.dart',
    );
    final header = _read(repositoryRoot, 'native/core/ianvs_core.h');
    final verifier = _read(repositoryRoot, 'tools/verify_native_contract.py');

    _requireTokens(pty, <String>[
      "'ianvs_session_create_v1'",
      "'ianvs_session_request_v1_json'",
      "'ianvs_session_take_frame_packet_v1_protobuf'",
      "'ianvs_session_poll_event_envelopes_json'",
      "'ianvs_session_graphic_asset_packet_v1_protobuf'",
    ]);
    _requireTokens(header, <String>[
      'ianvs_session_create_v1(',
      'ianvs_session_request_v1_json(',
      'ianvs_session_take_frame_packet_v1_protobuf(',
    ]);

    final forbidden = <String>[
      'PtySessionJsonRequestBackend',
      'supportsSessionConfigV1',
      'supportsSessionRequestV1',
      'supportsFramePacketV1',
      'ianvs_session_take_frame_diff_json',
      'ianvs_session_take_frame_diff_protobuf',
      'ianvs_session_request_json',
      'ianvs_session_poll_events_json',
      'ianvs_session_search_json',
      'ianvs_session_selection_text',
    ];
    _rejectTokens('ianvs_pty', pty, forbidden);
    _rejectTokens('C header', header, forbidden);
    _rejectTokens('ABI verifier', verifier, <String>['UNBOUND_LEGACY_EXPORTS']);
  });
}

const Set<String> _forbiddenProductionIdentifiers = <String>{
  'LegacyTerminalFrameDiffProtobuf',
  'TerminalFrameWireFormatPreference',
  'PtySessionJsonRequestBackend',
  'TerminalJsonFrameDecoder',
  'TerminalProtobufFrameDecoder',
  'takeFrameDiffJson',
  'takeFrameDiffProtobuf',
  'requestSessionJson',
  'supportsSessionConfigV1',
  'supportsSessionRequestV1',
  'supportsFramePacketV1',
  'fromProfileJson',
  'zmodemEvents',
  'zmodemDeferredWriteFailures',
  'beforeSessionCloseOnExit',
};

const Set<String> _forbiddenProductionFragments = <String>{
  'src/xterm/',
  'terminal_wire_compatibility.dart',
  'Stream<TerminalSessionEvent> get events',
  'Future<bool> Function()? allowClipboardCopy',
  'Future<bool> Function()? allowClipboardPasteRequest',
  'beforeSessionCloseOnExit,',
  'ianvs_session_take_frame_diff_json',
  'ianvs_session_take_frame_diff_protobuf',
  'ianvs_session_request_json',
  'ianvs_session_poll_events_json',
};

_ProductionScan _scanTerminalProduction(Directory packageRoot) {
  final lib = Directory('${packageRoot.path}/lib');
  final allSources = lib
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);
  final violations = <String>[];
  for (final file in allSources) {
    final relative = _relativeTo(packageRoot, file);
    final source = file.readAsStringSync();
    final result = parseString(
      content: source,
      path: file.path,
      throwIfDiagnostics: false,
    );
    for (final diagnostic in result.errors) {
      violations.add('$relative:${diagnostic.offset}: ${diagnostic.message}');
    }
    final visitor = _CurrentOnlyVisitor(relative, violations);
    result.unit.accept(visitor);
    for (final fragment in _forbiddenProductionFragments) {
      if (source.contains(fragment)) {
        violations.add('$relative: forbidden source fragment `$fragment`');
      }
    }
  }

  final entrypoint = File('${lib.path}/ianvs_terminal.dart');
  final reachable = <String>{};
  final pending = <File>[entrypoint];
  final libUri = lib.uri.path.endsWith('/')
      ? lib.uri
      : lib.uri.replace(path: '${lib.uri.path}/');
  while (pending.isNotEmpty) {
    final file = pending.removeLast();
    final relative = _relativeTo(packageRoot, file);
    if (!reachable.add(relative)) {
      continue;
    }
    if (!file.existsSync()) {
      violations.add('$relative: missing local production dependency');
      continue;
    }
    final unit = parseString(
      content: file.readAsStringSync(),
      path: file.path,
      throwIfDiagnostics: false,
    ).unit;
    for (final directive in unit.directives.whereType<UriBasedDirective>()) {
      final rawUri = directive.uri.stringValue;
      if (rawUri == null) {
        violations.add('$relative: non-literal production dependency URI');
        continue;
      }
      final dependency = _resolveLocalDependency(
        packageRoot: packageRoot,
        source: file,
        rawUri: rawUri,
      );
      if (dependency == null) {
        continue;
      }
      if (!dependency.uri.path.startsWith(libUri.path)) {
        violations.add('$relative: local dependency escapes lib: $rawUri');
        continue;
      }
      pending.add(dependency);
    }
  }
  return _ProductionScan(reachable: reachable, violations: violations..sort());
}

File? _resolveLocalDependency({
  required Directory packageRoot,
  required File source,
  required String rawUri,
}) {
  if (rawUri.startsWith('dart:')) {
    return null;
  }
  if (rawUri.startsWith('package:')) {
    const ownPrefix = 'package:ianvs_terminal/';
    if (!rawUri.startsWith(ownPrefix)) {
      return null;
    }
    return File.fromUri(
      Directory(
        '${packageRoot.path}/lib',
      ).uri.resolve(rawUri.substring(ownPrefix.length)),
    );
  }
  final parsed = Uri.tryParse(rawUri);
  if (parsed == null || parsed.hasScheme || rawUri.startsWith('/')) {
    return null;
  }
  return File.fromUri(source.uri.resolve(rawUri));
}

String _relativeTo(Directory root, File file) {
  final rootPath = root.absolute.path.endsWith(Platform.pathSeparator)
      ? root.absolute.path
      : '${root.absolute.path}${Platform.pathSeparator}';
  final absolute = file.absolute.path;
  return absolute.startsWith(rootPath)
      ? absolute.substring(rootPath.length)
      : absolute;
}

void _writeFixture(Directory root, String path, String source) {
  final file = File('${root.path}/$path');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(source);
}

final class _ProductionScan {
  const _ProductionScan({required this.reachable, required this.violations});

  final Set<String> reachable;
  final List<String> violations;
}

final class _CurrentOnlyVisitor extends RecursiveAstVisitor<void> {
  _CurrentOnlyVisitor(this.path, this.violations);

  final String path;
  final List<String> violations;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_forbiddenProductionIdentifiers.contains(node.name)) {
      violations.add(
        '$path:${node.offset}: forbidden predecessor identifier `${node.name}`',
      );
    }
    super.visitSimpleIdentifier(node);
  }
}

String _read(Directory root, String relativePath) =>
    File('${root.path}/$relativePath').readAsStringSync();

void _requireTokens(String source, List<String> tokens) {
  for (final token in tokens) {
    expect(source, contains(token), reason: 'missing current token: $token');
  }
}

void _rejectTokens(String label, String source, List<String> tokens) {
  for (final token in tokens) {
    expect(source, isNot(contains(token)), reason: '$label retains $token');
  }
}
