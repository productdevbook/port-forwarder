import Foundation

struct ConnectionConfig: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    var namespace: String
    var service: String
    var localPort: Int
    var remotePort: Int
    var proxyPort: Int?
    var isEnabled: Bool
    var autoReconnect: Bool
    /// Direct exec mode: Uses kubectl exec + netcat for true multi-connection support
    /// Requires netcat (nc) to be installed in the pod
    var useDirectExec: Bool

    init(
        id: UUID = UUID(),
        name: String,
        namespace: String,
        service: String,
        localPort: Int,
        remotePort: Int,
        proxyPort: Int? = nil,
        isEnabled: Bool = true,
        autoReconnect: Bool = true,
        useDirectExec: Bool = false
    ) {
        self.id = id
        self.name = name
        self.namespace = namespace
        self.service = service
        self.localPort = localPort
        self.remotePort = remotePort
        self.proxyPort = proxyPort
        self.isEnabled = isEnabled
        self.autoReconnect = autoReconnect
        self.useDirectExec = useDirectExec
    }

    static let defaultConfigs: [ConnectionConfig] = []
}

enum ConnectionStatus: String, Sendable {
    case disconnected = "Disconnected"
    case connecting = "Connecting..."
    case connected = "Connected"
    case error = "Error"

    var icon: String {
        switch self {
        case .disconnected: "circle"
        case .connecting: "circle.dotted"
        case .connected: "circle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }
}

@Observable
@MainActor
final class ConnectionState: Identifiable, Hashable {
    let id: UUID
    var config: ConnectionConfig
    var portForwardStatus: ConnectionStatus = .disconnected
    var proxyStatus: ConnectionStatus = .disconnected
    var portForwardTask: Task<Void, Never>?
    var proxyTask: Task<Void, Never>?
    var lastError: String?

    var isFullyConnected: Bool {
        if config.proxyPort != nil {
            return portForwardStatus == .connected && proxyStatus == .connected
        }
        return portForwardStatus == .connected
    }

    init(id: UUID, config: ConnectionConfig) {
        self.id = id
        self.config = config
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    nonisolated static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        lhs.id == rhs.id
    }
}
