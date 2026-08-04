import Foundation
import SwiftUI

@main
struct LocalMCPTunnel: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var controller: CLIController

    private static let legacyBundleIdentifier = "jp.co.varista.LocalMCPTunnelApp"
    private static let currentBundleIdentifier = "jp.co.walkingwifi.LocalMCPTunnel"
    private static let defaultsMigrationKey = "didMigrateLegacyDefaults"

    init() {
        Self.migrateLegacyDefaultsIfNeeded()

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

    private static func migrateLegacyDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultsMigrationKey) else { return }

        let currentDomain = defaults.persistentDomain(forName: currentBundleIdentifier) ?? [:]
        if let legacyDomain = defaults.persistentDomain(forName: legacyBundleIdentifier) {
            for (key, value) in legacyDomain where currentDomain[key] == nil {
                defaults.set(value, forKey: key)
            }
        }

        defaults.set(true, forKey: defaultsMigrationKey)
    }
}
