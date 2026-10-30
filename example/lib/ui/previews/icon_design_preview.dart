import 'package:flutter/material.dart';

import '../foundation/app_icons.dart';
import '../foundation/app_theme.dart';

const iconDesignEntries = <String, IconData>{
  'Settings': AppIcons.settings,
  'General': AppIcons.general,
  'Appearance': AppIcons.appearance,
  'Keymap': AppIcons.shortcuts,
  'Security': AppIcons.security,
  'Data': AppIcons.data,
  'Profile': AppIcons.profile,
  'Startup': AppIcons.startup,
  'Terminal': AppIcons.terminal,
  'Automation': AppIcons.automation,
  'Advanced': AppIcons.advanced,
  'Search': AppIcons.search,
  'Close': AppIcons.close,
  'Add': AppIcons.add,
  'Delete': AppIcons.remove,
  'Reset': AppIcons.restore,
  'Save': AppIcons.save,
  'More': AppIcons.more,
  'Back': AppIcons.back,
  'Next': AppIcons.forward,
  'Server': AppIcons.server,
  'Local': AppIcons.local,
  'Folder': AppIcons.folder,
  'Key': AppIcons.key,
  'Copy': AppIcons.copy,
  'Connect': AppIcons.connect,
  'Info': AppIcons.information,
  'Warning': AppIcons.warning,
  'Error': AppIcons.error,
  'Success': AppIcons.success,
};

/// Native preview: flutter run -d macos
/// --target lib/ui/previews/icon_design_preview.dart.
void main() => runApp(
  MaterialApp(
    theme: buildIanvsTerminalTheme(Brightness.light),
    darkTheme: buildIanvsTerminalTheme(Brightness.dark),
    home: const Scaffold(
      body: SingleChildScrollView(child: IconDesignPreview()),
    ),
  ),
);

class IconDesignPreview extends StatelessWidget {
  const IconDesignPreview({super.key, this.fontFamily = 'MaterialIcons'});

  final String fontFamily;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Wrap(
      spacing: 12,
      runSpacing: 20,
      children: [
        for (final entry in iconDesignEntries.entries)
          SizedBox(
            width: 126,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final size in [16.0, 20.0, 24.0])
                      ExcludeSemantics(
                        child: Text(
                          String.fromCharCode(entry.value.codePoint),
                          style: TextStyle(
                            fontFamily: fontFamily,
                            fontSize: size,
                            height: 1,
                            color: Theme.of(context).iconTheme.color,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(entry.key, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
      ],
    ),
  );
}
