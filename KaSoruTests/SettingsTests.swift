import XCTest
@testable import KaSoru

final class SettingsTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kasoru-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testDefaultsWhenNoFileExists() {
        let store = SettingsStore(directory: tempDir)
        let s = store.load()
        XCTAssertEqual(s.defaultCLI, .codex)
        XCTAssertTrue(s.promptTemplate.contains("<TEXT>"))
    }

    func testRoundTrip() {
        let store = SettingsStore(directory: tempDir)
        var s = store.load()
        s.defaultCLI = .claude
        s.promptTemplate = "Define: \"<TEXT>\""
        store.save(s)

        let store2 = SettingsStore(directory: tempDir)
        let loaded = store2.load()
        XCTAssertEqual(loaded.defaultCLI, .claude)
        XCTAssertEqual(loaded.promptTemplate, "Define: \"<TEXT>\"")
    }

    func testCorruptFileFallsBackToDefaults() {
        let path = tempDir.appendingPathComponent("settings.json")
        try! "not json {{{".write(to: path, atomically: true, encoding: .utf8)

        let store = SettingsStore(directory: tempDir)
        let s = store.load()
        XCTAssertEqual(s.defaultCLI, .codex)
    }
}
