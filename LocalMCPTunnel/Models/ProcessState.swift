import Foundation

enum ProcessState: Equatable {
    case stopped
    case starting
    case running(processIdentifier: Int32)
    case stopping
    case failed(String)

    var label: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting up"
        case let .running(processIdentifier):
            return "Running (PID: \(processIdentifier))"
        case .stopping:
            return "Stopping"
        case .failed:
            return "Error"
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .starting, .stopping:
            return true
        default:
            return false
        }
    }
}
