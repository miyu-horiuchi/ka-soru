import XCTest
@testable import KaSoru

final class SessionManagerTests: XCTestCase {
    /// Spawns `cat`, which echoes input back. Lets us verify pty I/O end-to-end
    /// without depending on codex/claude being installed.
    func testSpawnsAndReceivesOutput() throws {
        let sm = SessionManager(command: "cat", args: [])

        let exp = expectation(description: "received echo")
        exp.assertForOverFulfill = false
        var received = Data()
        sm.onOutput = { chunk in
            received.append(chunk)
            if String(data: received, encoding: .utf8)?.contains("hello") == true {
                exp.fulfill()
            }
        }

        try sm.sendPrompt("hello")
        wait(for: [exp], timeout: 3)

        sm.endSession()
    }

    func testReuseSessionAcrossPrompts() throws {
        let sm = SessionManager(command: "cat", args: [])

        let exp1 = expectation(description: "first echo")
        exp1.assertForOverFulfill = false
        let exp2 = expectation(description: "second echo")
        exp2.assertForOverFulfill = false
        var received = ""
        sm.onOutput = { chunk in
            received += String(data: chunk, encoding: .utf8) ?? ""
            if received.contains("first") { exp1.fulfill() }
            if received.contains("second") { exp2.fulfill() }
        }

        try sm.sendPrompt("first")
        wait(for: [exp1], timeout: 3)
        try sm.sendPrompt("second")
        wait(for: [exp2], timeout: 3)

        XCTAssertTrue(sm.isRunning)
        sm.endSession()
    }

    func testEndSessionStopsProcess() throws {
        let sm = SessionManager(command: "cat", args: [])
        try sm.sendPrompt("hi")
        XCTAssertTrue(sm.isRunning)
        sm.endSession()
        // Give it a moment to die
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertFalse(sm.isRunning)
    }
}
