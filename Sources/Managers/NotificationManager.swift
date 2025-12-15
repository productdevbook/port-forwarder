import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var isInitialized = false
    private var lastNotificationTime: [String: Date] = [:]
    private let notificationCooldown: TimeInterval = 60 // 1 minute cooldown per connection

    private override init() {
        super.init()
    }

    private func ensureInitialized() {
        guard !isInitialized else { return }
        isInitialized = true
        // Only set delegate when running as a proper .app bundle
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func requestPermission() {
        ensureInitialized()
        logInfo("Requesting notification permission...", source: "notification")
        logInfo("Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")", source: "notification")

        guard Bundle.main.bundleIdentifier != nil else {
            logWarning("Notifications require running as a .app bundle", source: "notification")
            return
        }

        // First check current authorization status
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                logInfo("Current notification status: \(status.rawValue) (0=notDetermined, 1=denied, 2=authorized, 3=provisional)", source: "notification")

                if status == .notDetermined {
                    // Only request if not yet determined
                    self.doRequestAuthorization()
                } else if status == .denied {
                    logWarning("Notifications were previously denied. Please enable in System Settings > Notifications > Port Forwarder", source: "notification")
                } else if status == .authorized {
                    logInfo("Notifications already authorized", source: "notification")
                }
            }
        }
    }

    private func doRequestAuthorization() {
        logInfo("Calling requestAuthorization...", source: "notification")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            Task { @MainActor in
                if granted {
                    logInfo("Notification permission granted", source: "notification")
                } else if let error {
                    logError("Notification permission error: \(error.localizedDescription)", source: "notification")
                } else {
                    logWarning("Notification permission denied by user", source: "notification")
                }
            }
        }
    }

    // Show notifications even when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Handle notification tap
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            // Open Settings window when notification is tapped
            NotificationCenter.default.post(name: .openSettings, object: nil)
        }
        completionHandler()
    }

    func sendNotification(title: String, body: String, isError: Bool = false) {
        ensureInitialized()

        // Default to true if not set
        let showNotifications = UserDefaults.standard.object(forKey: "showNotifications") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "showNotifications")

        guard showNotifications else { return }

        // Check if running as a proper .app bundle
        guard Bundle.main.bundleIdentifier != nil else {
            logDebug("Skipping notification (not running as .app bundle): \(title)", source: "notification")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = isError ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logError("Notification error: \(error.localizedDescription)", source: "notification")
            }
        }

        logDebug("Notification sent: \(title)", source: "notification")
    }

    func connectionConnected(name: String) {
        // Only notify if was previously disconnected (had a notification)
        if lastNotificationTime[name] != nil {
            lastNotificationTime.removeValue(forKey: name)
            sendNotification(
                title: "Connected",
                body: "\(name) is now connected",
                isError: false
            )
        }
    }

    func connectionDisconnected(name: String) {
        // Rate limit: only send once per cooldown period
        if let lastTime = lastNotificationTime[name],
           Date().timeIntervalSince(lastTime) < notificationCooldown {
            return
        }
        lastNotificationTime[name] = Date()

        sendNotification(
            title: "Disconnected",
            body: "\(name) has disconnected",
            isError: true
        )
    }

    func connectionError(name: String, error: String) {
        // Rate limit: only send once per cooldown period
        if let lastTime = lastNotificationTime[name],
           Date().timeIntervalSince(lastTime) < notificationCooldown {
            return
        }
        lastNotificationTime[name] = Date()

        sendNotification(
            title: "Connection Error",
            body: "\(name): \(error)",
            isError: true
        )
    }

    func allConnectionsReady() {
        // No notification for all connections ready
    }
}
