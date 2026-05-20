import AppKit
import Foundation

@MainActor
final class AppCoordinator {
    private let store = SettingsStore()
    private var cliSession: CLISession?
    private var popover: LookupPopover?
    private var settingsWindow: SettingsWindowController?
    private var permissionGuide: PermissionGuideController?
    private var hotkey: HotkeyListener?
    private var menuBar: MenuBarController?

    func start() {
        menuBar = MenuBarController(
            onOpenSettings: { [weak self] in self?.openSettings() },
            onNewSession: { [weak self] in self?.startNewSession() },
            onQuit: { NSApp.terminate(nil) }
        )

        if Permissions.accessibility() == .granted && Permissions.inputMonitoring() == .granted {
            attachHotkey()
        } else {
            showPermissionGuide()
        }
    }

    private func showPermissionGuide() {
        let guide = PermissionGuideController { [weak self] in
            self?.permissionGuide = nil
            self?.attachHotkey()
        }
        permissionGuide = guide
        guide.showAndFocus()
    }

    private func attachHotkey() {
        let listener = HotkeyListener { [weak self] in self?.onTrigger() }
        if !listener.start() {
            Toast.show("ka-soru couldn't listen for keys. Re-grant Input Monitoring.")
        }
        hotkey = listener
    }

    private func onTrigger() {
        let selection = SelectionReader.read()

        if (selection == nil || selection!.isEmpty) && popover == nil {
            Toast.show("Highlight a sentence first.")
            return
        }

        let cliName = store.load().defaultCLI.rawValue
        if !cliIsAvailable(cliName) {
            Toast.show("\(cliName) CLI not found on PATH. Install it first.")
            return
        }

        ensureSession(cliName: cliName)
        ensurePopover()

        let point = NSEvent.mouseLocation
        if let text = selection, !text.isEmpty {
            let template = PromptTemplate(template: store.load().promptTemplate)
            let prompt = template.render(with: text)
            popover?.appendNewPrompt(prompt, near: point)
        } else {
            // No new selection — just bring the popover to front
            popover?.appendNewPrompt("", near: point)
        }
    }

    private func ensureSession(cliName: String) {
        if let s = cliSession, s.cliName == cliName { return }
        cliSession?.cancel()
        cliSession = CLISession(cliName: cliName)
    }

    private func ensurePopover() {
        guard popover == nil, let session = cliSession else { return }
        popover = LookupPopover(session: session, onClose: { [weak self] in
            self?.popover = nil
        })
    }

    private func startNewSession() {
        cliSession?.startNewSession()
        popover?.startNewSession()
        Toast.show("Started a new session.")
    }

    private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(store: store)
        }
        settingsWindow?.showAndFocus()
    }

    private func cliIsAvailable(_ cli: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["which", cli]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }
}
