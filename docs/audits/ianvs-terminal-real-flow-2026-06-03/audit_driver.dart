import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main() async {
  final outDir = Directory(
    '/Users/robinfai/personal/ianvs/ianvs-terminal/docs/audits/ianvs-terminal-real-flow-2026-06-03',
  );
  final serviceUrl = Platform.environment['VM_SERVICE_URL'];
  if (serviceUrl == null || serviceUrl.isEmpty) {
    stderr.writeln('VM_SERVICE_URL is required.');
    exitCode = 2;
    return;
  }

  final driver = await FlutterDriver.connect(dartVmServiceUrl: serviceUrl);
  final observations = <Map<String, Object?>>[];

  Future<void> shot(String name, String note) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final bytes = await driver.screenshot();
    final file = File('${outDir.path}/$name.png');
    await file.writeAsBytes(bytes);
    final snapshot = await driver.requestData('shell.acceptance');
    observations.add({
      'screenshot': file.uri.pathSegments.last,
      'note': note,
      'snapshot': jsonDecode(snapshot),
    });
  }

  Future<void> openMenu() async {
    await driver.tap(find.byValueKey('shell-chrome-menu'));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  Future<void> tapText(String text) async {
    await driver.tap(find.text(text));
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  try {
    await driver.waitUntilFirstFrameRasterized();
    await shot('04-driver-start', 'Driver app start with local shell surface.');

    await openMenu();
    await shot('05-command-menu', 'Command menu opened from chrome action.');

    await tapText('New tab');
    await shot('06-new-tab', 'New tab selected from command menu.');

    await openMenu();
    await tapText('Split right');
    await shot('07-split-right', 'Split right selected from command menu.');

    await openMenu();
    await tapText('Search terminal output');
    await shot('08-search-scrollback', 'Search scrollback opened from command menu.');

    await File('${outDir.path}/driver-observations.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(observations),
    );
  } finally {
    await driver.close();
  }
}
