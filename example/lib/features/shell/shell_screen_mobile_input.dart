part of 'shell_screen.dart';

const double _minimumMobileTerminalFontScale = 0.7;
const double _maximumMobileTerminalFontScale = 2.0;

extension _ShellScreenMobileInput on _ShellScreenState {
  double _mobileFontScaleFor(String sessionId) {
    return _mobileTerminalFontScales[sessionId] ?? 1.0;
  }

  terminal.TerminalFontConfig _mobileFontFor(
    String sessionId,
    terminal.TerminalFontConfig base,
  ) {
    return base.copyWith(size: base.size * _mobileFontScaleFor(sessionId));
  }

  void _startMobileTerminalPinch(String sessionId, ScaleStartDetails details) {
    _mobileTerminalPinchStartScales[sessionId] = _mobileFontScaleFor(sessionId);
  }

  void _updateMobileTerminalPinch(
    String sessionId,
    ScaleUpdateDetails details,
  ) {
    if (details.pointerCount < 2) {
      return;
    }
    final startScale = _mobileTerminalPinchStartScales.putIfAbsent(
      sessionId,
      () => _mobileFontScaleFor(sessionId),
    );
    _setMobileTerminalFontScale(sessionId, startScale * details.scale);
  }

  void _endMobileTerminalPinch(String sessionId, ScaleEndDetails details) {
    _mobileTerminalPinchStartScales.remove(sessionId);
  }

  void _stepMobileTerminalFont(String sessionId, double delta) {
    _setMobileTerminalFontScale(
      sessionId,
      _mobileFontScaleFor(sessionId) + delta,
    );
    unawaited(HapticFeedback.selectionClick());
  }

  void _resetMobileTerminalFont(String sessionId) {
    _setMobileTerminalFontScale(sessionId, 1.0);
    unawaited(HapticFeedback.selectionClick());
  }

  void _setMobileTerminalFontScale(String sessionId, double scale) {
    final normalized = scale.clamp(
      _minimumMobileTerminalFontScale,
      _maximumMobileTerminalFontScale,
    );
    if ((_mobileFontScaleFor(sessionId) - normalized).abs() < 0.005) {
      return;
    }
    _mutateState(() {
      _mobileTerminalFontScales[sessionId] = normalized;
      _measuredTerminalCellSizes.remove(sessionId);
      _committedViewportSizes.remove(sessionId);
    });
  }

  void _sendMobileTerminalBytes(String sessionId, List<int> bytes) {
    if (bytes.isEmpty || _isSessionReadOnly(sessionId)) {
      return;
    }
    ref
        .read(terminalRuntimeControllerProvider)
        .sendInput(sessionId, Uint8List.fromList(bytes));
    _focusSession(sessionId);
  }

  void _dismissMobileTerminalKeyboard(String sessionId) {
    _focusNodeFor(sessionId).unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
  }
}

class _IosTerminalInputBar extends StatelessWidget {
  const _IosTerminalInputBar({
    super.key,
    required this.palette,
    required this.fontScale,
    required this.keyboardVisible,
    required this.onSendBytes,
    required this.onDecreaseFont,
    required this.onIncreaseFont,
    required this.onResetFont,
    required this.onDismissKeyboard,
  });

  final AppThemeTokens palette;
  final double fontScale;
  final bool keyboardVisible;
  final ValueChanged<List<int>> onSendBytes;
  final VoidCallback onDecreaseFont;
  final VoidCallback onIncreaseFont;
  final VoidCallback onResetFont;
  final VoidCallback onDismissKeyboard;

