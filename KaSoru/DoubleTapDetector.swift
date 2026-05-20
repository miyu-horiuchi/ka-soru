import Foundation

final class DoubleTapDetector {
    private let window: TimeInterval
    private var lastTap: TimeInterval?
    private var justFired = false

    init(window: TimeInterval = 0.3) {
        self.window = window
    }

    /// Records a tap. Returns true if this tap completes a double-tap.
    /// After firing, the next tap is treated as a fresh first tap.
    func register(at time: TimeInterval) -> Bool {
        defer { lastTap = time }
        if justFired {
            justFired = false
            return false
        }
        guard let prev = lastTap else { return false }
        if time - prev <= window {
            justFired = true
            return true
        }
        return false
    }
}
