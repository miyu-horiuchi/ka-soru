import AppKit
import SwiftUI
import Combine

struct LookupTurn: Equatable {
    let prompt: String
    var answer: String
}

@MainActor
final class LookupViewModel: ObservableObject {
    @Published var turns: [LookupTurn] = []
    @Published var draft: String = ""
    @Published var isWaiting: Bool = false
    @Published var errorMessage: String?

    let session: CLISession
    weak var popover: LookupPopover?

    init(session: CLISession) {
        self.session = session
    }

    /// Sends an initial prompt (from a new highlighted-text trigger).
    func startInitial(prompt: String) {
        sendInternal(prompt: prompt)
    }

    /// Sends a follow-up from the input field.
    func submitFollowUp() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWaiting else { return }
        draft = ""
        sendInternal(prompt: text)
    }

    private func sendInternal(prompt: String) {
        errorMessage = nil
        isWaiting = true
        turns.append(LookupTurn(prompt: prompt, answer: ""))
        let turnIndex = turns.count - 1

        session.sendPrompt(prompt) { [weak self] chunk in
            guard let self = self, turnIndex < self.turns.count else { return }
            self.turns[turnIndex].answer += chunk
        } onComplete: { [weak self] result in
            guard let self = self else { return }
            self.isWaiting = false
            if case .failure(let err) = result {
                self.errorMessage = err.localizedDescription
            }
        }
    }
}

/// A small floating window styled like the macOS Look Up popover.
/// Borderless, vibrant background, click-outside dismisses.
@MainActor
final class LookupPopover {
    private let session: CLISession
    private let model: LookupViewModel
    private let window: NSPanel
    private var clickMonitor: Any?
    private let onClose: () -> Void

    init(session: CLISession, onClose: @escaping () -> Void) {
        self.session = session
        self.onClose = onClose
        self.model = LookupViewModel(session: session)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        self.window = panel
        self.model.popover = self
    }

    /// Shows the popover at the given screen point, sends the initial prompt.
    func show(near point: NSPoint, initialPrompt: String?) {
        window.contentView = NSHostingView(rootView: LookupView(model: model, onClose: { [weak self] in self?.close() }))
        positionWindow(near: point)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installClickOutsideMonitor()

        if let p = initialPrompt {
            model.startInitial(prompt: p)
        }
    }

    /// Re-uses the existing popover for a new prompt (when the user triggers Cmd+E again).
    func appendNewPrompt(_ prompt: String, near point: NSPoint) {
        if !window.isVisible {
            window.makeKeyAndOrderFront(nil)
            positionWindow(near: point)
            installClickOutsideMonitor()
        }
        NSApp.activate(ignoringOtherApps: true)
        model.startInitial(prompt: prompt)
    }

    func close() {
        removeClickOutsideMonitor()
        window.orderOut(nil)
        onClose()
    }

    func startNewSession() {
        session.startNewSession()
        model.turns.removeAll()
        model.errorMessage = nil
        model.draft = ""
    }

    // MARK: - Positioning

    private func positionWindow(near point: NSPoint) {
        guard let screen = NSScreen.main else { return }
        var frame = window.frame
        // Place top-left of popover slightly below-right of the cursor
        var origin = NSPoint(x: point.x + 12, y: point.y - frame.height - 12)
        // Clamp inside the screen
        let visible = screen.visibleFrame
        origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - frame.width - 8))
        origin.y = max(visible.minY + 8, min(origin.y, visible.maxY - frame.height - 8))
        frame.origin = origin
        window.setFrame(frame, display: false)
    }

    // MARK: - Click-outside dismissal

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return }
            // Global monitor doesn't see clicks inside our own window — those clicks
            // never reach here, so any event here means click-outside.
            self.close()
        }
    }

    private func removeClickOutsideMonitor() {
        if let m = clickMonitor {
            NSEvent.removeMonitor(m)
            clickMonitor = nil
        }
    }
}
