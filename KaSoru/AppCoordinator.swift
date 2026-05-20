import AppKit
import Foundation

@MainActor
final class AppCoordinator {
    private let store = SettingsStore()
    private var session: SessionManager?
    private var terminal: TerminalWindowController?
    private var settingsWindow: SettingsWindowController?
    private var permissionGuide: PermissionGuideController?
    private var hotkey: HotkeyListener?
    private var menuBar: MenuBarController?
    private var sessionExitedUnexpectedly = false

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

        // Nothing highlighted and no session exists yet
        if (selection == nil || selection!.isEmpty) && session == nil {
            Toast.show("Highlight a sentence first.")
            return
        }

        let cli = store.load().defaultCLI.rawValue
        if !cliIsAvailable(cli) {
            Toast.show("\(cli) CLI not found on PATH. Install it first.")
            return
        }

        ensureSession()

        if sessionExitedUnexpectedly {
            Toast.show("Session restarted.")
            sessionExitedUnexpectedly = false
        }

        if let text = selection, !text.isEmpty {
            let template = PromptTemplate(template: store.load().promptTemplate)
            let prompt = template.render(with: text)
            do {
                try session?.sendPrompt(prompt)
            } catch {
                Toast.show("Couldn't start \(cli): \(error.localizedDescription)")
                session = nil
                return
            }
        }

        openTerminal()
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

    private func ensureSession() {
        if let s = session, s.isRunning { return }

        let cli = store.load().defaultCLI.rawValue
        let s = SessionManager(command: cli, args: [])
        s.onProcessExit = { [weak self] in
            guard let self = self else { return }
            // Mark as "unexpected exit" so next trigger toasts "Session restarted."
            // (Distinguishes from explicit endSession via startNewSession.)
            if self.session != nil {
                self.sessionExitedUnexpectedly = true
                self.session = nil
            }
        }
        self.session = s
    }

    private func openTerminal() {
        guard let session = session else { return }

        if terminal == nil {
            terminal = TerminalWindowController(
                session: session,
                onNewSession: { [weak self] in self?.startNewSession() },
                onOpenSettings: { [weak self] in self?.openSettings() }
            )
        }
        terminal?.showAndFocus()
    }

    private func startNewSession() {
        let wasRunning = session?.isRunning ?? false
        // Clear session first so onProcessExit's "unexpected" flag doesn't fire.
        let old = session
        session = nil
        sessionExitedUnexpectedly = false
        old?.endSession()
        terminal?.close()
        terminal = nil
        ensureSession()
        openTerminal()
        if wasRunning {
            Toast.show("Started a new session.")
        }
    }

    private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(store: store)
        }
        settingsWindow?.showAndFocus()
    }
}
