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

    /// Whether the focused element is editable (text field, text area, or contenteditable).
    /// Used by HotkeyListener to suppress double-tap-D inside text inputs.
    static func focusedElementIsEditable() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success,
              let element = focusedElement
        else { return false }

        let ax = element as! AXUIElement

        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(ax, kAXRoleAttribute as CFString, &role) == .success,
           let roleStr = role as? String {
            if roleStr == kAXTextFieldRole || roleStr == kAXTextAreaRole {
                return true
            }
        }

        // Catches web contenteditable (ChatGPT, Notion, Gmail compose, etc.)
        var editable: CFTypeRef?
        if AXUIElementCopyAttributeValue(ax, "AXEditable" as CFString, &editable) == .success,
           let isEditable = editable as? Bool {
            return isEditable
        }

        return false
    }

    /// True if the process has Accessibility permission. Prompts the user on first call
    /// if `prompt: true`.
    static func hasPermission(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
