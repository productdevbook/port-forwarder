import SwiftUI

struct ServiceBrowserView: View {
    @Bindable var discoveryManager: KubernetesDiscoveryManager
    let onServiceSelected: (ConnectionConfig) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Import from Kubernetes")
                    .font(.headline)
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content - 3 panel layout
            HStack(spacing: 0) {
                // Namespace List (left panel)
                NamespaceListView(
                    namespaces: discoveryManager.namespaces,
                    selectedNamespace: discoveryManager.selectedNamespace,
                    state: discoveryManager.namespaceState,
                    onSelect: { namespace in
                        Task { await discoveryManager.selectNamespace(namespace) }
                    },
                    onRefresh: {
                        Task { await discoveryManager.loadNamespaces() }
                    }
                )
                .frame(width: 180)

                Divider()

                // Service List (middle panel)
                ServiceListView(
                    services: discoveryManager.services,
                    selectedService: discoveryManager.selectedService,
                    state: discoveryManager.serviceState,
                    onSelect: { service in
                        discoveryManager.selectService(service)
                    }
                )
                .frame(minWidth: 180)

                Divider()

                // Port Selection (right panel)
                if let service = discoveryManager.selectedService {
                    ServiceDetailView(
                        service: service,
                        selectedPort: discoveryManager.selectedPort,
                        proxyEnabled: $discoveryManager.proxyEnabled,
                        suggestedLocalPort: discoveryManager.suggestLocalPort(for: discoveryManager.selectedPort?.port ?? 0),
                        onPortSelect: { port in
                            discoveryManager.selectPort(port)
                        }
                    )
                    .frame(width: 200)
                } else {
                    EmptySelectionView()
                        .frame(width: 200)
                }
            }

            Divider()

            // Footer with action buttons
            HStack {
                if case .error(let message) = discoveryManager.namespaceState {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    if let config = discoveryManager.createConnectionConfig() {
                        onServiceSelected(config)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(discoveryManager.selectedPort == nil)
            }
            .padding()
        }
        .frame(width: 800, height: 500)
        .task {
            if discoveryManager.namespaceState == .idle {
                await discoveryManager.loadNamespaces()
            }
        }
    }
}

// MARK: - Namespace List

private struct NamespaceListView: View {
    let namespaces: [KubernetesNamespace]
    let selectedNamespace: KubernetesNamespace?
    let state: DiscoveryState
    let onSelect: (KubernetesNamespace) -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Namespaces")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(state == .loading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // Content
            Group {
                switch state {
                case .loading:
                    VStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                case .error(let message):
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                        Button("Retry") {
                            onRefresh()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer()
                    }

                case .idle, .loaded:
                    if namespaces.isEmpty && state == .loaded {
                        VStack {
                            Spacer()
                            Text("No namespaces")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(namespaces) { namespace in
                                    NamespaceRow(
                                        namespace: namespace,
                                        isSelected: selectedNamespace?.id == namespace.id,
                                        onSelect: onSelect
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.02))
    }
}

private struct NamespaceRow: View {
    let namespace: KubernetesNamespace
    let isSelected: Bool
    let onSelect: (KubernetesNamespace) -> Void

    var body: some View {
        Button {
            onSelect(namespace)
        } label: {
            HStack {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(namespace.name)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Service List

private struct ServiceListView: View {
    let services: [KubernetesService]
    let selectedService: KubernetesService?
    let state: DiscoveryState
    let onSelect: (KubernetesService) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Services")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !services.isEmpty {
                    Text("\(services.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // Content
            Group {
                switch state {
                case .loading:
                    VStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading services...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                case .error(let message):
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                        Spacer()
                    }

                case .idle:
                    VStack {
                        Spacer()
                        Image(systemName: "arrow.left")
                            .foregroundStyle(.tertiary)
                        Text("Select a namespace")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }

                case .loaded:
                    if services.isEmpty {
                        VStack {
                            Spacer()
                            Text("No services found")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(services) { service in
                                    ServiceRow(
                                        service: service,
                                        isSelected: selectedService?.id == service.id,
                                        onSelect: onSelect
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.02))
    }
}

private struct ServiceRow: View {
    let service: KubernetesService
    let isSelected: Bool
    let onSelect: (KubernetesService) -> Void

    var body: some View {
        Button {
            onSelect(service)
        } label: {
            HStack {
                Image(systemName: "server.rack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(service.type)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("\(service.ports.count) port\(service.ports.count != 1 ? "s" : "")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Service Detail

private struct ServiceDetailView: View {
    let service: KubernetesService
    let selectedPort: KubernetesService.ServicePort?
    @Binding var proxyEnabled: Bool
    let suggestedLocalPort: Int
    let onPortSelect: (KubernetesService.ServicePort) -> Void

    private var suggestedProxyPort: Int {
        suggestedLocalPort - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Service Details")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Service Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.name)
                            .font(.headline)
                        HStack(spacing: 6) {
                            Text(service.type)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            if let ip = service.clusterIP, ip != "None" {
                                Text(ip)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    // Port Selection
                    Text("Select Port")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if service.ports.isEmpty {
                        Text("No ports defined")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(service.ports) { port in
                            PortSelectionRow(
                                port: port,
                                isSelected: selectedPort?.id == port.id,
                                onSelect: { onPortSelect(port) }
                            )
                        }
                    }

                    // Port Configuration
                    if selectedPort != nil {
                        Divider()

                        Text("Port Configuration")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Local port:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(suggestedLocalPort))
                                    .font(.system(.caption, design: .monospaced, weight: .medium))
                            }

                            Toggle("Enable Proxy (socat)", isOn: $proxyEnabled)
                                .toggleStyle(.checkbox)

                            if proxyEnabled {
                                HStack {
                                    Text("Proxy port:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(String(suggestedProxyPort))
                                        .font(.system(.caption, design: .monospaced, weight: .medium))
                                }
                            }

                            Divider()

                            HStack {
                                Text("Connect to:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("localhost:" + String(proxyEnabled ? suggestedProxyPort : suggestedLocalPort))
                                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    Spacer()
                }
                .padding(10)
            }
        }
        .background(Color.primary.opacity(0.02))
    }
}

private struct PortSelectionRow: View {
    let port: KubernetesService.ServicePort
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(String(port.port))
                            .font(.system(.body, design: .monospaced, weight: .medium))
                        if let name = port.name, !name.isEmpty {
                            Text("(\(name))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let proto = port.protocol {
                        Text(proto)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty Selection View

private struct EmptySelectionView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Service Details")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            VStack {
                Spacer()
                Image(systemName: "arrow.left")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("Select a service")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .background(Color.primary.opacity(0.02))
    }
}
