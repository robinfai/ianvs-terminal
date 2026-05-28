import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  static var suppressNextLastWindowTerminate = false

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
    if !flag, let window = sender.windows.first {
      window.makeKeyAndOrderFront(nil)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
