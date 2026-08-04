import Combine
import Foundation

@MainActor
final class CLIController: ObservableObject {
    @Published private(set) var tunnelState: ProcessState = .stopped
    @Published private(set) var localMCPState: ProcessState = .stopped
    @Published private(set) var tunnelLogText = ""
    @Published private(set) var localMCPLogText = ""
    @Published private(set) var permissionMode: PermissionMode = .ask
    @Published var presentedError: String?

    private enum DefaultsKeys {
        static let permissionMode = "permissionMode"
    }

    enum LogSource: String, CaseIterable, Identifiable {
        case tunnel
        case localMCP

        var id: Self { self }

        var label: String {
            switch self {
            case .tunnel:
                return "tunnel-client"
            case .localMCP:
                return "local-mcp"
            }
        }
    }

    private var initializationProcess: ManagedProcess?
    private var tunnelProcess: ManagedProcess?
    private var localMCPProcess: ManagedProcess?
    private var tunnelStopRequested = false
    private var localMCPStopRequested = false
    private var redactedValues: [String] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        permissionMode = PermissionMode(rawValue: defaults.string(forKey: DefaultsKeys.permissionMode) ?? "") ?? .ask
    }

    func initializeTunnel(using configuration: CLIConfiguration) {
        guard validate(configuration), initializationProcess == nil, tunnelProcess == nil else { return }

        do {
            rememberSecret(configuration.controlPlaneAPIKey)
            let environment = ShellPathResolver.augmentedEnvironment(apiKey: configuration.controlPlaneAPIKey)
            let executable = try ShellPathResolver.resolveExecutable(configuration.tunnelClientExecutable, environment: environment)
            let arguments = [
                "init",
                "--sample", configuration.sampleName,
                "--profile", configuration.profileName,
                "--tunnel-id", configuration.tunnelID,
                "--mcp-command", ShellPathResolver.expandHomeVariables(configuration.mcpCommand),
                "--force"
            ]
            appendLog("[tunnel:init] \(displayCommand(executable: executable.path, arguments: arguments))", to: .tunnel)
            tunnelState = .starting
            let process = try ManagedProcess(
                executable: executable,
                arguments: arguments,
                environment: environment,
                workingDirectory: configuration.workingDirectory,
                label: "tunnel:init",
                onOutput: { [weak self] line in self?.appendLog(line, to: .tunnel) },
                onTermination: { [weak self] status in
                    guard let self else { return }
                    self.initializationProcess = nil
                    self.tunnelState = status == 0 ? .stopped : .failed("終了コード: \(status)")
                }
            )
            initializationProcess = process
            try process.start()
        } catch {
            initializationProcess = nil
            tunnelState = .failed(error.localizedDescription)
            present(error, source: .tunnel)
        }
    }

    func startTunnel(using configuration: CLIConfiguration) {
        guard validate(configuration), initializationProcess == nil, tunnelProcess == nil else { return }
        do {
            rememberSecret(configuration.controlPlaneAPIKey)
            let environment = ShellPathResolver.augmentedEnvironment(apiKey: configuration.controlPlaneAPIKey)
            let executable = try ShellPathResolver.resolveExecutable(configuration.tunnelClientExecutable, environment: environment)
            let arguments = ["run", "--profile", configuration.profileName]
            appendLog("[tunnel] \(displayCommand(executable: executable.path, arguments: arguments))", to: .tunnel)
            tunnelState = .starting
            tunnelStopRequested = false

            let process = try ManagedProcess(
                executable: executable,
                arguments: arguments,
                environment: environment,
                workingDirectory: configuration.workingDirectory,
                label: "tunnel",
                onOutput: { [weak self] line in self?.appendLog(line, to: .tunnel) },
                onTermination: { [weak self] status in
                    guard let self else { return }
                    self.tunnelProcess = nil
                    let wasRequested = self.tunnelStopRequested
                    self.tunnelStopRequested = false
                    self.tunnelState = (wasRequested || status == 0) ? .stopped : .failed("終了コード: \(status)")
                }
            )
            tunnelProcess = process
            try process.start()
            tunnelState = .running(processIdentifier: process.processIdentifier)
        } catch {
            tunnelProcess = nil
            tunnelState = .failed(error.localizedDescription)
            present(error, source: .tunnel)
        }
    }

    func stopTunnel() {
        guard let tunnelProcess else { return }
        tunnelStopRequested = true
        tunnelState = .stopping
        appendLog("[tunnel] 停止要求を送信しました。", to: .tunnel)
        tunnelProcess.stop()
    }

    func startLocalMCP(using configuration: CLIConfiguration) {
        guard validate(configuration), localMCPProcess == nil else { return }
        do {
            rememberSecret(configuration.controlPlaneAPIKey)
            let environment = ShellPathResolver.augmentedEnvironment(apiKey: configuration.controlPlaneAPIKey)
            let executable = try ShellPathResolver.resolveExecutable(configuration.localMCPExecutable, environment: environment)
            let arguments = ["start", configuration.sessionID]
            appendLog("[local-mcp] \(displayCommand(executable: executable.path, arguments: arguments))", to: .localMCP)
            localMCPState = .starting
            localMCPStopRequested = false

            let process = try ManagedProcess(
                executable: executable,
                arguments: arguments,
                environment: environment,
                workingDirectory: configuration.workingDirectory,
                label: "local-mcp",
                onOutput: { [weak self] line in self?.appendLog(line, to: .localMCP) },
                onTermination: { [weak self] status in
                    guard let self else { return }
                    self.localMCPProcess = nil
                    let wasRequested = self.localMCPStopRequested
                    self.localMCPStopRequested = false
                    self.localMCPState = (wasRequested || status == 0) ? .stopped : .failed("終了コード: \(status)")
                }
            )
            localMCPProcess = process
            try process.start()
            localMCPState = .running(processIdentifier: process.processIdentifier)
            applyPermissionMode(to: process)
            applyAllowedDirectories(configuration.normalizedAllowedDirectories, to: process)
        } catch {
            localMCPProcess = nil
            localMCPState = .failed(error.localizedDescription)
            present(error, source: .localMCP)
        }
    }

    func stopLocalMCP() {
        guard let localMCPProcess else { return }
        localMCPStopRequested = true
        localMCPState = .stopping
        appendLog("[local-mcp] 停止要求を送信しました。", to: .localMCP)
        localMCPProcess.stop()
    }

    func sendPermission(_ command: PermissionCommand) {
        guard let process = localMCPProcess, process.isRunning else {
            presentedError = "先にlocal-mcpを起動してください。"
            return
        }
        do {
            try process.send(command.commandLine)
            updatePermissionModeIfNeeded(for: command)
            appendLog("[local-mcp:stdin] \(command.commandLine)", to: .localMCP)
        } catch {
            present(error, source: .localMCP)
        }
    }

    func canSendInput(to source: LogSource) -> Bool {
        activeInputTarget(for: source) != nil
    }

    @discardableResult
    func sendInput(_ input: String, to source: LogSource) -> Bool {
        let normalized = input.trimmingCharacters(in: .newlines)
        guard !normalized.isEmpty else { return false }
        guard let target = activeInputTarget(for: source) else {
            presentedError = "\(source.label)が起動していません。"
            return false
        }

        do {
            try target.process.send(normalized)
            if source == .localMCP {
                updatePermissionModeIfNeeded(for: normalized)
            }
            appendLog("[\(target.logLabel):stdin] \(normalized)", to: source)
            return true
        } catch {
            present(error, source: source)
            return false
        }
    }

    func logText(for source: LogSource) -> String {
        switch source {
        case .tunnel:
            return tunnelLogText
        case .localMCP:
            return localMCPLogText
        }
    }

    func clearLog(for source: LogSource) {
        switch source {
        case .tunnel:
            tunnelLogText = ""
        case .localMCP:
            localMCPLogText = ""
        }
    }

    func terminateAll() {
        initializationProcess?.forceStop()
        tunnelProcess?.forceStop()
        localMCPProcess?.forceStop()
        initializationProcess = nil
        tunnelProcess = nil
        localMCPProcess = nil
        tunnelState = .stopped
        localMCPState = .stopped
    }

    private func updatePermissionModeIfNeeded(for command: PermissionCommand) {
        switch command {
        case .ask:
            setPermissionMode(.ask)
        case .yolo:
            setPermissionMode(.yolo)
        case .allow, .revoke, .list, .status:
            break
        }
    }

    private func updatePermissionModeIfNeeded(for input: String) {
        switch input.trimmingCharacters(in: .whitespacesAndNewlines) {
        case PermissionCommand.ask.commandLine:
            setPermissionMode(.ask)
        case PermissionCommand.yolo.commandLine:
            setPermissionMode(.yolo)
        default:
            break
        }
    }

    private func setPermissionMode(_ mode: PermissionMode) {
        permissionMode = mode
        defaults.set(mode.rawValue, forKey: DefaultsKeys.permissionMode)
    }

    private func applyPermissionMode(to process: ManagedProcess) {
        let command: PermissionCommand = permissionMode == .yolo ? .yolo : .ask
        appendLog("[local-mcp] 保存済みのPermission Mode（\(permissionMode.label)）を適用します。", to: .localMCP)
        do {
            try process.send(command.commandLine)
            appendLog("[local-mcp:stdin] \(command.commandLine)", to: .localMCP)
        } catch {
            appendLog("[error] Permission Modeの自動適用に失敗しました: \(error.localizedDescription)", to: .localMCP)
            presentedError = "Permission Modeの自動適用に失敗しました。"
        }
    }

    private func applyAllowedDirectories(_ directories: [String], to process: ManagedProcess) {
        guard !directories.isEmpty else { return }

        appendLog("[local-mcp] 起動時の自動Allowを適用します（\(directories.count)件）。", to: .localMCP)
        for directory in directories {
            let command = PermissionCommand.allow(directory).commandLine
            do {
                try process.send(command)
                appendLog("[local-mcp:stdin] \(command)", to: .localMCP)
            } catch {
                appendLog("[error] 自動Allowに失敗しました: \(directory) - \(error.localizedDescription)", to: .localMCP)
                presentedError = "起動時の自動Allowに失敗しました: \(directory)"
                break
            }
        }
    }

    private func activeInputTarget(for source: LogSource) -> (process: ManagedProcess, logLabel: String)? {
        switch source {
        case .tunnel:
            if let tunnelProcess, tunnelProcess.isRunning {
                return (tunnelProcess, "tunnel")
            }
            if let initializationProcess, initializationProcess.isRunning {
                return (initializationProcess, "tunnel:init")
            }
            return nil
        case .localMCP:
            guard let localMCPProcess, localMCPProcess.isRunning else { return nil }
            return (localMCPProcess, "local-mcp")
        }
    }

    private func validate(_ configuration: CLIConfiguration) -> Bool {
        if let message = configuration.validationMessage {
            presentedError = message
            return false
        }
        return true
    }

    private func present(_ error: Error, source: LogSource? = nil) {
        if let source {
            appendLog("[error] \(error.localizedDescription)", to: source)
        }
        presentedError = error.localizedDescription
    }

    private func appendLog(_ message: String, to source: LogSource) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let normalized = message.hasSuffix("\n") ? String(message.dropLast()) : message
        let sanitized = redactedValues.reduce(normalized) { partial, secret in
            partial.replacingOccurrences(of: secret, with: "••••••••")
        }
        let entry = "[\(timestamp)] \(sanitized)\n"
        switch source {
        case .tunnel:
            tunnelLogText += entry
        case .localMCP:
            localMCPLogText += entry
        }
    }

    private func rememberSecret(_ value: String) {
        guard !value.isEmpty, !redactedValues.contains(value) else { return }
        redactedValues.append(value)
    }

    private func displayCommand(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map { value in
            value.contains(" ") ? "\"\(value)\"" : value
        }.joined(separator: " ")
    }
}

