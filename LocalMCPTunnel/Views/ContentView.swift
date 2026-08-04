import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: CLIController
    @State private var showingYoloConfirmation = false
    @State private var selectedLogSource: CLIController.LogSource = .tunnel
    @State private var tunnelInput = ""
    @State private var localMCPInput = ""

    var body: some View {
        VStack(spacing: 14) {
            header
            HStack(alignment: .top, spacing: 14) {
                tunnelCard
                localMCPCard
            }
            logCard
        }
        .padding(18)
        .frame(minWidth: 880, minHeight: 700)
        .alert("エラー", isPresented: Binding(
            get: { controller.presentedError != nil },
            set: { if !$0 { controller.presentedError = nil } }
        )) {
            Button("OK", role: .cancel) { controller.presentedError = nil }
        } message: {
            Text(controller.presentedError ?? "")
        }
        .confirmationDialog(
            "Yoloモードを有効にしますか？",
            isPresented: $showingYoloConfirmation,
            titleVisibility: .visible
        ) {
            Button("Yoloを有効化", role: .destructive) {
                controller.sendPermission(.yolo)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("確認なしで広い権限を許可する可能性があります。信頼できる環境でのみ使用してください。")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Local MCP Tunnel")
                    .font(.title2.bold())
                Text("tunnel-clientとlocal-mcpをまとめて操作します")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SettingsLink {
                Label("設定", systemImage: "gearshape")
            }
        }
    }

    private var tunnelCard: some View {
        GroupBox("Tunnel Client") {
            VStack(alignment: .leading, spacing: 12) {
                statusRow(controller.tunnelState)
                LabeledContent("Profile", value: settings.profileName.isEmpty ? "未設定" : settings.profileName)
                LabeledContent("Tunnel ID", value: settings.tunnelID.isEmpty ? "未設定" : settings.tunnelID)
                HStack {
                    Button("Init") {
                        settings.save()
                        controller.initializeTunnel(using: settings.configuration)
                    }
                    .disabled(controller.tunnelState.isBusy || controller.tunnelState.isRunning)

                    if controller.tunnelState.isRunning {
                        Button("停止", role: .destructive) { controller.stopTunnel() }
                    } else {
                        Button("Run") {
                            settings.save()
                            controller.startTunnel(using: settings.configuration)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.tunnelState.isBusy)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var localMCPCard: some View {
        GroupBox("local-mcp") {
            VStack(alignment: .leading, spacing: 12) {
                statusRow(controller.localMCPState)
                LabeledContent("Session", value: settings.sessionID.isEmpty ? "未設定" : settings.sessionID)
                LabeledContent("Working Dir", value: settings.workingDirectory)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack {
                    if controller.localMCPState.isRunning {
                        Button("停止", role: .destructive) { controller.stopLocalMCP() }
                    } else {
                        Button("Start") {
                            settings.save()
                            controller.startLocalMCP(using: settings.configuration)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.localMCPState.isBusy)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var logCard: some View {
        GroupBox {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Text("Log")
                        .font(.headline)

                    Picker("ログ種別", selection: $selectedLogSource) {
                        ForEach(CLIController.LogSource.allCases) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)

                    if selectedLogSource == .localMCP {
                        permissionToolbar
                    }

                    Spacer()

                    Button("コピー") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(selectedLogText, forType: .string)
                    }
                    Button("クリア") {
                        controller.clearLog(for: selectedLogSource)
                    }
                }

                LogTextView(
                    text: selectedLogText,
                    input: selectedInput,
                    isInputEnabled: controller.canSendInput(to: selectedLogSource),
                    prompt: "› ",
                    onSubmit: sendSelectedInput
                )
                .id(selectedLogSource)
                .frame(minHeight: 270)
            }
            .padding(6)
        }
    }

    private var permissionToolbar: some View {
        HStack(spacing: 8) {
            Picker("Permission Mode", selection: permissionModeSelection) {
                ForEach(PermissionMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)

            Button("Allow…") { chooseDirectory(for: .allow) }
            Button("Revoke…") { chooseDirectory(for: .revoke) }
            Button("List") { controller.sendPermission(.list) }
            Button("Status") { controller.sendPermission(.status) }
        }
        .disabled(!controller.localMCPState.isRunning)
    }

    private var permissionModeSelection: Binding<PermissionMode> {
        Binding(
            get: { controller.permissionMode },
            set: { selectPermissionMode($0) }
        )
    }

    private func selectPermissionMode(_ mode: PermissionMode) {
        guard mode != controller.permissionMode else { return }

        switch mode {
        case .ask:
            controller.sendPermission(.ask)
        case .yolo:
            showingYoloConfirmation = true
        }
    }

    private var selectedLogText: String {
        controller.logText(for: selectedLogSource)
    }

    private var selectedInput: Binding<String> {
        switch selectedLogSource {
        case .tunnel:
            return $tunnelInput
        case .localMCP:
            return $localMCPInput
        }
    }

    private func sendSelectedInput() {
        let input = selectedInput.wrappedValue
        guard controller.sendInput(input, to: selectedLogSource) else { return }
        selectedInput.wrappedValue = ""
    }

    private func statusRow(_ state: ProcessState) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(state.isRunning ? Color.green : (state.isBusy ? Color.orange : Color.secondary))
                .frame(width: 9, height: 9)
            Text(state.label)
                .font(.subheadline.weight(.medium))
            if case let .failed(message) = state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }

    private enum DirectoryAction {
        case allow
        case revoke
    }

    private func chooseDirectory(for action: DirectoryAction) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: ShellPathResolver.expanded(settings.workingDirectory))
        if panel.runModal() == .OK, let path = panel.url?.path {
            switch action {
            case .allow:
                controller.sendPermission(.allow(path))
            case .revoke:
                controller.sendPermission(.revoke(path))
            }
        }
    }
}
