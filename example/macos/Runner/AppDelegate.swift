import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  static var suppressNextLastWindowTerminate = false
  static var suppressNextTerminateConfirmation = false
  static let dartShutdownTimeout: TimeInterval = 10

  private var terminationReplyPending = false
  private var shutdownCompleted = false
  private var shutdownTimeoutWorkItem: DispatchWorkItem?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    scheduleForegroundMainWindow(for: NSApp)
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if shutdownCompleted {
      DispatchQueue.main.async {
        sender.reply(toApplicationShouldTerminate: true)
      }
      return .terminateLater
    }

    if terminationReplyPending {
      return .terminateLater
    }

    if Self.suppressNextTerminateConfirmation {
      Self.suppressNextTerminateConfirmation = false
    } else if !Self.confirmApplicationTermination() {
      return .terminateCancel
    }

    terminationReplyPending = true
    requestDartShutdownBeforeTermination(sender)
    return .terminateLater
  }

  private func requestDartShutdownBeforeTermination(_ sender: NSApplication) {
    let timeoutWorkItem = DispatchWorkItem { [weak self, weak sender] in
      guard let self, let sender else {
        return
      }
      self.finishTermination(sender)
    }
    shutdownTimeoutWorkItem?.cancel()
    shutdownTimeoutWorkItem = timeoutWorkItem
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.dartShutdownTimeout,
      execute: timeoutWorkItem
    )

    // Defer the channel call until after applicationShouldTerminate has
    // returned .terminateLater. This also makes a missing Flutter window safe.
    DispatchQueue.main.async { [weak self, weak sender] in
      guard let self, let sender else {
        return
      }
      guard
        let window = Self.preferredForegroundWindow(from: sender.windows)
          as? MainFlutterWindow
      else {
        self.finishTermination(sender)
        return
      }
      window.requestDartShutdown { [weak self, weak sender] in
        DispatchQueue.main.async {
          guard let self, let sender else {
            return
          }
          self.finishTermination(sender)
        }
      }
    }
  }

  private func finishTermination(_ sender: NSApplication) {
    guard terminationReplyPending else {
      return
    }
    terminationReplyPending = false
    shutdownCompleted = true
    shutdownTimeoutWorkItem?.cancel()
    shutdownTimeoutWorkItem = nil
    sender.reply(toApplicationShouldTerminate: true)
  }

  static func confirmApplicationTermination() -> Bool {
    let alert = NSAlert()
    alert.messageText = "Quit Ianvs Terminal?"
    alert.informativeText = "Active shell sessions will be closed."
    alert.alertStyle = .warning
    let cancelButton = alert.addButton(withTitle: "Cancel")
    _ = alert.addButton(withTitle: "Quit")
    cancelButton.keyEquivalent = "\u{1b}"

    return alert.runModal() == .alertSecondButtonReturn
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
