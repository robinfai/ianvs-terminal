import 'package:flutter/material.dart';

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
    return Semantics(
      label: 'Color palette',
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(theme.radius.lg),
          child: Material(
            color: Colors.transparent,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);

                void update(Offset localPosition) {
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

class HueSlider extends StatelessWidget {
  const HueSlider({super.key, required this.color, required this.onChanged});

  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Semantics(
      label: 'Hue slider',
      child: SizedBox(
        height: 16,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(theme.radius.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;

              void update(Offset localPosition) {
                final hue = ((localPosition.dx / width) * 360).clamp(
                  0.0,
                  360.0,
                );
                onChanged(color.withHue(hue == 360 ? 0 : hue));
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => update(details.localPosition),
                onPanStart: (details) => update(details.localPosition),
                onPanUpdate: (details) => update(details.localPosition),
                child: CustomPaint(
                  painter: _HueSliderPainter(
                    hue: color.hue,
                    borderColor: theme.border,
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
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
