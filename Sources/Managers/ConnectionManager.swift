import Foundation

extension Notification.Name {
    static let startAllConnections = Notification.Name("startAllConnections")
    static let stopAllConnections = Notification.Name("stopAllConnections")
    static let openSettings = Notification.Name("openSettings")
}

@Observable
@MainActor
final class ConnectionManager {
    var connections: [ConnectionState] = []
    var isMonitoring = false
    var isKillingProcesses = false

    private var monitorTask: Task<Void, Never>?
    private let configStorage = ConfigStorage()
    let processManager = ProcessManager()

    var allConnected: Bool {
        guard !connections.isEmpty else { return false }
        return connections.allSatisfy(\.isFullyConnected)
    }

    init() {
        loadConfigs()
        setupNotificationObserver()
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: .startAllConnections,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.startAll()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .stopAllConnections,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopAll()
            }
        }
    }

    func loadConfigs() {
        let configs = configStorage.load()
        connections = configs.map { ConnectionState(id: $0.id, config: $0) }
    }

    func saveConfigs() {
        configStorage.save(connections.map(\.config))
    }

    func addConnection(_ config: ConnectionConfig) {
        connections.append(ConnectionState(id: config.id, config: config))
        saveConfigs()
    }

    func removeConnection(_ id: UUID) {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        stopConnection(id)
        connections.remove(at: index)
        saveConfigs()
    }

    func updateConnection(_ config: ConnectionConfig) {
        guard let index = connections.firstIndex(where: { $0.id == config.id }) else { return }
        let wasConnected = connections[index].isFullyConnected
        if wasConnected {
            stopConnection(config.id)
        }
        connections[index].config = config
        saveConfigs()
        if wasConnected && config.isEnabled {
            startConnection(config.id)
        }
    }

    func startAll() {
        for connection in connections where connection.config.isEnabled {
            startConnection(connection.id)
        }
        startMonitoring()
    }

    func stopAll() {
        stopMonitoring()
        for connection in connections {
            stopConnection(connection.id)
        }
    }

    func killStuckProcesses() async {
        isKillingProcesses = true
        stopMonitoring()

        // First cancel all tasks
        for connection in connections {
            connection.portForwardTask?.cancel()
            connection.proxyTask?.cancel()
            connection.portForwardTask = nil
            connection.proxyTask = nil
        }

        // Wait for tasks to close
        try? await Task.sleep(for: .milliseconds(200))

        await processManager.killAllPortForwarderProcesses()

        // Reset all states
        for connection in connections {
            connection.portForwardStatus = .disconnected
            connection.proxyStatus = .disconnected
        }

        isKillingProcesses = false
    }

    func startConnection(_ id: UUID) {
        guard !isKillingProcesses else { return }
        guard let state = connections.first(where: { $0.id == id }) else { return }
        let config = state.config

        state.portForwardStatus = .connecting
        state.portForwardTask = Task {
            await runPortForward(for: state, config: config)
        }
    }

    func stopConnection(_ id: UUID) {
        guard let state = connections.first(where: { $0.id == id }) else { return }

        state.proxyTask?.cancel()
        state.proxyTask = nil
        state.proxyStatus = .disconnected

        state.portForwardTask?.cancel()
        state.portForwardTask = nil
        state.portForwardStatus = .disconnected

        Task { await processManager.killProcesses(for: id) }
    }

    func restartConnection(_ id: UUID) {
        stopConnection(id)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            startConnection(id)
        }
    }

    private func runPortForward(for state: ConnectionState, config: ConnectionConfig) async {
        // Direct exec mode: don't use kubectl port-forward, start exec proxy directly
        if config.useDirectExec, config.proxyPort != nil {
            await runDirectExecProxy(for: state, config: config)
            return
        }

        do {
            let process = try await processManager.startPortForward(
                id: state.id,
                namespace: config.namespace,
                service: config.service,
                localPort: config.localPort,
                remotePort: config.remotePort
            )

            // Wait and check if running
            try await Task.sleep(for: .seconds(2))

            if process.isRunning {
                state.portForwardStatus = .connected

                if config.proxyPort != nil {
                    state.proxyStatus = .connecting
                    state.proxyTask = Task {
                        await runProxy(for: state, config: config)
                    }
                } else {
                    // No proxy needed, connection is fully ready
                    NotificationManager.shared.connectionConnected(name: config.name)
                    checkAllConnected()
                }
            } else {
                state.portForwardStatus = .error
                state.lastError = "Port forward failed to start"
                NotificationManager.shared.connectionError(name: config.name, error: "Port forward failed to start")
            }
        } catch {
            state.portForwardStatus = .error
            state.lastError = error.localizedDescription
            NotificationManager.shared.connectionError(name: config.name, error: error.localizedDescription)
        }
    }

    /// Direct exec proxy: true multiple connections with kubectl exec + netcat
    /// Bypasses kubectl port-forward, opens separate exec for each connection
    private func runDirectExecProxy(for state: ConnectionState, config: ConnectionConfig) async {
        guard let proxyPort = config.proxyPort else { return }

        // In direct exec mode there's no port-forward, only proxy
        state.portForwardStatus = .connected
        state.proxyStatus = .connecting

        do {
            let process = try await processManager.startDirectExecProxy(
                id: state.id,
                namespace: config.namespace,
                service: config.service,
                externalPort: proxyPort,
                remotePort: config.remotePort
            )

            try await Task.sleep(for: .seconds(1))

            if process.isRunning {
                state.proxyStatus = .connected
                NotificationManager.shared.connectionConnected(name: config.name)
                checkAllConnected()
            } else {
                state.proxyStatus = .error
                state.portForwardStatus = .error
                state.lastError = "Direct exec proxy failed to start"
                NotificationManager.shared.connectionError(name: config.name, error: "Direct exec proxy failed to start")
            }
        } catch {
            state.proxyStatus = .error
            state.portForwardStatus = .error
            state.lastError = error.localizedDescription
            NotificationManager.shared.connectionError(name: config.name, error: error.localizedDescription)
        }
    }

    private func runProxy(for state: ConnectionState, config: ConnectionConfig) async {
        guard let proxyPort = config.proxyPort else { return }

        do {
            let process = try await processManager.startProxy(
                id: state.id,
                externalPort: proxyPort,
                internalPort: config.localPort
            )

            try await Task.sleep(for: .seconds(1))

            if process.isRunning {
                state.proxyStatus = .connected
                NotificationManager.shared.connectionConnected(name: config.name)
                checkAllConnected()
            } else {
                state.proxyStatus = .error
                state.lastError = "Socat proxy failed to start"
                NotificationManager.shared.connectionError(name: config.name, error: "Socat proxy failed to start")
            }
        } catch {
            state.proxyStatus = .error
            state.lastError = error.localizedDescription
            NotificationManager.shared.connectionError(name: config.name, error: error.localizedDescription)
        }
    }

    private func checkAllConnected() {
        if allConnected {
            NotificationManager.shared.allConnectionsReady()
        }
    }

    private func startMonitoring() {
        isMonitoring = true
        monitorTask = Task {
            while !Task.isCancelled && isMonitoring {
                await checkConnections()
                // 1 second interval for fast reconnect
                // Immediately detects kubectl "lost connection to pod" error
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopMonitoring() {
        isMonitoring = false
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func checkConnections() async {
        guard !isKillingProcesses else { return }
        for state in connections {
            guard state.config.isEnabled && state.config.autoReconnect else { continue }

            // Direct exec mode: only check proxy, no kubectl port-forward
            if state.config.useDirectExec, state.config.proxyPort != nil {
                await checkDirectExecConnection(state)
                continue
            }

            // Standard mode: kubectl port-forward + optional socat proxy
            let localPort = state.config.localPort
            let processRunning = await processManager.isProcessRunning(for: state.id, type: .portForward)
            let hasError = await processManager.hasRecentError(for: state.id)
            let pfWorking = await processManager.isPortOpen(port: localPort)

            // If disconnected or error, try to reconnect
            if state.portForwardStatus == .disconnected || state.portForwardStatus == .error {
                logInfo("Auto-reconnecting \(state.config.name)...", source: "monitor")
                await processManager.clearError(for: state.id)
                startConnection(state.id)
                continue
            }

            // If kubectl reported an error in stderr, reconnect immediately
            if state.portForwardStatus == .connected && hasError {
                logWarning("kubectl error detected for \(state.config.name), reconnecting...", source: "monitor")
                state.lastError = "kubectl error"
                NotificationManager.shared.connectionDisconnected(name: state.config.name)
                state.portForwardStatus = .disconnected
                state.proxyStatus = .disconnected
                await processManager.killProcesses(for: state.id)
                await processManager.clearError(for: state.id)
                startConnection(state.id)
                continue
            }

            // If process died, reconnect immediately
            if state.portForwardStatus == .connected && !processRunning {
                logWarning("Process died for \(state.config.name), reconnecting...", source: "monitor")
                state.lastError = "Process terminated"
                NotificationManager.shared.connectionDisconnected(name: state.config.name)
                state.portForwardStatus = .disconnected
                state.proxyStatus = .disconnected
                startConnection(state.id)
                continue
            }

            // If supposed to be connected but port not responding, reconnect
            if state.portForwardStatus == .connected && !pfWorking {
                logWarning("Port \(String(localPort)) not responding, reconnecting \(state.config.name)...", source: "monitor")
                state.lastError = "Connection lost"
                NotificationManager.shared.connectionDisconnected(name: state.config.name)
                state.portForwardStatus = .disconnected
                state.proxyStatus = .disconnected
                await processManager.killProcesses(for: state.id)
                startConnection(state.id)
                continue
            }

            // Check proxy if enabled
            if let proxyPort = state.config.proxyPort {
                // If proxy disconnected but port-forward is up, restart proxy
                if state.proxyStatus == .disconnected && state.portForwardStatus == .connected {
                    logInfo("Restarting proxy for \(state.config.name)...", source: "monitor")
                    state.proxyStatus = .connecting
                    state.proxyTask = Task {
                        await runProxy(for: state, config: state.config)
                    }
                    continue
                }

                // If proxy supposed to be connected but not working
                let proxyWorking = await processManager.isPortOpen(port: proxyPort)
                if state.proxyStatus == .connected && !proxyWorking {
                    logWarning("Proxy port \(String(proxyPort)) not responding, restarting proxy for \(state.config.name)...", source: "monitor")
                    state.proxyStatus = .error
                    state.lastError = "Proxy connection lost"
                    NotificationManager.shared.connectionError(name: state.config.name, error: "Proxy disconnected")
                    if state.portForwardStatus == .connected {
                        state.proxyStatus = .connecting
                        state.proxyTask = Task {
                            await runProxy(for: state, config: state.config)
                        }
                    }
                }
            }
        }
    }

    /// Connection check for direct exec mode
    /// In this mode there's no kubectl port-forward, only socat proxy
    private func checkDirectExecConnection(_ state: ConnectionState) async {
        guard state.config.proxyPort != nil else { return }

        // Wait while in connecting state, don't interfere
        if state.proxyStatus == .connecting {
            return
        }

        let proxyRunning = await processManager.isProcessRunning(for: state.id, type: .proxy)
        let hasError = await processManager.hasRecentError(for: state.id)

        // Reconnect if in disconnected or error state
        if state.proxyStatus == .disconnected || state.proxyStatus == .error {
            logInfo("Auto-reconnecting (direct exec) \(state.config.name)...", source: "monitor")
            await processManager.clearError(for: state.id)
            startConnection(state.id)
            return
        }

        // Restart if there's an error
        if state.proxyStatus == .connected && hasError {
            logWarning("Error detected for \(state.config.name), reconnecting...", source: "monitor")
            state.lastError = "Proxy error"
            NotificationManager.shared.connectionDisconnected(name: state.config.name)
            state.portForwardStatus = .disconnected
            state.proxyStatus = .disconnected
            await processManager.killProcesses(for: state.id)
            await processManager.clearError(for: state.id)
            startConnection(state.id)
            return
        }

        // Restart if process died
        if state.proxyStatus == .connected && !proxyRunning {
            logWarning("Proxy process died for \(state.config.name), reconnecting...", source: "monitor")
            state.lastError = "Proxy terminated"
            NotificationManager.shared.connectionDisconnected(name: state.config.name)
            state.portForwardStatus = .disconnected
            state.proxyStatus = .disconnected
            startConnection(state.id)
            return
        }
    }
}
