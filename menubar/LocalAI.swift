import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    let ports: [(Int, String, String)] = [
        (5000, "LLM 122B", "Sonnet"),
        (5001, "LLM 35B",  "Haiku"),
        (5002, "Vision",   "画像理解"),
        (4001, "Proxy",    "API変換"),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "AI"
        statusItem.button?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        buildMenu()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
        updateStatus()
    }

    func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Status header
        let header = NSMenuItem(title: "LOCAL AI", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(string: "LOCAL AI", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.systemBlue
        ])
        menu.addItem(header)

        // Service status items (will be updated dynamically)
        for (_, name, desc) in ports {
            let item = NSMenuItem(title: "  ○ \(name) — \(desc)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.tag = 1000 // tag to find later
            menu.addItem(item)
        }

        // RAM info
        let ram = ProcessInfo.processInfo.physicalMemory / (1024*1024*1024)
        let ramItem = NSMenuItem(title: "  RAM: \(ram)GB", action: nil, keyEquivalent: "")
        ramItem.isEnabled = false
        menu.addItem(ramItem)

        menu.addItem(NSMenuItem.separator())

        // === Control ===
        let controlHeader = NSMenuItem(title: "Control", action: nil, keyEquivalent: "")
        controlHeader.isEnabled = false
        menu.addItem(controlHeader)

        menu.addItem(NSMenuItem(title: "  Start All", action: #selector(startAll), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "  Stop All", action: #selector(stopAll), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "  Restart", action: #selector(restartAll), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "  Health Check (auto-fix)", action: #selector(healthCheck), keyEquivalent: "h"))

        menu.addItem(NSMenuItem.separator())

        // === Launch ===
        let launchHeader = NSMenuItem(title: "Launch", action: nil, keyEquivalent: "")
        launchHeader.isEnabled = false
        menu.addItem(launchHeader)

        menu.addItem(NSMenuItem(title: "  Claude Code (local)", action: #selector(launchCld), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "  Claude Code (cloud)", action: #selector(launchClc), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "  Terminal", action: #selector(openTerminal), keyEquivalent: "t"))

        menu.addItem(NSMenuItem.separator())

        // === Generate ===
        let genHeader = NSMenuItem(title: "Generate", action: nil, keyEquivalent: "")
        genHeader.isEnabled = false
        menu.addItem(genHeader)

        menu.addItem(NSMenuItem(title: "  Image (FLUX, ~17s)...", action: #selector(genImage), keyEquivalent: "i"))
        menu.addItem(NSMenuItem(title: "  Video (Wan 2.1, ~10min)...", action: #selector(genVideo), keyEquivalent: "v"))

        menu.addItem(NSMenuItem.separator())

        // === Tools ===
        let toolsHeader = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        toolsHeader.isEnabled = false
        menu.addItem(toolsHeader)

        menu.addItem(NSMenuItem(title: "  Benchmark", action: #selector(runBench), keyEquivalent: "b"))
        menu.addItem(NSMenuItem(title: "  Open Logs", action: #selector(openLogs), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "  Open Generated Images", action: #selector(openGenerated), keyEquivalent: "g"))
        menu.addItem(NSMenuItem(title: "  Copy API URL", action: #selector(copyURL), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "  GitHub: yukihamada/local-claude", action: #selector(openGitHub), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // ── Status ──

    func isPortAlive(_ port: Int) -> Bool {
        let url = URL(string: port == 4001 ? "http://127.0.0.1:\(port)/health" : "http://127.0.0.1:\(port)/v1/models")!
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

    func updateStatus() {
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            var statuses: [(Bool, String)] = []
            for (port, name, desc) in self.ports {
                let alive = self.isPortAlive(port)
                statuses.append((alive, "\(alive ? "●" : "○") \(name) — \(desc)"))
            }
            let running = statuses.filter { $0.0 }.count
            DispatchQueue.main.async {
                // Update icon
                if running == self.ports.count { self.statusItem.button?.title = "AI" }
                else if running > 0 { self.statusItem.button?.title = "AI·" }
                else { self.statusItem.button?.title = "AI" }

                // Update menu items
                if let menu = self.statusItem.menu {
                    var idx = 0
                    for item in menu.items {
                        if item.tag == 1000 && idx < statuses.count {
                            let (alive, text) = statuses[idx]
                            item.title = "  \(text)"
                            item.attributedTitle = NSAttributedString(string: "  \(text)", attributes: [
                                .foregroundColor: alive ? NSColor.systemGreen : NSColor.systemRed,
                                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                            ])
                            idx += 1
                        }
                    }
                }
            }
        }
    }

    // ── Helpers ──

    func runAI(_ cmd: String, completion: ((String) -> Void)? = nil) {
        DispatchQueue.global().async {
            let p = Process()
            let pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", "export PATH=/opt/homebrew/bin:$HOME/.cargo/bin:$PATH && ~/ai.sh \(cmd)"]
            p.standardOutput = pipe
            p.standardError = pipe
            try? p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8) ?? ""
            let clean: String
            if let regex = try? NSRegularExpression(pattern: "\\e\\[[0-9;]*m") {
                clean = regex.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
            } else { clean = raw }
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

    // ── Actions ──

    @objc func startAll() {
        statusItem.button?.title = "AI…"
        runAI("start") { [weak self] output in
            self?.updateStatus()
            self?.showAlert("Started", output)
        }
    }

    @objc func stopAll() {
        runAI("stop") { [weak self] output in
            self?.updateStatus()
            self?.showAlert("Stopped", output)
        }
    }

    @objc func restartAll() {
        statusItem.button?.title = "AI…"
        runAI("restart") { [weak self] output in
            self?.updateStatus()
            self?.showAlert("Restarted", output)
        }
    }

    @objc func healthCheck() {
        runAI("health") { [weak self] output in
            self?.updateStatus()
            self?.showAlert("Health Check", output)
        }
    }

    @objc func launchCld() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Terminal", "--args", "-e", "export PATH=/opt/homebrew/bin:$PATH && ai-local && claude --dangerously-skip-permissions"]
        try? p.run()
    }

    @objc func launchClc() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Terminal", "--args", "-e", "export PATH=/opt/homebrew/bin:$PATH && ai-cloud && claude"]
        try? p.run()
    }

    @objc func openTerminal() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }

    @objc func genImage() {
        promptInput("Generate Image", "a cyberpunk Tokyo street at night, neon, rain") { [weak self] prompt in
            self?.showAlert("Generating...", "Prompt: \(prompt)\nThis takes about 17 seconds.")
            self?.runAI("img \"\(prompt)\"") { output in
                self?.showAlert("Image Ready", output)
                // Open generated folder
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("generated"))
            }
        }
    }

    @objc func genVideo() {
        promptInput("Generate Video", "samurai on a cliff, sunset, dramatic wind") { [weak self] prompt in
            self?.showAlert("Generating...", "Prompt: \(prompt)\nThis takes about 10 minutes.")
            self?.runAI("vid \"\(prompt)\"") { output in
                self?.showAlert("Video Ready", output)
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("generated"))
            }
        }
    }

    @objc func runBench() {
        showAlert("Running...", "Benchmarking 122B and 35B models.\nThis takes about 30 seconds.")
        runAI("bench") { [weak self] output in
            self?.showAlert("Benchmark Results", output)
        }
    }

    @objc func openLogs() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        NSWorkspace.shared.open(home.appendingPathComponent("proxy.log"))
    }

    @objc func openGenerated() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("generated")
        if FileManager.default.fileExists(atPath: dir.path) {
            NSWorkspace.shared.open(dir)
        } else {
            showAlert("No images yet", "Run 'Generate Image' first.")
        }
    }

    @objc func copyURL() {
        let pb = NSPasteboard.general
        pb.clearContents()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let key = (try? String(contentsOf: home.appendingPathComponent(".local-ai-key"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "sk-ant-dummy"

        // Get en0 IP
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
        p.arguments = ["getifaddr", "en0"]
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        let ip = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "127.0.0.1"

        let info = """
        export ANTHROPIC_BASE_URL=http://\(ip):4001
        export ANTHROPIC_API_KEY=\(key)
        claude
        """
        pb.setString(info, forType: .string)
        showAlert("Copied to Clipboard!",
            "Paste this on another Mac:\n\n" +
            "export ANTHROPIC_BASE_URL=http://\(ip):4001\n" +
            "export ANTHROPIC_API_KEY=\(key)\n" +
            "claude\n\n" +
            "Or use SSH tunnel for extra security:\n" +
            "ssh -L 4001:127.0.0.1:4001 \(NSUserName())@\(ip)")
    }

    @objc func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/yukihamada/local-claude")!)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
