import Combine
import Foundation

struct CLIConfiguration: Equatable {
    var profileName: String
    var tunnelID: String
    var sessionID: String
    var sampleName: String
    var tunnelClientExecutable: String
    var localMCPExecutable: String
    var mcpCommand: String
    var workingDirectory: String
    var controlPlaneAPIKey: String
    var allowedDirectories: [String]

    var normalizedAllowedDirectories: [String] {
        var seen = Set<String>()
        return allowedDirectories.compactMap { directory in
            let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let expanded = ShellPathResolver.expanded(trimmed)
            guard seen.insert(expanded).inserted else { return nil }
            return expanded
        }
    }

    var validationMessage: String? {
        if profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Profile Nameを入力してください。"
        }
        if tunnelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Tunnel IDを入力してください。"
        }
        if sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Session IDを入力してください。"
        }
        if controlPlaneAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "CONTROL_PLANE_API_KEYを設定してください。"
        }
        return nil
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var profileName: String
    @Published var tunnelID: String
    @Published var sessionID: String
    @Published var sampleName: String
    @Published var tunnelClientExecutable: String
    @Published var localMCPExecutable: String
    @Published var mcpCommand: String
    @Published var workingDirectory: String
    @Published var controlPlaneAPIKey: String
    @Published var allowedDirectories: [String]
    @Published private(set) var saveMessage: String?

    private enum Keys {
        static let profileName = "profileName"
        static let tunnelID = "tunnelID"
        static let sessionID = "sessionID"
        static let sampleName = "sampleName"
        static let tunnelClientExecutable = "tunnelClientExecutable"
        static let localMCPExecutable = "localMCPExecutable"
        static let mcpCommand = "mcpCommand"
        static let workingDirectory = "workingDirectory"
        static let allowedDirectories = "allowedDirectories"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = .shared) {
        self.defaults = defaults
        self.keychain = keychain

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        profileName = defaults.string(forKey: Keys.profileName) ?? ""
        tunnelID = defaults.string(forKey: Keys.tunnelID) ?? ""
        sessionID = defaults.string(forKey: Keys.sessionID) ?? "local-mcp"
        sampleName = defaults.string(forKey: Keys.sampleName) ?? "sample_mcp_stdio_local"
        tunnelClientExecutable = defaults.string(forKey: Keys.tunnelClientExecutable) ?? "tunnel-client"
        localMCPExecutable = defaults.string(forKey: Keys.localMCPExecutable) ?? "$HOME/.local/bin/local-mcp"
        mcpCommand = defaults.string(forKey: Keys.mcpCommand) ?? "$HOME/.local/bin/local-mcp mcp"
        workingDirectory = defaults.string(forKey: Keys.workingDirectory) ?? home
        controlPlaneAPIKey = (try? keychain.read()) ?? ""
        allowedDirectories = Self.normalizedDirectories(defaults.stringArray(forKey: Keys.allowedDirectories) ?? [])
    }

    var configuration: CLIConfiguration {
        CLIConfiguration(
            profileName: profileName,
            tunnelID: tunnelID,
            sessionID: sessionID,
            sampleName: sampleName,
            tunnelClientExecutable: tunnelClientExecutable,
            localMCPExecutable: localMCPExecutable,
            mcpCommand: mcpCommand,
            workingDirectory: workingDirectory,
            controlPlaneAPIKey: controlPlaneAPIKey,
            allowedDirectories: allowedDirectories
        )
    }

    func addAllowedDirectories(_ directories: [String]) {
        allowedDirectories = Self.normalizedDirectories(allowedDirectories + directories)
    }

    func removeAllowedDirectory(_ directory: String) {
        allowedDirectories.removeAll { $0 == directory }
    }

    @discardableResult
    func save() -> Bool {
        allowedDirectories = Self.normalizedDirectories(allowedDirectories)

        defaults.set(profileName, forKey: Keys.profileName)
        defaults.set(tunnelID, forKey: Keys.tunnelID)
        defaults.set(sessionID, forKey: Keys.sessionID)
        defaults.set(sampleName, forKey: Keys.sampleName)
        defaults.set(tunnelClientExecutable, forKey: Keys.tunnelClientExecutable)
        defaults.set(localMCPExecutable, forKey: Keys.localMCPExecutable)
        defaults.set(mcpCommand, forKey: Keys.mcpCommand)
        defaults.set(workingDirectory, forKey: Keys.workingDirectory)
        defaults.set(allowedDirectories, forKey: Keys.allowedDirectories)

        do {
            try keychain.save(controlPlaneAPIKey)
            saveMessage = "設定を保存しました。"
            return true
        } catch {
            saveMessage = "APIキーの保存に失敗しました: \(error.localizedDescription)"
            return false
        }
    }

    func clearSaveMessage() {
        saveMessage = nil
    }

    private static func normalizedDirectories(_ directories: [String]) -> [String] {
        var seen = Set<String>()
        return directories.compactMap { directory in
            let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let expanded = ShellPathResolver.expanded(trimmed)
            guard seen.insert(expanded).inserted else { return nil }
            return expanded
        }
    }
}