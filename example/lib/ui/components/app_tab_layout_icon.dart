import 'package:flutter/material.dart';

/// The destination represented by a tab layout switch.
enum AppTabLayout { top, sidebar }

/// A matched pair of window glyphs with horizontal tabs or a left tab list.
class AppTabLayoutIcon extends StatelessWidget {
  const AppTabLayoutIcon({
    super.key,
    required this.layout,
    this.size = 18,
    this.color,
  });

  final AppTabLayout layout;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _TabLayoutPainter(
        layout,
        color ??
            IconTheme.of(context).color ??
            Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _TabLayoutPainter extends CustomPainter {
  const _TabLayoutPainter(this.layout, this.color);

  final AppTabLayout layout;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 18, size.height / 18);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 2, 16, 14),
        const Radius.circular(2),
      ),
      paint,
    );
    if (layout == AppTabLayout.top) {
      canvas.drawLine(const Offset(1, 6.25), const Offset(17, 6.25), paint);
      for (final x in [6.25, 11.75]) {
        canvas.drawLine(Offset(x, 2), Offset(x, 6.25), paint);
      }
    } else {
      canvas.drawLine(const Offset(6.5, 2), const Offset(6.5, 16), paint);
      for (final y in [5.5, 9.0, 12.5]) {
        canvas.drawLine(Offset(3.25, y), Offset(4.25, y), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TabLayoutPainter oldDelegate) =>
      layout != oldDelegate.layout || color != oldDelegate.color;
}
