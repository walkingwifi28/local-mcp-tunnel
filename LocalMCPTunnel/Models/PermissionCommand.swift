import Foundation

enum PermissionMode: String, CaseIterable, Identifiable {
    case ask
    case yolo

    var id: Self { self }

    var label: String {
        switch self {
        case .ask:
            return "Ask"
        case .yolo:
            return "Yolo"
        }
    }
}

enum PermissionCommand: Equatable {
    case ask
    case yolo
    case allow(String)
    case revoke(String)
    case list
    case status

    var commandLine: String {
        switch self {
        case .ask:
            return "/permission ask"
        case .yolo:
            return "/permission yolo"
        case let .allow(directory):
            return "/permission allow \(directory)"
        case let .revoke(directory):
            return "/permission revoke \(directory)"
        case .list:
            return "/permission list"
        case .status:
            return "/permission status"
        }
    }

    private static func quote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
