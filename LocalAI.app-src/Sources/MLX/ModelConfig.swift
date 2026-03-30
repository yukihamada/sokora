import Foundation

struct BackendConfig {
    let name: String
    let mlxModel: String
    let port: Int
    let label: String
}

enum ModelRegistry {
    static let backends: [String: BackendConfig] = [
        "main": BackendConfig(name: "main", mlxModel: modelMain, port: portMain, label: "Qwen3.5-122B"),
        "fast": BackendConfig(name: "fast", mlxModel: modelFast, port: portFast, label: "Qwen3.5-35B"),
        "vision": BackendConfig(name: "vision", mlxModel: modelVision, port: portVision, label: "Qwen3-VL-8B"),
    ]

    static let modelMain = ProcessInfo.processInfo.environment["MLX_MODEL_MAIN"] ?? "mlx-community/Qwen3.5-122B-A10B-4bit"
    static let modelFast = ProcessInfo.processInfo.environment["MLX_MODEL_FAST"] ?? "mlx-community/Qwen3.5-35B-A3B-4bit"
    static let modelVision = ProcessInfo.processInfo.environment["MLX_MODEL_VISION"] ?? "mlx-community/Qwen3-VL-8B-Instruct-4bit"
    static let portMain = Int(ProcessInfo.processInfo.environment["MLX_PORT_MAIN"] ?? "5000") ?? 5000
    static let portFast = Int(ProcessInfo.processInfo.environment["MLX_PORT_FAST"] ?? "5001") ?? 5001
    static let portVision = Int(ProcessInfo.processInfo.environment["MLX_PORT_VISION"] ?? "5002") ?? 5002
    static let proxyPort = Int(ProcessInfo.processInfo.environment["PROXY_PORT"] ?? "4001") ?? 4001

    // Anthropic model name -> backend key
    static let anthropicRoutes: [String: String] = [
        "claude-sonnet-4-6": "main",
        "claude-sonnet-4-6-20250514": "main",
        "claude-opus-4-6": "main",
        "claude-opus-4-6-20250514": "main",
        "claude-3-5-sonnet-20241022": "main",
        "claude-3-5-sonnet-latest": "main",
        "claude-haiku-4-5-20251001": "fast",
        "claude-3-5-haiku-latest": "fast",
    ]

    // OpenAI-style model name prefixes -> backend key
    static let openaiPrefixes: [(String, String)] = [
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
