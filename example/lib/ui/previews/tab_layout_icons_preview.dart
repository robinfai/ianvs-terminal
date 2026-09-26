import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../components/app_tab_layout_icon.dart';

@Preview(
  name: 'Tab layouts · light',
  group: 'Trail',
  size: Size(320, 100),
  brightness: Brightness.light,
)
@Preview(
  name: 'Tab layouts · dark',
  group: 'Trail',
  size: Size(320, 100),
  brightness: Brightness.dark,
)
Widget tabLayoutIconsPreview() => Material(
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      for (final layout in AppTabLayout.values)
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                for (final size in [16.0, 18.0, 20.0])
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: AppTabLayoutIcon(layout: layout, size: size),
                  ),
              ],
            ),
            Text(layout == AppTabLayout.top ? '顶部 tabs' : '侧边栏 tabs'),
          ],
        ),
    ],
  ),
);
