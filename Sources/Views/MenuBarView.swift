import SwiftUI

struct MenuBarView: View {
    @Bindable var manager: ConnectionManager
    @State private var isInstallingDeps = false
    @State private var hoveredConnection: UUID?
    @Environment(\.openSettings) private var openSettings

    private let checker = DependencyChecker.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Dependency warning
            if !checker.allRequiredInstalled {
                DependencyWarningView(isInstalling: $isInstallingDeps)
                Divider()
            }

            // Connections
            connectionsList

            Divider()

            // Actions
            actionsBar

            Divider()

            // Footer
            footer
        }
        .frame(width: 280)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Port Forwarder", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.system(.headline, design: .rounded))

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(manager.allConnected ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
                Text(manager.allConnected ? "Active" : "Inactive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Connections List

    private var connectionsList: some View {
        VStack(spacing: 1) {
            ForEach(manager.connections) { connection in
                ConnectionRow(
                    manager: manager,
                    connection: connection,
                    isHovered: hoveredConnection == connection.id
                )
                .onHover { hovering in
                    hoveredConnection = hovering ? connection.id : nil
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Actions Bar

    private var actionsBar: some View {
        HStack(spacing: 0) {
            ActionBarButton(
                title: "Start",
                icon: "play.fill",
                color: .primary
            ) {
                manager.startAll()
            }
            .disabled(!checker.allRequiredInstalled)

            ActionBarButton(
                title: "Stop",
                icon: "stop.fill",
                color: .primary
            ) {
                manager.stopAll()
            }

            if manager.isKillingProcesses {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Killing...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            } else {
                ActionBarButton(
                    title: "Kill",
                    icon: "xmark.circle.fill",
                    color: .red
                ) {
                    Task { await manager.killStuckProcesses() }
                }
            }

            Spacer()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.windows.first { $0.title.contains("Settings") }?
                        .makeKeyAndOrderFront(nil)
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    private var footer: some View {
        Button {
            manager.stopAll()
            NSApplication.shared.terminate(nil)
        } label: {
            Text("Quit")
                .font(.system(.body, design: .default))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Connection Row

struct ConnectionRow: View {
    @Bindable var manager: ConnectionManager
    let connection: ConnectionState
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: connection.isFullyConnected ? .green.opacity(0.5) : .clear, radius: 3)

            // Connection info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(connection.config.name)
                        .font(.system(.subheadline, weight: .medium))

                    if !connection.config.isEnabled {
                        Text("OFF")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    PortLabel(
                        icon: "k",
                        port: connection.config.localPort,
                        status: connection.portForwardStatus
                    )

                    if let proxyPort = connection.config.proxyPort {
                        PortLabel(
                            icon: "s",
                            port: proxyPort,
                            status: connection.proxyStatus
                        )
                    }
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 4) {
                if connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting {
                    ProgressView()
                        .scaleEffect(0.45)
                        .frame(width: 22, height: 22)
                } else {
                    SmallActionButton(
                        icon: connection.isFullyConnected ? "stop.fill" : "play.fill"
                    ) {
                        if connection.isFullyConnected {
                            manager.stopConnection(connection.id)
                        } else {
                            manager.startConnection(connection.id)
                        }
                    }
                    .disabled(!connection.config.isEnabled)
                }

                SmallActionButton(icon: "arrow.clockwise") {
                    manager.restartConnection(connection.id)
                }
                .disabled(!connection.config.isEnabled)
            }
            .opacity(isHovered || connection.isFullyConnected ? 1 : 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        if connection.portForwardStatus == .error || connection.proxyStatus == .error {
            return .red
        } else if connection.isFullyConnected {
            return .green
        } else if connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting {
            return .yellow
        }
        return .secondary.opacity(0.3)
    }
}

// MARK: - Port Label

struct PortLabel: View {
    let icon: String
    let port: Int
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(statusColor)
            Text(verbatim: "\(port)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var iconName: String {
        switch icon {
        case "k": "helm"  // Kubernetes wheel
        case "s": "arrow.left.arrow.right"  // socat proxy
        default: "circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .connected: .green
        case .connecting: .yellow
        case .error: .red
        case .disconnected: .secondary.opacity(0.5)
        }
    }
}

// MARK: - Buttons

struct ActionBarButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color == .red ? .red : .primary)
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct SmallActionButton: View {
    let icon: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.3)
    }
}

// MARK: - Dependency Warning

struct DependencyWarningView: View {
    @Binding var isInstalling: Bool
    private let checker = DependencyChecker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Missing Dependencies", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(checker.dependencies.filter { !$0.isInstalled }, id: \.name) { dep in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(dep.isRequired ? Color.red : Color.orange)
                            .frame(width: 5, height: 5)
                        Text(dep.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                isInstalling = true
                Task {
                    _ = await checker.checkAndInstallMissing()
                    isInstalling = false
                }
            } label: {
                Group {
                    if isInstalling {
                        HStack(spacing: 4) {
                            ProgressView().scaleEffect(0.5)
                            Text("Installing...")
                        }
                    } else {
                        Label("Install", systemImage: "arrow.down.circle")
                    }
                }
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isInstalling)
        }
        .padding(12)
    }
}
