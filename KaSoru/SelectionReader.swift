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
        DebugLog.write("SEL: focused result=\(focusedResult.rawValue) (0=success)")
        guard focusedResult == .success,
              let element = focusedElement
        else { return tryFallbackCopy() }

        let ax = element as! AXUIElement

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(ax, kAXRoleAttribute as CFString, &role)
        DebugLog.write("SEL: focused role=\(role as? String ?? "nil")")

        var selectedText: CFTypeRef?
        let selResult = AXUIElementCopyAttributeValue(
            ax,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )
        DebugLog.write("SEL: selectedText result=\(selResult.rawValue) value=\(((selectedText as? String) ?? "<nil>").prefix(60))")
        if selResult == .success, let text = selectedText as? String, !text.isEmpty {
            return text
        }

        return tryFallbackCopy()
    }

    /// Fallback: simulate Cmd+C, read clipboard, restore previous clipboard.
    /// Works in any app that supports copy, since it doesn't depend on the AX text APIs.
    private static func tryFallbackCopy() -> String? {
        let pb = NSPasteboard.general
        let savedItems = pb.pasteboardItems?.map { item -> [String: Data] in
            var dict: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type.rawValue] = data
                }
            }
            return dict
        } ?? []
        let savedChangeCount = pb.changeCount

        // Simulate Cmd+C
        let src = CGEventSource(stateID: .combinedSessionState)
        let cKey: CGKeyCode = 8  // kVK_ANSI_C
        let down = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        // Brief wait for the target app to update the pasteboard
        Thread.sleep(forTimeInterval: 0.08)

        let text: String?
        if pb.changeCount != savedChangeCount {
            text = pb.string(forType: .string)
            DebugLog.write("SEL: fallback copy got \((text ?? "<nil>").prefix(60))")
        } else {
            text = nil
            DebugLog.write("SEL: fallback copy got nothing (changeCount unchanged)")
        }

        // Restore previous clipboard
        pb.clearContents()
        for itemDict in savedItems {
            let item = NSPasteboardItem()
            for (typeRaw, data) in itemDict {
                item.setData(data, forType: NSPasteboard.PasteboardType(typeRaw))
            }
            pb.writeObjects([item])
        }

        return (text?.isEmpty == false) ? text : nil
    }

    /// True if the process has Accessibility permission. Prompts the user on first call
    /// if `prompt: true`.
    static func hasPermission(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
