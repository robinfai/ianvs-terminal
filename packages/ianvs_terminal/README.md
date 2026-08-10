# ianvs_terminal

`ianvs_terminal` 建在 `ianvs_pty` 之上，负责共享 terminal 运行时、viewport
适配，以及可选的 Flutter 嵌入组件。产品自己的窗口、路由和会话仍由宿主应用管理。

## 从 Git 仓库集成

依赖完整仓库，而不是只复制 `packages/` 目录。macOS 构建会通过 package build
hook 编译并打包 `native/core` 的 Rust 动态库；首次构建需要可用的 Rust/Cargo
工具链，后续会复用构建缓存。

```yaml
dependencies:
  ianvs_terminal:
    git:
      url: https://github.com/robinfai/ianvs-terminal.git
      ref: <commit>
      path: packages/ianvs_terminal
```

宿主只需要提供平台剪贴板桥接：

```dart
final runtime = TerminalRuntimeController.native(
  copyToClipboard: (text) => Clipboard.setData(ClipboardData(text: text)),
  readClipboard: () async =>
      (await Clipboard.getData('text/plain'))?.text ?? '',
);
```

## 嵌入一个底部终端区

`TerminalPanelController` 管理 tab 和原生 PTY 生命周期；`TerminalBottomPanel`
负责 tabs、紧跟 tabs 的 `+`、终端 viewport 和收起按钮。把 controller 放在宿主
会话的 State 中，并在该会话销毁时调用 `dispose()`，即可让所有终端跟随宿主会话
关闭。

```dart
late final runtime = TerminalRuntimeController.native(
  copyToClipboard: copyToClipboard,
  readClipboard: readClipboard,
);
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

// 宿主 toolbar
TerminalPanelToggleButton(controller: terminals)

// 宿主内容区底部
TerminalBottomPanel(controller: terminals)

@override
void dispose() {
  terminals.dispose();
  super.dispose();
}
```

需要使用宿主自己的 tab 外观或 viewport 包装时，可注入
`TerminalBottomPanelStyle`、`viewportBuilder` 和 `sessionBuilder`；只需要单个终端
时可直接使用 `TerminalSessionView`。

## 对上层暴露

- `TerminalSessionConfig`
- `TerminalLaunchConfig`
- `TerminalShellIntegrationConfig`
- `TerminalDisplayConfig`
- `TerminalRuntimeController`
- `TerminalSessionEvent`
- `TerminalSessionShellHookEvent`
- `TerminalViewport`
- `TerminalViewportController`
- `TerminalSessionView`
- `TerminalPanelController`
- `TerminalBottomPanel`
- `TerminalPanelToggleButton`

## Shell Hook Events

`TerminalRuntimeController.events` emits `TerminalSessionShellHookEvent` for
native `shell_hook` events. The event preserves the raw payload and exposes
lightweight fields for `hook`, `command`, `cwd`, `shell`, and `exitCode`.

The logical hook names stay shell-agnostic. zsh, bash, and fish integrations
emit `preexec`, `command_finished`, `precmd`, and `precmd.pwd`.

`TerminalShellIntegrationConfig.enabled` controls whether eligible sessions may
inject shell hooks. It defaults to `true`, but unsupported shells, most custom
shell arguments, VT220 emulation, or native proxy setup failures automatically
fall back to the original shell launch path without emitting shell-hook events.
The default zsh login shell arguments (`-l` or `--login`) remain eligible.
Native diagnostics export records the launch decision in the initial `started`
diagnostic event as `shell_integration.status`, `reason`, optional `kind`, and
optional `error`, so support logs can tell disabled/degraded sessions apart from
normal hook silence.

Bash integration uses a `DEBUG` trap for `preexec` and wraps `PROMPT_COMMAND`
for completion hooks. If a user already has a `DEBUG` trap, bash integration
automatically falls back without installing hooks. Bash may also report only the
first simple command for complex pipelines or compound commands.

## 宿主仍负责

- 产品专属的面板位置、主导航、窗口与菜单
- ACP 等上层业务会话如何绑定 terminal controller
- 系统剪贴板平台桥接
- profile 编辑器
- demo fixture

这些都留在 `example/`。剪贴板这类平台能力由上层通过 `copyToClipboard` / `readClipboard` 回调注入。

## 测试

```bash
cd packages/ianvs_terminal
flutter test
```
