import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../app_ui.dart';

@Preview(name: 'Notifications · Light', group: 'Feedback', size: Size(960, 640))
Widget notificationsLightPreview() => _preview(Brightness.light);

@Preview(name: 'Notifications · Dark', group: 'Feedback', size: Size(960, 640))
Widget notificationsDarkPreview() => _preview(Brightness.dark);

@Preview(
  name: 'Notifications · 320 px · 2× text',
  group: 'Feedback',
  size: Size(320, 400),
)
Widget notificationsLargeTextPreview() => _preview(Brightness.light, scale: 2);

Widget _preview(Brightness brightness, {double scale = 1}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildIanvsTerminalTheme(brightness, platform: TargetPlatform.macOS),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: AppNotificationHost(topInset: 44, child: child!),
  ),
  home: const _PreviewTerminal(),
);

class _PreviewTerminal extends StatefulWidget {
  const _PreviewTerminal();

  @override
  State<_PreviewTerminal> createState() => _PreviewTerminalState();
}

class _PreviewTerminalState extends State<_PreviewTerminal> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showExamples();
    });
  }

  void _showExamples() {
    AppNotifications.show(
      context,
      SnackBar(
        content: const Text('Recording saved: local-session.trail'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: 'Reveal', onPressed: () {}),
      ),
    );
    AppNotifications.show(
      context,
      const SnackBar(
        content: Text('Connection settings saved'),
        duration: Duration(seconds: 3),
      ),
    );
    _copy();
  }

  void _copy() => AppNotifications.show(
    context,
    const SnackBar(content: Text('Copied'), duration: Duration(seconds: 2)),
    icon: Icons.content_copy,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTheme;
    return Scaffold(
      backgroundColor: tokens.terminalSurface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPanel(
            tone: AppPanelTone.chrome,
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
            child: Wrap(
              spacing: tokens.spacing.lg,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Trail  /  Local terminal'),
                TextButton(onPressed: _copy, child: const Text('Copy')),
                TextButton(
                  onPressed: _showExamples,
                  child: const Text('Notify'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(tokens.spacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(r'$ git status'),
                  SizedBox(height: tokens.spacing.md),
                  const Text('On branch main\nWorking tree clean'),
                  const Spacer(),
                  TextField(
                    decoration: const InputDecoration(
                      prefixText: r'$ ',
                      hintText: 'Type a command…',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
