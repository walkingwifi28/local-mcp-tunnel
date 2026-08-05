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
            return "Please enter a Profile Name."
        }
        if tunnelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Please enter a Tunnel ID."
        }
        if sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Please enter a Session ID."
        }
        if controlPlaneAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Please set CONTROL_PLANE_API_KEY."
        }
        return nil
    }
}

@MainActor
final class AppSettings: ObservableObject {
    enum SaveResult {
        case success
        case failure(String)

        var didSave: Bool {
            if case .success = self { return true }
            return false
        }
    }

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
    private var saveMessageClearTask: Task<Void, Never>?

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
    func save() -> SaveResult {
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
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func showSaveMessage(for result: SaveResult) {
        switch result {
        case .success:
            showSaveMessage("Settings have been saved.")
        case .failure(let message):
            showSaveMessage("Failed to save API key: \(message)")
        }
    }

    func clearSaveMessage() {
        saveMessageClearTask?.cancel()
        saveMessageClearTask = nil
        saveMessage = nil
    }

    private func showSaveMessage(_ message: String) {
        saveMessageClearTask?.cancel()
        saveMessage = message

        saveMessageClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.saveMessage = nil
            self?.saveMessageClearTask = nil
        }
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
