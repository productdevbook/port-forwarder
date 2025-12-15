import Foundation
import Darwin

enum ProcessType: String {
    case portForward = "kubectl"
    case proxy = "socat"
}

enum KubectlError: Error, LocalizedError {
    case kubectlNotFound
    case executionFailed(String)
    case parsingFailed(String)
    case clusterNotConnected

    var errorDescription: String? {
        switch self {
        case .kubectlNotFound:
            return "kubectl not found. Please install kubernetes-cli."
        case .executionFailed(let message):
            return "kubectl failed: \(message)"
        case .parsingFailed(let message):
            return "Failed to parse response: \(message)"
        case .clusterNotConnected:
            return "Cannot connect to Kubernetes cluster. Check your kubectl configuration."
        }
    }
}

actor ProcessManager {
    private var processes: [UUID: [ProcessType: Process]] = [:]
    private var outputTasks: [UUID: [ProcessType: Task<Void, Never>]] = [:]
    private var connectionErrors: [UUID: Date] = [:]  // Track when errors occurred

    func startPortForward(
        id: UUID,
        namespace: String,
        service: String,
        localPort: Int,
        remotePort: Int
    ) async throws -> Process {
        let command = "kubectl port-forward -n \(namespace) svc/\(service) \(localPort):\(remotePort)"
        logInfo("Starting: \(command)", source: "kubectl")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/kubectl")
        process.arguments = [
            "port-forward",
            "-n", namespace,
            "svc/\(service)",
            "\(localPort):\(remotePort)",
            "--address=127.0.0.1"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            logInfo("Process started (PID: \(process.processIdentifier))", source: "kubectl")
        } catch {
            logError("Failed to start: \(error.localizedDescription)", source: "kubectl")
            throw error
        }

        if processes[id] == nil {
            processes[id] = [:]
        }
        processes[id]?[.portForward] = process

        startReadingOutput(pipe: pipe, id: id, type: .portForward)

        return process
    }

    /// Multi-connection proxy: socat spawns new kubectl port-forward for each connection
    /// This mode enables true simultaneous connections - each connection gets its own kubectl
    func startDirectExecProxy(
        id: UUID,
        namespace: String,
        service: String,
        externalPort: Int,
        remotePort: Int
    ) async throws -> Process {
        logInfo("Starting multi-conn proxy on port \(externalPort) → \(service):\(remotePort)", source: "socat")

        // Create wrapper script - runs for each connection
        // $$ = process ID, used for unique port calculation
        let wrapperScript = """
            #!/bin/bash
            # Calculate unique port (30000-60000 range)
            PORT=$((30000 + ($$ % 30000)))

            # Find another port if already in use
            while /usr/bin/nc -z 127.0.0.1 $PORT 2>/dev/null; do
                PORT=$((PORT + 1))
            done

            # Start kubectl port-forward (stdout/stderr disabled)
            /usr/local/bin/kubectl port-forward -n \(namespace) svc/\(service) $PORT:\(remotePort) --address=127.0.0.1 >/dev/null 2>&1 &
            KPID=$!

            # Cleanup trap
            trap "kill $KPID 2>/dev/null" EXIT

            # Wait for port to open (max 5 seconds)
            for i in 1 2 3 4 5 6 7 8 9 10; do
                if /usr/bin/nc -z 127.0.0.1 $PORT 2>/dev/null; then
                    break
                fi
                sleep 0.5
            done

            # Connect stdin/stdout to TCP using socat
            /opt/homebrew/bin/socat - TCP:127.0.0.1:$PORT
            """

        // Write script to temporary file
        let scriptPath = "/tmp/pf-wrapper-\(id.uuidString).sh"
        try wrapperScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        // Make executable
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", scriptPath]
        try chmod.run()
        chmod.waitUntilExit()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/socat")
        process.arguments = [
            "TCP-LISTEN:\(externalPort),fork,reuseaddr",
            "EXEC:\(scriptPath)"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            logInfo("Multi-conn proxy started (PID: \(process.processIdentifier))", source: "socat")
        } catch {
            logError("Failed to start multi-conn proxy: \(error.localizedDescription)", source: "socat")
            throw error
        }

        if processes[id] == nil {
            processes[id] = [:]
        }
        processes[id]?[.proxy] = process

        startReadingOutput(pipe: pipe, id: id, type: .proxy)

        return process
    }

    /// Standard proxy mode: socat connects to already-running kubectl port-forward
    /// Note: This mode supports single connection only, use startDirectExecProxy for multiple connections
    func startProxy(
        id: UUID,
        externalPort: Int,
        internalPort: Int
    ) async throws -> Process {
        let command = "socat TCP-LISTEN:\(externalPort) TCP:127.0.0.1:\(internalPort)"
        logInfo("Starting: \(command)", source: "socat")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/socat")
        // fork: create child process for each connection (multiple simultaneous connections)
        // reuseaddr: allow immediate port reuse
        process.arguments = [
            "TCP-LISTEN:\(externalPort),fork,reuseaddr",
            "TCP:127.0.0.1:\(internalPort)"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            logInfo("Process started (PID: \(process.processIdentifier))", source: "socat")
        } catch {
            logError("Failed to start: \(error.localizedDescription)", source: "socat")
            throw error
        }

        if processes[id] == nil {
            processes[id] = [:]
        }
        processes[id]?[.proxy] = process

        startReadingOutput(pipe: pipe, id: id, type: .proxy)

        return process
    }

    private func startReadingOutput(pipe: Pipe, id: UUID, type: ProcessType) {
        let task = Task { [weak self] in
            let handle = pipe.fileHandleForReading

            while true {
                let data = handle.availableData
                if data.isEmpty { break }

                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines where !line.isEmpty {
                        let lowercased = line.lowercased()
                        // kubectl port-forward error messages:
                        // - "error" - general errors
                        // - "failed" - failed operations
                        // - "unable to" - connection errors
                        // - "connection refused" - port not open
                        // - "lost connection" - kubectl v1.23+ bug: when first connection closes
                        // - "an error occurred" - kubectl general error format
                        let isError = lowercased.contains("error") ||
                                      lowercased.contains("failed") ||
                                      lowercased.contains("unable to") ||
                                      lowercased.contains("connection refused") ||
                                      lowercased.contains("lost connection") ||
                                      lowercased.contains("an error occurred")

                        if isError {
                            logError(line, source: type.rawValue)
                            // Mark this connection as having an error - triggers immediate reconnect
                            await self?.markConnectionError(id: id)
                        } else if lowercased.contains("warning") {
                            logWarning(line, source: type.rawValue)
                        } else {
                            logDebug(line, source: type.rawValue)
                        }
                    }
                }
            }
        }

        if outputTasks[id] == nil {
            outputTasks[id] = [:]
        }
        outputTasks[id]?[type] = task
    }

    private func markConnectionError(id: UUID) {
        connectionErrors[id] = Date()
    }

    func hasRecentError(for id: UUID, within seconds: TimeInterval = 10) -> Bool {
        guard let errorTime = connectionErrors[id] else { return false }
        return Date().timeIntervalSince(errorTime) < seconds
    }

    func clearError(for id: UUID) {
        connectionErrors.removeValue(forKey: id)
    }

    func killProcesses(for id: UUID) {
        // Cancel output reading tasks
        if let tasks = outputTasks[id] {
            for (_, task) in tasks {
                task.cancel()
            }
        }
        outputTasks[id] = nil

        // Kill processes
        guard let procs = processes[id] else { return }

        for (type, process) in procs {
            if process.isRunning {
                process.terminate()
                logInfo("Process terminated (PID: \(process.processIdentifier))", source: type.rawValue)
            }
        }
        processes[id] = nil

        // Cleanup temp wrapper script
        let scriptPath = "/tmp/pf-wrapper-\(id.uuidString).sh"
        try? FileManager.default.removeItem(atPath: scriptPath)
    }

    func isProcessRunning(for id: UUID, type: ProcessType) -> Bool {
        processes[id]?[type]?.isRunning ?? false
    }

    /// Check if a port is actually accepting connections (TCP health check)
    func isPortOpen(port: Int) -> Bool {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { Darwin.close(sock) }

        // Set a short timeout for the connection
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return result == 0
    }

    func killAllPortForwarderProcesses() async {
        logInfo("Killing all stuck processes...", source: "cleanup")

        // pkill -9 (SIGKILL) kubectl port-forward
        let pkillKubectl = Process()
        pkillKubectl.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkillKubectl.arguments = ["-9", "-f", "kubectl.*port-forward"]
        try? pkillKubectl.run()
        pkillKubectl.waitUntilExit()

        // pkill -9 (SIGKILL) socat TCP-LISTEN
        let pkillSocat = Process()
        pkillSocat.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkillSocat.arguments = ["-9", "-f", "socat.*TCP-LISTEN"]
        try? pkillSocat.run()
        pkillSocat.waitUntilExit()

        // Wait for ports to be freed
        try? await Task.sleep(for: .milliseconds(500))

        // Clear internal tracking
        processes.removeAll()
        for (_, tasks) in outputTasks {
            for (_, task) in tasks { task.cancel() }
        }
        outputTasks.removeAll()

        logInfo("All stuck processes killed", source: "cleanup")
    }

    // MARK: - Kubernetes Discovery

    func fetchNamespaces() async throws -> [KubernetesNamespace] {
        logInfo("Fetching namespaces...", source: "discovery")

        let output = try await executeKubectl(arguments: ["get", "namespaces", "-o", "json"])

        do {
            let response = try JSONDecoder().decode(
                KubernetesNamespace.ListResponse.self,
                from: Data(output.utf8)
            )
            let namespaces = KubernetesNamespace.from(response: response)
            logInfo("Found \(namespaces.count) namespaces", source: "discovery")
            return namespaces.sorted { $0.name < $1.name }
        } catch {
            logError("Failed to parse namespaces: \(error.localizedDescription)", source: "discovery")
            throw KubectlError.parsingFailed(error.localizedDescription)
        }
    }

    func fetchServices(namespace: String) async throws -> [KubernetesService] {
        logInfo("Fetching services in '\(namespace)'...", source: "discovery")

        let output = try await executeKubectl(arguments: ["get", "services", "-n", namespace, "-o", "json"])

        do {
            let response = try JSONDecoder().decode(
                KubernetesService.ListResponse.self,
                from: Data(output.utf8)
            )
            let services = KubernetesService.from(response: response)
            logInfo("Found \(services.count) services in '\(namespace)'", source: "discovery")
            return services.sorted { $0.name < $1.name }
        } catch {
            logError("Failed to parse services: \(error.localizedDescription)", source: "discovery")
            throw KubectlError.parsingFailed(error.localizedDescription)
        }
    }

    private func executeKubectl(arguments: [String]) async throws -> String {
        let kubectlPath = "/usr/local/bin/kubectl"

        guard FileManager.default.fileExists(atPath: kubectlPath) else {
            throw KubectlError.kubectlNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: kubectlPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                // Check for common connection errors
                if errorOutput.contains("Unable to connect") ||
                   errorOutput.contains("connection refused") ||
                   errorOutput.contains("no configuration") ||
                   errorOutput.contains("dial tcp") {
                    throw KubectlError.clusterNotConnected
                }
                throw KubectlError.executionFailed(errorOutput.isEmpty ? "Unknown error" : errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            return output
        } catch let error as KubectlError {
            throw error
        } catch {
            throw KubectlError.executionFailed(error.localizedDescription)
        }
    }
}
