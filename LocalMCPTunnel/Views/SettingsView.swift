import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var saveButtonState: SaveButtonState = .idle
    @State private var saveResetTask: Task<Void, Never>?
    @State private var updateButtonState: UpdateButtonState = .idle
    @State private var updateButtonResetTask: Task<Void, Never>?
    @StateObject private var updateService = AppUpdateService()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Tunnel") {
                    TextField("Profile Name", text: $settings.profileName)
                    TextField("Tunnel ID", text: $settings.tunnelID)
                    TextField("Sample Name", text: $settings.sampleName)
                    TextField("tunnel-client", text: $settings.tunnelClientExecutable)
                    SecureField("CONTROL_PLANE_API_KEY", text: $settings.controlPlaneAPIKey)
                }

                Section("local-mcp") {
                    TextField("Session ID", text: $settings.sessionID)
                    TextField("local-mcp", text: $settings.localMCPExecutable)
                    TextField("MCP Command", text: $settings.mcpCommand)
                }

                Section("起動時に自動Allow") {
                    if settings.allowedDirectories.isEmpty {
                        Text("登録されているディレクトリはありません。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(settings.allowedDirectories, id: \.self) { directory in
                            HStack(spacing: 10) {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                Text(directory)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(directory)
                                Spacer()
                                Button {
                                    settings.removeAllowedDirectory(directory)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("このディレクトリを削除")
                            }
                        }
                    }

                    HStack {
                        Button("ディレクトリを追加…") {
                            chooseAllowedDirectories()
                        }
                        if !settings.allowedDirectories.isEmpty {
                            Button("すべて削除", role: .destructive) {
                                settings.allowedDirectories.removeAll()
                            }
                        }
                        Spacer()
                    }

                    Text("local-mcpのStart直後に、登録した各ディレクトリへ /permission allow を自動送信します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                updateSection

                Section("実行環境") {
                    HStack {
                        TextField("Working Directory", text: $settings.workingDirectory)
                        Button("選択") { chooseWorkingDirectory() }
                    }
                }
            }
            .formStyle(.grouped)
            .padding()

            saveFooter
        }
        .frame(width: 660, height: 680)
        .task {
            updateService.checkForUpdatesIfNeeded()
        }
        .onChange(of: updateService.state) { _, newState in
            handleUpdateServiceStateChange(newState)
        }
        .onDisappear {
            saveResetTask?.cancel()
            updateButtonResetTask?.cancel()
        }
    }

    @ViewBuilder
    private var updateSection: some View {
        Section("アプリの更新") {
            LabeledContent("現在のバージョン") {
                Text("v\(updateService.currentVersion)")
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 12) {
                updateStatus
                Spacer(minLength: 12)
                updateButton
            }
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateService.state {
        case .idle:
            Text("GitHub Releaseから最新版を確認します。")
                .foregroundStyle(.secondary)
        case .checking:
            Label("更新を確認中…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .upToDate(let latestVersion):
            Label("最新バージョンです（v\(latestVersion)）。", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .updateAvailable(let release):
            Label("v\(release.version) が利用できます。", systemImage: "arrow.down.circle.fill")
        case .downloading(let release):
            Label("v\(release.version) をダウンロード・検証中…", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .installing(let release):
            Label("v\(release.version) をインストール中。完了後に再起動します…", systemImage: "gearshape.2")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var updateButton: some View {
        Button(action: handleUpdateButton) {
            ZStack {
                animatedButtonFace(isVisible: updateButtonState == .idle) {
                    Text("更新を確認")
                }

                animatedButtonFace(isVisible: updateButtonState == .checking) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("確認中…")
                }

                animatedButtonFace(isVisible: updateButtonState == .upToDate) {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                    Text("最新です")
                }

                animatedButtonFace(isVisible: updateButtonState == .updateAvailable) {
                    Image(systemName: "arrow.down")
                        .fontWeight(.semibold)
                    Text(updateAvailableButtonTitle)
                }

                animatedButtonFace(isVisible: updateButtonState == .downloading) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("取得中…")
                }

                animatedButtonFace(isVisible: updateButtonState == .installing) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("更新中…")
                }

                animatedButtonFace(isVisible: updateButtonState == .failure) {
                    Image(systemName: "exclamationmark")
                        .fontWeight(.semibold)
                    Text("再試行")
                }
            }
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: 136, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(updateButtonBackground)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .animation(saveAnimation, value: updateButtonState)
        }
        .buttonStyle(.plain)
        .disabled(updateService.isBusy || updateButtonState == .upToDate)
        .accessibilityLabel(updateButtonAccessibilityLabel)
    }

    private var updateAvailableButtonTitle: String {
        guard case .updateAvailable(let release) = updateService.state else {
            return "更新する"
        }
        return "v\(release.version)に更新"
    }

    private var updateButtonBackground: Color {
        switch updateButtonState {
        case .failure:
            return Color(red: 112 / 255, green: 48 / 255, blue: 48 / 255)
        case .idle, .checking, .upToDate, .updateAvailable, .downloading, .installing:
            return Color(red: 60 / 255, green: 62 / 255, blue: 64 / 255)
        }
    }

    private var updateButtonAccessibilityLabel: String {
        switch updateButtonState {
        case .idle:
            return "アプリの更新を確認"
        case .checking:
            return "アプリの更新を確認中"
        case .upToDate:
            return "アプリは最新です"
        case .updateAvailable:
            if case .updateAvailable(let release) = updateService.state {
                return "バージョン\(release.version)へ更新"
            }
            return "アプリを更新"
        case .downloading:
            return "アプリの更新をダウンロード中"
        case .installing:
            return "アプリを更新中"
        case .failure:
            return "アプリの更新に失敗しました。再試行"
        }
    }

    private func handleUpdateButton() {
        if case .updateAvailable = updateService.state {
            updateService.installAvailableUpdate()
        } else {
            updateService.checkForUpdates()
        }
    }

    private func handleUpdateServiceStateChange(_ state: AppUpdateService.State) {
        updateButtonResetTask?.cancel()

        let nextState: UpdateButtonState
        switch state {
        case .idle:
            nextState = .idle
        case .checking:
            nextState = .checking
        case .upToDate:
            nextState = .upToDate
        case .updateAvailable:
            nextState = .updateAvailable
        case .downloading:
            nextState = .downloading
        case .installing:
            nextState = .installing
        case .failed:
            nextState = .failure
        }

        withAnimation(saveAnimation) {
            updateButtonState = nextState
        }

        guard nextState == .upToDate else { return }

        updateButtonResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, case .upToDate = updateService.state else { return }

            withAnimation(saveAnimation) {
                updateButtonState = .idle
            }
        }
    }

    private var saveFooter: some View {
        HStack(spacing: 12) {
            if let saveMessage = settings.saveMessage,
               !saveMessage.hasPrefix("設定を保存しました") {
                Text(saveMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)
            saveButton
        }
        .padding(.horizontal, 13)
        .frame(height: 53)
        .background(Color(red: 35 / 255, green: 40 / 255, blue: 42 / 255))
    }

    private var saveButton: some View {
        Button(action: saveSettings) {
            ZStack {
                saveButtonFace(for: .idle) {
                    Text("保存")
                }

                saveButtonFace(for: .saving) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("保存中…")
                }

                saveButtonFace(for: .success) {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                    Text("保存しました")
                }

                saveButtonFace(for: .failure) {
                    Image(systemName: "exclamationmark")
                        .fontWeight(.semibold)
                    Text("再試行")
                }
            }
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: 136, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(saveButtonBackground)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(saveButtonState == .saving)
        .keyboardShortcut("s", modifiers: .command)
        .accessibilityLabel(saveButtonState.accessibilityLabel)
    }

    private var saveButtonBackground: Color {
        switch saveButtonState {
        case .failure:
            return Color(red: 112 / 255, green: 48 / 255, blue: 48 / 255)
        case .idle, .saving, .success:
            return Color(red: 60 / 255, green: 62 / 255, blue: 64 / 255)
        }
    }

    private func saveButtonFace<Content: View>(
        for state: SaveButtonState,
        @ViewBuilder content: () -> Content
    ) -> some View {
        animatedButtonFace(isVisible: saveButtonState == state, content: content)
            .animation(saveAnimation, value: saveButtonState)
    }

    private func animatedButtonFace<Content: View>(
        isVisible: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            content()
        }
        .opacity(isVisible ? 1 : 0)
        .offset(y: reduceMotion || isVisible ? 0 : 3)
        .blur(radius: reduceMotion || isVisible ? 0 : 2)
        .accessibilityHidden(!isVisible)
    }

    private var saveAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)
    }

    private func saveSettings() {
        guard saveButtonState != .saving else { return }

        saveResetTask?.cancel()
        settings.clearSaveMessage()

        withAnimation(saveAnimation) {
            saveButtonState = .saving
        }

        let didSave = settings.save()
        saveResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }

            withAnimation(saveAnimation) {
                saveButtonState = didSave ? .success : .failure
            }

            try? await Task.sleep(for: .milliseconds(didSave ? 1000 : 2200))
            guard !Task.isCancelled else { return }

            withAnimation(saveAnimation) {
                saveButtonState = .idle
            }
        }
    }

    private func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: ShellPathResolver.expanded(settings.workingDirectory))
        if panel.runModal() == .OK, let url = panel.url {
            settings.workingDirectory = url.path
        }
    }

    private func chooseAllowedDirectories() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "追加"
        panel.message = "local-mcp起動時に自動でAllowするディレクトリを選択してください。"
        panel.directoryURL = URL(fileURLWithPath: ShellPathResolver.expanded(settings.workingDirectory))
        if panel.runModal() == .OK {
            settings.addAllowedDirectories(panel.urls.map(\.path))
        }
    }


    private enum UpdateButtonState: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable
        case downloading
        case installing
        case failure
    }

    private enum SaveButtonState {
        case idle
        case saving
        case success
        case failure

        var accessibilityLabel: String {
            switch self {
            case .idle:
                return "設定を保存"
            case .saving:
                return "設定を保存中"
            case .success:
                return "設定を保存しました"
            case .failure:
                return "設定の保存に失敗しました。再試行"
            }
        }
    }
}
