import SwiftUI

struct SettingsView: View {
    @Bindable var manager: ConnectionManager

    var body: some View {
        TabView {
            ConnectionsTab(manager: manager)
                .tabItem {
                    Label("Connections", systemImage: "point.3.connected.trianglepath.dotted")
                }

            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            LogsTab()
                .tabItem {
                    Label("Logs", systemImage: "doc.text")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 900, height: 650)
    }
}

// MARK: - Connections Tab

struct ConnectionsTab: View {
    @Bindable var manager: ConnectionManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(manager.connections) { connection in
                    ConnectionCard(connection: connection, manager: manager)
                }

                AddConnectionButton(manager: manager)
            }
            .padding(20)
        }
    }
}

struct ConnectionCard: View {
    let connection: ConnectionState
    @Bindable var manager: ConnectionManager
    @State private var isExpanded = false

    private var statusColor: Color {
        if connection.portForwardStatus == .error || connection.proxyStatus == .error {
            return .red
        } else if connection.isFullyConnected {
            return .green
        } else if connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting {
            return .orange
        } else {
            return .gray.opacity(0.4)
        }
    }

    private var statusText: String {
        if connection.portForwardStatus == .error || connection.proxyStatus == .error {
            return "Error"
        } else if connection.isFullyConnected {
            return "Connected"
        } else if connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting {
            return "Connecting..."
        } else {
            return "Disconnected"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                Text(connection.config.name)
                    .fontWeight(.medium)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text("\(connection.config.namespace)/\(connection.config.service)")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .lineLimit(1)

                Spacer()

                // Status badge
                Text(statusText)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)

                Button {
                    manager.removeConnection(connection.id)
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                ConnectionEditForm(connection: connection, manager: manager)
                    .padding(12)
            }
        }
        .background(statusColor.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor.opacity(0.3), lineWidth: 1)
        )
    }
}

struct ConnectionEditForm: View {
    let connection: ConnectionState
    @Bindable var manager: ConnectionManager

    @State private var name: String
    @State private var namespace: String
    @State private var service: String
    @State private var localPort: Int
    @State private var remotePort: Int
    @State private var proxyEnabled: Bool
    @State private var proxyPort: Int
    @State private var isEnabled: Bool
    @State private var autoReconnect: Bool
    @State private var useDirectExec: Bool

    init(connection: ConnectionState, manager: ConnectionManager) {
        self.connection = connection
        self.manager = manager
        _name = State(initialValue: connection.config.name)
        _namespace = State(initialValue: connection.config.namespace)
        _service = State(initialValue: connection.config.service)
        _localPort = State(initialValue: connection.config.localPort)
        _remotePort = State(initialValue: connection.config.remotePort)
        _proxyEnabled = State(initialValue: connection.config.proxyPort != nil)
        _proxyPort = State(initialValue: connection.config.proxyPort ?? connection.config.localPort - 1)
        _isEnabled = State(initialValue: connection.config.isEnabled)
        _autoReconnect = State(initialValue: connection.config.autoReconnect)
        _useDirectExec = State(initialValue: connection.config.useDirectExec)
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Name").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                TextField("", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                    .onChange(of: name) { save() }
            }

            GridRow {
                Text("Namespace").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                TextField("", text: $namespace)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                    .onChange(of: namespace) { save() }
            }

            GridRow {
                Text("Service").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                TextField("", text: $service)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                    .onChange(of: service) { save() }
            }

