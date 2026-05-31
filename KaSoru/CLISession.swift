import Foundation

/// Manages a multi-turn conversation with claude or codex via non-interactive CLI calls.
///
/// For codex, we ask it to write the final answer to a temp file (-o) and ignore the
/// noisy banner stream on stdout. The popover shows "Thinking…" until the file is ready.
/// Thread-safe accumulator for stdout chunks read off a background readability handler.
private final class RawBuffer {
    private let lock = NSLock()
    private var storage = ""
    func append(_ s: String) { lock.lock(); storage += s; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return storage }
}

final class CLISession {
    let cliName: String

    /// userInfo key on a failure error indicating the CLI failed because auth is dead
    /// (token invalidated / refresh-token reuse / 401). The UI uses this to offer sign-in.
    static let authErrorKey = "CLISessionAuthError"

    /// Heuristic: does this CLI output indicate the user's credentials are no longer valid
    /// and they need to sign in again?
    static func isAuthError(_ text: String) -> Bool {
        let t = text.lowercased()
        let markers = [
            "token_invalidated",
            "refresh_token_reused",
            "authentication token has been invalidated",
            "your refresh token was already used",
            "please try signing in again",
            "please log out and sign in",
            "401 unauthorized",
            "unauthorized",
            "auth error: 401",
        ]
        return markers.contains { t.contains($0) }
    }

    /// Keep at most this many recent turns in the prompt history sent to the model.
    /// Older turns are dropped so the prompt doesn't grow unbounded.
    private static let maxHistoryTurns = 3

    /// Run a stranded-process sweep this often.
    private static let cleanupInterval: TimeInterval = 30

    private var hasOngoingConversation = false
    private var history: [(user: String, assistant: String)] = []

    private var currentProcess: Process?
    private var cleanupTimer: DispatchSourceTimer?

    init(cliName: String) {
        self.cliName = cliName
        startPeriodicCleanup()
    }

    deinit {
        cleanupTimer?.cancel()
        // Final sweep on shutdown.
        nukeStrandedCLIProcesses()
    }

