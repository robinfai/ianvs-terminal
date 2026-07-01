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
    this.toolbelt,
    this.splitRight,
    this.splitDown,
    this.closePane,
    this.focusNextPane,
    this.focusPreviousPane,
    this.copy,
    this.copyMode,
    this.paste,
    this.advancedPaste,
    this.pasteHistory,
    this.instantReplay,
    this.globalSearch,
    this.autocomplete,
    this.autoComposer,
    this.copyCommandOutput,
    this.searchScrollback,
    this.nextSearchMatch,
    this.previousSearchMatch,
    this.clearSearch,
    this.nextPrompt,
    this.previousPrompt,
    this.selectCommandOutput,
    this.shellIntegrationUtilities,
    this.openRecentDirectory,
    this.tmuxIntegration,
    this.coprocess,
    this.annotations,
    this.capturedOutput,
    this.passwordManager,
    this.clearScrollback,
    this.toggleReadOnly,
    this.toggleCommandPalette,
    this.toggleHotkeyWindow,
    this.openDefaults,
    this.defaults,
    this.profiles,
    this.dynamicProfiles,
    this.openThemePicker,
    this.applyLayoutTemplate,
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
    this.applyTheme,
    this.toggleCommandFinishedNotify,
    this.toggleBellNotify,
    this.toggleSilenceMonitor,
    this.toggleActivityMonitor,
  });

  final ShellActionBinding? newTab;
  final ShellActionBinding? closeTab;
  final ShellActionBinding? reopenClosedTab;
  final ShellActionBinding? reopenClosedPane;
  final ShellActionBinding? duplicateCurrentCwd;
  final ShellActionBinding? toolbelt;
  final ShellActionBinding? splitRight;
  final ShellActionBinding? splitDown;
  final ShellActionBinding? closePane;
  final ShellActionBinding? focusNextPane;
  final ShellActionBinding? focusPreviousPane;
  final ShellActionBinding? copy;
  final ShellActionBinding? copyMode;
  final ShellActionBinding? paste;
  final ShellActionBinding? advancedPaste;
  final ShellActionBinding? pasteHistory;
  final ShellActionBinding? instantReplay;
  final ShellActionBinding? globalSearch;
  final ShellActionBinding? autocomplete;
  final ShellActionBinding? autoComposer;
  final ShellActionBinding? copyCommandOutput;
  final ShellActionBinding? searchScrollback;
  final ShellActionBinding? nextSearchMatch;
  final ShellActionBinding? previousSearchMatch;
  final ShellActionBinding? clearSearch;
  final ShellActionBinding? nextPrompt;
  final ShellActionBinding? previousPrompt;
  final ShellActionBinding? selectCommandOutput;
  final ShellActionBinding? shellIntegrationUtilities;
  final ShellActionBinding? openRecentDirectory;
  final ShellActionBinding? tmuxIntegration;
  final ShellActionBinding? coprocess;
  final ShellActionBinding? annotations;
  final ShellActionBinding? capturedOutput;
  final ShellActionBinding? passwordManager;
  final ShellActionBinding? clearScrollback;
  final ShellActionBinding? toggleReadOnly;
  final ShellActionBinding? toggleCommandPalette;
  final ShellActionBinding? toggleHotkeyWindow;
  final ShellActionBinding? openDefaults;
  final ShellActionBinding? defaults;
  final ShellActionBinding? profiles;
  final ShellActionBinding? dynamicProfiles;
  final ShellActionBinding? openThemePicker;
  final ShellActionBinding? applyLayoutTemplate;
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
  final ShellActionBinding? applyTheme;
  final ShellActionBinding? toggleCommandFinishedNotify;
  final ShellActionBinding? toggleBellNotify;
  final ShellActionBinding? toggleSilenceMonitor;
  final ShellActionBinding? toggleActivityMonitor;

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
    add('toolbelt', toolbelt);
    add('splitRight', splitRight);
    add('splitDown', splitDown);
    add('closePane', closePane);
    add('focusNextPane', focusNextPane);
    add('focusPreviousPane', focusPreviousPane);
    add('copy', copy);
    add('copyMode', copyMode);
    add('paste', paste);
    add('advancedPaste', advancedPaste);
    add('pasteHistory', pasteHistory);
    add('instantReplay', instantReplay);
    add('globalSearch', globalSearch);
    add('autocomplete', autocomplete);
    add('autoComposer', autoComposer);
    add('copyCommandOutput', copyCommandOutput);
    add('searchScrollback', searchScrollback);
    add('nextSearchMatch', nextSearchMatch);
    add('previousSearchMatch', previousSearchMatch);
    add('clearSearch', clearSearch);
    add('nextPrompt', nextPrompt);
    add('previousPrompt', previousPrompt);
    add('selectCommandOutput', selectCommandOutput);
    add('shellIntegrationUtilities', shellIntegrationUtilities);
    add('openRecentDirectory', openRecentDirectory);
    add('tmuxIntegration', tmuxIntegration);
    add('coprocess', coprocess);
    add('annotations', annotations);
    add('capturedOutput', capturedOutput);
    add('passwordManager', passwordManager);
    add('clearScrollback', clearScrollback);
    add('toggleReadOnly', toggleReadOnly);
    add('toggleCommandPalette', toggleCommandPalette);
    add('toggleHotkeyWindow', toggleHotkeyWindow);
    add('openDefaults', openDefaults);
    add('defaults', defaults);
    add('profiles', profiles);
    add('dynamicProfiles', dynamicProfiles);
    add('openThemePicker', openThemePicker);
    add('applyLayoutTemplate', applyLayoutTemplate);
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
    add('applyTheme', applyTheme);
    add('toggleCommandFinishedNotify', toggleCommandFinishedNotify);
    add('toggleBellNotify', toggleBellNotify);
    add('toggleSilenceMonitor', toggleSilenceMonitor);
    add('toggleActivityMonitor', toggleActivityMonitor);

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
