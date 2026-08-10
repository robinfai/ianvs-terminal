# ianvs_terminal_core

`ianvs_terminal_core` is an embeddable macOS terminal for Flutter desktop apps.
It ships the Dart/Flutter terminal runtime, viewport, tabbed bottom panel, and
the Rust-backed native PTY implementation as one package.

## Requirements

- macOS on Apple silicon or Intel
- Flutter 3.41 or newer
- Rust 1.88 or newer with Cargo available during the application build

The package build hook compiles and bundles `libianvs_core.dylib`; host apps do
not need to add a custom Xcode build phase.

## Install

```yaml
dependencies:
  ianvs_terminal_core: ^0.1.0
```

## Create a terminal runtime

The host owns platform clipboard access and passes it to the runtime:

```dart
import 'package:flutter/services.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

final runtime = TerminalRuntimeController.native(
  copyToClipboard: (text) =>
      Clipboard.setData(ClipboardData(text: text)),
  readClipboard: () async =>
      (await Clipboard.getData('text/plain'))?.text ?? '',
);
```

## Embed a themed bottom panel

`TerminalPanelController` owns tab and PTY lifecycles. Keep it with the host
session state and dispose it when that session closes.

```dart
late final terminals = TerminalPanelController(
  runtime: runtime,
  disposeRuntime: true,
  defaultTabFactory: (index) {
    final local = defaultLocalTerminalPanelTab(index);
    return TerminalPanelTabDefinition(
      title: index == 1 ? 'Terminal' : 'Terminal $index',
      sessionConfig: local.sessionConfig.copyWith(
        launch: local.sessionConfig.launch.copyWith(cwd: workspacePath),
      ),
    );
  },
);

TerminalPanelToggleButton(controller: terminals);

TerminalBottomPanel(
  controller: terminals,
  style: const TerminalBottomPanelStyle(
    panelBackgroundColor: Color(0xff171b1a),
    tabBarBackgroundColor: Color(0xfff1f3f1),
    activeTabIndicatorColor: Color(0xff0b7e75),
  ),
);
```

For a single terminal use `TerminalSessionView`. For custom product chrome,
provide `viewportBuilder`, `sessionBuilder`, or a `TerminalBottomPanelStyle`.

## Public surface

- `TerminalRuntimeController` and native PTY contracts
- `TerminalSessionConfig` and launch/display configuration
- `TerminalViewport` and `TerminalViewportColors`
- `TerminalSessionView`
- `TerminalPanelController`, `TerminalBottomPanel`, and toggle button
- recording, replay, diagnostics, and shell-hook events

The host application remains responsible for windows, navigation, product
sessions, permissions, and platform clipboard integration.

## License

BSD-3-Clause. Bundled third-party Rust sources retain their own license files.
