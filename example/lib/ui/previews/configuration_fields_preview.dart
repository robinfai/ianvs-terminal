import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../components/app_configuration_field.dart';
import '../components/app_dropdown_form_field.dart';
import '../foundation/app_theme.dart';
import '../foundation/app_theme_tokens.dart';

@Preview(
  name: 'Configuration fields · Light desktop',
  group: 'Configuration',
  size: Size(760, 360),
)
Widget configurationFieldsLightDesktopPreview() {
  return const _ConfigurationFieldsPreview(brightness: Brightness.light);
}

@Preview(
  name: 'Configuration fields · Dark desktop',
  group: 'Configuration',
  size: Size(760, 360),
)
Widget configurationFieldsDarkDesktopPreview() {
  return const _ConfigurationFieldsPreview(brightness: Brightness.dark);
}

@Preview(
  name: 'Configuration fields · 390 px · 1.5× text',
  group: 'Configuration',
  size: Size(390, 560),
  textScaleFactor: 1.5,
)
Widget configurationFieldsCompactPreview() {
  return const _ConfigurationFieldsPreview(
    brightness: Brightness.light,
    platform: TargetPlatform.iOS,
  );
}

class _ConfigurationFieldsPreview extends StatefulWidget {
  const _ConfigurationFieldsPreview({
    required this.brightness,
    this.platform = TargetPlatform.macOS,
  });

  final Brightness brightness;
  final TargetPlatform platform;

  @override
  State<_ConfigurationFieldsPreview> createState() =>
      _ConfigurationFieldsPreviewState();
}

class _ConfigurationFieldsPreviewState
    extends State<_ConfigurationFieldsPreview> {
  late final TextEditingController _nameController;
  String _language = 'English';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'Production shell');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = buildIanvsTerminalTheme(
      widget.brightness,
      platform: widget.platform,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: widget.brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: Scaffold(
        body: SafeArea(
          child: Builder(
            builder: (context) => SingleChildScrollView(
              padding: EdgeInsets.all(context.appTheme.spacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Configuration fields',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: context.appTheme.spacing.xxl),
                  AppConfigurationField(
                    label: 'Profile name',
                    helper: 'Used in tabs and the profile launcher.',
                    child: TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        hintText: 'Enter a profile name',
                      ),
                    ),
                  ),
                  SizedBox(height: context.appTheme.spacing.xxl),
                  AppConfigurationField(
                    label: 'Language',
                    helper: 'Choose the application language.',
                    child: AppDropdownFormField<String>(
                      initialValue: _language,
                      decoration: const InputDecoration(),
                      items: const [
                        DropdownMenuItem(
                          value: 'English',
                          child: Text('English'),
                        ),
                        DropdownMenuItem(value: '简体中文', child: Text('简体中文')),
                        DropdownMenuItem(
                          value: 'System default',
                          child: Text('System default'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _language = value);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
