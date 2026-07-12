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

}
