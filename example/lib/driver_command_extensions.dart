// Flutter's legacy driver API is supplied transitively by the test harness.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_test/flutter_test.dart';

class UnsyncedTapCommandExtension extends CommandExtension {
  UnsyncedTapCommandExtension();

  @override
  String get commandKind => 'tap';

  @override
  Command deserialize(
    Map<String, String> params,
    DeserializeFinderFactory finderFactory,
    DeserializeCommandFactory commandFactory,
  ) {
    return Tap.deserialize(params, finderFactory);
  }

  @override
  Future<Result> call(
    Command command,
    WidgetController prober,
    CreateFinderFactory finderFactory,
    CommandHandlerFactory handlerFactory,
  ) async {
    final tapCommand = command as Tap;
    final finder = finderFactory.createFinder(tapCommand.finder);
    await _waitForFinder(finder);
    await prober.tap(finder, warnIfMissed: false);
    return Result.empty;
  }

  Future<void> _waitForFinder(Finder finder) async {
    if (finder.evaluate().isNotEmpty) {
      return;
    }

    final completer = Completer<void>();
    late final Timer timer;
    timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (finder.evaluate().isNotEmpty && !completer.isCompleted) {
        timer.cancel();
        completer.complete();
      }
    });
    await completer.future;
    timer.cancel();
  }
}
