import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

// Repository contract gates intentionally exercise the canonical pure-Dart
// decoders without importing a Flutter barrel or a generated standalone copy.
// ignore: avoid_relative_lib_imports
import '../packages/ianvs_pty/lib/src/pty_runtime_capabilities.dart';
// Exercise the canonical config decoder under the same repository-only gate.
// ignore: avoid_relative_lib_imports
import '../packages/ianvs_terminal/lib/src/config/terminal_session_config_v1.dart';

void main() {
  test('runtime wire inventory contains exactly the exported ABI', () {
    final manifest =
        jsonDecode(
              File('native/core/ianvs_core_abi_v1.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    final functions = manifest['functions']! as Map<String, Object?>;
    final inventory = File(
      'docs/protocols/RUNTIME_WIRE_INVENTORY.md',
    ).readAsStringSync();
    final symbols = RegExp(
      r'^\| `(ianvs_\w+)` \|',
      multiLine: true,
    ).allMatches(inventory).map((match) => match.group(1)!).toList();

    expect(symbols, unorderedEquals(functions.keys));
    expect(symbols.toSet(), hasLength(symbols.length));
  });

  test('documented capabilities match the native feature declaration', () {
    final raw = _jsonExample('RUNTIME_CAPABILITIES_V1.md');
    final capabilities = PtyRuntimeCapabilities.fromJsonString(raw);
    final source = File(
      'native/core/src/runtime_contract.rs',
    ).readAsStringSync();
    final featureBlock = RegExp(
      r'const FEATURES: &\[&str\] = &\[(.*?)\];',
      dotAll: true,
    ).firstMatch(source)!.group(1)!;
    final features = RegExp(
      '"([^"]+)"',
    ).allMatches(featureBlock).map((match) => match.group(1)!).toList();

    // The documentation labels this as the macOS/Linux manifest, where all
    // declared features are available, including both ZMODEM capabilities.
    expect(capabilities.features, features);
    expect(capabilities.frameSchemaVersions, ['terminal-frame-diff-v1']);
    expect(capabilities.recordingSchemaVersions, [1]);
  });

  test(
    'documented SessionConfig is accepted by the current strict decoder',
    () {
      final raw = _jsonExample('SESSION_CONFIG_V1.md');
      final config = TerminalSessionConfigV1.fromJsonString(raw);

      expect(config.toJson(), jsonDecode(raw));
    },
  );
}

String _jsonExample(String document) {
  final source = File('docs/protocols/$document').readAsStringSync();
  final match = RegExp(r'```json\n(.*?)\n```', dotAll: true).firstMatch(source);
  expect(match, isNotNull, reason: '$document must contain a JSON example');
  return match!.group(1)!;
}
