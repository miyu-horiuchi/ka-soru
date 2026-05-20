import AppKit
import Carbon.HIToolbox

final class HotkeyListener {
    /// Virtual keycode for `D` on US keyboard.
    private static let keyCodeD: Int64 = Int64(kVK_ANSI_D)

    private let detector = DoubleTapDetector(window: 0.3)
    private let onTrigger: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    /// Begins listening. Requires Input Monitoring permission.
    /// Returns false if the tap could not be created (permission missing).
    @discardableResult
    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let listener = Unmanaged<HotkeyListener>.fromOpaque(refcon).takeUnretainedValue()
                listener.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            return false
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        guard type == .keyDown else { return }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Self.keyCodeD else { return }

        // Suppress if user is typing in a text input.
        if SelectionReader.focusedElementIsEditable() { return }

        let now = ProcessInfo.processInfo.systemUptime
        if detector.register(at: now) {
            DispatchQueue.main.async { [weak self] in
                self?.onTrigger()
            }
        }
    }
}