  static const List<_IosTerminalKeySpec> _keys = <_IosTerminalKeySpec>[
    _IosTerminalKeySpec('Esc', <int>[0x1b], 'Escape'),
    _IosTerminalKeySpec('⌃C', <int>[0x03], 'Control C'),
    _IosTerminalKeySpec('⌃D', <int>[0x04], 'Control D'),
    _IosTerminalKeySpec('⌃L', <int>[0x0c], 'Control L'),
    _IosTerminalKeySpec('Tab', <int>[0x09], 'Tab'),
    _IosTerminalKeySpec('↑', <int>[0x1b, 0x5b, 0x41], 'Previous command'),
    _IosTerminalKeySpec('↓', <int>[0x1b, 0x5b, 0x42], 'Next command'),
    _IosTerminalKeySpec('←', <int>[0x1b, 0x5b, 0x44], 'Move cursor left'),
    _IosTerminalKeySpec('→', <int>[0x1b, 0x5b, 0x43], 'Move cursor right'),
    _IosTerminalKeySpec('/', <int>[0x2f], 'Slash'),
    _IosTerminalKeySpec('-', <int>[0x2d], 'Hyphen'),
    _IosTerminalKeySpec('_', <int>[0x5f], 'Underscore'),
    _IosTerminalKeySpec('~', <int>[0x7e], 'Tilde'),
    _IosTerminalKeySpec('|', <int>[0x7c], 'Pipe'),
    _IosTerminalKeySpec(r'\', <int>[0x5c], 'Backslash'),
    _IosTerminalKeySpec(r'$', <int>[0x24], 'Dollar sign'),
    _IosTerminalKeySpec('&', <int>[0x26], 'Ampersand'),
    _IosTerminalKeySpec(';', <int>[0x3b], 'Semicolon'),
    _IosTerminalKeySpec(':', <int>[0x3a], 'Colon'),
    _IosTerminalKeySpec('.', <int>[0x2e], 'Period'),
    _IosTerminalKeySpec('"', <int>[0x22], 'Double quote'),
    _IosTerminalKeySpec("'", <int>[0x27], 'Single quote'),
    _IosTerminalKeySpec('(', <int>[0x28], 'Left parenthesis'),
    _IosTerminalKeySpec(')', <int>[0x29], 'Right parenthesis'),
    _IosTerminalKeySpec('[', <int>[0x5b], 'Left bracket'),
    _IosTerminalKeySpec(']', <int>[0x5d], 'Right bracket'),
  ];

  @override
  Widget build(BuildContext context) {
    final textColor = palette.textPrimary;
    return Semantics(
      container: true,
      label: context.l10n.terminalKeyboardShortcuts,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.panel,
          border: Border(top: BorderSide(color: palette.border)),
        ),
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              _IosTerminalBarButton(
                key: const Key('ios-terminal-font-decrease'),
                label: 'A−',
                semanticLabel: context.l10n.decreaseTerminalTextSize,
                palette: palette,
                onPressed: onDecreaseFont,
              ),
              _IosTerminalBarButton(
                key: const Key('ios-terminal-font-reset'),
                label: '${(fontScale * 100).round()}%',
                semanticLabel: context.l10n.resetTerminalTextSize,
                palette: palette,
                minWidth: 52,
                onPressed: onResetFont,
              ),
              _IosTerminalBarButton(
                key: const Key('ios-terminal-font-increase'),
                label: 'A+',
                semanticLabel: context.l10n.increaseTerminalTextSize,
                palette: palette,
                onPressed: onIncreaseFont,
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                indent: 8,
                endIndent: 8,
                color: palette.border,
              ),
              Expanded(
                child: ListView.separated(
                  key: const Key('ios-terminal-character-list'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: _keys.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 4),
                  itemBuilder: (context, index) {
                    final spec = _keys[index];
                    return _IosTerminalBarButton(
                      key: Key('ios-terminal-key-${spec.semanticLabel}'),
                      label: spec.label,
                      semanticLabel: context.l10n.insertTerminalKey(spec.label),
                      palette: palette,
                      onPressed: () {
                        onSendBytes(spec.bytes);
                        if (index < 9) {
                          unawaited(HapticFeedback.selectionClick());
                        }
                      },
                    );
                  },
                ),
              ),
              if (keyboardVisible) ...[
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 8,
                  endIndent: 8,
                  color: palette.border,
                ),
                Semantics(
                  button: true,
                  label: context.l10n.dismissKeyboard,
                  child: IconButton(
                    key: const Key('ios-terminal-dismiss-keyboard'),
                    tooltip: context.l10n.dismissKeyboard,
                    onPressed: onDismissKeyboard,
                    color: textColor,
                    icon: const Icon(Icons.keyboard_hide_rounded, size: 20),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IosTerminalBarButton extends StatelessWidget {
  const _IosTerminalBarButton({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.palette,
    required this.onPressed,
    this.minWidth = 44,
  });

  final String label;
  final String semanticLabel;
  final AppThemeTokens palette;
  final VoidCallback onPressed;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: palette.chromeElevated,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(8),
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth, minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: palette.textPrimary,
                      fontFamily: terminalPrimaryFontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IosTerminalKeySpec {
  const _IosTerminalKeySpec(this.label, this.bytes, this.semanticLabel);

  final String label;
  final List<int> bytes;
  final String semanticLabel;
}
