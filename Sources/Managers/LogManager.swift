import Foundation

struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let source: String
    let message: String

    enum LogLevel: String, Sendable {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case debug = "DEBUG"
    }
}

@Observable
@MainActor
final class LogManager {
    static let shared = LogManager()

    var logs: [LogEntry] = []
    private let maxLogs = 500

    private init() {}

    func log(_ message: String, level: LogEntry.LogLevel = .info, source: String = "App") {
        let entry = LogEntry(timestamp: Date(), level: level, source: source, message: message)
        logs.append(entry)

        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }

        print("[\(entry.level.rawValue)] [\(source)] \(message)")
    }

    func info(_ message: String, source: String = "App") {
        log(message, level: .info, source: source)
    }

    func warning(_ message: String, source: String = "App") {
        log(message, level: .warning, source: source)
    }

    func error(_ message: String, source: String = "App") {
        log(message, level: .error, source: source)
    }

    func debug(_ message: String, source: String = "App") {
        log(message, level: .debug, source: source)
    }

    func clear() {
        logs.removeAll()
    }

    // Async versions for use from other actors
    nonisolated func logAsync(_ message: String, level: LogEntry.LogLevel = .info, source: String = "App") {
        Task { @MainActor in
            LogManager.shared.log(message, level: level, source: source)
        }
    }

    nonisolated func infoAsync(_ message: String, source: String = "App") {
        logAsync(message, level: .info, source: source)
    }

    nonisolated func warningAsync(_ message: String, source: String = "App") {
        logAsync(message, level: .warning, source: source)
    }

    nonisolated func errorAsync(_ message: String, source: String = "App") {
        logAsync(message, level: .error, source: source)
    }

    nonisolated func debugAsync(_ message: String, source: String = "App") {
        logAsync(message, level: .debug, source: source)
    }
}

// Global log functions for convenience - send to main actor
func logInfo(_ message: String, source: String = "App") {
    Task { @MainActor in
        LogManager.shared.log(message, level: .info, source: source)
    }
}

func logWarning(_ message: String, source: String = "App") {
    Task { @MainActor in
        LogManager.shared.log(message, level: .warning, source: source)
    }
}

func logError(_ message: String, source: String = "App") {
    Task { @MainActor in
        LogManager.shared.log(message, level: .error, source: source)
    }
}

func logDebug(_ message: String, source: String = "App") {
    Task { @MainActor in
        LogManager.shared.log(message, level: .debug, source: source)
    }
}
