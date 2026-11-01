import Darwin
import Flutter
import UIKit
import XCTest

class RunnerTests: XCTestCase {
  func testRustCoreSymbolCanBeResolvedLikeDartFFI() throws {
    // A direct Swift reference can force-link a symbol and mask the production
    // bug. Resolve it dynamically, exactly as DynamicLibrary.process() does.
    let process = dlopen(nil, RTLD_NOW)
    defer { if let process = process { dlclose(process) } }
    let symbol = try XCTUnwrap(dlsym(process, "ianvs_ping"))
    let ping = unsafeBitCast(symbol, to: (@convention(c) () -> Int32).self)
    XCTAssertEqual(ping(), 42)
  }
}
