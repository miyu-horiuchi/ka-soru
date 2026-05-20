import SwiftUI
import AppKit
import ApplicationServices

enum PermissionStatus {
    case granted
    case missing
}

enum Permissions {
    static func accessibility() -> PermissionStatus {
        AXIsProcessTrusted() ? .granted : .missing
    }

    /// There's no public API to query Input Monitoring status. The best signal is whether
    /// `CGEvent.tapCreate` for `.cgSessionEventTap` succeeds. We attempt a no-op tap.
    static func inputMonitoring() -> PermissionStatus {
        let mask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else {
            return .missing
        }
        CFMachPortInvalidate(tap)
        return .granted
    }

    static func openAccessibilityPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openInputMonitoringPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

final class PermissionGuideController: NSWindowController {
    let onAllGranted: () -> Void

    init(onAllGranted: @escaping () -> Void) {
        self.onAllGranted = onAllGranted
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ka-soru — Setup"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: PermissionGuideView(onAllGranted: { [weak self] in
            self?.close()
            onAllGranted()
        }))
    }

    required init?(coder: NSCoder) { fatalError() }

    func showAndFocus() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct PermissionGuideView: View {
    let onAllGranted: () -> Void

    @State private var ax: PermissionStatus = .missing
    @State private var im: PermissionStatus = .missing

    let pollTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ka-soru needs two macOS permissions to work")
                .font(.title3.bold())

            permissionRow(
                title: "Accessibility",
                why: "Reads highlighted text from other apps",
                status: ax,
                action: {
                    Permissions.promptAccessibility()
                    Permissions.openAccessibilityPane()
                }
            )

            permissionRow(
                title: "Input Monitoring",
                why: "Listens for the double-tap-D shortcut",
                status: im,
                action: { Permissions.openInputMonitoringPane() }
            )

            Spacer()

            HStack {
                Spacer()
                Button("Continue") { onAllGranted() }
                    .disabled(ax != .granted || im != .granted)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .onAppear { refresh() }
        .onReceive(pollTimer) { _ in refresh() }
    }

    private func refresh() {
        ax = Permissions.accessibility()
        im = Permissions.inputMonitoring()
    }

    @ViewBuilder
    private func permissionRow(title: String, why: String, status: PermissionStatus, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status == .granted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(status == .granted ? .green : .secondary)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(why).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if status != .granted {
                Button("Open System Settings", action: action)
            }
        }
    }
}
