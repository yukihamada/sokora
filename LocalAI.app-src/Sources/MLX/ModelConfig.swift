import Foundation

struct BackendConfig {
    let name: String
    let mlxModel: String
    let port: Int
    let label: String
}

struct ModelPreset {
    let id: String
    let displayName: String
    let mlxModelID: String
    let ramGB: Int
    let slot: String  // "main" | "fast" | "vision"
}

enum ModelRegistry {

    // MARK: - Preset Catalog

    static let presets: [ModelPreset] = [
        // Main (高品質)
        ModelPreset(id: "qwen122b",   displayName: "Qwen3.5-122B (高品質)",  mlxModelID: "mlx-community/Qwen3.5-122B-A10B-4bit",        ramGB: 60, slot: "main"),
        ModelPreset(id: "deepseekv4", displayName: "DeepSeek-V4 (最高品質)", mlxModelID: "mlx-community/DeepSeek-V4-4bit",               ramGB: 80, slot: "main"),
        ModelPreset(id: "qwen14b",    displayName: "Qwen3-14B (中品質)",     mlxModelID: "mlx-community/Qwen3-14B-4bit",                 ramGB: 9,  slot: "main"),
        // Fast (高速)
        ModelPreset(id: "qwen35b",    displayName: "Qwen3.5-35B (高速)",     mlxModelID: "mlx-community/Qwen3.5-35B-A3B-4bit",           ramGB: 8,  slot: "fast"),
        ModelPreset(id: "qwen9b",     displayName: "Qwen3.5-9B (軽量)",      mlxModelID: "mlx-community/Qwen3.5-9B-4bit",                ramGB: 5,  slot: "fast"),
        ModelPreset(id: "qwen4b",     displayName: "Qwen3.5-4B (超軽量)",    mlxModelID: "mlx-community/Qwen3.5-4B-4bit",                ramGB: 3,  slot: "fast"),
        // Vision
        ModelPreset(id: "vl8b",       displayName: "Qwen3-VL-8B (ビジョン)", mlxModelID: "mlx-community/Qwen3-VL-8B-Instruct-4bit",      ramGB: 5,  slot: "vision"),
        ModelPreset(id: "vl4b",       displayName: "Qwen3-VL-4B (軽量VL)",   mlxModelID: "mlx-community/Qwen3-VL-4B-Instruct-4bit",      ramGB: 3,  slot: "vision"),
    ]

    // MARK: - Active Model Selection (UserDefaults)

    static func activeModelID(slot: String) -> String {
        let defaults = ["main": "qwen122b", "fast": "qwen35b", "vision": "vl8b"]
        return UserDefaults.standard.string(forKey: "sokora.model.\(slot)") ?? defaults[slot] ?? "qwen122b"
    }

    static func setActiveModel(slot: String, presetID: String) {
        UserDefaults.standard.set(presetID, forKey: "sokora.model.\(slot)")
        // ai.sh 用の環境変数ファイルを更新
        updateEnvFile()
    }

    static func activePreset(slot: String) -> ModelPreset {
        let id = activeModelID(slot: slot)
        return presets.first(where: { $0.id == id && $0.slot == slot })
            ?? presets.first(where: { $0.slot == slot })!
    }

    /// ~/.sokora_env に環境変数を書き出す（ai.sh が source して使う）
    private static func updateEnvFile() {
        let main   = activePreset(slot: "main").mlxModelID
        let fast   = activePreset(slot: "fast").mlxModelID
        let vision = activePreset(slot: "vision").mlxModelID
        let content = """
        export MLX_MODEL_MAIN="\(main)"
        export MLX_MODEL_FAST="\(fast)"
        export MLX_MODEL_VISION="\(vision)"
        """
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sokora_env")
        try? content.write(to: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Dynamic Backends (reads UserDefaults)

    static var backends: [String: BackendConfig] {
        let mainPreset   = activePreset(slot: "main")
        let fastPreset   = activePreset(slot: "fast")
        let visionPreset = activePreset(slot: "vision")
        return [
            "main":   BackendConfig(name: "main",   mlxModel: mainPreset.mlxModelID,   port: portMain,   label: mainPreset.displayName),
            "fast":   BackendConfig(name: "fast",   mlxModel: fastPreset.mlxModelID,   port: portFast,   label: fastPreset.displayName),
            "vision": BackendConfig(name: "vision", mlxModel: visionPreset.mlxModelID, port: portVision, label: visionPreset.displayName),
        ]
    }

    static let portMain   = Int(ProcessInfo.processInfo.environment["MLX_PORT_MAIN"]   ?? "5000") ?? 5000
    static let portFast   = Int(ProcessInfo.processInfo.environment["MLX_PORT_FAST"]   ?? "5001") ?? 5001
    static let portVision = Int(ProcessInfo.processInfo.environment["MLX_PORT_VISION"] ?? "5002") ?? 5002
    static let proxyPort  = Int(ProcessInfo.processInfo.environment["PROXY_PORT"]      ?? "4001") ?? 4001

    // MARK: - Routing

    static let anthropicRoutes: [String: String] = [
        "claude-sonnet-4-6": "main",
        "claude-sonnet-4-6-20250514": "main",
        "claude-opus-4-6": "main",
        "claude-opus-4-6-20250514": "main",
        "claude-3-5-sonnet-20241022": "main",
        "claude-3-5-sonnet-latest": "main",
        "claude-haiku-4-5-20251001": "fast",
        "claude-3-5-haiku-latest": "fast",
        "deepseek-chat": "main",
        "deepseek-v4": "main",
    ]

    static let openaiPrefixes: [(String, String)] = [
        ("deepseek", "main"),
        ("qwen3.5-122b", "main"),
        ("qwen3.5-35b", "fast"),
        ("qwen3-vl-8b", "vision"),
        ("gpt-4o-mini", "fast"),
        ("gpt-4", "main"),
        ("gpt-3.5", "fast"),
    ]

    static func backend(for anthropicModel: String, hasImages: Bool = false) -> BackendConfig {
        if hasImages { return backends["vision"] ?? backends["main"]! }
        let key = anthropicRoutes[anthropicModel] ?? "main"
        return backends[key] ?? backends["main"]!
    }

    static func backendOpenAI(for model: String, hasImages: Bool = false) -> BackendConfig {
        if hasImages { return backends["vision"] ?? backends["main"]! }
        let lower = model.lowercased().replacingOccurrences(of: "openai/", with: "")
        for (prefix, key) in openaiPrefixes {
            if lower.hasPrefix(prefix) { return backends[key] ?? backends["main"]! }
        }
        return backend(for: model, hasImages: hasImages)
    }
}
