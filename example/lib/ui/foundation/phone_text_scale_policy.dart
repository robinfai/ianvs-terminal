import 'package:flutter/material.dart';

/// The phone product uses fixed UI type. The display size, rather than the
/// resizable window, keeps iPad Split View and Stage Manager on system scaling.
/// Terminal pinch changes TerminalFontConfig and remains independent of this.
class PhoneTextScalePolicy extends StatelessWidget {
  const PhoneTextScalePolicy({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final display = View.of(context).display;
    final phone =
        Theme.of(context).platform == TargetPlatform.iOS &&
        (display.size / display.devicePixelRatio).shortestSide < 600;
    if (!phone) return child;
    return MediaQuery.withNoTextScaling(child: child);
  }
}
