import ArgumentParser
import Foundation
import Logging
import Hummingbird

// MARK: - Root Command

@main
struct Sokora: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sokora",
        abstract: "Sokora — Apple Silicon LLM inference node (OpenAI-compatible API)",
        subcommands: [
            StartCommand.self,
            StopCommand.self,
            StatusCommand.self,
            InstallCommand.self
        ],
        defaultSubcommand: StartCommand.self
    )
}

// MARK: - Start

struct StartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start the Sokora inference server"
    )

    @Option(name: .long, help: "HuggingFace model ID (e.g. mlx-community/Qwen3-8B-4bit)")
    var model: String?

    @Option(name: .long, help: "TCP port to listen on (default: 5001)")
    var port: Int?

    @Option(name: .long, help: "Bind host (default: 127.0.0.1)")
    var host: String?

    @Option(name: [.customLong("kv-bits")], help: "KV cache quantization bits: 4 = TurboQuant LEAN, 0 = disabled")
    var kvBits: Int?

    @Option(name: [.customLong("cache-mode")], help: "KV cache strategy: standard | quantized | streaming | h2o")
    var cacheMode: String?

    @Option(name: [.customLong("max-tokens")], help: "Default max generation tokens (default: 2048)")
    var maxTokens: Int?

    @Option(name: .long, help: "Sampling temperature (default: 0.6)")
    var temperature: Double?

    @Option(name: [.customLong("top-p")], help: "Nucleus sampling top-p (default: 1.0)")
    var topP: Double?

    @Flag(name: [.customLong("no-register")], help: "Skip registration with chatweb.ai")
    var noRegister = false

    func run() async throws {
        var config = SokoraConfig.fromEnv()
        if let m = model        { config.model = m }
        if let p = port         { config.port = p }
        if let h = host         { config.host = h }
        if let b = kvBits       { config.kvBits = b == 0 ? nil : b }
        if let cm = cacheMode   { config.cacheMode = SokoraConfig.CacheMode(rawValue: cm) ?? config.cacheMode }
        if let mt = maxTokens   { config.maxTokens = mt }
        if let t = temperature  { config.temperature = t }
        if let tp = topP        { config.topP = tp }
        if noRegister           { config.registerOnStart = false }

        var logger = Logger(label: "sokora")
        logger.logLevel = .info

        logger.info("""
            Sokora starting
              model      : \(config.model)
              port       : \(config.port)
              host       : \(config.host)
              cache_mode : \(config.cacheMode.rawValue)
              kv_bits    : \(config.kvBits.map(String.init) ?? "off")
              max_tokens : \(config.maxTokens)
              temperature: \(config.temperature)
              top_p      : \(config.topP)
              register   : \(config.registerOnStart)
            """)

        // Load model — fallback to Python mlx_lm if model type unsupported
        let manager = ModelManager(config: config, logger: logger)
        do {
            try await manager.load()
        } catch {
            let msg = String(describing: error)
            if msg.contains("unsupported") || msg.contains("Unsupported") ||
               msg.contains("keyNotFound") || msg.contains("typeMismatch") ||
               msg.contains("valueNotFound") || msg.contains("dataCorrupted") ||
               msg.contains("Offline mode") || msg.contains("Metadata not available") ||
               msg.contains("config.json") || msg.contains("couldn't be opened") {
                logger.warning("[sokora] Swift MLX cannot load '\(config.model)': \(msg)")
                logger.warning("[sokora] Falling back to Python mlx_lm.server")
                try launchPythonFallback(config: config, logger: logger)
                // launchPythonFallback blocks until the Python server exits
                return
            }
            throw error
        }

        // RAM detection
        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        logger.info("System RAM: \(String(format: "%.1f", ramGB)) GB")

        // Node registration with chatweb.ai
        let registration = NodeRegistration(config: config, logger: logger)
        if config.registerOnStart {
            await registration.startRegistrationLoop(ramGB: ramGB, models: [config.model])
        }

        // Start HTTP server (blocks until shutdown signal)
        try await runServer(config: config, modelManager: manager, logger: logger)
    }
}

// MARK: - Stop

struct StopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop a running Sokora server"
    )

    func run() async throws {
        let task = Process()
        task.launchPath = "/usr/bin/pkill"
        task.arguments = ["-f", "sokora start"]
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                print("Sokora stopped.")
            } else {
                print("No running Sokora process found.")
            }
        } catch {
            print("Failed to stop Sokora: \(error.localizedDescription)")
        }
    }
}

// MARK: - Status

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check if Sokora is running"
    )

    @Option(name: .long, help: "Port to check (default: 5001)")
    var port: Int = 5001

    @Option(name: .long, help: "Host to check (default: 127.0.0.1)")
    var host: String = "127.0.0.1"

    func run() async throws {
        guard let url = URL(string: "http://\(host):\(port)/health") else {
            print("Invalid host/port combination.")
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("Running: \(body)")
            } else {
                print("Unexpected response from \(url)")
            }
        } catch {
            print("Not running on \(host):\(port) — \(error.localizedDescription)")
        }
    }
}

