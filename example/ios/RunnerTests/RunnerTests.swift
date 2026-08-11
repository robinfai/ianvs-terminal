import Flutter
import UIKit
import XCTest

@_silgen_name("ianvs_ping")
private func ianvsPing() -> Int32

class RunnerTests: XCTestCase {

  func testRustCoreStaticSymbolIsLinkedIntoTheApplication() {
    XCTAssertEqual(ianvsPing(), 42)
  }

}
