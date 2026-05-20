import AppKit
import SwiftUI

enum Toast {
    static func show(_ message: String, duration: TimeInterval = 2.0) {
        DispatchQueue.main.async {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 44),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .statusBar
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true

            let view = NSHostingView(rootView: ToastView(message: message))
            window.contentView = view

            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                let x = frame.midX - 140
                let y = frame.maxY - 80
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }

            window.orderFrontRegardless()

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                window.orderOut(nil)
            }
        }
    }
}

private struct ToastView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
    }
}
