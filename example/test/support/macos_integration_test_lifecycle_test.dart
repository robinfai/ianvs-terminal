import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'macos_integration_test_lifecycle.dart';

void main() {
  testWidgets('restores a hidden binding through legal lifecycle states', (
    tester,
  ) async {
    final binding = tester.binding;
    final observed = <AppLifecycleState>[];
    final observer = _LifecycleObserver(observed.add);
    binding.addObserver(observer);
    addTearDown(() {
      binding.removeObserver(observer);
      _restoreResumed(binding);
    });

    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    observed.clear();

    ensureMacosIntegrationTestFramesEnabled(binding);

    expect(binding.lifecycleState, AppLifecycleState.resumed);
    expect(binding.framesEnabled, isTrue);
    expect(observed, const [
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
  });

  testWidgets('does not override a paused binding', (tester) async {
    final binding = tester.binding;
    addTearDown(() => _restoreResumed(binding));
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.paused);

    expect(
      () => ensureMacosIntegrationTestFramesEnabled(binding),
      throwsA(isA<TestFailure>()),
    );
    expect(binding.lifecycleState, AppLifecycleState.paused);
    expect(binding.framesEnabled, isFalse);

    _restoreResumed(binding);
    expect(binding.lifecycleState, AppLifecycleState.resumed);
    expect(binding.framesEnabled, isTrue);
  });
}

void _restoreResumed(TestWidgetsFlutterBinding binding) {
  switch (binding.lifecycleState) {
    case AppLifecycleState.paused:
      binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    case AppLifecycleState.hidden:
      binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    case AppLifecycleState.inactive:
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    case AppLifecycleState.detached:
    case null:
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    case AppLifecycleState.resumed:
      break;
  }
  expect(binding.lifecycleState, AppLifecycleState.resumed);
}

final class _LifecycleObserver with WidgetsBindingObserver {
  _LifecycleObserver(this.onStateChanged);

  final ValueChanged<AppLifecycleState> onStateChanged;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onStateChanged(state);
  }
}
