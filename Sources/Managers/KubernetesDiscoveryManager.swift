import Foundation

enum DiscoveryState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

@Observable
@MainActor
final class KubernetesDiscoveryManager: Identifiable {
    let id = UUID()

    var namespaces: [KubernetesNamespace] = []
    var services: [KubernetesService] = []
    var selectedNamespace: KubernetesNamespace?
    var selectedService: KubernetesService?
    var selectedPort: KubernetesService.ServicePort?
    var proxyEnabled = true  // Default to enabled for socat proxy

    var namespaceState: DiscoveryState = .idle
    var serviceState: DiscoveryState = .idle

    private let processManager: ProcessManager

    init(processManager: ProcessManager) {
        self.processManager = processManager
    }

    // MARK: - Actions

    func loadNamespaces() async {
        namespaceState = .loading
        namespaces = []
        services = []
        selectedNamespace = nil
        selectedService = nil
        selectedPort = nil

        do {
            namespaces = try await processManager.fetchNamespaces()
            namespaceState = .loaded
        } catch {
            let message = (error as? KubectlError)?.errorDescription ?? error.localizedDescription
            namespaceState = .error(message)
            logError("Failed to load namespaces: \(message)", source: "discovery")
        }
    }

    func selectNamespace(_ namespace: KubernetesNamespace) async {
        selectedNamespace = namespace
        selectedService = nil
        selectedPort = nil
        services = []
        serviceState = .loading

        do {
            services = try await processManager.fetchServices(namespace: namespace.name)
            serviceState = .loaded
        } catch {
            let message = (error as? KubectlError)?.errorDescription ?? error.localizedDescription
            serviceState = .error(message)
            logError("Failed to load services: \(message)", source: "discovery")
        }
    }

    func selectService(_ service: KubernetesService) {
        selectedService = service
        // Auto-select first port if available
        selectedPort = service.ports.first
    }

    func selectPort(_ port: KubernetesService.ServicePort) {
        selectedPort = port
    }

    // MARK: - Connection Creation

    func createConnectionConfig() -> ConnectionConfig? {
        guard let namespace = selectedNamespace,
              let service = selectedService,
              let port = selectedPort else {
            return nil
        }

        let remotePort = port.port
        let localPort = suggestLocalPort(for: remotePort)
        let proxyPort = proxyEnabled ? suggestProxyPort(for: localPort) : nil

        return ConnectionConfig(
            name: service.name,
            namespace: namespace.name,
            service: service.name,
            localPort: localPort,
            remotePort: remotePort,
            proxyPort: proxyPort
        )
    }

    func suggestLocalPort(for remotePort: Int) -> Int {
        // Common port mappings - use same port if possible, otherwise map to higher port
        switch remotePort {
        case 80: return 8080
        case 443: return 8443
        default:
            // For other ports, use the same port if > 1024, otherwise add 8000
            return remotePort > 1024 ? remotePort : remotePort + 8000
        }
    }

    func suggestProxyPort(for localPort: Int) -> Int {
        // Proxy port is typically localPort - 1
        return localPort - 1
    }

    func reset() {
        namespaces = []
        services = []
        selectedNamespace = nil
        selectedService = nil
        selectedPort = nil
        namespaceState = .idle
        serviceState = .idle
    }
}