            GridRow {
                Text("Ports").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                HStack(spacing: 8) {
                    TextField("", value: $localPort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .onChange(of: localPort) { save() }
                    Text("→").foregroundStyle(.tertiary)
                    TextField("", value: $remotePort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .onChange(of: remotePort) { save() }
                }
            }

            GridRow {
                Text("Proxy").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                HStack(spacing: 12) {
                    Toggle("", isOn: $proxyEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: proxyEnabled) { save() }

                    if proxyEnabled {
                        TextField("", value: $proxyPort, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .onChange(of: proxyPort) { save() }

                        Toggle("Multi-conn", isOn: $useDirectExec)
                            .toggleStyle(.checkbox)
                            .onChange(of: useDirectExec) { save() }
                            .help("Multiple simultaneous connections (kubectl exec + netcat)")
                    }
                }
            }

            GridRow {
                Text("Options").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                HStack(spacing: 16) {
                    Toggle("Enabled", isOn: $isEnabled)
                        .onChange(of: isEnabled) { save() }
                    Toggle("Auto Reconnect", isOn: $autoReconnect)
                        .onChange(of: autoReconnect) { save() }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private func save() {
        var config = connection.config
        config.name = name
        config.namespace = namespace
        config.service = service
        config.localPort = localPort
        config.remotePort = remotePort
        config.proxyPort = proxyEnabled ? proxyPort : nil
        config.isEnabled = isEnabled
        config.autoReconnect = autoReconnect
        config.useDirectExec = useDirectExec
        manager.updateConnection(config)
    }
}

struct AddConnectionButton: View {
    @Bindable var manager: ConnectionManager
    @State private var discoveryManager: KubernetesDiscoveryManager?

    var body: some View {
        HStack(spacing: 16) {
            // Manual add button
            Button {
                let config = ConnectionConfig(
                    name: "New Connection",
                    namespace: "default",
                    service: "service-name",
                    localPort: 8080,
                    remotePort: 80
                )
                manager.addConnection(config)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Connection")
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            // Import from Kubernetes button
            Button {
                let dm = KubernetesDiscoveryManager(processManager: manager.processManager)
                Task { await dm.loadNamespaces() }
                discoveryManager = dm
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import from Kubernetes")
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
        .sheet(item: $discoveryManager) { dm in
            ServiceBrowserView(
                discoveryManager: dm,
                onServiceSelected: { config in
                    manager.addConnection(config)
                    discoveryManager = nil
                },
                onCancel: {
                    discoveryManager = nil
                }
            )
        }
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @AppStorage("autoStartConnections") private var autoStartConnections = true
    @AppStorage("showNotifications") private var showNotifications = true
    @State private var launchAtLogin = LaunchAtLoginManager.shared.isEnabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLoginManager.shared.isEnabled = newValue
                    }
                Toggle("Auto-start Connections", isOn: $autoStartConnections)
            }

            Section("Notifications") {
                Toggle("Show Notifications", isOn: $showNotifications)
                    .onChange(of: showNotifications) { _, newValue in
                        if newValue {
                            NotificationManager.shared.requestPermission()
                        }
                    }
            }

            Section("Dependencies") {
                LabeledContent("kubectl") {
                    DependencyStatus(
                        isInstalled: FileManager.default.fileExists(atPath: "/usr/local/bin/kubectl"),
                        package: "kubernetes-cli"
                    )
                }

                LabeledContent("socat") {
                    DependencyStatus(
                        isInstalled: FileManager.default.fileExists(atPath: "/opt/homebrew/bin/socat"),
                        package: "socat"
                    )
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

struct DependencyStatus: View {
    let isInstalled: Bool
    let package: String
    @State private var isInstalling = false

    var body: some View {
        HStack(spacing: 6) {
            if isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Installed")
                    .foregroundStyle(.secondary)
            } else {
                if isInstalling {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Install") {
                        install()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func install() {
        isInstalling = true
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
            process.arguments = ["install", package]
            try? process.run()
            process.waitUntilExit()
            await MainActor.run { isInstalling = false }
        }
    }
}

// MARK: - Logs Tab

struct LogsTab: View {
    private var logManager = LogManager.shared
    @State private var filterLevel: LogEntry.LogLevel?
    @State private var searchText = ""
    @State private var copied = false

    var filteredLogs: [LogEntry] {
        logManager.logs.filter { entry in
            let matchesLevel = filterLevel == nil || entry.level == filterLevel
            let matchesSearch = searchText.isEmpty ||
                entry.message.localizedCaseInsensitiveContains(searchText) ||
                entry.source.localizedCaseInsensitiveContains(searchText)
            return matchesLevel && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar - always at top
            HStack(spacing: 8) {
                Picker("Level", selection: $filterLevel) {
                    Text("All").tag(nil as LogEntry.LogLevel?)
                    Text("Errors").tag(LogEntry.LogLevel.error as LogEntry.LogLevel?)
                    Text("Info").tag(LogEntry.LogLevel.info as LogEntry.LogLevel?)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)

                Spacer()

                Button {
                    copyAllLogs()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied!" : "Copy All")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(logManager.logs.isEmpty)

                Button {
                    logManager.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Log content - fills remaining space
            if filteredLogs.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No Logs")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Logs will appear here when connections are started")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filteredLogs) { entry in
                            LogRow(entry: entry)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func copyAllLogs() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var md = "## Port Forwarder Logs\n\n"
        md += "Generated: \(dateFormatter.string(from: Date()))\n\n"

        if logManager.logs.isEmpty {
            md += "_No logs_\n"
        } else {
            md += "```\n"
            for entry in logManager.logs {
                let time = dateFormatter.string(from: entry.timestamp)
                md += "[\(time)] [\(entry.level.rawValue)] [\(entry.source)] \(entry.message)\n"
            }
            md += "```\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)

        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

struct LogRow: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Timestamp
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 55, alignment: .leading)

            // Level indicator
            Circle()
                .fill(levelColor)
                .frame(width: 6, height: 6)
                .padding(.top, 4)

            // Source
            Text(entry.source)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .leading)

            // Message
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(entry.level == .error ? .red : .primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(entry.level == .error ? Color.red.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var levelColor: Color {
        switch entry.level {
        case .info: .blue
        case .warning: .orange
        case .error: .red
        case .debug: .gray
        }
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Port Forwarder")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Version 1.0.0")
                .foregroundStyle(.secondary)

            Text("Kubernetes port-forward & socat proxy manager")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Link(destination: URL(string: "https://github.com")!) {
                Label("View on GitHub", systemImage: "link")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
