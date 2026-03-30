import AppKit

@MainActor
class MenubarController {
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    private let ports: [(port: Int, name: String, desc: String)] = [
        (5000, "LLM 122B", "Sonnet"),
        (5001, "LLM 35B",  "Haiku"),
        (5002, "Vision",   "画像理解"),
        (4001, "Proxy",    "API変換"),
    ]

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "AI"
        statusItem.button?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        buildMenu()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatus() }
        }
        updateStatus()
    }

    // MARK: - Menu

    func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Header
        let header = NSMenuItem(title: "LOCAL AI", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(string: "LOCAL AI", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.systemBlue
        ])
        menu.addItem(header)

        // Service status rows
        for entry in ports {
            let item = NSMenuItem(title: "  ○ \(entry.name) — \(entry.desc)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.tag = entry.port
            menu.addItem(item)
        }

        // DePIN status row
        let depinItem = NSMenuItem(title: "  ○ DePIN — Solana節点", action: nil, keyEquivalent: "")
        depinItem.isEnabled = false
        depinItem.tag = 9999
        menu.addItem(depinItem)

        let ram = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        let ramItem = NSMenuItem(title: "  RAM: \(ram)GB", action: nil, keyEquivalent: "")
        ramItem.isEnabled = false
        menu.addItem(ramItem)

        menu.addItem(.separator())

        // === Control ===
        addHeader(menu, "Control")
        addItem(menu, "  ▶ Start All",              #selector(startAll),   "s")
        addItem(menu, "  ■ Stop All",               #selector(stopAll),    "x")
        addItem(menu, "  ↻ Restart",                #selector(restartAll), "r")
        addItem(menu, "  ✓ Health Check (auto-fix)", #selector(healthCheck),"h")

        menu.addItem(.separator())

        // === Launch ===
        addHeader(menu, "Launch")
        addItem(menu, "  Claude Code (local)",  #selector(launchCld),     "c")
        addItem(menu, "  Claude Code (cloud)",  #selector(launchClc),     "")
        addItem(menu, "  Aider (local)",        #selector(launchAider),   "")
        addItem(menu, "  Terminal",             #selector(openTerminal),  "t")
        addItem(menu, "  Dashboard",            #selector(openDashboard), "d")

        menu.addItem(.separator())

        // === Generate ===
        addHeader(menu, "Generate")
        addItem(menu, "  Image (FLUX, ~17s)...",    #selector(genImage), "i")
        addItem(menu, "  Video (Wan 2.1, ~10min)...", #selector(genVideo), "v")

        menu.addItem(.separator())

        // === DePIN ===
        addHeader(menu, "DePIN (Solana)")
        addItem(menu, "  Start DePIN Node",     #selector(startDepin),      "")
        addItem(menu, "  Stop DePIN Node",      #selector(stopDepin),       "")
        addItem(menu, "  DePIN Status",         #selector(depinStatus),     "")
        addItem(menu, "  Copy DePIN Wallet",    #selector(copyDepinWallet), "")

        menu.addItem(.separator())

        // === Remote Access ===
        addHeader(menu, "Remote Access")
        addItem(menu, "  Start Tunnel (anywhere)", #selector(startTunnel),   "")
        addItem(menu, "  Stop Tunnel",             #selector(stopTunnel),    "")
        addItem(menu, "  Copy Remote URL",         #selector(copyRemoteURL), "")
        addItem(menu, "  Copy LAN URL",            #selector(copyURL),       "")

        menu.addItem(.separator())

        // === Tools ===
        addHeader(menu, "Tools")
        addItem(menu, "  Benchmark",              #selector(runBench),      "b")
        addItem(menu, "  Open Logs",              #selector(openLogs),      "l")
        addItem(menu, "  Open Generated Images",  #selector(openGenerated), "")

        menu.addItem(.separator())
        addItem(menu, "  GitHub: yukihamada/sokora", #selector(openGitHub), "")
        menu.addItem(.separator())
        addItem(menu, "Quit", #selector(quit), "q")

        statusItem.menu = menu
    }

    private func addHeader(_ menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        menu.addItem(item)
    }

    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    // MARK: - Status Update

    func updateStatus() {
        Task.detached { [weak self] in
            guard let self else { return }
            var results: [(Int, Bool)] = []
            for entry in await self.ports {
                let alive = Self.isPortAlive(entry.port)
                results.append((entry.port, alive))
            }
            // DePIN
            let depinAlive = Self.isProcessRunning("depin")
            results.append((9999, depinAlive))

            let runningCount = results.filter { $0.1 }.count
            let total = results.count

            await MainActor.run { [weak self] in
                guard let self else { return }
                if runningCount == total       { self.statusItem.button?.title = "AI" }
                else if runningCount > 0       { self.statusItem.button?.title = "AI·" }
                else                           { self.statusItem.button?.title = "AI" }

                guard let menu = self.statusItem.menu else { return }
                for item in menu.items {
                    guard item.tag > 0,
                          let (_, alive) = results.first(where: { $0.0 == item.tag }) else { continue }

                    let label: String
                    if item.tag == 9999 {
                        label = "DePIN — Solana節点"
                    } else if let entry = self.ports.first(where: { $0.port == item.tag }) {
                        label = "\(entry.name) — \(entry.desc)"
                    } else { continue }

                    item.title = "  \(alive ? "●" : "○") \(label)"
                    item.attributedTitle = NSAttributedString(string: "  \(alive ? "●" : "○") \(label)", attributes: [
                        .foregroundColor: alive ? NSColor.systemGreen : NSColor.systemRed,
                        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                    ])
                }
            }
        }
    }

    // MARK: - Helpers

    nonisolated static func isPortAlive(_ port: Int) -> Bool {
        let urlStr = port == 4001
            ? "http://127.0.0.1:\(port)/health"
            : "http://127.0.0.1:\(port)/v1/models"
        guard let url = URL(string: urlStr) else { return false }
        var req = URLRequest(url: url, timeoutInterval: 2)
        req.httpMethod = "GET"
        let sem = DispatchSemaphore(value: 0)
        var alive = false
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            if let r = resp as? HTTPURLResponse, r.statusCode == 200 { alive = true }
            sem.signal()
        }.resume()
        sem.wait()
        return alive
    }

    nonisolated static func isProcessRunning(_ name: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", name]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    func runShell(_ cmd: String, completion: ((String) -> Void)? = nil) {
        DispatchQueue.global().async {
            let p = Process()
            let pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", "export PATH=/opt/homebrew/bin:$HOME/.cargo/bin:$PATH\n\(cmd)"]
            p.standardOutput = pipe
            p.standardError = pipe
            try? p.run()
            p.waitUntilExit()
            let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let clean = raw.replacingOccurrences(of: "\\e\\[[0-9;]*m", with: "", options: .regularExpression)
            completion?(clean)
        }
    }

    func promptInput(_ title: String, _ placeholder: String, completion: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 350, height: 24))
            input.placeholderString = placeholder
            alert.accessoryView = input
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = input
            if alert.runModal() == .alertFirstButtonReturn && !input.stringValue.isEmpty {
                completion(input.stringValue)
            }
        }
    }

    func showAlert(_ title: String, _ msg: String) {
        DispatchQueue.main.async {
            let a = NSAlert()
            a.messageText = title
            a.informativeText = msg
            a.runModal()
        }
    }

    func getLANIP() -> String {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
        p.arguments = ["getifaddr", "en0"]
        p.standardOutput = pipe
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "127.0.0.1"
    }

    func getAPIKey() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return (try? String(contentsOf: home.appendingPathComponent(".local-ai-key"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "sk-ant-dummy"
    }

    // MARK: - Control

    @objc func startAll() {
        statusItem.button?.title = "AI…"
        runShell("~/ai.sh start") { [weak self] output in
            Task { @MainActor in
                self?.updateStatus()
                self?.showAlert("Started", output)
            }
        }
    }

    @objc func stopAll() {
        runShell("~/ai.sh stop") { [weak self] output in
            Task { @MainActor in
                self?.updateStatus()
                self?.showAlert("Stopped", output)
            }
        }
    }

    @objc func restartAll() {
        statusItem.button?.title = "AI…"
        runShell("~/ai.sh restart") { [weak self] output in
            Task { @MainActor in
                self?.updateStatus()
                self?.showAlert("Restarted", output)
            }
        }
    }

    @objc func healthCheck() {
        runShell("~/ai.sh health") { [weak self] output in
            Task { @MainActor in
                self?.updateStatus()
                self?.showAlert("Health Check", output.isEmpty ? "All healthy" : output)
            }
        }
    }

    // MARK: - Launch

    @objc func launchCld() {
        let script = "export PATH=/opt/homebrew/bin:$PATH && source ~/mlx_env/bin/activate && export ANTHROPIC_BASE_URL=http://127.0.0.1:4001 && export ANTHROPIC_API_KEY=sk-ant-dummy && claude --dangerously-skip-permissions"
        openTerminalWith(script)
    }

    @objc func launchClc() {
        let script = "export PATH=/opt/homebrew/bin:$PATH && unset ANTHROPIC_BASE_URL && claude"
        openTerminalWith(script)
    }

    @objc func launchAider() {
        let script = "export PATH=/opt/homebrew/bin:$PATH && source ~/mlx_env/bin/activate && OPENAI_API_BASE=http://127.0.0.1:4001/v1 OPENAI_API_KEY=sk-dummy aider --model openai/qwen3.5-122b"
        openTerminalWith(script)
    }

    @objc func openTerminal() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }

    @objc func openDashboard() {
        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:4001/")!)
    }

    private func openTerminalWith(_ cmd: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Terminal", "--args", "-e", cmd]
        try? p.run()
    }

    // MARK: - Generate

    @objc func genImage() {
        promptInput("Generate Image", "a cyberpunk Tokyo street at night, neon, rain") { [weak self] prompt in
            self?.showAlert("Generating...", "Prompt: \(prompt)\nThis takes about 17 seconds.")
            self?.runShell("~/ai.sh img \"\(prompt)\"") { output in
                self?.showAlert("Image Ready", output)
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("generated"))
            }
        }
    }

    @objc func genVideo() {
        promptInput("Generate Video", "samurai on a cliff, sunset, dramatic wind") { [weak self] prompt in
            self?.showAlert("Generating...", "Prompt: \(prompt)\nThis takes about 10 minutes.")
            self?.runShell("~/ai.sh vid \"\(prompt)\"") { output in
                self?.showAlert("Video Ready", output)
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("generated"))
            }
        }
    }

    // MARK: - DePIN

    @objc func startDepin() {
        let depinPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("sokora/depin").path
        let script = """
        cd \(depinPath)
        if cargo build --release 2>/dev/null; then
            nohup ./target/release/sokora-depin --public > ~/depin.log 2>&1 &
            echo "DePIN node started (PID: $!)"
        else
            echo "Build failed. Running: cargo build --release"
            cargo build --release 2>&1 | tail -5
        fi
        """
        showAlert("Starting DePIN...", "Building and starting Solana node.\nThis may take a moment.")
        runShell(script) { [weak self] output in
            Task { @MainActor in self?.updateStatus() }
            self?.showAlert("DePIN", output)
        }
    }

    @objc func stopDepin() {
        runShell("pkill -f sokora-depin") { [weak self] _ in
            Task { @MainActor in self?.updateStatus() }
            self?.showAlert("DePIN Stopped", "Node stopped.")
        }
    }

    @objc func depinStatus() {
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("depin.log").path
        let log = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "No log yet."
        let lines = log.components(separatedBy: "\n").suffix(20).joined(separator: "\n")
        let running = Self.isProcessRunning("sokora-depin")
        showAlert("DePIN Status", "\(running ? "● Running" : "○ Stopped")\n\n\(lines)")
    }

    @objc func copyDepinWallet() {
        // Read wallet address from solana config or depin config
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/solana/id.json").path
        if FileManager.default.fileExists(atPath: configPath) {
            runShell("solana address 2>/dev/null || cat ~/.config/solana/id.json | python3 -c 'import sys,json,base58; k=json.load(sys.stdin)[:32]; print(base58.b58encode(bytes(k)).decode())' 2>/dev/null || echo 'No wallet found'") { [weak self] output in
                let addr = output.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(addr, forType: .string)
                    self?.showAlert("Wallet Address Copied", addr)
                }
            }
        } else {
            showAlert("No Wallet", "No Solana wallet found.\nRun: solana-keygen new")
        }
    }

    // MARK: - Remote Access

    @objc func startTunnel() {
        DispatchQueue.global().async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", "export PATH=/opt/homebrew/bin:$PATH && pkill -f cloudflared 2>/dev/null; sleep 1 && nohup cloudflared tunnel --url http://127.0.0.1:4001 > ~/cloudflared.log 2>&1 &"]
            try? p.run(); p.waitUntilExit()
            sleep(5)
            let home = FileManager.default.homeDirectoryForCurrentUser
            if let log = try? String(contentsOf: home.appendingPathComponent("cloudflared.log"), encoding: .utf8),
               let range = log.range(of: "https://[a-z0-9-]+\\.trycloudflare\\.com", options: .regularExpression) {
                let url = String(log[range])
                self?.showAlert("Tunnel Active!", "URL: \(url)\n\nAnyone with this URL can access your AI from anywhere.")
            } else {
                self?.showAlert("Tunnel", "Starting... use 'Copy Remote URL' in a few seconds.")
            }
        }
    }

    @objc func stopTunnel() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", "cloudflared"]
        try? p.run(); p.waitUntilExit()
        showAlert("Tunnel Stopped", "Remote access disabled.")
    }

    @objc func copyRemoteURL() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let key = getAPIKey()
        let log = (try? String(contentsOf: home.appendingPathComponent("cloudflared.log"), encoding: .utf8)) ?? ""
        if let range = log.range(of: "https://[a-z0-9-]+\\.trycloudflare\\.com", options: .regularExpression) {
            let url = String(log[range])
            let info = """
            # Claude Code
            export ANTHROPIC_BASE_URL=\(url)
            export ANTHROPIC_API_KEY=\(key)
            claude --dangerously-skip-permissions

            # Aider
            OPENAI_API_BASE=\(url)/v1 OPENAI_API_KEY=\(key) aider --model openai/qwen3.5-122b
            """
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(info, forType: .string)
            showAlert("Copied!", "Remote URL:\n\(url)\n\nPaste on any machine.")
        } else {
            showAlert("No Tunnel", "Start a tunnel first.")
        }
    }

    @objc func copyURL() {
        let ip = getLANIP()
        let key = getAPIKey()
        let info = """
        # Claude Code (LAN)
        export ANTHROPIC_BASE_URL=http://\(ip):4001
        export ANTHROPIC_API_KEY=\(key)
        claude --dangerously-skip-permissions

        # Aider (LAN)
        OPENAI_API_BASE=http://\(ip):4001/v1 OPENAI_API_KEY=\(key) aider --model openai/qwen3.5-122b

        # SSH Tunnel
        ssh -L 4001:127.0.0.1:4001 \(NSUserName())@\(ip)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
        showAlert("LAN URL Copied!", "ANTHROPIC_BASE_URL=http://\(ip):4001\nAPI_KEY=\(key)")
    }

    // MARK: - Tools

    @objc func runBench() {
        showAlert("Running Benchmark...", "Testing 122B and 35B models.\nThis takes about 30 seconds.")
        runShell("~/ai.sh bench") { [weak self] output in
            self?.showAlert("Benchmark Results", output.isEmpty ? "Done." : output)
        }
    }

    @objc func openLogs() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Open both proxy log and localai log
        NSWorkspace.shared.open(home.appendingPathComponent("localai-swift.log"))
    }

    @objc func openGenerated() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("generated")
        if FileManager.default.fileExists(atPath: dir.path) {
            NSWorkspace.shared.open(dir)
        } else {
            showAlert("No Images Yet", "Run 'Generate Image' first.")
        }
    }

    @objc func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/yukihamada/sokora")!)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
