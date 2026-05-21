import Foundation

/// Manages a multi-turn conversation with claude or codex via non-interactive CLI calls.
///
/// For codex, we ask it to write the final answer to a temp file (-o) and ignore the
/// noisy banner stream on stdout. The popover shows "Thinking…" until the file is ready.
final class CLISession {
    let cliName: String

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

        if invocation.streamsClean {
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                streamingAccumulated += chunk
                DispatchQueue.main.async { onChunk(chunk) }
            }
        } else {
            stdout.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }
        }

        proc.terminationHandler = { [weak self] p in
            stdout.fileHandleForReading.readabilityHandler = nil
            // ALWAYS remove the temp output file — success OR failure.
            if let outputFile = invocation.outputFile {
                try? FileManager.default.removeItem(at: outputFile)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if p.terminationStatus == 0 {
                    let finalAnswer: String
                    if let outputFile = invocation.outputFile,
                       let data = try? Data(contentsOf: outputFile),
                       let text = String(data: data, encoding: .utf8) {
                        finalAnswer = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !finalAnswer.isEmpty {
                            onChunk(finalAnswer)
                        }
                    } else {
                        finalAnswer = streamingAccumulated
                    }
                    self.appendHistory(user: invocation.fullText, assistant: finalAnswer)
                    self.hasOngoingConversation = true
                    onComplete(.success(()))
                } else {
                    let stderrData = (try? stderr.fileHandleForReading.readToEnd()) ?? nil
                    let stderrText = stderrData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let msg = stderrText.isEmpty ? "\(self.cliName) exited with status \(p.terminationStatus)" : stderrText
                    onComplete(.failure(NSError(domain: "CLISession", code: Int(p.terminationStatus),
                                                userInfo: [NSLocalizedDescriptionKey: msg])))
                }
                self.currentProcess = nil
            }
        }

        do {
            try proc.run()
            self.currentProcess = proc
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
            // If spawn fails outright we still need to clean up the temp file
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

    func cancel() {
        if let p = currentProcess, p.isRunning {
            kill(p.processIdentifier, SIGKILL)
        }
        currentProcess = nil
        nukeStrandedCLIProcesses()
    }

    // MARK: - Cleanup

    private func startPeriodicCleanup() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + Self.cleanupInterval, repeating: Self.cleanupInterval)
        timer.setEventHandler { [weak self] in
            self?.nukeStrandedCLIProcesses()
            self?.sweepStaleTempFiles()
        }
        timer.resume()
        self.cleanupTimer = timer
    }

    private func nukeStrandedCLIProcesses() {
        let signature: String
        switch cliName {
        case "codex": signature = "--ignore-user-config --ephemeral --ignore-rules"
        case "claude": signature = "--disable-slash-commands"
        default: return
        }
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-9", "-f", signature]
        pkill.standardOutput = Pipe()
        pkill.standardError = Pipe()
        try? pkill.run()
        pkill.waitUntilExit()
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

    private func appendHistory(user: String, assistant: String) {
        history.append((user: user, assistant: assistant))
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
