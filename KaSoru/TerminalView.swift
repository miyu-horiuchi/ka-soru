import SwiftUI
import SwiftTerm
import AppKit

struct KaSoruTerminalView: NSViewRepresentable {
    let session: SessionManager

    func makeNSView(context: Context) -> SessionTerminalView {
        let bridge = SessionTerminalView(frame: .zero)
        bridge.bind(to: session)
        return bridge
    }

    func updateNSView(_ nsView: SessionTerminalView, context: Context) {
        nsView.rebind(to: session)
    }
}

/// SwiftTerm view that bridges its data callbacks to a SessionManager.
final class SessionTerminalView: SwiftTerm.TerminalView, TerminalViewDelegate {
    private weak var session: SessionManager?

    override init(frame: NSRect) {
        super.init(frame: frame)
        self.terminalDelegate = self
        self.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.terminalDelegate = self
    }

    func bind(to session: SessionManager) {
        self.session = session
        session.onOutput = { [weak self] data in
            guard let self = self else { return }
            data.withUnsafeBytes { buf in
                let array = Array(buf.bindMemory(to: UInt8.self))
                self.feed(byteArray: array[...])
            }
        }
        // Push initial size to the session
        let term = getTerminal()
        session.resize(rows: UInt16(term.rows), cols: UInt16(term.cols))
    }

    func rebind(to session: SessionManager) {
        bind(to: session)
    }

    // MARK: TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        session?.sendRaw(Data(data))
    }

    func scrolled(source: TerminalView, position: Double) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        session?.resize(rows: UInt16(newRows), cols: UInt16(newCols))
    }
    func clipboardCopy(source: TerminalView, content: Data) {
        if let s = String(data: content, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(s, forType: .string)
        }
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func bell(source: TerminalView) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }
}
