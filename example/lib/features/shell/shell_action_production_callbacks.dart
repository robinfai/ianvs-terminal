import 'shell_action_production_action_set.dart';
import 'shell_action_production_binding_builder.dart';
import 'shell_action_runtime_bindings.dart';

class ShellActionProductionCallbacks {
  const ShellActionProductionCallbacks({
    this.newTab,
    this.closeTab,
    this.reopenClosedTab,
    this.reopenClosedPane,
    this.duplicateCurrentCwd,
    this.splitRight,
    this.splitDown,
    this.closePane,
    this.focusNextPane,
    this.focusPreviousPane,
    this.copy,
    this.paste,
    this.instantReplay,
    this.copyCommandOutput,
    this.searchScrollback,
    this.nextSearchMatch,
    this.previousSearchMatch,
    this.clearSearch,
    this.nextPrompt,
    this.previousPrompt,
    this.clearBuffer,
    this.toggleReadOnly,
    this.toggleCommandPalette,
    this.toggleHotkeyWindow,
    this.openDefaults,
    this.defaults,
    this.profiles,
    this.exportScrollback,
    this.exportDiagnostics,
    this.resizePaneLeft,
    this.resizePaneRight,
    this.resizePaneUp,
    this.resizePaneDown,
    this.swapPane,
    this.zoomPane,
    this.openProfile,
    this.editProfile,
    this.setDefaultProfile,
    this.toggleSilenceMonitor,
  });

  final ShellActionBinding? newTab;
  final ShellActionBinding? closeTab;
  final ShellActionBinding? reopenClosedTab;
  final ShellActionBinding? reopenClosedPane;
  final ShellActionBinding? duplicateCurrentCwd;
  final ShellActionBinding? splitRight;
  final ShellActionBinding? splitDown;
  final ShellActionBinding? closePane;
  final ShellActionBinding? focusNextPane;
  final ShellActionBinding? focusPreviousPane;
  final ShellActionBinding? copy;
  final ShellActionBinding? paste;
  final ShellActionBinding? instantReplay;
  final ShellActionBinding? copyCommandOutput;
  final ShellActionBinding? searchScrollback;
  final ShellActionBinding? nextSearchMatch;
  final ShellActionBinding? previousSearchMatch;
  final ShellActionBinding? clearSearch;
  final ShellActionBinding? nextPrompt;
  final ShellActionBinding? previousPrompt;
  final ShellActionBinding? clearBuffer;
  final ShellActionBinding? toggleReadOnly;
  final ShellActionBinding? toggleCommandPalette;
  final ShellActionBinding? toggleHotkeyWindow;
  final ShellActionBinding? openDefaults;
  final ShellActionBinding? defaults;
  final ShellActionBinding? profiles;
  final ShellActionBinding? exportScrollback;
  final ShellActionBinding? exportDiagnostics;
  final ShellActionBinding? resizePaneLeft;
  final ShellActionBinding? resizePaneRight;
  final ShellActionBinding? resizePaneUp;
  final ShellActionBinding? resizePaneDown;
  final ShellActionBinding? swapPane;
  final ShellActionBinding? zoomPane;
  final ShellActionBinding? openProfile;
  final ShellActionBinding? editProfile;
  final ShellActionBinding? setDefaultProfile;
  final ShellActionBinding? toggleSilenceMonitor;

  Map<String, ShellActionBinding> toBindingsByName() {
    final bindings = <String, ShellActionBinding>{};

    void add(String name, ShellActionBinding? binding) {
      if (binding != null) {
        bindings[name] = binding;
      }
    }

    add('newTab', newTab);
    add('closeTab', closeTab);
    add('reopenClosedTab', reopenClosedTab);
    add('reopenClosedPane', reopenClosedPane);
    add('duplicateCurrentCwd', duplicateCurrentCwd);
    add('splitRight', splitRight);
    add('splitDown', splitDown);
    add('closePane', closePane);
    add('focusNextPane', focusNextPane);
    add('focusPreviousPane', focusPreviousPane);
    add('copy', copy);
    add('paste', paste);
    add('instantReplay', instantReplay);
    add('copyCommandOutput', copyCommandOutput);
    add('searchScrollback', searchScrollback);
    add('nextSearchMatch', nextSearchMatch);
    add('previousSearchMatch', previousSearchMatch);
    add('clearSearch', clearSearch);
    add('nextPrompt', nextPrompt);
    add('previousPrompt', previousPrompt);
    add('clearBuffer', clearBuffer);
    add('toggleReadOnly', toggleReadOnly);
    add('toggleCommandPalette', toggleCommandPalette);
    add('toggleHotkeyWindow', toggleHotkeyWindow);
    add('openDefaults', openDefaults);
    add('defaults', defaults);
    add('profiles', profiles);
    add('exportScrollback', exportScrollback);
    add('exportDiagnostics', exportDiagnostics);
    add('resizePaneLeft', resizePaneLeft);
    add('resizePaneRight', resizePaneRight);
    add('resizePaneUp', resizePaneUp);
    add('resizePaneDown', resizePaneDown);
    add('swapPane', swapPane);
    add('zoomPane', zoomPane);
    add('openProfile', openProfile);
    add('editProfile', editProfile);
    add('setDefaultProfile', setDefaultProfile);
    add('toggleSilenceMonitor', toggleSilenceMonitor);

    return Map.unmodifiable(bindings);
  }

  ShellActionProductionBindingBuildResult build({
    ShellActionProductionActionSet? actionSet,
  }) {
    return ShellActionProductionBindingBuilder(
      actionSet: actionSet,
      bindingsByName: toBindingsByName(),
    ).build();
  }
}
