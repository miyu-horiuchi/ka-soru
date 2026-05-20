import AppKit
import SwiftUI

final class TerminalWindowController: NSWindowController {
    let session: SessionManager
    let onNewSession: () -> Void
    let onOpenSettings: () -> Void

    init(session: SessionManager,
         onNewSession: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void) {
        self.session = session
        self.onNewSession = onNewSession
        self.onOpenSettings = onOpenSettings

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 440),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(white: 0.08, alpha: 1.0)
        window.center()

        super.init(window: window)

        let root = TerminalPopupView(
            session: session,
            onNewSession: onNewSession,
            onOpenSettings: onOpenSettings,
            onClose: { [weak self] in self?.close() }
        )
        window.contentView = NSHostingView(rootView: root)
    }

    required init?(coder: NSCoder) { fatalError() }

    func showAndFocus() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct TerminalPopupView: View {
    let session: SessionManager
    let onNewSession: () -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("New Session", action: onNewSession)
                Button("Settings", action: onOpenSettings)
                Spacer()
                Button("Close", action: onClose)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(white: 0.12))

            KaSoruTerminalView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
