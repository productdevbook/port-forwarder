import Foundation

struct Dependency: Sendable {
    let name: String
    let path: String
    let brewPackage: String
    let isRequired: Bool

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

actor DependencyChecker {
    static let shared = DependencyChecker()

    nonisolated let dependencies: [Dependency] = [
        Dependency(
            name: "kubectl",
            path: "/usr/local/bin/kubectl",
            brewPackage: "kubernetes-cli",
            isRequired: true
        ),
        Dependency(
            name: "socat",
            path: "/opt/homebrew/bin/socat",
            brewPackage: "socat",
            isRequired: false
        )
    ]

    nonisolated var missingRequired: [Dependency] {
        dependencies.filter { $0.isRequired && !$0.isInstalled }
    }

    nonisolated var missingOptional: [Dependency] {
        dependencies.filter { !$0.isRequired && !$0.isInstalled }
    }

    nonisolated var allRequiredInstalled: Bool {
        missingRequired.isEmpty
    }

    func checkAndInstallMissing() async -> (success: Bool, message: String) {
        let missing = dependencies.filter { !$0.isInstalled }

        guard !missing.isEmpty else {
            return (true, "All dependencies are installed")
        }

        let brewPath: String
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            brewPath = "/opt/homebrew/bin/brew"
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
            brewPath = "/usr/local/bin/brew"
        } else {
            return (false, "Homebrew is not installed. Please install it from https://brew.sh")
        }

        var results: [String] = []

        for dep in missing {
            let result = await installWithBrew(brewPath: brewPath, package: dep.brewPackage)
            results.append("\(dep.name): \(result.success ? "Installed" : "Failed - \(result.message)")")
        }

        let allSuccess = missing.allSatisfy(\.isInstalled)
        return (allSuccess, results.joined(separator: "\n"))
    }

    private func installWithBrew(brewPath: String, package: String) async -> (success: Bool, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = ["install", package]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return process.terminationStatus == 0 ? (true, "Installed") : (false, output)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
