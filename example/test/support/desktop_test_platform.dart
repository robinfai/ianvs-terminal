import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Desktop shell tests use the real platform variant lifecycle, including
/// restoring debug overrides before Flutter verifies its test invariants.
void desktopTestWidgets(
  String description,
  WidgetTesterCallback callback, {
  bool? skip,
  Timeout? timeout,
  bool semanticsEnabled = true,
  TestVariant<Object?>? variant,
  dynamic tags,
  int? retry,
}) => testWidgets(
  description,
  callback,
  skip: skip,
  timeout: timeout,
  semanticsEnabled: semanticsEnabled,
  variant: variant ?? TargetPlatformVariant.only(TargetPlatform.linux),
  tags: tags,
  retry: retry,
);
