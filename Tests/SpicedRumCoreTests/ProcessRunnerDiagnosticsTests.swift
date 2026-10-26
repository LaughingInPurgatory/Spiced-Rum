import XCTest
@testable import SpicedRumCore

final class ProcessRunnerDiagnosticsTests: XCTestCase {
    func testCapturePreservesExactSuccessfulOutput() async throws {
        let output = try await ProcessRunner.capture(URL(fileURLWithPath: "/usr/bin/printf"), ["hello"])
        XCTAssertEqual(output, "hello")
    }

    func testSignalKillIsRecordedSeparatelyFromTimeout() async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: log) }
        do {
            try await ProcessRunner.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "kill -KILL $$"], directory: log.deletingLastPathComponent(), log: log, timeout: 30)
            XCTFail("The killed process must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("signal 9")) }
        XCTAssertTrue(try String(contentsOf: log).contains("was terminated by signal 9"))
    }

    func testTimeoutIsRecordedInPreservedLog() async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: log) }
        do {
            try await ProcessRunner.run(URL(fileURLWithPath: "/bin/sleep"), ["10"], directory: log.deletingLastPathComponent(), log: log, timeout: 0.1)
            XCTFail("The sleeping process must time out")
        } catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        XCTAssertTrue(try String(contentsOf: log).contains("timed out"))
    }
}
