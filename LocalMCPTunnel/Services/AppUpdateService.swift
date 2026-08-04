import AppKit
import CryptoKit
import Foundation

@MainActor
final class AppUpdateService: ObservableObject {
    struct ReleaseInfo: Equatable {
        let version: String
        let tagName: String
        let archiveURL: URL
        let checksumURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate(latestVersion: String)
        case updateAvailable(ReleaseInfo)
        case downloading(ReleaseInfo)
        case installing(ReleaseInfo)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    let currentVersion: String

    private let repositoryOwner = "walkingwifi28"
    private let repositoryName = "local-mcp-tunnel"
    private let bundleIdentifier = "jp.co.walkingwifi.LocalMCPTunnel"

    init(bundle: Bundle = .main) {
        currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing:
            return true
        case .idle, .upToDate, .updateAvailable, .failed:
            return false
        }
    }

    func checkForUpdatesIfNeeded() {
        guard case .idle = state else { return }
        checkForUpdates()
    }

    func checkForUpdates() {
        guard !isBusy else { return }
        state = .checking

        Task {
            let clock = ContinuousClock()
            let minimumLoadingEnd = clock.now.advanced(by: .milliseconds(500))

            do {
                let release = try await fetchLatestRelease()
                try? await clock.sleep(until: minimumLoadingEnd)

                if Self.isVersion(release.version, newerThan: currentVersion) {
                    state = .updateAvailable(release)
                } else {
                    state = .upToDate(latestVersion: release.version)
                }
            } catch {
                try? await clock.sleep(until: minimumLoadingEnd)
                state = .failed(Self.userMessage(for: error))
            }
        }
    }

