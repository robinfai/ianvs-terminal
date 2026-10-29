import 'package:app/ui/components/app_configuration_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('configuration text field exposes its visible label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppConfigurationField(
            label: 'API Key',
            child: TextField(obscureText: true),
          ),
        ),
      ),
    );
    expect(
      tester
          .getSemantics(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label == 'API Key' &&
                  widget.explicitChildNodes,
            ),
          )
          .label,
      contains('API Key'),
    );
    semantics.dispose();
  });
}
