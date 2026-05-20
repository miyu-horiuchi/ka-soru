import Foundation

struct PromptTemplate: Equatable {
    static let placeholder = "<TEXT>"

    let template: String

    func render(with text: String) -> String {
        if template.contains(Self.placeholder) {
            return template.replacingOccurrences(of: Self.placeholder, with: text)
        }
        return "\(template)\n\n\(text)"
    }
}