// MARK: - Install LaunchAgent

struct InstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install a macOS LaunchAgent so Sokora auto-starts on login"
    )

    @Option(name: .long, help: "Model ID")
    var model: String = "mlx-community/Qwen3-8B-4bit"

    @Option(name: .long, help: "Port")
    var port: Int = 5001

    @Option(name: [.customLong("cache-mode")], help: "Cache mode: standard|quantized|streaming|h2o")
    var cacheMode: String = "quantized"

    @Option(name: [.customLong("kv-bits")], help: "KV bits (4 or 0 to disable)")
    var kvBits: Int = 4

    @Flag(name: [.customLong("uninstall")], help: "Uninstall the LaunchAgent instead")
    var uninstall = false

    func run() async throws {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let plistPath = homeDir + "/Library/LaunchAgents/io.sokora.node.plist"
        let logDir = homeDir + "/sokora/logs"

        if uninstall {
            let unload = Process()
            unload.launchPath = "/bin/launchctl"
            unload.arguments = ["unload", "-w", plistPath]
            try? unload.run()
            unload.waitUntilExit()
            try? FileManager.default.removeItem(atPath: plistPath)
            print("LaunchAgent uninstalled.")
            return
        }

        // Resolve binary path
        let sokoraPath = CommandLine.arguments[0]

        // Create log directory
        try FileManager.default.createDirectory(
            atPath: logDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        var programArgs = [sokoraPath, "start", "--model", model, "--port", "\(port)", "--cache-mode", cacheMode]
        if kvBits == 0 { programArgs += ["--kv-bits", "0"] }
        else           { programArgs += ["--kv-bits", "\(kvBits)"] }

        let argsXML = programArgs.map { "        <string>\($0)</string>" }.joined(separator: "\n")

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>io.sokora.node</string>
            <key>ProgramArguments</key>
            <array>
        \(argsXML)
            </array>
            <key>EnvironmentVariables</key>
            <dict>
                <key>PATH</key>
                <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
            </dict>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>ThrottleInterval</key>
            <integer>60</integer>
            <key>StandardOutPath</key>
            <string>\(logDir)/sokora.log</string>
            <key>StandardErrorPath</key>
            <string>\(logDir)/sokora.err</string>
        </dict>
        </plist>
        """

        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)

        // Unload any existing version first (ignore errors)
        let unload = Process()
        unload.launchPath = "/bin/launchctl"
        unload.arguments = ["unload", plistPath]
        try? unload.run()
        unload.waitUntilExit()

        // Load the new plist
        let load = Process()
        load.launchPath = "/bin/launchctl"
        load.arguments = ["load", "-w", plistPath]
        try load.run()
        load.waitUntilExit()

        if load.terminationStatus == 0 {
            print("LaunchAgent installed and started.")
            print("  Plist : \(plistPath)")
            print("  Model : \(model)")
            print("  Port  : \(port)")
            print("  Cache : \(cacheMode) (kv-bits=\(kvBits))")
            print("  Logs  : \(logDir)/sokora.log")
            print("")
            print("To uninstall: sokora install --uninstall")
        } else {
            print("LaunchAgent installed but launchctl load returned status \(load.terminationStatus).")
            print("You can load it manually: launchctl load -w \(plistPath)")
        }
    }
}

// MARK: - Python mlx_lm fallback

/// Launch `python3 -m mlx_lm.server` as a subprocess and block until it exits.
/// Used when the model type is not supported by mlx-swift-examples.
func launchPythonFallback(config: SokoraConfig, logger: Logger) throws {
    // Find python3
    // Find python3 that has mlx_lm installed
    let pythonCandidates = [
        "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11",
        "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
        "/usr/local/bin/python3.11",
        "/usr/local/bin/python3",
        "/opt/homebrew/bin/python3.11",
        "/opt/homebrew/bin/python3",
        "/usr/bin/python3",
    ]
    let python = pythonCandidates.first {
        FileManager.default.isExecutableFile(atPath: $0)
    } ?? "/usr/bin/python3"

    // Use `python -m mlx_lm server` (newer API; mlx_lm.server is deprecated)
    let args: [String] = ["-m", "mlx_lm", "server",
        "--model", config.model,
        "--port", "\(config.port)",
        "--host", config.host,
    ]
    // Note: --kv-bits is Swift-only; Python mlx_lm server uses different flags

    logger.info("[sokora] Launching: \(python) \(args.joined(separator: " "))")

    let proc = Process()
    proc.launchPath = python
    proc.arguments = args
    proc.standardOutput = FileHandle.standardOutput
    proc.standardError = FileHandle.standardError

    try proc.run()
    proc.waitUntilExit()
    logger.info("[sokora] Python fallback exited with status \(proc.terminationStatus)")
}
