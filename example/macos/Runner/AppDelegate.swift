import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  static var suppressNextLastWindowTerminate = false
  static var suppressNextTerminateConfirmation = false
  static let dartShutdownTimeout: TimeInterval = 10

  private var terminationReplyPending = false
  private var terminationAttemptGeneration: UInt64 = 0
  private var pendingTerminationAttempt: UInt64?
  private var shutdownCompleted = false
  private var shutdownTimeoutWorkItem: DispatchWorkItem?

  // Injectable process-boundary seams keep the terminate-later handshake
  // deterministic in RunnerTests without replacing NSApplication itself.
  var dartShutdownRequestOverride:
    ((NSApplication, @escaping (DartShutdownSafety) -> Void) -> Void)?
  var terminationReplyOverride: ((NSApplication, Bool) -> Void)?
  var shutdownTimeoutSchedulerOverride: ((TimeInterval, @escaping () -> Void) -> DispatchWorkItem)?
  var unsafeTerminationConfirmationOverride: ((DartShutdownSafety.UnsafeReason) -> Bool)?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    scheduleForegroundMainWindow(for: NSApp)
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
  {
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
    terminationAttemptGeneration &+= 1
    let attempt = terminationAttemptGeneration
    pendingTerminationAttempt = attempt
    requestDartShutdownBeforeTermination(sender, attempt: attempt)
    return .terminateLater
  }

  private func requestDartShutdownBeforeTermination(
    _ sender: NSApplication,
    attempt: UInt64
  ) {
    let timeoutHandler = { [weak self, weak sender] in
      guard let self, let sender else {
        return
      }
      self.resolveUnsafeTermination(
        .dartTimedOut,
        sender: sender,
        attempt: attempt
      )
    }
    let timeoutWorkItem: DispatchWorkItem
    if let scheduler = shutdownTimeoutSchedulerOverride {
      timeoutWorkItem = scheduler(Self.dartShutdownTimeout, timeoutHandler)
    } else {
      timeoutWorkItem = DispatchWorkItem(block: timeoutHandler)
      DispatchQueue.main.asyncAfter(
        deadline: .now() + Self.dartShutdownTimeout,
        execute: timeoutWorkItem
      )
    }
    shutdownTimeoutWorkItem?.cancel()
    shutdownTimeoutWorkItem = timeoutWorkItem

    // Defer the channel call until after applicationShouldTerminate has
    // returned .terminateLater. This also makes a missing Flutter window safe.
    DispatchQueue.main.async { [weak self, weak sender] in
      guard let self, let sender else {
        return
      }
      let completion: (DartShutdownSafety) -> Void = { [weak self, weak sender] safety in
        DispatchQueue.main.async {
          guard let self, let sender else {
            return
          }
          self.resolveDartShutdown(safety, sender: sender, attempt: attempt)
        }
      }
      if let request = self.dartShutdownRequestOverride {
        request(sender, completion)
        return
      }
      guard
        let window = Self.preferredForegroundWindow(from: sender.windows)
          as? MainFlutterWindow
      else {
        completion(.unsafeToTerminate(.channelUnavailable))
        return
      }
      window.requestDartShutdown(completion: completion)
    }
  }

  private func resolveDartShutdown(
    _ safety: DartShutdownSafety,
    sender: NSApplication,
    attempt: UInt64
  ) {
    guard pendingTerminationAttempt == attempt else {
      return
    }
    switch safety {
    case .safeToTerminate:
      finishTermination(sender, attempt: attempt)
    case .unsafeToTerminate(let reason):
      resolveUnsafeTermination(reason, sender: sender, attempt: attempt)
    }
  }

  private func resolveUnsafeTermination(
    _ reason: DartShutdownSafety.UnsafeReason,
    sender: NSApplication,
    attempt: UInt64
  ) {
    guard pendingTerminationAttempt == attempt else {
      return
    }
    let forceTermination =
      unsafeTerminationConfirmationOverride?(reason)
      ?? Self.confirmUnsafeApplicationTermination(reason: reason)
    if forceTermination {
      finishTermination(sender, attempt: attempt)
      return
    }
    cancelTermination(sender, attempt: attempt)
  }

  private func finishTermination(_ sender: NSApplication, attempt: UInt64) {
    guard pendingTerminationAttempt == attempt else {
      return
    }
    terminationReplyPending = false
    pendingTerminationAttempt = nil
    shutdownCompleted = true
    shutdownTimeoutWorkItem?.cancel()
    shutdownTimeoutWorkItem = nil
    reply(to: sender, shouldTerminate: true)
  }

  private func cancelTermination(_ sender: NSApplication, attempt: UInt64) {
    guard pendingTerminationAttempt == attempt else {
      return
    }
    terminationReplyPending = false
    pendingTerminationAttempt = nil
    shutdownCompleted = false
    shutdownTimeoutWorkItem?.cancel()
    shutdownTimeoutWorkItem = nil
    Self.suppressNextLastWindowTerminate = false
    Self.suppressNextTerminateConfirmation = false
    reply(to: sender, shouldTerminate: false)
  }

  private func reply(to sender: NSApplication, shouldTerminate: Bool) {
    if let replyOverride = terminationReplyOverride {
      replyOverride(sender, shouldTerminate)
      return
    }
    sender.reply(toApplicationShouldTerminate: shouldTerminate)
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

  static func confirmUnsafeApplicationTermination(
    reason: DartShutdownSafety.UnsafeReason
  ) -> Bool {
    let alert = NSAlert()
    alert.messageText = "Ianvs Terminal Is Still Finishing Up"
    alert.informativeText =
      switch reason {
      case .dartTimedOut:
        "Session recordings or other runtime resources are still being saved. "
          + "Keep the app open and try Quit again. Quitting now may lose data."
      case .channelUnavailable, .invalidResponse, .dartRejectedTermination:
        "Ianvs Terminal could not confirm that session recordings and runtime "
          + "resources are safe. Keep the app open and try Quit again. "
          + "Quitting now may lose data."
      }
    alert.alertStyle = .critical
    let keepRunningButton = alert.addButton(withTitle: "Keep Running")
    _ = alert.addButton(withTitle: "Quit Anyway")
    keepRunningButton.keyEquivalent = "\u{1b}"

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
