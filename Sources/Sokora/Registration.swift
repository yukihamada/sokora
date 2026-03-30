import Foundation
import Logging

actor NodeRegistration {
    let config: SokoraConfig
    let logger: Logger
    let nodeId: String
    private var registrationTask: Task<Void, Never>?

    init(config: SokoraConfig, logger: Logger) {
        self.config = config
        self.logger = logger
        self.nodeId = Self.machineId()
    }

    // MARK: - Machine ID

    static func machineId() -> String {
        // Use ioreg to read the IOPlatformSerialNumber
        let task = Process()
        task.launchPath = "/usr/sbin/ioreg"
        task.arguments = ["-rd1", "-c", "IOPlatformExpertDevice"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // suppress stderr
        do {
            try task.run()
        } catch {
            return "sokora-\(UUID().uuidString.prefix(8))"
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Pattern: "IOPlatformSerialNumber" = "XXXXXXXXXX"
        let pattern = #"\"IOPlatformSerialNumber\"\s*=\s*\"([^\"]+)\""#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let range = Range(match.range(at: 1), in: output) {
            return "sokora-\(String(output[range]))"
        }

        return "sokora-\(UUID().uuidString.prefix(8))"
    }

    // MARK: - Registration Loop

    func startRegistrationLoop(ramGB: Double, models: [String]) {
        registrationTask?.cancel()
        registrationTask = Task {
            while !Task.isCancelled {
                await register(ramGB: ramGB, models: models)
                // Re-register every 4 minutes (server evicts after 90 min idle)
                do {
                    try await Task.sleep(for: .seconds(240))
                } catch {
                    break // Task cancelled
                }
            }
        }
    }

    func stopRegistrationLoop() {
        registrationTask?.cancel()
        registrationTask = nil
    }

    // MARK: - Single Registration

    func register(ramGB: Double, models: [String]) async {
        guard config.registerOnStart else { return }
        let tunnelURL = config.tunnelURL ?? "http://\(config.host):\(config.port)"

        let payload = SokoraRegisterRequest(
            nodeId: nodeId,
            tunnelUrl: tunnelURL,
            ramGb: ramGB,
            modelsJson: models,
            version: "1.0.0-swift"
        )

        guard let url = URL(string: "\(config.chatweb)/api/v1/sokora/register") else {
            logger.warning("Invalid chatweb URL: \(config.chatweb)")
            return
        }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else {
            logger.warning("Failed to encode registration payload")
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = data
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 200 || http.statusCode == 201 {
                    logger.info("Registered with chatweb.ai: node=\(nodeId) tunnel=\(tunnelURL)")
                } else {
                    logger.warning("Registration returned HTTP \(http.statusCode)")
                }
            }
        } catch {
            logger.warning("Registration failed: \(error.localizedDescription)")
        }
    }
}
