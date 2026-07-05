import CoreGraphics
import Foundation

struct IdleMonitor {
    func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
    }

    func isIdle(threshold: TimeInterval) -> Bool {
        idleSeconds() >= threshold
    }
}
