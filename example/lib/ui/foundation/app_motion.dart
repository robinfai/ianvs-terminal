import 'package:flutter/material.dart';

/// Dialog routes must opt out explicitly; shortening their duration still
/// produces a visible fade when the system requests reduced motion.
AnimationStyle? appDialogAnimation(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : null;

/// Keep platform navigation (including its back gesture) in the normal mode,
/// and show the destination in place when Reduce Motion is enabled.
class AppPageTransitionsTheme extends PageTransitionsTheme {
  const AppPageTransitionsTheme();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => MediaQuery.disableAnimationsOf(context)
      ? child
      : super.buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );

  @override
  DelegatedTransitionBuilder? delegatedTransition(TargetPlatform platform) {
    final delegate = super.delegatedTransition(platform);
    if (delegate == null) return null;
    return (context, animation, secondaryAnimation, allowSnapshotting, child) =>
        MediaQuery.disableAnimationsOf(context)
        ? child
        : delegate(
            context,
            animation,
            secondaryAnimation,
            allowSnapshotting,
            child,
          );
  }
}
