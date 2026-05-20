import AppKit
import ApplicationServices

enum SelectionReader {
    /// Reads the currently selected text from the focused element of the frontmost app.
    /// Returns nil if no app is frontmost, no element is focused, or no selection exists.
    /// Requires Accessibility permission (System Settings → Privacy & Security → Accessibility).
    static func read() -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedElement: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard focusedResult == .success,
              let element = focusedElement
        else { return nil }

        var selectedText: CFTypeRef?
        let selResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )
        guard selResult == .success,
              let text = selectedText as? String,
              !text.isEmpty
        else { return nil }

        return text
    }

    /// True if the process has Accessibility permission. Prompts the user on first call
    /// if `prompt: true`.
    static func hasPermission(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
