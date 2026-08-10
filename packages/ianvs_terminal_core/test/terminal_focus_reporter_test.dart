import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/src/terminal/terminal_focus_reporter.dart';

void main() {
  group(TerminalFocusReporter, () {
    late TerminalFocusReporter reporter;

    setUp(() {
      reporter = TerminalFocusReporter();
    });

    test('disabled tracking returns null and clears dedupe state', () {
      expect(
        reporter
            .synchronize(focusTrackingEnabled: true, hasFocus: true)
            ?.focused,
        isTrue,
      );

      expect(
        reporter.synchronize(focusTrackingEnabled: false, hasFocus: true),
        isNull,
      );
      expect(
        reporter
            .synchronize(focusTrackingEnabled: true, hasFocus: true)
            ?.focused,
        isTrue,
      );
    });

    test('reports initial focus once', () {
      expect(
        reporter
            .synchronize(focusTrackingEnabled: true, hasFocus: true)
            ?.focused,
        isTrue,
      );
      expect(
        reporter.synchronize(focusTrackingEnabled: true, hasFocus: true),
        isNull,
      );
    });

    test('reports focused to unfocused transition once', () {
      reporter.synchronize(focusTrackingEnabled: true, hasFocus: true);

      expect(
        reporter
            .synchronize(focusTrackingEnabled: true, hasFocus: false)
            ?.focused,
        isFalse,
      );
      expect(
        reporter.synchronize(focusTrackingEnabled: true, hasFocus: false),
        isNull,
      );
    });

    test('detach reports focus out from reported or node focus', () {
      reporter.synchronize(focusTrackingEnabled: true, hasFocus: true);
      expect(
        reporter
            .detach(focusTrackingEnabled: true, focusNodeHasFocus: false)
            ?.focused,
        isFalse,
      );
      expect(
        reporter.detach(focusTrackingEnabled: true, focusNodeHasFocus: false),
        isNull,
      );

      reporter.reset();
      expect(
        reporter
            .detach(focusTrackingEnabled: true, focusNodeHasFocus: true)
            ?.focused,
        isFalse,
      );
      expect(
        reporter.detach(focusTrackingEnabled: false, focusNodeHasFocus: true),
        isNull,
      );
    });

    test('reset lets a new owner report focus in', () {
      reporter.synchronize(focusTrackingEnabled: true, hasFocus: true);

      reporter.reset();

      expect(
        reporter
            .synchronize(focusTrackingEnabled: true, hasFocus: true)
            ?.focused,
        isTrue,
      );
    });
  });
}
