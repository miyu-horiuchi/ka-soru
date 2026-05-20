import AppKit
import Carbon.HIToolbox

final class HotkeyListener {
    private static let keyCodeE: Int64 = Int64(kVK_ANSI_D)  // re-using; will check actual key below

    private let onTrigger: () -> Void
    private var monitor: Any?

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    /// Begins listening for Cmd+E using NSEvent's global monitor.
    /// Requires Accessibility permission (no Input Monitoring needed).
    @discardableResult
    func start() -> Bool {
        // Remove any existing
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }

        let m = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return }
            self.handle(event: event)
        }
        self.monitor = m

        DebugLog.write("KASORU: HotkeyListener attached global monitor (\(m == nil ? "nil" : "ok"))")
        return m != nil
    }

    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func handle(event: NSEvent) {
        // event.keyCode is UInt16 on NSEvent
        let keyCode = event.keyCode
        // kVK_ANSI_E = 0x0E
        guard keyCode == UInt16(kVK_ANSI_E) else { return }

        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        DebugLog.write("KASORU: E keyDown, flags=\(flags.rawValue)")
        guard flags == [.command] else { return }

        DebugLog.write("KASORU: Cmd+E matched, dispatching")
        DispatchQueue.main.async { [weak self] in
            self?.onTrigger()
        }
    }
}
