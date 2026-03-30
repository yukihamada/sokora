import AppKit

@MainActor
class MenubarController {
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "\u{1F9E0}\u{1F4A4}"
        statusItem.button?.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        buildMenu()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        refreshStatus()
    }

    func buildMenu() {
        let menu = NSMenu()

        for (_, cfg) in ModelRegistry.backends.sorted(by: { $0.key < $1.key }) {
            let item = NSMenuItem(title: "  \u{25CB} \(cfg.label)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.tag = cfg.port
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let startItem = NSMenuItem(title: "\u{25B6} Start", action: #selector(startServers), keyEquivalent: "s")
        startItem.target = self
        menu.addItem(startItem)

        let stopItem = NSMenuItem(title: "\u{25A0} Stop", action: #selector(stopServers), keyEquivalent: "x")
        stopItem.target = self
        menu.addItem(stopItem)

        menu.addItem(.separator())

        let dashItem = NSMenuItem(title: "\u{1F310} Open Dashboard", action: #selector(openDashboard), keyEquivalent: "d")
        dashItem.target = self
        menu.addItem(dashItem)

        let copyItem = NSMenuItem(title: "\u{1F4CB} Copy API URL", action: #selector(copyAPIURL), keyEquivalent: "u")
        copyItem.target = self
        menu.addItem(copyItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit LocalAI", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func refreshStatus() {
        Task {
            var runningCount = 0
            let allPorts = ModelRegistry.backends.values.map { $0.port } + [ModelRegistry.proxyPort]
            for port in allPorts {
                if await HealthHandler.isAlive(port: port) { runningCount += 1 }
            }
            await MainActor.run {
                if runningCount == allPorts.count {
                    self.statusItem.button?.title = "\u{1F9E0}"
                } else if runningCount > 0 {
                    self.statusItem.button?.title = "\u{1F9E0}\u{26A1}"
                } else {
                    self.statusItem.button?.title = "\u{1F9E0}\u{1F4A4}"
                }
            }

            for item in self.statusItem.menu?.items ?? [] {
                guard item.tag > 0 else { continue }
                let port = item.tag
                let alive = await HealthHandler.isAlive(port: port)
                let label = ModelRegistry.backends.values.first(where: { $0.port == port })?.label ?? ":\(port)"
                await MainActor.run {
                    item.title = "  \(alive ? "\u{25CF}" : "\u{25CB}") \(label)"
                }
            }
        }
    }

    @objc func startServers() {
        let script = """
        source ~/mlx_env/bin/activate
        ~/ai.sh start
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", script]
        try? p.run()
        statusItem.button?.title = "\u{1F9E0}\u{23F3}"
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.refreshStatus()
        }
    }

    @objc func stopServers() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", "~/ai.sh stop"]
        try? p.run()
        statusItem.button?.title = "\u{1F9E0}\u{1F4A4}"
    }

    @objc func openDashboard() {
        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:\(ModelRegistry.proxyPort)/")!)
    }

    @objc func copyAPIURL() {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
        p.arguments = ["getifaddr", "en0"]
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        let ip = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "127.0.0.1"
        let text = """
        # Claude Code
        export ANTHROPIC_BASE_URL=http://\(ip):\(ModelRegistry.proxyPort)
        export ANTHROPIC_API_KEY=sk-ant-dummy
        claude --dangerously-skip-permissions

        # Aider
        OPENAI_API_BASE=http://\(ip):\(ModelRegistry.proxyPort)/v1 OPENAI_API_KEY=sk-dummy aider --model openai/qwen3.5-122b
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
