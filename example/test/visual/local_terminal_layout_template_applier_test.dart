import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/visual/local_terminal_layout_template_applier.dart';
import 'package:app/features/visual/local_terminal_visual_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal layout template applier', () {
    test('applies local one-pane template', () {
      final workspace = LocalTerminalLayoutTemplateApplier.apply(
        template: const LocalTerminalLayoutTemplate(
          id: 'one',
          name: 'One',
          paneCount: 1,
          localOnly: true,
        ),
        context: _context(),
      );

      expect(workspace, isNotNull);
      expect(workspace!.activeTab!.root.isLeaf, isTrue);
      expect(workspace.activeTab!.activePaneId, 'pane-1');
    });

    test('applies local two-pane template', () {
      final workspace = LocalTerminalLayoutTemplateApplier.apply(
        template: const LocalTerminalLayoutTemplate(
          id: 'two',
          name: 'Two',
          paneCount: 2,
          localOnly: true,
        ),
        context: _context(),
      );

      expect(workspace, isNotNull);
      expect(workspace!.activeTab!.root.isLeaf, isFalse);
      expect(workspace.activeTab!.root.containsPane('pane-2'), isTrue);
    });

    test('rejects non-local template', () {
      final workspace = LocalTerminalLayoutTemplateApplier.apply(
        template: const LocalTerminalLayoutTemplate(
          id: 'remote',
          name: 'Remote',
          paneCount: 2,
          localOnly: false,
        ),
        context: _context(),
      );

      expect(workspace, isNull);
    });

    test('rejects unsupported multi-pane template', () {
      final workspace = LocalTerminalLayoutTemplateApplier.apply(
        template: const LocalTerminalLayoutTemplate(
          id: 'three',
          name: 'Three',
          paneCount: 3,
          localOnly: true,
        ),
        context: _context(),
      );

      expect(workspace, isNull);
    });
  });
}

LocalTerminalLayoutTemplateApplyContext _context() {
  return const LocalTerminalLayoutTemplateApplyContext(
    tabId: 'tab-1',
    firstPaneId: 'pane-1',
    secondPaneId: 'pane-2',
    splitNodeId: 'split-1',
    sessionIntent: TerminalRelaunchSpec(profileId: 'default'),
  );
}
