import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final packageRoot = Directory.current.absolute;

  test('standalone package exposes only current runtime contracts', () {
    final production = _scanProduction(packageRoot);
    expect(
      production.violations,
      isEmpty,
      reason: production.violations.join('\n'),
    );
    expect(
      production.reachable,
      containsAll(<String>{
        'lib/ianvs_terminal_core.dart',
        'lib/src/embed/terminal_session_handle.dart',
        'lib/src/embed/terminal_session_view.dart',
        'lib/src/embed/terminal_bottom_panel.dart',
        'lib/src/config/terminal_session_config_v1.dart',
        'lib/src/pty/native_pty_backend.dart',
        'lib/src/runtime/terminal_frame_transport_coordinator.dart',
        'lib/src/runtime/terminal_session_request_transport.dart',
      }),
    );

    final handle = _read(
      packageRoot,
      'lib/src/embed/terminal_session_handle.dart',
    );
    _requireTokens(handle, <String>[
      'Stream<TerminalRuntimeSignal> get runtimeSignals',
      'runtime.runtimeSignals.where',
      'signal.sessionEpoch == epoch',
    ]);
    _rejectTokens('session handle', handle, <String>[
      'StreamController<',
      'onTitleChange',
      'onExit(',
      'TerminalOptions',
    ]);

    for (final path in <String>[
      'lib/src/xterm/terminal_api.dart',
      'lib/src/contracts/terminal_wire_compatibility.dart',
      'lib/src/transport/terminal_json_frame_decoder.dart',
      'lib/src/transport/terminal_protobuf_frame_decoder.dart',
    ]) {
      expect(File('${packageRoot.path}/$path').existsSync(), isFalse);
    }
  });

  test('standalone PTY and native ABI contain only current symbols', () {
    final pty = _read(packageRoot, 'lib/src/pty/native_pty_backend.dart');
    final header = _read(packageRoot, 'native/core/ianvs_core.h');
    final manifest = _read(packageRoot, 'native/core/ianvs_core_abi_v1.json');

    for (final current in <String>[
      'ianvs_session_create_v1',
      'ianvs_session_request_v1_json',
      'ianvs_session_take_frame_packet_v1_protobuf',
      'ianvs_session_poll_event_envelopes_json',
    ]) {
      expect(pty, contains(current));
      expect(header, contains(current));
      expect(manifest, contains(current));
    }
    for (final predecessor in _forbiddenNativeSymbols) {
      _rejectTokens('PTY binding', pty, <String>[predecessor]);
      _rejectTokens('C header', header, <String>[predecessor]);
      _rejectTokens('ABI manifest', manifest, <String>[predecessor]);
    }
  });

  test('recursive gate catches arbitrary aliases and re-exports', () {
    final fixture = Directory.systemTemp.createTempSync(
      'ianvs_terminal_core_current_only_',
    );
    addTearDown(() => fixture.deleteSync(recursive: true));
    _writeFixture(
      fixture,
      'lib/ianvs_terminal_core.dart',
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

    final production = _scanProduction(fixture);
    expect(
      production.reachable,
      containsAll(<String>{
        'lib/ianvs_terminal_core.dart',
        'lib/src/oddly_named_router.dart',
        'lib/src/nested/current_relay.dart',
        'lib/support/arbitrary_bridge.dart',
      }),
    );
    expect(
      production.violations.join('\n'),
      allOf(
        contains('lib/support/arbitrary_bridge.dart'),
        contains('requestSessionJson'),
        contains('lib/src/dormant_unexported_file.dart'),
        contains('takeFrameDiffJson'),
      ),
    );
  });
}

const Set<String> _forbiddenIdentifiers = <String>{
  'LegacyTerminalFrameDiffProtobuf',
  'TerminalFrameWireFormatPreference',
  'PtySessionJsonRequestBackend',
  'PtySessionProtobufFrameBackend',
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
  'TerminalOptions',
  'TerminalAddon',
};

const Set<String> _forbiddenFragments = <String>{
  'src/xterm/',
  'terminal_wire_compatibility.dart',
  'Stream<TerminalSessionEvent> get events',
  'Future<bool> Function()? allowClipboardCopy',
  'Future<bool> Function()? allowClipboardPasteRequest',
  'ianvs_session_take_frame_diff_json',
  'ianvs_session_take_frame_diff_protobuf',
  'ianvs_session_request_json',
  'ianvs_session_poll_events_json',
};

const List<String> _forbiddenNativeSymbols = <String>[
  'ianvs_session_create(',
  'ianvs_replay_session_create(',
  'ianvs_session_resize(',
  'ianvs_session_search_json',
  'ianvs_session_selection_text',
  'ianvs_session_request_json',
  'ianvs_session_take_frame_diff_json',
  'ianvs_session_take_frame_diff_protobuf',
  'ianvs_session_poll_events_json',
];

_ProductionScan _scanProduction(Directory packageRoot) {
  final lib = Directory('${packageRoot.path}/lib');
  final violations = <String>[];
  final files = lib.existsSync()
      ? lib
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList(growable: false)
      : const <File>[];
  for (final file in files) {
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
    result.unit.accept(_CurrentOnlyVisitor(relative, violations));
    for (final fragment in _forbiddenFragments) {
      if (source.contains(fragment)) {
        violations.add('$relative: forbidden source fragment `$fragment`');
      }
    }
  }

  final reachable = <String>{};
  final pending = <File>[File('${lib.path}/ianvs_terminal_core.dart')];
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
      if (dependency != null) {
        pending.add(dependency);
      }
    }
  }
  return _ProductionScan(reachable, violations..sort());
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
    const ownPrefix = 'package:ianvs_terminal_core/';
    return rawUri.startsWith(ownPrefix)
        ? File.fromUri(
            Directory(
              '${packageRoot.path}/lib',
            ).uri.resolve(rawUri.substring(ownPrefix.length)),
          )
        : null;
  }
  final parsed = Uri.tryParse(rawUri);
  return parsed == null || parsed.hasScheme || rawUri.startsWith('/')
      ? null
      : File.fromUri(source.uri.resolve(rawUri));
}

final class _CurrentOnlyVisitor extends RecursiveAstVisitor<void> {
  _CurrentOnlyVisitor(this.path, this.violations);

  final String path;
  final List<String> violations;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_forbiddenIdentifiers.contains(node.name)) {
      violations.add(
        '$path:${node.offset}: forbidden predecessor identifier `${node.name}`',
      );
    }
    super.visitSimpleIdentifier(node);
  }
}

final class _ProductionScan {
  const _ProductionScan(this.reachable, this.violations);

  final Set<String> reachable;
  final List<String> violations;
}

String _relativeTo(Directory root, File file) {
  final prefix = root.absolute.path.endsWith(Platform.pathSeparator)
      ? root.absolute.path
      : '${root.absolute.path}${Platform.pathSeparator}';
  return file.absolute.path.startsWith(prefix)
      ? file.absolute.path.substring(prefix.length)
      : file.absolute.path;
}

void _writeFixture(Directory root, String relativePath, String source) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(source);
}

String _read(Directory root, String relativePath) =>
    File('${root.path}/$relativePath').readAsStringSync();

void _requireTokens(String source, Iterable<String> tokens) {
  for (final token in tokens) {
    expect(source, contains(token), reason: 'missing current token: $token');
  }
}

void _rejectTokens(String label, String source, Iterable<String> tokens) {
  for (final token in tokens) {
    expect(source, isNot(contains(token)), reason: '$label retains $token');
  }
}
