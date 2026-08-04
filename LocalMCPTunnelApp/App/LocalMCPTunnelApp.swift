import SwiftUI

@main
struct LocalMCPTunnelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var controller: CLIController

    init() {
        let settings = AppSettings()
        let controller = CLIController()
        _settings = StateObject(wrappedValue: settings)
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(settings: settings, controller: controller)
                .onAppear { appDelegate.controller = controller }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 960, height: 760)

        Settings {
            SettingsView(settings: settings)
        }
    }
}
