import Cocoa
import FlutterMacOS
import XCTest
@testable import Ianvs_Terminal_Dev

class RunnerTests: XCTestCase {

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

}
