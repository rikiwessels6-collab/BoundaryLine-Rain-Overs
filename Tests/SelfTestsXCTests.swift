import XCTest
@testable import BoundaryLineRain

/// Runs the same on-device self-tests the app shows under About > Run self-tests,
/// but on a real compiler in CI. Any failed check fails the build.
final class SelfTestsXCTests: XCTestCase {
    func testAllSelfTestsPass() {
        let results = BoundaryLineSelfTests.run()
        XCTAssertFalse(results.isEmpty, "No self-tests ran")
        let failures = results.filter { !$0.passed }
        print("SELFTESTS: \(results.count) checks, \(failures.count) failed")
        for f in failures { XCTFail("\(f.name) -- \(f.detail)") }
    }
}
