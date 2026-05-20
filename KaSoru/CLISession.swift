import Foundation

/// Manages a multi-turn conversation with claude or codex via non-interactive CLI calls.
///
/// Each `sendPrompt` spawns the CLI as a one-shot process. Conversation continuity is
/// handled by the CLI itself when available (`claude -c`), or by tracking history in-process
/// and pre-pending it to the next prompt (fallback for codex).
final class CLISession {
    let cliName: String

    /// True after at least one successful turn — used to add `-c` to claude on follow-ups.
    private var hasOngoingConversation = false

    /// History used as fallback when the CLI lacks a native "continue" flag (codex).
    /// Format: alternating user / assistant turns.
    private var history: [(user: String, assistant: String)] = []

    private var currentProcess: Process?
    private var stdoutPipe: Pipe?

    init(cliName: String) {
        self.cliName = cliName
    }

    /// Spawns the CLI with the prompt + accumulated context, streams stdout chunks to
    /// `onChunk` on the main queue, calls `onComplete` when the process exits.
    func sendPrompt(_ prompt: String,
                    onChunk: @escaping (String) -> Void,
                    onComplete: @escaping (Result<Void, Error>) -> Void) {
        cancel()

        let (executable, args, fullText) = buildInvocation(prompt: prompt)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [executable] + args
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"  // discourage CLIs from emitting ANSI color
        env["NO_COLOR"] = "1"
        proc.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = nil
        proc.standardOutput = stdout
        proc.standardError = stderr
        self.stdoutPipe = stdout

        var accumulated = ""

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            accumulated += chunk
            DispatchQueue.main.async { onChunk(chunk) }
        }

        proc.terminationHandler = { [weak self] p in
            stdout.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self = self else { return }
                if p.terminationStatus == 0 {
                    self.history.append((user: fullText, assistant: accumulated))
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
        } catch {
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
            p.terminate()
        }
        currentProcess = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
    }

    // MARK: - Invocation strategy per CLI

    private func buildInvocation(prompt: String) -> (executable: String, args: [String], fullText: String) {
        switch cliName {
        case "claude":
            // claude has native conversation continuation
            let args: [String] = hasOngoingConversation
                ? ["-c", "-p", prompt, "--output-format", "text"]
                : ["-p", prompt, "--output-format", "text"]
            return (cliName, args, prompt)

        case "codex":
            // codex exec is one-shot. We embed history ourselves.
            let composedPrompt = composedWithHistory(prompt)
            return (cliName, ["exec", composedPrompt], composedPrompt)

        default:
            return (cliName, [prompt], prompt)
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
