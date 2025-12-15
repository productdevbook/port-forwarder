import Foundation

struct ConfigStorage: Sendable {
    private let configURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("PortForwarder", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        configURL = appDir.appendingPathComponent("connections.json")
    }

    func load() -> [ConnectionConfig] {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            let defaults = ConnectionConfig.defaultConfigs
            save(defaults)
            return defaults
        }

        do {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode([ConnectionConfig].self, from: data)
        } catch {
            logError("Failed to load configs: \(error)", source: "ConfigStorage")
            return ConnectionConfig.defaultConfigs
        }
    }

    func save(_ configs: [ConnectionConfig]) {
        do {
            let data = try JSONEncoder().encode(configs)
            try data.write(to: configURL)
        } catch {
            logError("Failed to save configs: \(error)", source: "ConfigStorage")
        }
    }
}
