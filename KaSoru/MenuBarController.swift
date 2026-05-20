import AppKit

final class MenuBarController {
    private let statusItem: NSStatusItem
    private let onOpenSettings: () -> Void
    private let onNewSession: () -> Void
    private let onQuit: () -> Void

    init(onOpenSettings: @escaping () -> Void,
         onNewSession: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        self.onNewSession = onNewSession
        self.onQuit = onQuit

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "ks"
            button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        }

        let menu = NSMenu()
        menu.addItem(makeItem("Open Settings…", selector: #selector(openSettings)))
        menu.addItem(makeItem("New Session", selector: #selector(newSession)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit ka-soru", selector: #selector(quit)))
        statusItem.menu = menu
        menu.items.forEach { $0.target = self }
    }

    private func makeItem(_ title: String, selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        return item
    }

    @objc private func openSettings() { onOpenSettings() }
    @objc private func newSession() { onNewSession() }
    @objc private func quit() { onQuit() }
}
