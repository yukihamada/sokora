import AppKit

// MARK: - i18n

private func L(_ ja: String, _ en: String) -> String {
    Locale.current.language.languageCode?.identifier == "ja" ? ja : en
}

// MARK: - MenubarController

@MainActor
class MenubarController {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var depinActive = false
    private var tunnelURL: String? = nil
    private var caffeinateProcess: Process? = nil
    private var proxyDownCount = 0

    private let mlxPorts: [(port: Int, key: String)] = [
        (5000, "main"), (5001, "fast"), (5002, "vision"), (4001, "proxy")
    ]

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🧠"
        buildMenu()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        refreshStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.firstLaunchCheck()
        }
    }

    // MARK: - Menu Build

    func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let ram = ProcessInfo.processInfo.physicalMemory / (1024*1024*1024)

        // ── ヘッダー ──────────────────────────────────
        let header = NSMenuItem(title: "Sokora", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(string: "  🧠  Sokora", attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: 13, weight: .bold)
        ])
        menu.addItem(header)

        // ステータス行 (●●● 形式で1行にまとめる)
        let statusRow = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusRow.isEnabled = false; statusRow.tag = 1000
        menu.addItem(statusRow)

        // tok/sec + リクエスト数
        let statsRow = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statsRow.isEnabled = false; statsRow.tag = 7777; statsRow.isHidden = true
        menu.addItem(statsRow)

        menu.addItem(.separator())

        // ── クイックアクション ─────────────────────────
        addItem(menu, L("  ▶  AIを起動", "  ▶  Start AI"),   #selector(startAll),   "s")
        addItem(menu, L("  ■  AIを停止", "  ■  Stop AI"),    #selector(stopAll),    "x")
        addItem(menu, L("  ↻  再起動",   "  ↻  Restart"),    #selector(restartAll), "r")

        menu.addItem(.separator())

        // ── AI ツール ──────────────────────────────────
        addItem(menu, L("  💬  Claude Code (ローカル)", "  💬  Claude Code (Local)"), #selector(launchCld),     "c")
        addItem(menu, L("  🤖  Aider (コード編集)",      "  🤖  Aider (Code Edit)"),   #selector(launchAider),   "a")
        addItem(menu, L("  🌐  ダッシュボード",           "  🌐  Dashboard"),            #selector(openDashboard), "d")

        menu.addItem(.separator())

        // ── モデル選択サブメニュー ──────────────────────
        let modelMenu = NSMenu()
        let modelParent = NSMenuItem(title: L("  🧠  モデル", "  🧠  Model"), action: nil, keyEquivalent: "")
        modelParent.tag = 2000  // モデル名を動的更新
        menu.addItem(modelParent)
        menu.setSubmenu(modelMenu, for: modelParent)
        buildModelSubmenu(modelMenu)

        menu.addItem(.separator())

        // ── DePIN サブメニュー ─────────────────────────
        let depinMenu = NSMenu()
        let depinParent = NSMenuItem(title: L("  🌍  DePIN", "  🌍  DePIN"), action: nil, keyEquivalent: "")
        depinParent.tag = 3000
        menu.addItem(depinParent)
        menu.setSubmenu(depinMenu, for: depinParent)
        buildDepinSubmenu(depinMenu)

        // ── 接続サブメニュー ───────────────────────────
        let connectMenu = NSMenu()
        let connectParent = NSMenuItem(title: L("  🔗  接続・共有", "  🔗  Connect"), action: nil, keyEquivalent: "")
        menu.addItem(connectParent)
        menu.setSubmenu(connectMenu, for: connectParent)
        buildConnectSubmenu(connectMenu)

        // ── その他サブメニュー ─────────────────────────
        let moreMenu = NSMenu()
        let moreParent = NSMenuItem(title: L("  ⋯  その他", "  ⋯  More"), action: nil, keyEquivalent: "")
        menu.addItem(moreParent)
        menu.setSubmenu(moreMenu, for: moreParent)
        buildMoreSubmenu(moreMenu)

        menu.addItem(.separator())
        addItem(menu, L("Sokoraを終了", "Quit Sokora"), #selector(quit), "q")

        statusItem.menu = menu
    }

    private func buildModelSubmenu(_ menu: NSMenu) {
        menu.autoenablesItems = false
        let currentMain  = ModelRegistry.activePreset(slot: "main")
        let currentFast  = ModelRegistry.activePreset(slot: "fast")
        let currentVision = ModelRegistry.activePreset(slot: "vision")

        addDisabled(menu, L("  メインモデル (高品質)", "  Main (Quality)"), size: 11)
        for p in ModelRegistry.presets.filter({ $0.slot == "main" }) {
            let item = NSMenuItem(title: "  \(p.id == currentMain.id ? "✓" : " ")  \(p.displayName)  (\(p.ramGB)GB)",
                                  action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = p.id
            menu.addItem(item)
        }
        menu.addItem(.separator())
        addDisabled(menu, L("  高速モデル", "  Fast Model"), size: 11)
        for p in ModelRegistry.presets.filter({ $0.slot == "fast" }) {
            let item = NSMenuItem(title: "  \(p.id == currentFast.id ? "✓" : " ")  \(p.displayName)  (\(p.ramGB)GB)",
                                  action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = p.id
            menu.addItem(item)
        }
        menu.addItem(.separator())
        addDisabled(menu, L("  ビジョン", "  Vision"), size: 11)
        for p in ModelRegistry.presets.filter({ $0.slot == "vision" }) {
            let item = NSMenuItem(title: "  \(p.id == currentVision.id ? "✓" : " ")  \(p.displayName)  (\(p.ramGB)GB)",
                                  action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = p.id
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("  ↻ モデル再起動", "  ↻ Restart with new model"), action: #selector(restartAll), keyEquivalent: ""))
        menu.items.last?.target = self
    }

    private func buildDepinSubmenu(_ menu: NSMenu) {
        menu.autoenablesItems = false
        addItemTo(menu, L("  🌍  外部公開を開始",  "  🌍  Start Public Node"), #selector(startDepin))
        addItemTo(menu, L("  🔒  外部公開を停止",  "  🔒  Stop Public Node"),  #selector(stopDepin))
        menu.addItem(.separator())
        addItemTo(menu, L("  📊  ノード状態を確認", "  📊  Node Status"),       #selector(depinStatus))
        addItemTo(menu, L("  🔑  接続情報をコピー", "  🔑  Copy Connect Info"), #selector(copyDepinInfo))
    }

    private func buildConnectSubmenu(_ menu: NSMenu) {
        menu.autoenablesItems = false
        addItemTo(menu, L("  🚇  Tunnel開始",        "  🚇  Start Tunnel"),     #selector(startTunnel))
        addItemTo(menu, L("  🚫  Tunnel停止",         "  🚫  Stop Tunnel"),      #selector(stopTunnel))
        menu.addItem(.separator())
        addItemTo(menu, L("  📋  リモートURLをコピー","  📋  Copy Remote URL"),  #selector(copyRemoteURL))
        addItemTo(menu, L("  📋  LAN URLをコピー",    "  📋  Copy LAN URL"),     #selector(copyURL))
        menu.addItem(.separator())
        addItemTo(menu, L("  💬  Claude Code (クラウド)", "  💬  Claude Code (Cloud)"), #selector(launchClc))
    }

    private func buildMoreSubmenu(_ menu: NSMenu) {
        menu.autoenablesItems = false
        addItemTo(menu, L("  🖼  画像を生成...",  "  🖼  Generate Image..."), #selector(genImage))
        addItemTo(menu, L("  🎬  動画を生成...",  "  🎬  Generate Video..."), #selector(genVideo))
        menu.addItem(.separator())
        addItemTo(menu, L("  ⚡  ベンチマーク",   "  ⚡  Benchmark"),         #selector(runBench))
        addItemTo(menu, L("  📄  ログを開く",     "  📄  Open Logs"),         #selector(openLogs))
        addItemTo(menu, L("  🖥  ターミナル",      "  🖥  Terminal"),           #selector(openTerminal))
        addItemTo(menu, L("  🖼  生成ファイル",   "  🖼  Generated Files"),    #selector(openGenerated))
        menu.addItem(.separator())
        addItemTo(menu, L("  📦  GitHubを開く",   "  📦  GitHub"),             #selector(openGitHub))
        addItemTo(menu, L("  ✓   ヘルスチェック", "  ✓   Health Check"),       #selector(healthCheck))
    }

    // MARK: - Helpers

    private func addDisabled(_ menu: NSMenu, _ title: String, bold: Bool = false,
                              color: NSColor = .secondaryLabelColor, size: CGFloat = 12) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: color,
            .font: bold ? NSFont.systemFont(ofSize: size, weight: .bold)
                        : NSFont.systemFont(ofSize: size, weight: .regular)
        ])
        menu.addItem(item)
    }

    private func addItem(_ menu: NSMenu, _ title: String, _ sel: Selector, _ key: String) {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        item.target = self; menu.addItem(item)
    }

    private func addItemTo(_ menu: NSMenu, _ title: String, _ sel: Selector) {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        item.target = self; menu.addItem(item)
    }

    // MARK: - Status Refresh

    func refreshStatus() {
        Task.detached { [weak self] in
            guard let self else { return }
            var portResults: [(Int, String, Bool)] = []
            for entry in await self.mlxPorts {
                portResults.append((entry.port, entry.key, Self.isPortAlive(entry.port)))
            }
            let depinRunning = await self.depinActive || Self.isProcessRunning("cloudflared")
            let idleSecs = Self.getIdleSeconds()
            let isIdle = idleSecs >= 300

            // /api/stats
            var tokPerSec = "0.0"; var totalReqs = 0; var depinReqs = 0
            if portResults.first(where: { $0.0 == 4001 })?.2 == true,
               let url = URL(string: "http://127.0.0.1:4001/api/stats"),
               let (d, _) = try? await URLSession.shared.data(from: url),
               let stats = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                tokPerSec = stats["tok_per_sec"] as? String ?? "0.0"
                totalReqs = stats["total_requests"] as? Int ?? 0
                depinReqs = stats["depin_requests"] as? Int ?? 0
            }

            let running = portResults.filter { $0.2 }.count
            let proxyAlive = portResults.first(where: { $0.0 == 4001 })?.2 ?? false

            await MainActor.run { [weak self] in
                guard let self else { return }

                // Auto-recovery
                if !proxyAlive {
                    self.proxyDownCount += 1
                    if self.proxyDownCount >= 2 {
                        self.proxyDownCount = 0
                        self.runShell("~/ai.sh start 2>/dev/null || true")
                    }
                } else { self.proxyDownCount = 0 }

                // アイコン
                self.statusItem.button?.title = running == 0 ? "🧠💤"
                    : (depinRunning && isIdle ? "🧠💰" : "🧠")

                guard let menu = self.statusItem.menu else { return }

                // ステータス行 (tag 1000) — ●●○ 形式
                if let statusItem = menu.items.first(where: { $0.tag == 1000 }) {
                    let dots = portResults.map { (_, key, alive) -> String in
                        let emoji = alive ? "●" : "○"
                        let label: String
                        switch key {
                        case "proxy": label = "Proxy"
                        case "main":  label = "122B"
                        case "fast":  label = "35B"
                        case "vision": label = "VL"
                        default: label = key
                        }
                        return "\(emoji) \(label)"
                    }.joined(separator: "  ")
                    let color: NSColor = running == portResults.count ? .systemGreen
                        : (running > 0 ? .systemYellow : .systemRed)
                    statusItem.attributedTitle = NSAttributedString(
                        string: "  " + dots,
                        attributes: [.foregroundColor: color,
                                     .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]
                    )
                }

                // 統計行 (tag 7777)
                if let statsItem = menu.items.first(where: { $0.tag == 7777 }) {
                    if totalReqs > 0 || (Double(tokPerSec) ?? 0) > 0 {
                        statsItem.isHidden = false
                        var text = "  ⚡ \(tokPerSec) tok/s · \(totalReqs) req"
                        if depinReqs > 0 { text += " · 🌍 \(depinReqs) DePIN" }
                        if depinRunning {
                            text += isIdle ? "  💰" : "  🟢"
                        }
                        statsItem.attributedTitle = NSAttributedString(
                            string: text,
                            attributes: [.foregroundColor: NSColor.systemBlue,
                                         .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]
                        )
                    } else { statsItem.isHidden = true }
                }

                // モデルメニュー表示名を更新 (tag 2000)
                if let modelItem = menu.items.first(where: { $0.tag == 2000 }) {
                    let preset = ModelRegistry.activePreset(slot: "main")
                    modelItem.title = L("  🧠  \(preset.displayName)", "  🧠  \(preset.displayName)")
                }

                // DePIN親メニュー更新 (tag 3000)
                if let depinItem = menu.items.first(where: { $0.tag == 3000 }) {
                    let status = depinRunning ? (isIdle ? "💰" : "🟢") : "○"
                    depinItem.title = "  🌍  DePIN  \(status)"
                }
            }
        }
    }

    // MARK: - Static helpers

    nonisolated static func isPortAlive(_ port: Int) -> Bool {
        let urlStr = port == 4001 ? "http://127.0.0.1:\(port)/health"
                                  : "http://127.0.0.1:\(port)/v1/models"
        guard let url = URL(string: urlStr) else { return false }
        var req = URLRequest(url: url, timeoutInterval: 2)
        req.httpMethod = "GET"
        let sem = DispatchSemaphore(value: 0); var alive = false
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            alive = (resp as? HTTPURLResponse)?.statusCode == 200; sem.signal()
        }.resume(); sem.wait(); return alive
    }

    nonisolated static func isProcessRunning(_ name: String) -> Bool {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", name]; p.standardOutput = pipe
        try? p.run(); p.waitUntilExit(); return p.terminationStatus == 0
    }

    nonisolated static func getIdleSeconds() -> Double {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "ioreg -c IOHIDSystem | awk '/HIDIdleTime/{print $NF/1000000000; exit}'"]
        p.standardOutput = pipe; p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        return Double(String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0
    }

    nonisolated static func which(_ cmd: String) -> String? {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        p.arguments = [cmd]; p.standardOutput = pipe; p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : out
    }

    // MARK: - Sleep

    private func preventSleep() {
        guard caffeinateProcess == nil else { return }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-i"]; try? p.run(); caffeinateProcess = p
    }

    private func allowSleep() { caffeinateProcess?.terminate(); caffeinateProcess = nil }

    // MARK: - Shell

    func runShell(_ cmd: String, completion: ((String) -> Void)? = nil) {
        DispatchQueue.global().async {
            let p = Process(); let pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", "export PATH=/opt/homebrew/bin:$HOME/.cargo/bin:$PATH\n\(cmd)"]
            p.standardOutput = pipe; p.standardError = pipe
            try? p.run(); p.waitUntilExit()
            completion?(String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        }
    }

    func showAlert(_ title: String, _ msg: String) {
        DispatchQueue.main.async {
            let a = NSAlert(); a.messageText = title; a.informativeText = msg; a.runModal()
        }
    }

    func promptInput(_ title: String, _ placeholder: String, completion: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert(); alert.messageText = title
            let tf = NSTextField(frame: NSRect(x:0,y:0,width:380,height:24))
            tf.placeholderString = placeholder; alert.accessoryView = tf
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: L("キャンセル","Cancel"))
            alert.window.initialFirstResponder = tf
            if alert.runModal() == .alertFirstButtonReturn, !tf.stringValue.isEmpty {
                completion(tf.stringValue)
            }
        }
    }

    func getLANIP() -> String {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
        p.arguments = ["getifaddr", "en0"]; p.standardOutput = pipe
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "127.0.0.1"
    }

    func getAPIKey() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return (try? String(contentsOf: home.appendingPathComponent(".local-ai-key"),
            encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "sk-ant-dummy"
    }

    private func openTerminalWith(_ cmd: String) {
        let escaped = cmd.replacingOccurrences(of: "\"", with: "\\\"")
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "tell application \"Terminal\" to do script \"\(escaped)\""]
        try? p.run()
    }

    // MARK: - First Launch

    private func firstLaunchCheck() {
        guard !UserDefaults.standard.bool(forKey: "sokora.launched") else { return }
        UserDefaults.standard.set(true, forKey: "sokora.launched")
        var missing: [String] = []
        if Self.which("cloudflared") == nil { missing.append("cloudflared") }
        guard !missing.isEmpty else { return }
        let hasBrew = Self.which("brew") != nil
        let alert = NSAlert()
        alert.messageText = L("Sokoraへようこそ！", "Welcome to Sokora!")
        alert.informativeText = L(
            "外部公開（DePIN）に必要な cloudflared がインストールされていません。\(hasBrew ? "\n「インストール」を押すと brew install cloudflared を実行します。" : "\n先に https://brew.sh から Homebrew をインストールしてください。")",
            "cloudflared (needed for DePIN) is not installed.\(hasBrew ? "\nClick 'Install' to run brew install cloudflared." : "\nFirst install Homebrew from https://brew.sh")"
        )
        if hasBrew { alert.addButton(withTitle: L("インストール","Install")) }
        alert.addButton(withTitle: L("後で","Later"))
        if hasBrew, alert.runModal() == .alertFirstButtonReturn {
            openTerminalWith("export PATH=/opt/homebrew/bin:$PATH && brew install cloudflared && echo '✅ Done'")
        }
    }

    // MARK: - Actions: Control

    @objc func startAll() {
        statusItem.button?.title = "🧠⏳"
        runShell("~/ai.sh start") { [weak self] out in
            Task { @MainActor in
                self?.refreshStatus()
                if !out.isEmpty { self?.showAlert(L("起動","Started"), out) }
            }
        }
    }

    @objc func stopAll() {
        runShell("~/ai.sh stop") { [weak self] _ in
            Task { @MainActor in self?.statusItem.button?.title = "🧠💤"; self?.refreshStatus() }
        }
    }

    @objc func restartAll() {
        statusItem.button?.title = "🧠⏳"
        runShell("~/ai.sh restart") { [weak self] out in
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    @objc func healthCheck() {
        runShell("~/ai.sh health 2>/dev/null || echo '...'") { [weak self] out in
            Task { @MainActor in
                self?.refreshStatus()
                self?.showAlert(L("ヘルスチェック","Health Check"), out.isEmpty ? L("正常","OK") : out)
            }
        }
    }

    // MARK: - Actions: Model Select

    @objc func selectModel(_ sender: NSMenuItem) {
        guard let presetID = sender.representedObject as? String,
              let preset = ModelRegistry.presets.first(where: { $0.id == presetID }) else { return }
        ModelRegistry.setActiveModel(slot: preset.slot, presetID: presetID)
        buildMenu()  // メニューを再構築して ✓ を更新
        showAlert(
            L("モデルを変更しました", "Model changed"),
            L("再起動で有効になります:\n\(preset.displayName)\n\(preset.mlxModelID)",
              "Restart to apply:\n\(preset.displayName)\n\(preset.mlxModelID)")
        )
    }

    // MARK: - Actions: AI Tools

    @objc func launchCld() {
        openTerminalWith("export PATH=/opt/homebrew/bin:$PATH && export ANTHROPIC_BASE_URL=http://127.0.0.1:4001 && export ANTHROPIC_API_KEY=sk-ant-dummy && claude --dangerously-skip-permissions")
    }

    @objc func launchClc() {
        openTerminalWith("export PATH=/opt/homebrew/bin:$PATH && unset ANTHROPIC_BASE_URL && claude")
    }

    @objc func launchAider() {
        openTerminalWith("export PATH=/opt/homebrew/bin:$PATH && source ~/mlx_env/bin/activate && OPENAI_API_BASE=http://127.0.0.1:4001/v1 OPENAI_API_KEY=sk-dummy aider --model openai/qwen3.5-122b")
    }

    @objc func openTerminal() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }

    @objc func openDashboard() {
        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:4001/")!)
    }

    // MARK: - Actions: Generate

    @objc func genImage() {
        promptInput(L("画像プロンプト","Image Prompt"), "a cyberpunk Tokyo street at night") { [weak self] prompt in
            self?.showAlert(L("生成中...","Generating..."), L("約17秒","~17 seconds"))
            self?.runShell("~/ai.sh img \"\(prompt)\"") { _ in
                self?.showAlert(L("完成！","Done!"), "~/generated/")
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("generated"))
                }
            }
        }
    }

    @objc func genVideo() {
        promptInput(L("動画プロンプト","Video Prompt"), "samurai on a cliff, sunset") { [weak self] prompt in
            self?.showAlert(L("生成中...","Generating..."), L("約10分","~10 min"))
            self?.runShell("~/ai.sh vid \"\(prompt)\"") { _ in
                self?.showAlert(L("完成！","Done!"), "~/generated/")
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("generated"))
                }
            }
        }
    }

    // MARK: - Actions: DePIN

    @objc func startDepin() {
        depinActive = true; preventSleep(); statusItem.button?.title = "🧠🌍"
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", "export PATH=/opt/homebrew/bin:$PATH && pkill -f cloudflared 2>/dev/null; sleep 1 && nohup cloudflared tunnel --url http://127.0.0.1:4001 > ~/cloudflared.log 2>&1 &"]
            try? p.run(); p.waitUntilExit()
            var url: String? = nil
            for _ in 0..<20 {
                sleep(2)
                let home = FileManager.default.homeDirectoryForCurrentUser
                if let log = try? String(contentsOf: home.appendingPathComponent("cloudflared.log"), encoding: .utf8),
                   let r = log.range(of: "https://[a-z0-9-]+\\.trycloudflare\\.com", options: .regularExpression) {
                    url = String(log[r]); break
                }
            }
            guard let tunnelURL = url else {
                Task { @MainActor in
                    self.depinActive = false; self.allowSleep()
                    self.showAlert(L("エラー","Error"), "brew install cloudflared")
                }
                return
            }
            self.registerNode(tunnelURL: tunnelURL)
        }
    }

    private func registerNode(tunnelURL: String) {
        let nodeID = UserDefaults.standard.string(forKey: "sokora.depin.nodeID") ?? {
            let n = "sokora-\(UUID().uuidString.prefix(8).lowercased())"
            UserDefaults.standard.set(n, forKey: "sokora.depin.nodeID"); return n
        }()
        let apiKey = UserDefaults.standard.string(forKey: "sokora.depin.apiKey") ?? {
            let k = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            UserDefaults.standard.set(k, forKey: "sokora.depin.apiKey"); return k
        }()
        let ram = ProcessInfo.processInfo.physicalMemory / (1024*1024*1024)
        guard let url = URL(string: "https://chatweb.ai/api/v1/nodes/register"),
              let body = try? JSONSerialization.data(withJSONObject: [
                "node_id": nodeID, "api_key": apiKey, "tunnel_url": tunnelURL,
                "ram_gb": ram, "models": ["main","fast","vision"], "version": "1.0.0"
              ]) else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"; req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
            Task { @MainActor in
                guard let self else { return }
                self.tunnelURL = tunnelURL; self.refreshStatus()
                self.showAlert(
                    L("🌍 DePIN起動！","🌍 DePIN Active!"),
                    "URL: \(tunnelURL)\n\nANTHROPIC_BASE_URL=\(tunnelURL)\nANTHROPIC_API_KEY=sk-ant-dummy"
                )
            }
        }.resume()
    }

    @objc func stopDepin() {
        depinActive = false; allowSleep(); tunnelURL = nil
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", "cloudflared"]; try? p.run(); p.waitUntilExit()
        Task { @MainActor in refreshStatus() }
    }

    @objc func depinStatus() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let log = (try? String(contentsOf: home.appendingPathComponent("cloudflared.log"), encoding: .utf8)) ?? ""
        let turl = tunnelURL ?? log.range(of: "https://[a-z0-9-]+\\.trycloudflare\\.com", options: .regularExpression).map { String(log[$0]) }
        let nodeID = UserDefaults.standard.string(forKey: "sokora.depin.nodeID") ?? "—"
        let running = Self.isProcessRunning("cloudflared")
        let idle = Self.getIdleSeconds()
        showAlert("DePIN", """
        \(running ? "● Running" : "○ Stopped")
        \(running ? (idle >= 300 ? "💰 Idle earning" : "🟢 Local priority") : "")
        Node ID: \(nodeID)
        URL: \(turl ?? "none")
        Idle: \(Int(idle))s
        """)
    }

    @objc func copyDepinInfo() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let log = (try? String(contentsOf: home.appendingPathComponent("cloudflared.log"), encoding: .utf8)) ?? ""
        guard let r = log.range(of: "https://[a-z0-9-]+\\.trycloudflare\\.com", options: .regularExpression) else {
            showAlert(L("Tunnelなし","No Tunnel"), L("先にDePINを起動","Start DePIN first")); return
        }
        let turl = String(log[r])
        let nodeID = UserDefaults.standard.string(forKey: "sokora.depin.nodeID") ?? "unknown"
        let info = "Node ID: \(nodeID)\nURL: \(turl)\n\nexport ANTHROPIC_BASE_URL=\(turl)\nexport ANTHROPIC_API_KEY=sk-ant-dummy\nclaude --dangerously-skip-permissions"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(info, forType: .string)
        showAlert(L("コピーしました","Copied!"), turl)
    }

    // MARK: - Actions: Connect

    @objc func startTunnel() {
        DispatchQueue.global().async { [weak self] in
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", "export PATH=/opt/homebrew/bin:$PATH && pkill -f cloudflared 2>/dev/null; sleep 1 && nohup cloudflared tunnel --url http://127.0.0.1:4001 > ~/cloudflared.log 2>&1 &"]
            try? p.run(); p.waitUntilExit(); sleep(6)
            let home = FileManager.default.homeDirectoryForCurrentUser
            if let log = try? String(contentsOf: home.appendingPathComponent("cloudflared.log"), encoding: .utf8),
               let r = log.range(of: "https://[a-z0-9-]+\\.trycloudflare\\.com", options: .regularExpression) {
                self?.showAlert(L("🚇 Tunnel起動！","🚇 Tunnel Active!"), String(log[r]))
            }
        }
    }

    @objc func stopTunnel() {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", "cloudflared"]; try? p.run(); p.waitUntilExit()
    }

    @objc func copyRemoteURL() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let log = (try? String(contentsOf: home.appendingPathComponent("cloudflared.log"), encoding: .utf8)) ?? ""
        guard let r = log.range(of: "https://[a-z0-9-]+\\.trycloudflare\\.com", options: .regularExpression) else {
            showAlert(L("Tunnelなし","No Tunnel"), L("先にTunnelを起動","Start tunnel first")); return
        }
        let url = String(log[r]); let key = getAPIKey()
        let info = "export ANTHROPIC_BASE_URL=\(url)\nexport ANTHROPIC_API_KEY=\(key)\nclaude --dangerously-skip-permissions"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(info, forType: .string)
        showAlert(L("コピーしました！","Copied!"), url)
    }

    @objc func copyURL() {
        let ip = getLANIP(); let key = getAPIKey()
        let info = "export ANTHROPIC_BASE_URL=http://\(ip):4001\nexport ANTHROPIC_API_KEY=\(key)\nclaude --dangerously-skip-permissions"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(info, forType: .string)
        showAlert(L("LAN URLをコピー","LAN URL Copied"), "http://\(ip):4001")
    }

    // MARK: - Actions: More

    @objc func runBench() {
        showAlert(L("ベンチマーク実行中...","Benchmarking..."), "~30s")
        runShell("~/ai.sh bench") { [weak self] out in
            self?.showAlert(L("結果","Results"), out.isEmpty ? "Done." : out)
        }
    }

    @objc func openLogs() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("sokora.log"))
    }

    @objc func openGenerated() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("generated")
        NSWorkspace.shared.open(FileManager.default.fileExists(atPath: dir.path) ? dir
            : FileManager.default.homeDirectoryForCurrentUser)
    }

    @objc func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/yukihamada/sokora")!)
    }

    @objc func quit() { allowSleep(); NSApp.terminate(nil) }
}
