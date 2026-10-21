import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Hold to dictate into a draft; recognition never submits the draft.
class IosVoiceInput extends StatefulWidget {
  const IosVoiceInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.chinese,
    required this.child,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool chinese;
  final Widget child;

  @override
  State<IosVoiceInput> createState() => _IosVoiceInputState();
}

class _IosVoiceInputState extends State<IosVoiceInput>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('app/voice_input');
  static int _nextId = 0;
  int? _id;
  bool _released = false;
  bool _cancelArmed = false;
  Completer<void>? _releaseSignal;
  OverlayEntry? _recordingOverlay;
  final GlobalKey _cancelZone = GlobalKey();

  void _removeOverlay() {
    _recordingOverlay?.remove();
    _recordingOverlay?.dispose();
    _recordingOverlay = null;
  }

  void _showOverlay() {
    _recordingOverlay = OverlayEntry(
      builder: (overlayContext) {
        final media = MediaQuery.of(overlayContext);
        final colors = Theme.of(context).colorScheme;
        final overlayText = colors.brightness == Brightness.dark
            ? colors.onSurface
            : colors.onInverseSurface;
        final height = media.size.height;
        final panelHeight = math.min(200.0, height * .33);
        return Positioned.fill(
          child: AbsorbPointer(
            child: Material(
              color: colors.scrim.withValues(alpha: .56),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: panelHeight,
                    child: AnimatedContainer(
                      key: _cancelZone,
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colors.error.withValues(
                              alpha: _cancelArmed ? .12 : 0,
                            ),
                            colors.error.withValues(
                              alpha: _cancelArmed ? .26 : 0,
                            ),
                          ],
                        ),
                      ),
                      child: Semantics(
                        key: const Key('voice-cancel-zone'),
                        liveRegion: true,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              24,
                              12,
                              24,
                              _cancelArmed ? 48 : 18,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_cancelArmed) ...[
                                    Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: colors.error.withValues(
                                          alpha: .24,
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(7),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: colors.error,
                                        ),
                                        child: Icon(
                                          CupertinoIcons.xmark,
                                          size: 26,
                                          color: colors.onError,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _t('Release to cancel', '松开取消'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: overlayText,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _t(
                                        'Slide back down to continue',
                                        '滑回下方继续说话',
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: overlayText.withValues(
                                              alpha: .8,
                                            ),
                                          ),
                                    ),
                                  ] else ...[
                                    Icon(
                                      CupertinoIcons.chevron_up,
                                      size: 22,
                                      color: overlayText.withValues(alpha: .85),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _t(
                                        'Slide into the area above to cancel',
                                        '上方区域可取消',
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: overlayText.withValues(
                                              alpha: .85,
                                            ),
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      key: const Key('voice-recording-panel'),
                      height: panelHeight,
                      padding: EdgeInsets.fromLTRB(
                        20,
                        16,
                        20,
                        math.max(12, media.padding.bottom),
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        boxShadow: [
                          BoxShadow(
                            color: colors.error.withValues(
                              alpha: _cancelArmed ? .5 : 0,
                            ),
                            blurRadius: 28,
                            spreadRadius: 2,
                            offset: const Offset(0, -8),
                          ),
                        ],
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      child: panelHeight < 140
                          ? Center(
                              child: Text(
                                _cancelArmed
                                    ? _t('Slide back to continue', '滑回继续说话')
                                    : _t('Release to transcribe', '松开转文字'),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: _VoiceWaveform(
                                    muted: _cancelArmed,
                                    color: _cancelArmed
                                        ? colors.outlineVariant
                                        : colors.primary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _cancelArmed
                                      ? _t('Slide back to continue', '滑回继续说话')
                                      : _t('Release to transcribe', '松开转文字'),
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: colors.onSurface,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _cancelArmed
                                      ? _t(
                                          'Release to discard this recording',
                                          '松开将取消此次输入',
                                        )
                                      : _t(
                                          'Keep speaking, slide up to cancel',
                                          '继续说话，上滑取消',
                                        ),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_recordingOverlay!);
  }

  void _move(LongPressMoveUpdateDetails details) {
    if (_id == null || _released) return;
    final box = _cancelZone.currentContext?.findRenderObject() as RenderBox?;
    final cancel =
        box != null &&
        (Offset.zero & box.size).contains(
          box.globalToLocal(details.globalPosition),
        );
    if (cancel != _cancelArmed) {
      setState(() => _cancelArmed = cancel);
      _recordingOverlay?.markNeedsBuild();
      unawaited(HapticFeedback.selectionClick());
    }
  }

  String _t(String en, String zh) => widget.chinese ? zh : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _start() async {
    if (!widget.enabled || _id != null) return;
    final id = ++_nextId;
    final controller = widget.controller;
    final original = controller.value;
    final releaseSignal = Completer<void>();
    _releaseSignal = releaseSignal;
    setState(() {
      _id = id;
      _released = false;
      _cancelArmed = false;
    });
    _showOverlay();
    try {
      final text = await _channel.invokeMethod<String>('start', {
        'id': id,
        'locale': Localizations.localeOf(context).toLanguageTag(),
      });
      await releaseSignal.future;
      if (!mounted || _id != id || !widget.enabled) return;
      // Never overwrite edits, a sent draft, or a different input owner.
      if (text != null &&
          text.isNotEmpty &&
          identical(controller, widget.controller) &&
          controller.value == original) {
        final selection = original.selection.isValid
            ? original.selection
            : TextSelection.collapsed(offset: original.text.length);
        controller.value = TextEditingValue(
          text: original.text.replaceRange(
            selection.start,
            selection.end,
            text,
          ),
          selection: TextSelection.collapsed(
            offset: selection.start + text.length,
          ),
        );
      }
    } on PlatformException catch (error) {
      if (mounted && _id == id) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              _t(
                error.code == 'permission_denied'
                    ? 'Allow microphone and speech recognition in Settings.'
                    : 'Voice input unavailable. Please try again.',
                error.code == 'permission_denied'
                    ? '请在系统设置中允许麦克风和语音识别权限。'
                    : '语音输入暂不可用，请重试。',
              ),
            ),
          ),
        );
      }
    } on MissingPluginException {
      if (mounted && _id == id) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              _t('Voice input requires the iOS app.', '请在 iOS 应用中使用语音输入。'),
            ),
          ),
        );
      }
    } finally {
      if (mounted && _id == id) {
        _removeOverlay();
        setState(() => _id = null);
      }
    }
  }

  Future<void> _command(String method, int id) async {
    try {
      await _channel.invokeMethod<void>(method, {'id': id});
    } on PlatformException {
      // Native teardown also runs on interruption/backgrounding.
    } on MissingPluginException {
      // A preview host may not register the iOS channel.
    }
  }

  void _stop() {
    final id = _id;
    if (id == null || _released) return;
    if (_cancelArmed) {
      setState(_cancel);
      return;
    }
    _removeOverlay();
    setState(() => _released = true);
    _releaseSignal?.complete();
    _releaseSignal = null;
    unawaited(_command('stop', id));
  }

  void _cancel() {
    final id = _id;
    if (id == null) return;
    _removeOverlay();
    _id = null;
    _releaseSignal?.complete();
    _releaseSignal = null;
    unawaited(_command('cancel', id));
  }

  @override
  void didUpdateWidget(IosVoiceInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || oldWidget.controller != widget.controller) _cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission dialogs can temporarily make the app inactive.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      setState(_cancel);
    }
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      _UnfocusedVoiceLongPress:
          GestureRecognizerFactoryWithHandlers<_UnfocusedVoiceLongPress>(
            _UnfocusedVoiceLongPress.new,
            (recognizer) {
              // Decide at pointer-down, before TextField can request focus.
              // Keep that decision for the whole gesture.
              recognizer.canStart = () =>
                  widget.enabled && !widget.focusNode.hasFocus;
              recognizer.onLongPressStart = (_) {
                unawaited(_start());
              };
              recognizer.onLongPressMoveUpdate = _move;
              recognizer.onLongPressEnd = (_) => _stop();
            },
          ),
    },
    child: Listener(
      onPointerCancel: (_) => setState(_cancel),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Opacity(
            opacity: _released && _id != null ? 0 : 1,
            child: AbsorbPointer(absorbing: _id != null, child: widget.child),
          ),
          if (_id != null && _released)
            Semantics(
              liveRegion: true,
              child: Text(
                _released
                    ? _t('Transcribing…', '正在识别…')
                    : _cancelArmed
                    ? _t('Release to cancel', '松开取消')
                    : _t('Listening · slide up to cancel', '正在聆听，上滑取消…'),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Never enters the text selection gesture arena when the editor has focus.
class _UnfocusedVoiceLongPress extends LongPressGestureRecognizer {
  _UnfocusedVoiceLongPress()
    : super(duration: const Duration(milliseconds: 350));

  bool Function()? canStart;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      (canStart?.call() ?? false) && super.isPointerAllowed(event);
}

/// An activity waveform, not a microphone volume meter.
class _VoiceWaveform extends StatefulWidget {
  const _VoiceWaveform({required this.color, required this.muted});
  final Color color;
  final bool muted;
  @override
  State<_VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<_VoiceWaveform>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
    } else {
      unawaited(_animation.repeat());
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    builder: (context, _) => SizedBox(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 25; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                width: 4,
                height: widget.muted
                    ? 8
                    : 8 +
                          40 *
                              math
                                  .sin(i * .65 + _animation.value * math.pi * 2)
                                  .abs() *
                              (1 - (i - 12).abs() / 16),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }
}
