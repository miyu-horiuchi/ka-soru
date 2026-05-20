import Foundation

final class SessionManager {
    private let command: String
    private let args: [String]
    private var pty: PTY?
    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "dev.kasoru.session")

    /// Called on the main queue whenever bytes arrive from the CLI.
    var onOutput: ((Data) -> Void)?
    /// Called on the main queue when the underlying process exits.
    var onProcessExit: (() -> Void)?

    var isRunning: Bool {
        pty?.process.isRunning ?? false
    }

    init(command: String, args: [String]) {
        self.command = command
        self.args = args
    }

    /// Sends a prompt to the session, spawning the process if not yet running.
    /// Appends a newline so the CLI treats it as a complete line of input.
    func sendPrompt(_ text: String) throws {
        if !isRunning {
            try spawn()
        }
        let payload = (text + "\n").data(using: .utf8) ?? Data()
        pty?.write(payload)
    }

    /// Sends raw bytes (used by TerminalWindow when user types in the popup).
    func sendRaw(_ data: Data) {
        pty?.write(data)
    }

    func resize(rows: UInt16, cols: UInt16) {
        pty?.resize(rows: rows, cols: cols)
    }

    /// Kills the running process (if any) and clears state.
    func endSession() {
        readSource?.cancel()
        readSource = nil
        pty?.close()
        pty = nil
    }

    private func spawn() throws {
        let p = try PTY.spawn(command: command, args: args, rows: 30, cols: 100)
        self.pty = p

        let source = DispatchSource.makeReadSource(fileDescriptor: p.masterFD, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self = self, let pty = self.pty else { return }
            let chunk = Self.readAvailable(fd: pty.masterFD)
            if !chunk.isEmpty {
                DispatchQueue.main.async {
                    self.onOutput?(chunk)
                }
            }
        }
        source.setCancelHandler { /* nothing */ }
        source.resume()
        self.readSource = source

        // Detect process exit on a background queue
        DispatchQueue.global().async { [weak self] in
            p.process.waitUntilExit()
            DispatchQueue.main.async {
                self?.onProcessExit?()
            }
        }
    }

    private static func readAvailable(fd: Int32) -> Data {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        if n <= 0 { return Data() }
        return Data(bytes: buffer, count: n)
    }
}