    func sendPrompt(_ prompt: String,
                    onChunk: @escaping (String) -> Void,
                    onComplete: @escaping (Result<Void, Error>) -> Void) {
        cancel()

        // Capture the raw user-typed prompt before we wrap it in conversation history,
        // so subsequent turns don't repeatedly prepend "User: User: User: ..."
        let rawUserPrompt = prompt
        let invocation = buildInvocation(prompt: prompt)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [invocation.executable] + invocation.args
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        proc.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        let stdinPipe = Pipe()
        try? stdinPipe.fileHandleForWriting.close()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdout
        proc.standardError = stderr

        var streamingAccumulated = ""
        // For non-clean CLIs (codex) we don't surface stdout live, but we keep a copy
        // so failures can be inspected for auth markers (the 401 banner prints here).
        let rawStdout = RawBuffer()

        if invocation.streamsClean {
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                streamingAccumulated += chunk
                DispatchQueue.main.async { onChunk(chunk) }
            }
        } else {
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                rawStdout.append(chunk)
            }
        }

        proc.terminationHandler = { [weak self] p in
            DebugLog.write("CLI: terminated status=\(p.terminationStatus) reason=\(p.terminationReason.rawValue)")
            stdout.fileHandleForReading.readabilityHandler = nil

            // Read the output file BEFORE deleting it.
            var fileAnswer: String? = nil
            if let outputFile = invocation.outputFile {
                if let data = try? Data(contentsOf: outputFile),
                   let text = String(data: data, encoding: .utf8) {
                    fileAnswer = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                try? FileManager.default.removeItem(at: outputFile)
            }

            DispatchQueue.main.async {
                guard let self = self else { return }
                if p.terminationStatus == 0 {
                    let finalAnswer: String
                    if let a = fileAnswer, !a.isEmpty {
                        finalAnswer = a
                        onChunk(a)
                    } else {
                        finalAnswer = streamingAccumulated
                    }
                    self.appendHistory(rawUserPrompt: rawUserPrompt, assistant: finalAnswer)
                    self.hasOngoingConversation = true
                    onComplete(.success(()))
                } else {
                    let stderrData = (try? stderr.fileHandleForReading.readToEnd()) ?? nil
                    let stderrText = stderrData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    // Auth markers may appear on stderr OR on codex's discarded stdout banner.
                    let combined = stderrText + "\n" + rawStdout.value
                    let msg = stderrText.isEmpty ? "\(self.cliName) exited with status \(p.terminationStatus)" : stderrText
                    let isAuth = Self.isAuthError(combined)
                    onComplete(.failure(NSError(domain: "CLISession", code: Int(p.terminationStatus),
                                                userInfo: [NSLocalizedDescriptionKey: msg,
                                                           CLISession.authErrorKey: isAuth])))
                }
                self.currentProcess = nil
            }
        }

        DebugLog.write("CLI: spawning \(invocation.executable) with \(invocation.args.count) args, outputFile=\(invocation.outputFile?.lastPathComponent ?? "none")")
        do {
            try proc.run()
            self.currentProcess = proc
            DebugLog.write("CLI: spawned pid=\(proc.processIdentifier)")
            // 60s timeout — if codex hangs, kill it and surface an error so the
            // popover isn't stuck on "Thinking…" forever.
            let runningProc = proc
            DispatchQueue.global().asyncAfter(deadline: .now() + 60) { [weak self] in
                guard let self = self else { return }
                if runningProc.isRunning {
                    kill(runningProc.processIdentifier, SIGKILL)
                    DispatchQueue.main.async {
                        self.nukeStrandedCLIProcesses()
                    }
                }
            }
        } catch {
            DebugLog.write("CLI: spawn FAILED: \(error)")
            if let outputFile = invocation.outputFile {
                try? FileManager.default.removeItem(at: outputFile)
            }
            onComplete(.failure(error))
        }
    }

    func startNewSession() {
        cancel()
        hasOngoingConversation = false
        history.removeAll()
    }

    /// Re-authenticates the underlying CLI. For codex this clears the poisoned
    /// refresh token (`logout`) and starts the browser OAuth flow (`login`),
    /// which opens the user's browser and blocks until they finish signing in.
    /// Currently only codex supports this; other CLIs complete immediately.
    func authenticate(onComplete: @escaping (Result<Void, Error>) -> Void) {
        guard cliName == "codex" else {
            DispatchQueue.main.async { onComplete(.success(())) }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Clear the stale credentials (best-effort — ignore failures).
            Self.runBlocking(executable: "codex", args: ["logout"], timeout: 30)

            // 2. Start the interactive browser login. This opens the browser and
            //    waits for the OAuth callback, so give it a generous timeout.
            let result = Self.runBlocking(executable: "codex", args: ["login"], timeout: 300)

            DispatchQueue.main.async {
                switch result {
                case .success:
                    onComplete(.success(()))
                case .failure(let err):
                    onComplete(.failure(err))
                }
            }
        }
    }

    /// Runs a CLI command to completion off the main thread, returning success on exit 0.
    @discardableResult
    private static func runBlocking(executable: String, args: [String], timeout: TimeInterval) -> Result<Void, Error> {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [executable] + args
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        proc.environment = env
        let out = Pipe(); let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.standardInput = Pipe()

        do {
            try proc.run()
        } catch {
            DebugLog.write("AUTH: failed to launch \(executable) \(args): \(error)")
            return .failure(error)
        }

        // Enforce a timeout so a hung login can't wedge forever.
        let deadline = DispatchTime.now() + timeout
        let watchdog = DispatchWorkItem {
            if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global().asyncAfter(deadline: deadline, execute: watchdog)
        proc.waitUntilExit()
        watchdog.cancel()

        if proc.terminationStatus == 0 {
            return .success(())
        }
        let errData = (try? err.fileHandleForReading.readToEnd()) ?? nil
        let errText = errData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let msg = errText.isEmpty ? "\(executable) \(args.joined(separator: " ")) exited \(proc.terminationStatus)" : errText
        DebugLog.write("AUTH: \(executable) \(args) failed: \(msg)")
        return .failure(NSError(domain: "CLISession.auth", code: Int(proc.terminationStatus),
                                userInfo: [NSLocalizedDescriptionKey: msg]))
    }

    func cancel() {
        if let p = currentProcess, p.isRunning {
            DebugLog.write("CLI: cancel() killing pid=\(p.processIdentifier)")
            kill(p.processIdentifier, SIGKILL)
        }
        currentProcess = nil
        nukeStrandedCLIProcesses(excluding: nil)
    }

    // MARK: - Cleanup

    private func startPeriodicCleanup() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + Self.cleanupInterval, repeating: Self.cleanupInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            // ONLY sweep when nothing is actively running — otherwise pkill would
            // kill the codex we just spawned for the current prompt.
            DispatchQueue.main.async {
                if self.currentProcess == nil || !(self.currentProcess?.isRunning ?? false) {
                    self.nukeStrandedCLIProcesses(excluding: nil)
                    self.sweepStaleTempFiles()
                }
            }
        }
        timer.resume()
        self.cleanupTimer = timer
    }

    /// Kills any stranded codex/claude exec processes that match our arg signature,
    /// optionally excluding a specific PID we want to keep alive.
    private func nukeStrandedCLIProcesses(excluding excludedPID: Int32? = nil) {
        let signature: String
        switch cliName {
        case "codex": signature = "--ignore-user-config --ephemeral --ignore-rules"
        case "claude": signature = "--disable-slash-commands"
        default: return
        }

        // Find matching PIDs via pgrep, then SIGKILL each one (skipping excludedPID).
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", signature]
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        pgrep.standardError = Pipe()
        do {
            try pgrep.run()
            pgrep.waitUntilExit()
        } catch {
            return
        }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? nil
        guard let dataUnwrapped = data,
              let text = String(data: dataUnwrapped, encoding: .utf8)
        else { return }
        for line in text.split(separator: "\n") {
            guard let pid = Int32(String(line).trimmingCharacters(in: CharacterSet.whitespaces)) else { continue }
            if pid == excludedPID { continue }
            kill(pid, SIGKILL)
        }
    }

    /// Remove kasoru temp output files older than 2 minutes.
    private func sweepStaleTempFiles() {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let contents = (try? FileManager.default.contentsOfDirectory(at: tmpDir,
                                                                     includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let cutoff = Date().addingTimeInterval(-120)
        for url in contents where url.lastPathComponent.hasPrefix("kasoru-codex-") {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let m = mtime, m < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - History

    private func appendHistory(rawUserPrompt: String, assistant: String) {
        history.append((user: rawUserPrompt, assistant: assistant))
        if history.count > Self.maxHistoryTurns {
            history.removeFirst(history.count - Self.maxHistoryTurns)
        }
    }

    // MARK: - Invocation strategy per CLI

    private struct Invocation {
        let executable: String
        let args: [String]
        let fullText: String
        let streamsClean: Bool
        let outputFile: URL?
    }

    private func buildInvocation(prompt: String) -> Invocation {
        switch cliName {
        case "claude":
            let base: [String] = [
                "--model", "haiku",
                "--disable-slash-commands",
                "-p", prompt,
                "--output-format", "text"
            ]
            let args = hasOngoingConversation ? ["-c"] + base : base
            return Invocation(executable: cliName, args: args, fullText: prompt,
                              streamsClean: true, outputFile: nil)

        case "codex":
            let composedPrompt = composedWithHistory(prompt)
            let outputFile = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("kasoru-codex-\(UUID().uuidString).txt")
            let args: [String] = [
                "exec",
                "--skip-git-repo-check",
                "--ignore-user-config",
                "--ephemeral",
                "--ignore-rules",
                "-c", "model=\"gpt-5.5\"",
                "-c", "model_reasoning_effort=\"low\"",
                "-o", outputFile.path,
                composedPrompt
            ]
            return Invocation(executable: cliName, args: args, fullText: composedPrompt,
                              streamsClean: false, outputFile: outputFile)

        default:
            return Invocation(executable: cliName, args: [prompt], fullText: prompt,
                              streamsClean: true, outputFile: nil)
        }
    }

    private func composedWithHistory(_ prompt: String) -> String {
        guard !history.isEmpty else { return prompt }
        var s = ""
        for turn in history {
            s += "User: \(turn.user)\n\nAssistant: \(turn.assistant)\n\n"
        }
        s += "User: \(prompt)"
        return s
    }
}
