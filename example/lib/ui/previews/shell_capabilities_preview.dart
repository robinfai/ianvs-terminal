import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../features/sessions/shell_capabilities_dialog.dart';
import '../../features/sessions/shell_connection_chain.dart';
import '../../features/sessions/shell_integration_capabilities.dart';
import '../app_ui.dart';

@Preview(name: 'Capabilities · Light', group: 'Sessions', size: Size(900, 850))
Widget shellCapabilitiesLightPreview() => _preview(Brightness.light);

@Preview(name: 'Capabilities · Dark', group: 'Sessions', size: Size(900, 850))
Widget shellCapabilitiesDarkPreview() => _preview(Brightness.dark);

@Preview(
  name: 'Capabilities · 390 px · 2× text',
  group: 'Sessions',
  size: Size(390, 700),
  textScaleFactor: 2,
)
Widget shellCapabilitiesCompactPreview() =>
    _preview(Brightness.light, platform: TargetPlatform.iOS);

Widget _preview(
  Brightness brightness, {
  TargetPlatform platform = TargetPlatform.macOS,
}) => MaterialApp(
  theme: buildIanvsTerminalTheme(brightness, platform: platform),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: ShellCapabilitiesDialog(
      sessionTitle: '生产环境',
      connectionChain: const [
        ShellConnectionHop(kind: ShellConnectionHopKind.localClient),
        ShellConnectionHop(
          kind: ShellConnectionHopKind.jump,
          host: 'bastion.example',
          user: 'ops',
          port: 2222,
        ),
        ShellConnectionHop(
          kind: ShellConnectionHopKind.sshShell,
          contextId: 'root',
          host: 'app.example',
          user: 'deploy',
          port: 22,
        ),
      ],
      capabilities: const ShellIntegrationCapabilities.pending(),
      onClose: () {},
    ),
  ),
);
