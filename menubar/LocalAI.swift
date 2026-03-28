import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    let ports = [(5000, "LLM 122B"), (5001, "LLM 35B"), (5002, "Vision"), (4001, "Proxy")]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "AI"
        buildMenu()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.updateIcon()
        }
        updateIcon()
    }

    func buildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Status", action: #selector(showStatus), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "▶ Start All", action: #selector(startAll), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "■ Stop All", action: #selector(stopAll), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "↻ Restart", action: #selector(restartAll), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Health Check", action: #selector(healthCheck), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Generate Image...", action: #selector(genImage), keyEquivalent: "i"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Logs", action: #selector(openLogs), keyEquivalent: "l"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func isPortAlive(_ port: Int) -> Bool {
        let url = URL(string: "http://127.0.0.1:\(port)/v1/models")!
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.httpMethod = "GET"
        let sem = DispatchSemaphore(value: 0)
        var alive = false
        URLSession.shared.dataTask(with: request) { data, resp, _ in
            if let r = resp as? HTTPURLResponse, r.statusCode == 200 { alive = true }
            sem.signal()
        }.resume()
        sem.wait()
        return alive
    }

    func updateIcon() {
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            let running = self.ports.filter { self.isPortAlive($0.0) }.count
            DispatchQueue.main.async {
                if running == self.ports.count { self.statusItem.button?.title = "AI" }
                else if running > 0 { self.statusItem.button?.title = "AI·" }
                else { self.statusItem.button?.title = "AI" }
            }
        }
    }

    func runAI(_ cmd: String) -> String {
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
        // Strip ANSI escape codes
        guard let regex = try? NSRegularExpression(pattern: "\\e\\[[0-9;]*m") else { return raw }
        return regex.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
    }

    @objc func showStatus() {
        let output = runAI("status")
        showAlert("Local AI Status", output)
    }

    @objc func startAll() {
        statusItem.button?.title = "AI…"
        DispatchQueue.global().async { [weak self] in
            let _ = self?.runAI("start")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.updateIcon() }
            self?.notify("Local AI", "Servers started")
        }
    }

    @objc func stopAll() {
        let _ = runAI("stop")
        statusItem.button?.title = "AI"
        notify("Local AI", "Servers stopped")
    }

    @objc func restartAll() {
        statusItem.button?.title = "AI…"
        DispatchQueue.global().async { [weak self] in
            let _ = self?.runAI("stop")
            sleep(2)
            let _ = self?.runAI("start")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.updateIcon() }
            self?.notify("Local AI", "Servers restarted")
        }
    }

    @objc func healthCheck() {
        let output = runAI("health")
        showAlert("Health Check", output)
    }

    @objc func genImage() {
        let alert = NSAlert()
        alert.messageText = "Generate Image"
        alert.informativeText = "Enter prompt:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.placeholderString = "a cyberpunk Tokyo street at night"
        alert.accessoryView = input
        alert.addButton(withTitle: "Generate")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn && !input.stringValue.isEmpty {
            let prompt = input.stringValue
            notify("Local AI", "Generating: \(prompt)")
            DispatchQueue.global().async { [weak self] in
                let _ = self?.runAI("img \"\(prompt)\"")
                self?.notify("Local AI", "Image ready!")
            }
        }
    }

    @objc func openLogs() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        NSWorkspace.shared.open(home.appendingPathComponent("proxy.log"))
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    func showAlert(_ title: String, _ msg: String) {
        DispatchQueue.main.async {
            let a = NSAlert()
            a.messageText = title
            a.informativeText = msg
            a.runModal()
        }
    }

    func notify(_ title: String, _ body: String) {
        // Simple log notification (no deprecated API)
        NSLog("LocalAI: \(title) — \(body)")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
