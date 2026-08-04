import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

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
                if let saveMessage = settings.saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(
                            saveMessage.hasPrefix("設定を")
                                ? Color.secondary
                                : Color.red
                        )
                }
                Spacer()
                Button("保存") {
                    settings.save()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 660, height: 680)
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
}