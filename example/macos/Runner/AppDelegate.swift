import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  static var suppressNextLastWindowTerminate = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    scheduleForegroundMainWindow(for: NSApp)
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
    Self.foregroundMainWindow(in: sender)
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  static func preferredForegroundWindow(from windows: [NSWindow]) -> NSWindow? {
    windows.first { $0 is MainFlutterWindow }
      ?? windows.first { $0.canBecomeKey }
      ?? windows.first
  }

  static func foregroundMainWindow(in app: NSApplication) {
    guard let window = preferredForegroundWindow(from: app.windows) else {
      return
    }

    if window.isMiniaturized {
      window.deminiaturize(nil)
    }

    app.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  private func scheduleForegroundMainWindow(for app: NSApplication) {
    DispatchQueue.main.async {
      Self.foregroundMainWindow(in: app)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      Self.foregroundMainWindow(in: app)
    }
  }
}
