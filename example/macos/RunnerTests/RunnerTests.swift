import Cocoa
import FlutterMacOS
import XCTest
@testable import Ianvs_Terminal_Dev

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
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

  func testReopenChoosesMainFlutterWindowEvenWhenItIsHidden() {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    let mainWindow = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )

    XCTAssertIdentical(
      AppDelegate.windowToShowForActivation(from: [panel, mainWindow]),
      mainWindow
    )
  }

  func testReopenUsesRegisteredMainWindowWhenWindowListIsEmpty() {
    let mainWindow = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    defer { AppDelegate.resetRegisteredMainWindowForTests() }

    AppDelegate.registerMainWindowForActivation(mainWindow)

    XCTAssertIdentical(
      AppDelegate.windowToShowForActivation(from: []),
      mainWindow
    )
  }

  func testRegisteredMainWindowIsRetainedForActivationFallback() {
    weak var weakWindow: MainFlutterWindow?
    defer { AppDelegate.resetRegisteredMainWindowForTests() }

    autoreleasepool {
      let mainWindow = MainFlutterWindow(
        contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      weakWindow = mainWindow
      AppDelegate.registerMainWindowForActivation(mainWindow)
    }

    XCTAssertNotNil(weakWindow)
    XCTAssertIdentical(
      AppDelegate.windowToShowForActivation(from: []),
      weakWindow
    )
  }

  func testReopenUsesMainWindowOutletFallbackWhenWindowListIsEmpty() {
    let mainWindow = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    defer { AppDelegate.resetRegisteredMainWindowForTests() }

    AppDelegate.resetRegisteredMainWindowForTests()

    XCTAssertIdentical(
      AppDelegate.windowToShowForActivation(
        from: [],
        fallback: mainWindow
      ),
      mainWindow
    )
  }

  func testMainWindowOrdersFrontAfterAwakeWhenStillHidden() {
    XCTAssertTrue(MainFlutterWindow.shouldOrderFrontAfterAwake(isVisible: false))
    XCTAssertFalse(MainFlutterWindow.shouldOrderFrontAfterAwake(isVisible: true))
  }

  func testAppDoesNotRestoreStaleWindowStateOnLaunch() {
    let app = NSApplication.shared
    let delegate = AppDelegate()

    XCTAssertFalse(delegate.applicationSupportsSecureRestorableState(app))
  }

  func testNativeWindowDragRegionCoversOnlyLeadingChromeGap() {
    let contentSize = NSSize(width: 900, height: 600)

    XCTAssertTrue(
      MainFlutterWindow.shouldStartNativeWindowDrag(
        at: NSPoint(x: 80, y: 580),
        contentSize: contentSize
      )
    )
    XCTAssertFalse(
      MainFlutterWindow.shouldStartNativeWindowDrag(
        at: NSPoint(x: 150, y: 580),
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
    XCTAssertFalse(
      MainFlutterWindow.shouldStartNativeWindowDrag(
        atMouseLocation: NSPoint(x: 240, y: 778),
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

  func testNativeWindowDragOriginTracksGlobalMouseDelta() {
    let nextOrigin = MainFlutterWindow.nativeWindowDragOrigin(
      startFrameOrigin: NSPoint(x: -1178, y: 245),
      startMouseLocation: NSPoint(x: -1088, y: 822),
      currentMouseLocation: NSPoint(x: -948, y: 744)
    )

    XCTAssertEqual(nextOrigin.x, -1038)
    XCTAssertEqual(nextOrigin.y, 167)
  }

  func testLaunchFrameMovesBackInsideVisibleScreenWhenOffscreen() {
    let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let offscreenFrame = NSRect(x: -760, y: 394, width: 800, height: 600)

    let constrainedFrame = MainFlutterWindow.launchFrameInsideVisibleScreen(
      offscreenFrame,
      visibleFrame: visibleFrame
    )

    XCTAssertGreaterThanOrEqual(constrainedFrame.minX, visibleFrame.minX)
    XCTAssertGreaterThanOrEqual(constrainedFrame.minY, visibleFrame.minY)
    XCTAssertLessThanOrEqual(constrainedFrame.maxX, visibleFrame.maxX)
    XCTAssertLessThanOrEqual(constrainedFrame.maxY, visibleFrame.maxY)
  }

  func testCommandRIsNativeCommandSearchShortcut() {
    let event = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [.command],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "r",
      charactersIgnoringModifiers: "r",
      isARepeat: false,
      keyCode: 15
    )

    XCTAssertTrue(
      MainFlutterWindow.shouldOpenCommandSearchShortcut(event)
    )
  }

  func testPlainRIsNotNativeCommandSearchShortcut() {
    let event = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "r",
      charactersIgnoringModifiers: "r",
      isARepeat: false,
      keyCode: 15
    )

    XCTAssertFalse(
      MainFlutterWindow.shouldOpenCommandSearchShortcut(event)
    )
  }

}
