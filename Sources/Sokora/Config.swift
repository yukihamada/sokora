import Foundation

struct SokoraConfig: Sendable {
    var model: String
    var port: Int
    var host: String
    var maxTokens: Int
    var kvBits: Int?          // nil = no quantization, 4 = TurboQuant LEAN
    var kvGroupSize: Int
    var cacheMode: CacheMode  // .standard, .quantized, .streaming, .h2o
    var streamingSink: Int    // StreamingLLM sink tokens
    var streamingWindow: Int  // StreamingLLM window size
    var h2oHeavyHitters: Int
    var h2oRecent: Int
    var chatweb: String       // chatweb.ai base URL for registration
    var tunnelURL: String?    // Cloudflare tunnel URL (set by cloudflared)
    var temperature: Double
    var topP: Double
    var registerOnStart: Bool

    enum CacheMode: String, Sendable {
        case standard   = "standard"
        case quantized  = "quantized"   // TurboQuant LEAN (kvBits built-in)
        case streaming  = "streaming"   // RotatingKVCache
        case h2o        = "h2o"         // Heavy-Hitter Oracle
    }

    static func fromEnv() -> SokoraConfig {
        func env(_ key: String, _ defaultValue: String) -> String {
            ProcessInfo.processInfo.environment[key] ?? defaultValue
        }
        func envInt(_ key: String, _ def: Int) -> Int {
            Int(ProcessInfo.processInfo.environment[key] ?? "") ?? def
        }
        let modeStr = env("SOKORA_CACHE_MODE", "quantized")
        let rawKvBits = envInt("SOKORA_KV_BITS", 4)
        return SokoraConfig(
            model:            env("SOKORA_MODEL", "mlx-community/Qwen3-8B-4bit"),
            port:             envInt("SOKORA_PORT", 5001),
            host:             env("SOKORA_HOST", "127.0.0.1"),
            maxTokens:        envInt("SOKORA_MAX_TOKENS", 2048),
            kvBits:           rawKvBits == 0 ? nil : rawKvBits,
            kvGroupSize:      envInt("SOKORA_KV_GROUP_SIZE", 64),
            cacheMode:        CacheMode(rawValue: modeStr) ?? .quantized,
            streamingSink:    envInt("SOKORA_STREAMING_SINK", 4),
            streamingWindow:  envInt("SOKORA_STREAMING_WINDOW", 1020),
            h2oHeavyHitters:  envInt("SOKORA_H2O_HH", 64),
            h2oRecent:        envInt("SOKORA_H2O_RECENT", 512),
            chatweb:          env("SOKORA_CHATWEB_URL", "https://chatweb-ai.fly.dev"),
            tunnelURL:        ProcessInfo.processInfo.environment["SOKORA_TUNNEL_URL"],
            temperature:      Double(env("SOKORA_TEMPERATURE", "0.6")) ?? 0.6,
            topP:             Double(env("SOKORA_TOP_P", "1.0")) ?? 1.0,
            registerOnStart:  env("SOKORA_REGISTER", "1") == "1"
        )
    }
}
