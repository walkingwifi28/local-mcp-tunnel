import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var saveButtonState: SaveButtonState = .idle
    @State private var saveResetTask: Task<Void, Never>?

    var body: some View {
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

            Section("実行環境") {
                HStack {
                    TextField("Working Directory", text: $settings.workingDirectory)
                    Button("選択") { chooseWorkingDirectory() }
                }
            }

            HStack {
                if let saveMessage = settings.saveMessage,
                   !saveMessage.hasPrefix("設定を保存しました") {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                saveButton
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 660, height: 680)
        .onDisappear {
            saveResetTask?.cancel()
        }
    }

    private var saveButton: some View {
        Button(action: saveSettings) {
            ZStack {
                saveButtonFace(for: .idle) {
                    Text("保存")
                }

                saveButtonFace(for: .saving, tone: .secondary) {
                    ProgressView()
                        .controlSize(.small)
                    Text("保存中…")
                }

                saveButtonFace(for: .success, tone: .green) {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                    Text("保存しました")
                }

                saveButtonFace(for: .failure, tone: .red) {
                    Image(systemName: "exclamationmark")
                        .fontWeight(.semibold)
                    Text("再試行")
                }
            }
            .frame(minWidth: 112, minHeight: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(saveButtonState == .saving)
        .keyboardShortcut("s", modifiers: .command)
        .accessibilityLabel(saveButtonState.accessibilityLabel)
    }

    private func saveButtonFace<Content: View>(
        for state: SaveButtonState,
        tone: Color = .primary,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            content()
        }
        .foregroundStyle(tone)
        .opacity(saveButtonState == state ? 1 : 0)
        .offset(y: reduceMotion || saveButtonState == state ? 0 : 3)
        .blur(radius: reduceMotion || saveButtonState == state ? 0 : 2)
        .animation(saveAnimation, value: saveButtonState)
        .accessibilityHidden(saveButtonState != state)
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
