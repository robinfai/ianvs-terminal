import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/app_ui.dart';

class ColorPickerPalette extends StatelessWidget {
  const ColorPickerPalette({
    super.key,
    required this.color,
    required this.onChanged,
    this.aspectRatio = 2.4,
  });

  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final effectiveAspectRatio = _usablePositiveFinite(
      aspectRatio,
      fallback: 2.4,
    );
    return Semantics(
      label: 'Color palette',
      child: AspectRatio(
        aspectRatio: effectiveAspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(theme.radius.lg),
          child: Material(
            color: Colors.transparent,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);

                void update(Offset localPosition) {
                  if (!_isUsableSize(size)) {
                    return;
                  }
                  final saturation = (localPosition.dx / size.width).clamp(
                    0.0,
                    1.0,
                  );
                  final value = (1 - (localPosition.dy / size.height)).clamp(
                    0.0,
                    1.0,
                  );
                  onChanged(color.withSaturation(saturation).withValue(value));
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => update(details.localPosition),
                  onPanStart: (details) => update(details.localPosition),
                  onPanUpdate: (details) => update(details.localPosition),
                  child: CustomPaint(
                    painter: _ColorPickerPalettePainter(color: color),
                    foregroundPainter: _ColorPickerPaletteMarkerPainter(
                      color: color,
                      borderColor: theme.border,
                    ),
                    child: const SizedBox.expand(),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class HueSlider extends StatefulWidget {
  const HueSlider({super.key, required this.color, required this.onChanged});

  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;

  @override
  State<HueSlider> createState() => _HueSliderState();
}

class _HueSliderState extends State<HueSlider> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'hue-slider');
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _adjust(double delta) {
    final hue = (widget.color.hue + delta) % 360;
    widget.onChanged(widget.color.withHue(hue < 0 ? hue + 360 : hue));
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Semantics(
      label: 'Hue',
      value: '${widget.color.hue.round()} degrees',
      increasedValue: '${(widget.color.hue + 1).round() % 360} degrees',
      decreasedValue: '${(widget.color.hue - 1).round() % 360} degrees',
      slider: true,
      focusable: true,
      onIncrease: () => _adjust(1),
      onDecrease: () => _adjust(-1),
      child: Focus(
        focusNode: _focusNode,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          final step = HardwareKeyboard.instance.isShiftPressed ? 10.0 : 1.0;
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _adjust(-step);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _adjust(step);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 24,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(theme.radius.md),
            border: Border.all(
              color: _focused ? theme.focusRing : Colors.transparent,
              width: 2,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(theme.radius.sm),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;

                void update(Offset localPosition) {
                  if (!width.isFinite || width <= 0) {
                    return;
                  }
                  final hue = ((localPosition.dx / width) * 360).clamp(
                    0.0,
                    360.0,
                  );
                  widget.onChanged(widget.color.withHue(hue == 360 ? 0 : hue));
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    _focusNode.requestFocus();
                    update(details.localPosition);
                  },
                  onPanStart: (details) {
                    _focusNode.requestFocus();
                    update(details.localPosition);
                  },
                  onPanUpdate: (details) => update(details.localPosition),
                  child: CustomPaint(
                    painter: _HueSliderPainter(
                      hue: widget.color.hue,
                      borderColor: theme.border,
                    ),
                    child: const SizedBox.expand(),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

bool _isUsableSize(Size size) {
  return size.width.isFinite &&
      size.height.isFinite &&
      size.width > 0 &&
      size.height > 0;
}

double _usablePositiveFinite(double value, {required double fallback}) {
  return value.isFinite && value > 0 ? value : fallback;
}

class _ColorPickerPalettePainter extends CustomPainter {
  const _ColorPickerPalettePainter({required this.color});

  final HSVColor color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = color.withSaturation(1).withValue(1).toColor();

    canvas.drawRect(rect, Paint()..color = hueColor);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.white, Colors.transparent],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _ColorPickerPalettePainter other) {
    return other.color != color;
  }
}

class _ColorPickerPaletteMarkerPainter extends CustomPainter {
  const _ColorPickerPaletteMarkerPainter({
    required this.color,
    required this.borderColor,
  });

  final HSVColor color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(
      color.saturation * size.width,
      (1 - color.value) * size.height,
    );

    canvas.drawCircle(
      center,
      8,
      Paint()
        ..color = Colors.transparent
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      center,
      9.5,
      Paint()
        ..color = borderColor.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _ColorPickerPaletteMarkerPainter other) {
    return other.color != color || other.borderColor != borderColor;
  }
}

class _HueSliderPainter extends CustomPainter {
  const _HueSliderPainter({required this.hue, required this.borderColor});

  final double hue;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Colors.red,
            Colors.yellow,
            Colors.green,
            Colors.cyan,
            Colors.blue,
            Colors.purple,
            Colors.red,
          ],
        ).createShader(rect),
    );

    final indicatorX = (hue / 360) * size.width;
    final center = Offset(indicatorX.clamp(0.0, size.width), size.height / 2);
    canvas.drawCircle(
      center,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      center,
      9.5,
      Paint()
        ..color = borderColor.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _HueSliderPainter other) {
    return other.hue != hue || other.borderColor != borderColor;
  }
}
