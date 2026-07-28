import Foundation

public enum SafetyEvent: Equatable, Sendable {
    case controlEnabled
    case controlDisabled
    case sensorAge(seconds: TimeInterval)
    case heartbeatLost
    case writeFailed
    case willSleep
}

public enum SafetyAction: Equatable, Sendable {
    case restoreSystemAuto
    case stopControl
}

public struct SafetyStateMachine: Sendable {
    private var isControlActive = false

    public init() {}

    public mutating func handle(_ event: SafetyEvent) -> [SafetyAction] {
        switch event {
        case .controlEnabled:
            isControlActive = true
            return []
        case .controlDisabled:
            return stopIfActive()
        case .sensorAge(let seconds):
            return seconds > 5 ? stopIfActive() : []
        case .heartbeatLost, .writeFailed, .willSleep:
            return stopIfActive()
        }
    }

    private mutating func stopIfActive() -> [SafetyAction] {
        guard isControlActive else {
            return []
        }
        isControlActive = false
        return [.restoreSystemAuto, .stopControl]
    }
}
