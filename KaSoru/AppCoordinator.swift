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
        DebugLog.write("KASORU: AppCoordinator.start()")
        menuBar = MenuBarController(
            onOpenSettings: { [weak self] in self?.openSettings() },
            onNewSession: { [weak self] in self?.startNewSession() },
            onQuit: { NSApp.terminate(nil) }
        )

        let ax = Permissions.accessibility()
        DebugLog.write("KASORU: permissions ax=\(ax) (input monitoring no longer required)")
        if ax == .granted {
            attachHotkey()
        } else {
            DebugLog.write("KASORU: missing accessibility, prompting")
            Permissions.promptAccessibility()
            showPermissionGuide()
        }
    }

    private func showPermissionGuide() {
        // Don't stack a second guide window if one is already up (repeated triggers).
        if let existing = permissionGuide {
            existing.showAndFocus()
            return
        }
        let guide = PermissionGuideController { [weak self] in
            self?.permissionGuide = nil
            self?.attachHotkey()
        }
        permissionGuide = guide
        guide.showAndFocus()
    }

    private func attachHotkey() {
        DebugLog.write("KASORU: attachHotkey()")
        let listener = HotkeyListener { [weak self] in
            DebugLog.write("KASORU: trigger callback fired")
            self?.onTrigger()
        }
        let started = listener.start()
        DebugLog.write("KASORU: HotkeyListener.start() -> \(started)")
        if !started {
            Toast.show("ka-soru couldn't listen for keys. Re-grant Input Monitoring.")
        }
        hotkey = listener
    }

    private func onTrigger() {
        // Accessibility is revoked whenever the app's code identity changes (e.g. after a
        // rebuild of this ad-hoc-signed app). Without it, both the AX selection read and the
        // synthetic-Cmd+C fallback fail silently, so every lookup comes up empty. Detect that
        // here and send the user to re-grant, instead of opening a dead popover with no clue.
        if Permissions.accessibility() == .missing {
            DebugLog.write("TRIG: accessibility missing → opening pane + guide")
            Permissions.openAccessibilityPane()
            Toast.show("ka-soru lost Accessibility permission (this happens after an update). Re-add it in System Settings, then try again.")
            showPermissionGuide()
            return
        }

        let selection = SelectionReader.read()
        DebugLog.write("TRIG: selection=\((selection ?? "<nil>").prefix(60)) popover=\(popover != nil ? "exists" : "nil")")

        if (selection == nil || selection!.isEmpty) && popover == nil {
            DebugLog.write("TRIG: no selection + no popover → toast")
            Toast.show("Highlight a sentence first.")
            return
        }

        let cliName = store.load().defaultCLI.rawValue
        let available = cliIsAvailable(cliName)
        DebugLog.write("TRIG: cli=\(cliName) available=\(available)")
        if !available {
            Toast.show("\(cliName) CLI not found on PATH. Install it first.")
            return
        }

        ensureSession(cliName: cliName)
        ensurePopover()
        DebugLog.write("TRIG: session=\(cliSession != nil) popover=\(popover != nil)")

        let point = NSEvent.mouseLocation
        DebugLog.write("TRIG: mouse=\(point)")
        if let text = selection, !text.isEmpty {
            let template = PromptTemplate(template: store.load().promptTemplate)
            let prompt = template.render(with: text)
            DebugLog.write("TRIG: appending prompt (\(prompt.prefix(60))…)")
            popover?.appendNewPrompt(prompt, near: point)
        } else {
            DebugLog.write("TRIG: no new text, just bringing popover forward")
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
