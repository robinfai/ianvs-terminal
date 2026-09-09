import 'package:flutter_test/flutter_test.dart';

/// Keeps visual reviews faithful to the application's actual popup shadows.
class ConfigurationCaptureBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}
