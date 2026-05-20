import Darwin
import Foundation

struct PTY {
    let masterFD: Int32
    let process: Process

    /// Spawns `command` in a new pseudoterminal.
    /// - Parameters:
    ///   - command: executable path or name on PATH
    ///   - args: arguments
    ///   - rows: initial terminal height
    ///   - cols: initial terminal width
    static func spawn(command: String, args: [String], rows: UInt16, cols: UInt16) throws -> PTY {
        var master: Int32 = 0
        var slave: Int32 = 0
        var winsize = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)

        if openpty(&master, &slave, nil, nil, &winsize) != 0 {
            throw NSError(domain: "PTY", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "openpty failed"])
        }

        let process = Process()
        // Search PATH if no slash in command
        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: command)
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + args
        }
        if process.arguments == nil {
            process.arguments = args
        }

        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        // Inherit user's PATH (codex/claude installed via npm need this)
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        process.environment = env

        try process.run()
        Darwin.close(slave)

        return PTY(masterFD: master, process: process)
    }

    func write(_ data: Data) {
        data.withUnsafeBytes { buf in
            _ = Darwin.write(masterFD, buf.baseAddress, buf.count)
        }
    }

    func resize(rows: UInt16, cols: UInt16) {
        var ws = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)
    }

    func close() {
        Darwin.close(masterFD)
        if process.isRunning {
            process.terminate()
        }
    }
}
