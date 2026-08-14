import 'package:app/data/services/portable_master_key.dart';
import 'package:app/features/security/master_key_management.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('copy requires confirmation and exports the portable key', (
    tester,
  ) async {
    final repository = PortableMasterKeyRepository(
      storage: _MemoryMasterKeyStorage(),
    );
    final expected = (await repository.readOrCreate()).portableValue;
    String? copied;

    await _pumpPanel(
      tester,
      repository,
      clipboardWriter: (value) async => copied = value,
    );
    await tester.tap(find.byKey(const Key('master-key-copy')));
    await tester.pumpAndSettle();

    expect(copied, isNull);
    expect(find.textContaining('Anyone with this key'), findsOneWidget);

    await tester.tap(find.byKey(const Key('master-key-confirm-copy')));
    await tester.pumpAndSettle();

    expect(copied, expected);
    expect(copied, startsWith('ianvs-key-v1.'));
    expect(find.byKey(const Key('master-key-status')), findsOneWidget);
  });

  testWidgets('a copied key can be pasted into an empty device', (
    tester,
  ) async {
    final source = PortableMasterKeyRepository(
      storage: _MemoryMasterKeyStorage(),
    );
    await source.readOrCreate();
    final encoded = await source.exportPortable();
    final destination = PortableMasterKeyRepository(
      storage: _MemoryMasterKeyStorage(),
    );

    await _pumpPanel(tester, destination);
    await tester.tap(find.byKey(const Key('master-key-import')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('master-key-import-field')),
      encoded,
    );
    await tester.tap(find.byKey(const Key('master-key-confirm-import')));
    await tester.pumpAndSettle();

    expect(await destination.exportPortable(), encoded);
    expect(find.text('Master key imported successfully.'), findsOneWidget);
  });

  testWidgets('pasting a different key does not replace local key material', (
    tester,
  ) async {
    final destination = PortableMasterKeyRepository(
      storage: _MemoryMasterKeyStorage(),
    );
    final installed = await destination.readOrCreate();
    final different = PortableMasterKey.fromSecret(
      'different-master-key-material',
    );

    await _pumpPanel(tester, destination);
    await tester.tap(find.byKey(const Key('master-key-import')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('master-key-import-field')),
      different.portableValue,
    );
    await tester.tap(find.byKey(const Key('master-key-confirm-import')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('master-key-error')), findsOneWidget);
    expect(await destination.exportPortable(), installed.portableValue);
  });
}

Future<void> _pumpPanel(
  WidgetTester tester,
  PortableMasterKeyRepository repository, {
  MasterKeyClipboardWriter? clipboardWriter,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildIanvsTerminalTheme(Brightness.dark),
      home: Scaffold(
        body: MasterKeyManagementPanel(
          repository: repository,
          clipboardWriter: clipboardWriter,
        ),
      ),
    ),
  );
  await tester.pump();
}

final class _MemoryMasterKeyStorage implements PortableMasterKeyStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String portableValue) async {
    value = portableValue;
  }
}
