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
            return "停止中"
        case .starting:
            return "起動中"
        case let .running(processIdentifier):
            return "実行中 (PID: \(processIdentifier))"
        case .stopping:
            return "停止処理中"
        case .failed:
            return "エラー"
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