private final class ManagedProcess {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let label: String
    private let onOutput: @MainActor (String) -> Void
    private let onTermination: @MainActor (Int32) -> Void
    private var stopFallback: DispatchWorkItem?

    var processIdentifier: Int32 { process.processIdentifier }
    var isRunning: Bool { process.isRunning }

    init(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String,
        label: String,
        onOutput: @escaping @MainActor (String) -> Void,
        onTermination: @escaping @MainActor (Int32) -> Void
    ) throws {
        self.label = label
        self.onOutput = onOutput
        self.onTermination = onTermination
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let expandedDirectory = ShellPathResolver.expanded(workingDirectory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProcessError.invalidWorkingDirectory(expandedDirectory)
        }
        process.currentDirectoryURL = URL(fileURLWithPath: expandedDirectory, isDirectory: true)

        stdoutPipe.fileHandleForReading.readabilityHandler = makeReadHandler(stream: "stdout")
        stderrPipe.fileHandleForReading.readabilityHandler = makeReadHandler(stream: "stderr")
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.stopFallback?.cancel()
            self.closePipes()
            Task { @MainActor in
                self.onOutput("[\(self.label)] 終了しました (code: \(process.terminationStatus))")
                self.onTermination(process.terminationStatus)
            }
        }
    }

    func start() throws {
        try process.run()
    }

    func send(_ command: String) throws {
        guard process.isRunning else { throw ProcessError.notRunning }
        guard let data = (command + "\n").data(using: .utf8) else { throw ProcessError.encodingFailed }
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }

    func stop() {
        guard process.isRunning else { return }
        process.interrupt()
        let fallback = DispatchWorkItem { [weak self] in
            guard let self, self.process.isRunning else { return }
            self.process.terminate()
        }
        stopFallback = fallback
        DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: fallback)
    }

    func forceStop() {
        stopFallback?.cancel()
        if process.isRunning { process.terminate() }
        closePipes()
    }

    private func makeReadHandler(stream: String) -> (FileHandle) -> Void {
        { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for line in lines where !line.isEmpty {
                Task { @MainActor in
                    self.onOutput("[\(self.label):\(stream)] \(line)")
                }
            }
        }
    }

    private func closePipes() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe.fileHandleForWriting.close()
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()
    }

    enum ProcessError: LocalizedError {
        case invalidWorkingDirectory(String)
        case notRunning
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case let .invalidWorkingDirectory(path):
                return "作業ディレクトリが存在しません: \(path)"
            case .notRunning:
                return "プロセスが起動していません。"
            case .encodingFailed:
                return "コマンドをUTF-8へ変換できませんでした。"
            }
        }
    }
}