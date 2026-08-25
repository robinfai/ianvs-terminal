import Cocoa
import FlutterMacOS
import XCTest
@testable import Ianvs_Terminal_Dev

private final class CloseTrackingMainFlutterWindow: MainFlutterWindow {
  private(set) var didRequestCloseConfirmation = false

  override func shouldCloseWindowAfterConfirmation() -> Bool {
    didRequestCloseConfirmation = true
    return false
  }
}

private final class ConfirmedCloseTrackingMainFlutterWindow: MainFlutterWindow {
  private(set) var terminationRequestCount = 0

  override func shouldCloseWindowAfterConfirmation() -> Bool {
    return true
  }

  override func requestApplicationTermination() {
    terminationRequestCount += 1
  }
}

private final class DragTrackingMainFlutterWindow: MainFlutterWindow {
  private(set) var performedDragEvent: NSEvent?

  override func performDrag(with event: NSEvent) {
    performedDragEvent = event
  }
}

class RunnerTests: XCTestCase {

  override func tearDown() {
    AppDelegate.suppressNextLastWindowTerminate = false
    AppDelegate.suppressNextTerminateConfirmation = false
    super.tearDown()
  }

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

  func testApplicationDidFinishLaunchingDoesNotCallMissingSuperclassSelector() {
    let delegate = AppDelegate()

    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification)
    )
  }

  func testDartShutdownMessageRequiresExplicitSafeTerminationContract() {
    XCTAssertEqual(
      DartShutdownSafety.fromPlatformResult([
        "completed": true,
        "timedOut": false,
        "safeToTerminate": true,
        "unsafeToTerminate": false,
      ]),
      .safeToTerminate
    )
    XCTAssertEqual(
      DartShutdownSafety.fromPlatformResult([
        "completed": false,
        "timedOut": true,
        "safeToTerminate": false,
        "unsafeToTerminate": true,
      ]),
      .unsafeToTerminate(.dartTimedOut)
    )
    XCTAssertEqual(
      DartShutdownSafety.fromPlatformResult([
        "completed": true,
        "timedOut": false,
      ]),
      .unsafeToTerminate(.invalidResponse)
    )
  }

  func testTimedOutPendingShutdownCancelsQuitAndAFutureQuitCanRetry() {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    var shutdownRequests: [(DartShutdownSafety) -> Void] = []
    var replies: [Bool] = []
    var scheduledTimeouts: [() -> Void] = []
    let firstRequest = expectation(description: "first Dart shutdown request")
    let firstReply = expectation(description: "first termination reply")

    delegate.dartShutdownRequestOverride = { _, completion in
      shutdownRequests.append(completion)
      if shutdownRequests.count == 1 {
        firstRequest.fulfill()
      }
    }
    delegate.terminationReplyOverride = { _, shouldTerminate in
      replies.append(shouldTerminate)
      if replies.count == 1 {
        firstReply.fulfill()
      }
    }
    delegate.shutdownTimeoutSchedulerOverride = { _, handler in
      scheduledTimeouts.append(handler)
      return DispatchWorkItem {}
    }
    delegate.unsafeTerminationConfirmationOverride = { _ in false }

    AppDelegate.suppressNextTerminateConfirmation = true
    XCTAssertEqual(delegate.applicationShouldTerminate(app), .terminateLater)
    wait(for: [firstRequest], timeout: 1)

    // A pending recording keeps the Dart result unsafe. The native timeout
    // must cancel this quit instead of destroying the Flutter engine.
    scheduledTimeouts.first?()
    wait(for: [firstReply], timeout: 1)
    XCTAssertEqual(replies, [false])
    XCTAssertFalse(AppDelegate.suppressNextTerminateConfirmation)
    XCTAssertFalse(AppDelegate.suppressNextLastWindowTerminate)

    let secondRequest = expectation(description: "retry Dart shutdown request")
    let secondReply = expectation(description: "retry termination reply")
    delegate.dartShutdownRequestOverride = { _, completion in
      shutdownRequests.append(completion)
      secondRequest.fulfill()
    }
    delegate.terminationReplyOverride = { _, shouldTerminate in
      replies.append(shouldTerminate)
      secondReply.fulfill()
    }
    AppDelegate.suppressNextTerminateConfirmation = true
    XCTAssertEqual(delegate.applicationShouldTerminate(app), .terminateLater)
    wait(for: [secondRequest], timeout: 1)

    let staleAttemptDrained = expectation(
      description: "stale termination attempt callbacks drained"
    )
    shutdownRequests.first?(.safeToTerminate)
    scheduledTimeouts.first?()
    DispatchQueue.main.async {
      staleAttemptDrained.fulfill()
    }
    wait(for: [staleAttemptDrained], timeout: 1)
    XCTAssertEqual(replies, [false])

    shutdownRequests.last?(.safeToTerminate)
    wait(for: [secondReply], timeout: 1)

    XCTAssertEqual(shutdownRequests.count, 2)
    XCTAssertEqual(replies, [false, true])
  }

  func testDartTimedOutReplyCancelsQuitWithoutWaitingForNativeFallback() {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    var reply: Bool?
    let request = expectation(description: "Dart shutdown request")
    let didReply = expectation(description: "termination reply")

    delegate.dartShutdownRequestOverride = { _, completion in
      request.fulfill()
      completion(.unsafeToTerminate(.dartTimedOut))
    }
    delegate.terminationReplyOverride = { _, shouldTerminate in
      reply = shouldTerminate
      didReply.fulfill()
    }
    delegate.shutdownTimeoutSchedulerOverride = { _, _ in DispatchWorkItem {} }
    delegate.unsafeTerminationConfirmationOverride = { reason in
      XCTAssertEqual(reason, .dartTimedOut)
      return false
    }

    AppDelegate.suppressNextTerminateConfirmation = true
    XCTAssertEqual(delegate.applicationShouldTerminate(app), .terminateLater)
    wait(for: [request, didReply], timeout: 1)

    XCTAssertEqual(reply, false)
    XCTAssertFalse(AppDelegate.suppressNextTerminateConfirmation)
  }

  func testUnsafeDartResultOnlyTerminatesAfterExplicitSecondConfirmation() {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    var reply: Bool?
    let request = expectation(description: "Dart shutdown request")
    let didReply = expectation(description: "termination reply")

    delegate.dartShutdownRequestOverride = { _, completion in
      request.fulfill()
      completion(.unsafeToTerminate(.dartRejectedTermination))
    }
    delegate.terminationReplyOverride = { _, shouldTerminate in
      reply = shouldTerminate
      didReply.fulfill()
    }
    delegate.shutdownTimeoutSchedulerOverride = { _, _ in DispatchWorkItem {} }
    delegate.unsafeTerminationConfirmationOverride = { reason in
      XCTAssertEqual(reason, .dartRejectedTermination)
      return true
    }

    AppDelegate.suppressNextTerminateConfirmation = true
    XCTAssertEqual(delegate.applicationShouldTerminate(app), .terminateLater)
    wait(for: [request, didReply], timeout: 1)
    XCTAssertEqual(reply, true)
  }

  func testMainWindowCloseIsCancelledBeforeTheWindowCloses() {
    let window = CloseTrackingMainFlutterWindow()

    window.installWindowCloseConfirmationDelegate()

    XCTAssertTrue(window.delegate === window)
    XCTAssertFalse(window.windowShouldClose(window))
    XCTAssertTrue(window.didRequestCloseConfirmation)
  }

  func testConfirmedMainWindowCloseKeepsFlutterAliveAndRequestsAppTermination() {
    let window = ConfirmedCloseTrackingMainFlutterWindow()

    window.installWindowCloseConfirmationDelegate()

    XCTAssertFalse(window.windowShouldClose(window))
    XCTAssertEqual(window.terminationRequestCount, 1)
    XCTAssertTrue(AppDelegate.suppressNextTerminateConfirmation)
    AppDelegate.suppressNextTerminateConfirmation = false
  }

  func testTerminalFolderFileMenuIsStandardAndIdempotent() throws {
    let window = MainFlutterWindow()
    let mainMenu = NSMenu(title: "Main Menu")
    mainMenu.addItem(NSMenuItem(title: "Ianvs Terminal", action: nil, keyEquivalent: ""))

    window.bindNativeTerminalFolderMenuItem(in: mainMenu)
    window.bindNativeTerminalFolderMenuItem(in: mainMenu)

    let fileItems = mainMenu.items.filter { $0.title == "File" }
    let fileItem = try XCTUnwrap(fileItems.first)
    let openItems = try XCTUnwrap(fileItem.submenu).items.filter {
      $0.title == "New Tab at Folder…"
    }
    let openItem = try XCTUnwrap(openItems.first)
    XCTAssertEqual(fileItems.count, 1)
    XCTAssertEqual(openItems.count, 1)
    XCTAssertEqual(openItem.keyEquivalent, "o")
    XCTAssertEqual(openItem.keyEquivalentModifierMask, [.command])
    XCTAssertTrue(openItem.target === window)
    XCTAssertEqual(openItem.action, #selector(MainFlutterWindow.openTerminalAtFolder(_:)))
  }

  func testSettingsMenuIsEnabledStandardAndIdempotent() throws {
    let window = MainFlutterWindow()
    let mainMenu = NSMenu(title: "Main Menu")
    let appMenuItem = NSMenuItem(
      title: "Ianvs Terminal",
      action: nil,
      keyEquivalent: ""
    )
    let appMenu = NSMenu(title: "Ianvs Terminal")
    appMenu.addItem(
      NSMenuItem(title: "About Ianvs Terminal", action: nil, keyEquivalent: "")
    )
    appMenu.addItem(
      NSMenuItem(title: "Preferences…", action: nil, keyEquivalent: ",")
    )
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    window.bindNativeSettingsMenuItem(in: mainMenu)
    window.bindNativeSettingsMenuItem(in: mainMenu)

    let settingsItems = appMenu.items.filter { $0.title == "Settings…" }
    let settingsItem = try XCTUnwrap(settingsItems.first)
    XCTAssertEqual(settingsItems.count, 1)
    XCTAssertEqual(settingsItem.keyEquivalent, ",")
    XCTAssertEqual(settingsItem.keyEquivalentModifierMask, [.command])
    XCTAssertTrue(settingsItem.isEnabled)
    XCTAssertTrue(settingsItem.target === window)
    XCTAssertEqual(
      settingsItem.action,
      #selector(MainFlutterWindow.openSettings(_:))
    )
  }

  func testTerminalSessionFileMenuUsesRequestedShortcutsAndIsIdempotent() throws {
    let window = MainFlutterWindow()
    let mainMenu = NSMenu(title: "Main Menu")
    mainMenu.addItem(NSMenuItem(title: "Ianvs Terminal", action: nil, keyEquivalent: ""))

    window.bindNativeTerminalSessionMenuItems(in: mainMenu)
    window.bindNativeTerminalSessionMenuItems(in: mainMenu)

    let fileMenu = try XCTUnwrap(mainMenu.items.first { $0.title == "File" }?.submenu)
    let localItems = fileMenu.items.filter { $0.title == "New Tab" }
    let sshItems = fileMenu.items.filter { $0.title == "New SSH Session…" }
    let localItem = try XCTUnwrap(localItems.first)
    let sshItem = try XCTUnwrap(sshItems.first)

    XCTAssertEqual(localItems.count, 1)
    XCTAssertEqual(localItem.keyEquivalent, "t")
    XCTAssertEqual(localItem.keyEquivalentModifierMask, [.command])
    XCTAssertTrue(localItem.target === window)
    XCTAssertEqual(localItem.action, #selector(MainFlutterWindow.openNewTab(_:)))

    XCTAssertEqual(sshItems.count, 1)
    XCTAssertEqual(sshItem.keyEquivalent, "t")
    XCTAssertEqual(sshItem.keyEquivalentModifierMask, [.command, .shift])
    XCTAssertTrue(sshItem.target === window)
    XCTAssertEqual(sshItem.action, #selector(MainFlutterWindow.openSshSession(_:)))
  }

  func testMainWindowFrameUsesStableAutosaveName() {
    XCTAssertEqual(
      MainFlutterWindow.mainWindowFrameAutosaveName,
      "IanvsTerminalMainWindow"
    )
  }

  func testMainWindowChromeRestoresFrameAfterApplyingFullSizeStyle() {
    let autosaveName = "RunnerTests.MainWindow.\(UUID().uuidString)"
    defer { NSWindow.removeFrame(usingName: autosaveName) }
    let styleMask: NSWindow.StyleMask = [
      .titled,
      .closable,
      .miniaturizable,
      .resizable,
    ]
    let seedWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
      styleMask: styleMask,
      backing: .buffered,
      defer: false
    )
    seedWindow.setFrame(
      NSRect(x: 120, y: 160, width: 920, height: 680),
      display: false
    )
    let savedFrame = seedWindow.frame
    seedWindow.saveFrame(usingName: autosaveName)

    let window = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: styleMask,
      backing: .buffered,
      defer: false
    )

    XCTAssertTrue(
      window.configureMainWindowChromeAndRestoreFrame(
        autosaveName: autosaveName
      )
    )
    XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
    XCTAssertTrue(window.isMovable)
    XCTAssertEqual(window.frame.origin.x, savedFrame.origin.x, accuracy: 0.01)
    XCTAssertEqual(window.frame.origin.y, savedFrame.origin.y, accuracy: 0.01)
    XCTAssertEqual(window.frame.width, savedFrame.width, accuracy: 0.01)
    XCTAssertEqual(window.frame.height, savedFrame.height, accuracy: 0.01)

    let firstRestoredFrame = window.frame
    XCTAssertTrue(
      window.configureMainWindowChromeAndRestoreFrame(
        autosaveName: autosaveName
      )
    )
    XCTAssertEqual(window.frame, firstRestoredFrame)
    _ = window.setFrameAutosaveName("")
    XCTAssertEqual(window.frameAutosaveName, "")
  }

  func testNotificationAuthorizationFailureUsesExpectedErrorCode() {
    let window = MainFlutterWindow()

    let error = window.notificationAuthorizationFailedError(
      message: "Notifications are disabled for Ianvs Terminal in System Settings."
    )

    XCTAssertEqual(error.code, "notification_authorization_failed")
    XCTAssertEqual(
      error.message,
      "Notifications are disabled for Ianvs Terminal in System Settings."
    )
    XCTAssertNil(error.details)
  }

  func testItermClipboardSelectionsMapToNamedPasteboards() {
    XCTAssertEqual(
      MainFlutterWindow.itermClipboardPasteboardName(for: "c"),
      NSPasteboard.Name.general
    )
    XCTAssertEqual(
      MainFlutterWindow.itermClipboardPasteboardName(for: "find"),
      NSPasteboard.Name.find
    )
    XCTAssertEqual(
      MainFlutterWindow.itermClipboardPasteboardName(for: "font"),
      NSPasteboard.Name.font
    )
    XCTAssertEqual(
      MainFlutterWindow.itermClipboardPasteboardName(for: "unknown"),
      NSPasteboard.Name.general
    )
  }

  func testPreferredForegroundWindowChoosesFlutterWindowFirst() {
    let utilityWindow = NSWindow()
    let mainWindow = MainFlutterWindow()

    let selected = AppDelegate.preferredForegroundWindow(
      from: [utilityWindow, mainWindow]
    )

    XCTAssertTrue(selected === mainWindow)
  }

  func testPreferredForegroundWindowFallsBackToKeyCapableWindow() {
    let keyCapableWindow = NSWindow()

    let selected = AppDelegate.preferredForegroundWindow(
      from: [keyCapableWindow]
    )

    XCTAssertTrue(selected === keyCapableWindow)
  }

  func testNativeWindowDragRegionCoversTitlebarExceptTrailingControls() {
    let contentSize = NSSize(width: 900, height: 600)

    XCTAssertTrue(
      MainFlutterWindow.shouldStartNativeWindowDrag(
        at: NSPoint(x: 80, y: 580),
        contentSize: contentSize
      )
    )
    XCTAssertTrue(
      MainFlutterWindow.shouldStartNativeWindowDrag(
        at: NSPoint(x: 450, y: 580),
        contentSize: contentSize
      )
    )
    XCTAssertFalse(
      MainFlutterWindow.shouldStartNativeWindowDrag(
        at: NSPoint(x: 880, y: 580),
        contentSize: contentSize
      )
    )
    XCTAssertFalse(
      MainFlutterWindow.shouldStartNativeWindowDrag(
        at: NSPoint(x: 80, y: 530),
        contentSize: contentSize
      )
    )
  }

  func testNativeWindowDragRegionAvoidsStandardWindowButtons() {
    let contentSize = NSSize(width: 900, height: 600)
    let closeButtonFrame = NSRect(x: 16, y: 570, width: 14, height: 14)

    XCTAssertFalse(
      MainFlutterWindow.shouldStartNativeWindowDrag(
        at: NSPoint(x: 22, y: 577),
        contentSize: contentSize,
        standardButtonFrames: [closeButtonFrame]
      )
    )
    XCTAssertTrue(
      MainFlutterWindow.shouldStartNativeWindowDrag(
        at: NSPoint(x: 80, y: 577),
        contentSize: contentSize,
        standardButtonFrames: [closeButtonFrame]
      )
    )
  }

  func testNativeWindowDragRegionMatchesScreenCoordinates() {
    let windowFrame = NSRect(x: 100, y: 200, width: 800, height: 600)

    XCTAssertTrue(
      MainFlutterWindow.shouldStartNativeWindowDrag(
        atMouseLocation: NSPoint(x: 190, y: 778),
        windowFrame: windowFrame
      )
    )
    XCTAssertTrue(
      MainFlutterWindow.shouldStartNativeWindowDrag(
        atMouseLocation: NSPoint(x: 500, y: 778),
        windowFrame: windowFrame
      )
    )
    XCTAssertFalse(
      MainFlutterWindow.shouldStartNativeWindowDrag(
        atMouseLocation: NSPoint(x: 870, y: 778),
        windowFrame: windowFrame
      )
    )
    XCTAssertFalse(
      MainFlutterWindow.shouldStartNativeWindowDrag(
        atMouseLocation: NSPoint(x: 190, y: 730),
        windowFrame: windowFrame
      )
    )
  }

  func testNativeWindowDragRegionAvoidsStandardWindowButtonsInScreenCoordinates() {
    let windowFrame = NSRect(x: 100, y: 200, width: 800, height: 600)
    let closeButtonFrame = NSRect(x: 116, y: 770, width: 14, height: 14)

    XCTAssertFalse(
      MainFlutterWindow.shouldStartNativeWindowDrag(
        atMouseLocation: NSPoint(x: 122, y: 777),
        windowFrame: windowFrame,
        standardButtonFrames: [closeButtonFrame]
      )
    )
    XCTAssertTrue(
      MainFlutterWindow.shouldStartNativeWindowDrag(
        atMouseLocation: NSPoint(x: 190, y: 777),
        windowFrame: windowFrame,
        standardButtonFrames: [closeButtonFrame]
      )
    )
  }

  func testNativeWindowDragUsesOriginalMouseDownEventSynchronously() throws {
    let window = DragTrackingMainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.styleMask.insert(.fullSizeContentView)
    window.setFrame(
      NSRect(x: 100, y: 200, width: 800, height: 600),
      display: false
    )
    let mouseDown = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: NSPoint(x: 400, y: 580),
        modifierFlags: [],
        timestamp: 1,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1
      )
    )

    XCTAssertTrue(window.performNativeWindowDragIfNeeded(for: mouseDown))
    XCTAssertTrue(window.performedDragEvent === mouseDown)
  }

  func testOsc72PasteboardAndOperationMappingsAreDeterministic() {
    XCTAssertEqual(
      MainFlutterWindow.osc72PasteboardTypes(for: "text/plain"),
      [.string]
    )
    XCTAssertEqual(
      MainFlutterWindow.osc72PasteboardTypes(for: "text/uri-list"),
      [.fileURL, .URL]
    )
    XCTAssertEqual(MainFlutterWindow.osc72OperationMask([.copy, .move]), 3)
    XCTAssertEqual(MainFlutterWindow.osc72OperationMask(.copy), 1)
    XCTAssertEqual(MainFlutterWindow.osc72OperationMask([]), 0)
  }

  func testUserAttentionMappingsAcceptOnlyOwnedModes() {
    XCTAssertEqual(
      MainFlutterWindow.userAttentionType(for: "critical"),
      .criticalRequest
    )
    XCTAssertEqual(
      MainFlutterWindow.userAttentionType(for: "informational"),
      .informationalRequest
    )
    XCTAssertNil(MainFlutterWindow.userAttentionType(for: "yes"))
    XCTAssertNil(MainFlutterWindow.userAttentionType(for: "critical "))
  }

  func testOsc72UriListAndBoundedReadRange() throws {
    let data = try XCTUnwrap(
      MainFlutterWindow.osc72UriListData([
        URL(fileURLWithPath: "/tmp/a b.txt"),
        URL(fileURLWithPath: "/tmp/c.txt")
      ])
    )
    XCTAssertEqual(
      String(data: data, encoding: .utf8),
      "file:///tmp/a%20b.txt\r\nfile:///tmp/c.txt\r\n"
    )
    XCTAssertEqual(
      MainFlutterWindow.osc72ReadRange(offset: 3072, maxBytes: 3072, dataCount: 5000),
      3072..<5000
    )
    XCTAssertNil(
      MainFlutterWindow.osc72ReadRange(offset: 0, maxBytes: 4096, dataCount: 5000)
    )
    XCTAssertNil(
      MainFlutterWindow.osc72ReadRange(offset: 5001, maxBytes: 1, dataCount: 5000)
    )
  }

  func testOsc5522MimeMappingsPatternsAndPasteboardListingAreDeterministic() throws {
    XCTAssertEqual(MainFlutterWindow.pasteboardType(forMime: "text/plain"), .string)
    XCTAssertEqual(MainFlutterWindow.pasteboardType(forMime: "image/png"), .png)
    XCTAssertEqual(MainFlutterWindow.mime(forPasteboardType: .html), "text/html")
    let customType = MainFlutterWindow.pasteboardType(
      forMime: "application/x-ianvs-probe"
    )
    XCTAssertTrue(customType.rawValue.hasPrefix("dev.ianvs.terminal.mime."))
    XCTAssertEqual(
      MainFlutterWindow.mime(forPasteboardType: customType),
      "application/x-ianvs-probe"
    )
    XCTAssertTrue(MainFlutterWindow.mimePattern("image/*", matches: "image/png"))
    XCTAssertTrue(MainFlutterWindow.mimePattern("*/*", matches: "application/pdf"))
    XCTAssertFalse(MainFlutterWindow.mimePattern("text/*", matches: "image/png"))

    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setData(Data([0, 1, 2]), forType: .png))
    XCTAssertTrue(pasteboard.setData(Data("hello".utf8), forType: .string))
    XCTAssertEqual(
      MainFlutterWindow.clipboardMimeTypes(pasteboard),
      ["image/png", "image/tiff", "text/plain"]
    )
    pasteboard.releaseGlobally()

    let customPasteboard = NSPasteboard.withUniqueName()
    XCTAssertTrue(
      MainFlutterWindow.writeClipboardEntries(
        [
          (customType, Data([3, 2, 1])),
          (
            MainFlutterWindow.pasteboardType(
              forMime: "application/octet-stream"
            ),
            Data([3, 2, 1])
          ),
        ],
        to: customPasteboard
      )
    )
    XCTAssertEqual(
      MainFlutterWindow.clipboardMimeTypes(customPasteboard),
      ["application/octet-stream", "application/x-ianvs-probe"]
    )
    XCTAssertEqual(customPasteboard.data(forType: customType), Data([3, 2, 1]))
    customPasteboard.releaseGlobally()
  }

}
