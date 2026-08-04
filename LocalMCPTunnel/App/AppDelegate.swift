import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var controller: CLIController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.terminateAll()
    }
}
