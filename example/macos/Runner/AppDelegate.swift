import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  static var suppressNextLastWindowTerminate = false
  private static var registeredMainWindow: NSWindow?

  static func registerMainWindowForActivation(_ window: NSWindow) {
    registeredMainWindow = window
  }

  static func resetRegisteredMainWindowForTests() {
    registeredMainWindow = nil
  }

  static func savedApplicationStateURL(
    bundleIdentifier: String?,
    homeDirectory: URL
  ) -> URL? {
    guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
      return nil
    }
    return homeDirectory
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Saved Application State", isDirectory: true)
      .appendingPathComponent("\(bundleIdentifier).savedState", isDirectory: true)
  }

  static func removeSavedApplicationState(
    bundleIdentifier: String? = Bundle.main.bundleIdentifier,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    fileManager: FileManager = .default
  ) {
    guard
      let url = savedApplicationStateURL(
        bundleIdentifier: bundleIdentifier,
        homeDirectory: homeDirectory
      )
    else {
      return
    }
    try? fileManager.removeItem(at: url)
  }

  static func windowToShowForActivation(
    from windows: [NSWindow],
    fallback: NSWindow? = registeredMainWindow
  ) -> NSWindow? {
    windows.first { $0 is MainFlutterWindow } ??
      fallback ??
      registeredMainWindow ??
      windows.first
  }

  override func applicationWillFinishLaunching(_ notification: Notification) {
    Self.removeSavedApplicationState()
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    DispatchQueue.main.async { [weak self] in
      self?.showMainWindowIfAvailable(NSApp)
    }
  }

  override func applicationDidBecomeActive(_ notification: Notification) {
    showMainWindowIfAvailable(NSApp)
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let alert = NSAlert()
    alert.messageText = "Quit Ianvs Terminal?"
    alert.informativeText = "Active shell sessions will be closed."
    alert.alertStyle = .warning
    let cancelButton = alert.addButton(withTitle: "Cancel")
    _ = alert.addButton(withTitle: "Quit")
    cancelButton.keyEquivalent = "\u{1b}"

    return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    if Self.suppressNextLastWindowTerminate {
      Self.suppressNextLastWindowTerminate = false
      return false
    }
    return true
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      showMainWindowIfAvailable(sender)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return false
  }

  private func showMainWindowIfAvailable(_ sender: NSApplication) {
    guard let window = Self.windowToShowForActivation(
      from: sender.windows,
      fallback: mainFlutterWindow
    ) else {
      return
    }
    sender.activate(ignoringOtherApps: true)
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.makeKeyAndOrderFront(nil)
  }
}
