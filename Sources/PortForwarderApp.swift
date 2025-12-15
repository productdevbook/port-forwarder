import SwiftUI
import AppKit

@main
struct PortForwarderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var manager = ConnectionManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(manager: manager)
        } label: {
            Image(systemName: manager.allConnected ? "network" : "network.slash")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(manager: manager)
        }
    }

    init() {
        // Set defaults for first launch
        if UserDefaults.standard.object(forKey: "showNotifications") == nil {
            UserDefaults.standard.set(true, forKey: "showNotifications")
        }
        if UserDefaults.standard.object(forKey: "autoStartConnections") == nil {
            UserDefaults.standard.set(true, forKey: "autoStartConnections")
        }
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var onboardingWindow: NSWindow?
    var settingsWindow: NSWindow?
    var manager: ConnectionManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hasOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        // Listen for openSettings notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettingsWindow),
            name: .openSettings,
            object: nil
        )

        if hasOnboarded {
            // Onboarding completed, run as menu bar app
            NSApp.setActivationPolicy(.accessory)

            // Auto-start connections
            if UserDefaults.standard.bool(forKey: "autoStartConnections") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NotificationCenter.default.post(name: .startAllConnections, object: nil)
                }
            }
        } else {
            // First launch, show onboarding
            showOnboarding()
        }
    }

    @objc func openSettingsWindow() {
        // If settings window exists, just show it
        if let window = settingsWindow {
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            window.level = .normal
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create settings window with shared manager
        let manager = self.manager ?? ConnectionManager()
        self.manager = manager

        let settingsView = SettingsView(manager: manager)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Port Forwarder Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 500, height: 400))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.settingsWindow = window

        // Bring window to front
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.level = .normal
        NSApp.activate(ignoringOtherApps: true)
    }

    func showOnboarding() {
        let onboardingView = OnboardingView()
        let hostingController = NSHostingController(rootView: onboardingView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Port Forwarder"
        window.styleMask = [.titled, .closable]
        window.center()
        window.setContentSize(NSSize(width: 420, height: 340))
        window.isReleasedWhenClosed = false

        self.onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Close connections and wait
        Task {
            await killAllConnections()

            // Terminate app after all connections are closed
            await MainActor.run {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }

        // Wait until connections are closed
        return .terminateLater
    }

    private func killAllConnections() async {
        logInfo("App terminating, killing all connections...", source: "app")

        // Use killStuckProcesses if ConnectionManager exists (force kill with pkill -9)
        if let manager = self.manager {
            await manager.killStuckProcesses()
        } else {
            // Run pkill directly if manager doesn't exist
            await killProcessesDirectly()
        }

        logInfo("All connections killed", source: "app")
    }

    private func killProcessesDirectly() async {
        // pkill -9 kubectl port-forward
        let pkillKubectl = Process()
        pkillKubectl.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkillKubectl.arguments = ["-9", "-f", "kubectl.*port-forward"]
        try? pkillKubectl.run()
        pkillKubectl.waitUntilExit()

        // pkill -9 socat
        let pkillSocat = Process()
        pkillSocat.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkillSocat.arguments = ["-9", "-f", "socat.*TCP-LISTEN"]
        try? pkillSocat.run()
        pkillSocat.waitUntilExit()

        try? await Task.sleep(for: .milliseconds(300))
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        // Clear reference and hide from Dock when settings window closes
        if window == settingsWindow {
            settingsWindow = nil

            // Hide from Dock (return to menu bar app mode)
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
