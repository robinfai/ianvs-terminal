import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/visual/local_terminal_visual_action_reducer.dart';
import 'package:app/features/visual/local_terminal_visual_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal visual action reducer', () {
    test('open theme picker action returns picker result', () {
      final result = LocalTerminalVisualActionReducer.reduce(
        actionId: TerminalActionId.openThemePicker,
        context: const LocalTerminalVisualActionContext(),
      );

      expect(result, isA<LocalTerminalOpenThemePickerResult>());
    });

    test('export scrollback action builds export payload', () {
      final result = LocalTerminalVisualActionReducer.reduce(
        actionId: TerminalActionId.exportScrollback,
        context: const LocalTerminalVisualActionContext(
          scrollbackText: 'hello',
          exportFormat: LocalTerminalExportFormat.json,
        ),
      );

      expect(result, isA<LocalTerminalExportScrollbackResult>());
      expect(
        (result as LocalTerminalExportScrollbackResult).export.format,
        LocalTerminalExportFormat.json,
      );
      expect(result.export.content, 'hello');
    });

    test('unhandled visual action returns noop', () {
      final result = LocalTerminalVisualActionReducer.reduce(
        actionId: TerminalActionId.newTab,
        context: const LocalTerminalVisualActionContext(),
      );

      expect(result, isA<LocalTerminalVisualNoopResult>());
    });

    test('apply layout template action returns template result', () {
      final result = LocalTerminalVisualActionReducer.reduce(
        actionId: TerminalActionId.applyLayoutTemplate,
        context: const LocalTerminalVisualActionContext(
          layoutTemplate: LocalTerminalLayoutTemplate(
            id: 'two-pane',
            name: 'Two Pane',
            paneCount: 2,
            localOnly: true,
          ),
        ),
      );

      expect(result, isA<LocalTerminalApplyLayoutTemplateResult>());
      expect(
        (result as LocalTerminalApplyLayoutTemplateResult).template!.id,
        'two-pane',
      );
    });
  });
}