    func installAvailableUpdate() {
        guard case .updateAvailable(let release) = state else { return }
        state = .downloading(release)

        Task {
            do {
                let package = try await downloadAndPrepare(release)
                state = .installing(release)
                try launchInstaller(package: package)

                try? await Task.sleep(for: .milliseconds(250))
                NSApplication.shared.terminate(nil)
            } catch {
                state = .failed(Self.userMessage(for: error))
            }
        }
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo {
        let endpoint = URL(string: "https://api.github.com/repos/\(repositoryOwner)/\(repositoryName)/releases/latest")!
        let request = makeRequest(url: endpoint, accept: "application/vnd.github+json")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTPResponse(response, data: data)

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = Self.version(from: release.tagName)
        let archiveName = "Local-MCP-Tunnel-\(version)-arm64.zip"
        let checksumName = "\(archiveName).sha256"

        guard let archiveURL = release.assets.first(where: { $0.name == archiveName })?.browserDownloadURL,
              let checksumURL = release.assets.first(where: { $0.name == checksumName })?.browserDownloadURL else {
            throw UpdateError.releaseAssetsMissing
        }

        return ReleaseInfo(
            version: version,
            tagName: release.tagName,
            archiveURL: archiveURL,
            checksumURL: checksumURL
        )
    }

    private func downloadAndPrepare(_ release: ReleaseInfo) async throws -> PreparedPackage {
        async let archiveDownload = downloadData(from: release.archiveURL)
        async let checksumDownload = downloadData(from: release.checksumURL)
        let (archiveData, checksumData) = try await (archiveDownload, checksumDownload)

        guard let checksumText = String(data: checksumData, encoding: .utf8),
              let expectedChecksum = checksumText.split(whereSeparator: { $0.isWhitespace }).first,
              expectedChecksum.count == 64 else {
            throw UpdateError.invalidChecksumFile
        }

        let actualChecksum = SHA256.hash(data: archiveData)
            .map { String(format: "%02x", $0) }
            .joined()

        guard actualChecksum.caseInsensitiveCompare(String(expectedChecksum)) == .orderedSame else {
            throw UpdateError.checksumMismatch
        }

        let archiveName = "Local-MCP-Tunnel-\(release.version)-arm64.zip"
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalMCPTunnelUpdate-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = temporaryRoot.appendingPathComponent(archiveName)
        let extractDirectory = temporaryRoot.appendingPathComponent("Extracted", isDirectory: true)

        try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        try archiveData.write(to: archiveURL, options: .atomic)

        let expectedBundleIdentifier = bundleIdentifier
        let targetAppURL = Bundle.main.bundleURL

        return try await Task.detached(priority: .userInitiated) {
            try Self.runProcess(
                executable: "/usr/bin/ditto",
                arguments: ["-x", "-k", archiveURL.path, extractDirectory.path]
            )

            let sourceAppURL = extractDirectory.appendingPathComponent("Local MCP Tunnel.app", isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sourceAppURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw UpdateError.appBundleMissing
            }

            guard let downloadedBundle = Bundle(url: sourceAppURL),
                  downloadedBundle.bundleIdentifier == expectedBundleIdentifier else {
                throw UpdateError.invalidAppBundle
            }

            let downloadedVersion = downloadedBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            guard downloadedVersion == release.version else {
                throw UpdateError.versionMismatch
            }

            try Self.runProcess(
                executable: "/usr/bin/codesign",
                arguments: ["--verify", "--deep", "--strict", sourceAppURL.path]
            )

            return PreparedPackage(
                temporaryRoot: temporaryRoot,
                sourceAppURL: sourceAppURL,
                targetAppURL: targetAppURL
            )
        }.value
    }

    private func downloadData(from url: URL) async throws -> Data {
        let request = makeRequest(url: url, accept: "application/octet-stream")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTPResponse(response, data: data)
        return data
    }

    private func makeRequest(url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Local-MCP-Tunnel/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        return request
    }

    private func launchInstaller(package: PreparedPackage) throws {
        let targetParent = package.targetAppURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: targetParent.path) else {
            throw UpdateError.installLocationNotWritable
        }

        let scriptURL = package.temporaryRoot.appendingPathComponent("install-update.zsh")
        let script = """
        #!/bin/zsh
        set -u

        APP_PID="$1"
        SOURCE_APP="$2"
        TARGET_APP="$3"
        TEMP_ROOT="$4"
        BACKUP_APP="${TARGET_APP}.update-backup"

        while /bin/kill -0 "$APP_PID" 2>/dev/null; do
          /bin/sleep 0.2
        done

        /bin/rm -rf "$BACKUP_APP"

        if [[ -e "$TARGET_APP" ]]; then
          if ! /bin/mv "$TARGET_APP" "$BACKUP_APP"; then
            /usr/bin/open "$TARGET_APP" >/dev/null 2>&1 || true
            exit 1
          fi
        fi

        if /usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"; then
          /usr/bin/xattr -dr com.apple.quarantine "$TARGET_APP" >/dev/null 2>&1 || true
          /bin/rm -rf "$BACKUP_APP"
          /usr/bin/open "$TARGET_APP"
          /bin/sleep 2
          /bin/rm -rf "$TEMP_ROOT"
          exit 0
        fi

        /bin/rm -rf "$TARGET_APP"
        if [[ -e "$BACKUP_APP" ]]; then
          /bin/mv "$BACKUP_APP" "$TARGET_APP"
          /usr/bin/open "$TARGET_APP" >/dev/null 2>&1 || true
        fi
        exit 1
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            package.sourceAppURL.path,
            package.targetAppURL.path,
            package.temporaryRoot.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    nonisolated private static func runProcess(executable: String, arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateError.commandFailed(message ?? executable)
        }
    }

    private static func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw UpdateError.releaseNotFound
            }

            let apiMessage = (try? JSONDecoder().decode(GitHubAPIError.self, from: data))?.message
            throw UpdateError.httpError(statusCode: httpResponse.statusCode, message: apiMessage)
        }
    }

    private static func version(from tagName: String) -> String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    private static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = numericVersionParts(candidate)
        let currentParts = numericVersionParts(current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }
        return false
    }

    private static func numericVersionParts(_ version: String) -> [Int] {
        version.split(separator: ".").map { component in
            let digits = component.prefix(while: { $0.isNumber })
            return Int(digits) ?? 0
        }
    }

    private static func userMessage(for error: Error) -> String {
        guard let updateError = error as? UpdateError else {
            return "更新処理に失敗しました: \(error.localizedDescription)"
        }

        switch updateError {
        case .releaseNotFound:
            return "公開済みの更新が見つかりませんでした。"
        case .releaseAssetsMissing:
            return "最新版のarm64用ZIPまたはSHA-256ファイルが見つかりません。"
        case .invalidChecksumFile:
            return "更新ファイルのSHA-256情報を読み取れませんでした。"
        case .checksumMismatch:
            return "更新ファイルのSHA-256が一致しないため、インストールを中止しました。"
        case .appBundleMissing, .invalidAppBundle, .versionMismatch:
            return "ダウンロードした更新ファイルが正しくありません。"
        case .installLocationNotWritable:
            return "現在のアプリ保存先へ書き込めません。アプリをApplicationsフォルダへ移動して再試行してください。"
        case .httpError(let statusCode, let message):
            if let message, !message.isEmpty {
                return "更新の確認に失敗しました（HTTP \(statusCode): \(message)）。"
            }
            return "更新の確認に失敗しました（HTTP \(statusCode)）。"
        case .invalidResponse:
            return "更新サーバーから正しい応答を受け取れませんでした。"
        case .commandFailed(let message):
            return "更新ファイルの検証に失敗しました: \(message)"
        }
    }

    private struct PreparedPackage {
        let temporaryRoot: URL
        let sourceAppURL: URL
        let targetAppURL: URL
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private struct GitHubAPIError: Decodable {
        let message: String
    }

    private enum UpdateError: Error {
        case invalidResponse
        case httpError(statusCode: Int, message: String?)
        case releaseNotFound
        case releaseAssetsMissing
        case invalidChecksumFile
        case checksumMismatch
        case appBundleMissing
        case invalidAppBundle
        case versionMismatch
        case installLocationNotWritable
        case commandFailed(String)
    }
}
