import SwiftUI
import AppKit

final class SettingsWindowController: NSWindowController {
    let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ka-soru Settings"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsView(store: store))
    }

    required init?(coder: NSCoder) { fatalError() }

    func showAndFocus() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsView: View {
    let store: SettingsStore

    @State private var template: String = ""
    @State private var cli: CLITool = .codex

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Default CLI").font(.headline)
            Picker("", selection: $cli) {
                ForEach(CLITool.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Prompt template").font(.headline)
            Text("Use `<TEXT>` where the highlighted sentence should appear.")
                .font(.caption)
                .foregroundColor(.secondary)
            TextEditor(text: $template)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .border(Color.secondary.opacity(0.3))

            Spacer()
            HStack {
                Spacer()
                Button("Save") {
                    var s = store.load()
                    s.promptTemplate = template
                    s.defaultCLI = cli
                    store.save(s)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onAppear {
            let s = store.load()
            template = s.promptTemplate
            cli = s.defaultCLI
        }
    }
}
