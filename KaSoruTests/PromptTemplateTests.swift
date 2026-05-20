import XCTest
@testable import KaSoru

final class PromptTemplateTests: XCTestCase {
    func testBasicSubstitution() {
        let t = PromptTemplate(template: "Explain: \"<TEXT>\"")
        XCTAssertEqual(t.render(with: "hello"), "Explain: \"hello\"")
    }

    func testMultiplePlaceholders() {
        let t = PromptTemplate(template: "<TEXT> ... again <TEXT>")
        XCTAssertEqual(t.render(with: "x"), "x ... again x")
    }

    func testNoPlaceholderJustAppends() {
        let t = PromptTemplate(template: "Translate to French.")
        XCTAssertEqual(t.render(with: "Hello"), "Translate to French.\n\nHello")
    }

    func testTextWithQuotesIsNotEscaped() {
        let t = PromptTemplate(template: "Say: <TEXT>")
        XCTAssertEqual(t.render(with: #"a "b" c"#), #"Say: a "b" c"#)
    }

    func testTextWithNewlinesPreserved() {
        let t = PromptTemplate(template: "Translate: <TEXT>")
        XCTAssertEqual(t.render(with: "line1\nline2"), "Translate: line1\nline2")
    }

    func testEmptyText() {
        let t = PromptTemplate(template: "Echo: <TEXT>")
        XCTAssertEqual(t.render(with: ""), "Echo: ")
    }
}
