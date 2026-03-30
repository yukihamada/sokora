import Foundation

/// グローバルリクエスト統計（スレッドセーフ）
actor RequestStats {
    static let shared = RequestStats()
    private init() {}

    private(set) var totalRequests: Int = 0
    private(set) var depinRequests: Int = 0   // Cloudflare経由の外部リクエスト
    private(set) var totalTokensOut: Int = 0
    private(set) var lastTokPerSec: Double = 0
    private var recentTps: [Double] = []
    let startTime: Date = Date()

    func record(isExternal: Bool, outputTokens: Int, elapsed: TimeInterval) {
        totalRequests += 1
        if isExternal { depinRequests += 1 }
        totalTokensOut += outputTokens
        if elapsed > 0, outputTokens > 0 {
            let tps = Double(outputTokens) / elapsed
            recentTps.append(tps)
            if recentTps.count > 10 { recentTps.removeFirst() }
            lastTokPerSec = recentTps.reduce(0, +) / Double(recentTps.count)
        }
    }

    func snapshot() -> [String: Any] {
        [
            "total_requests": totalRequests,
            "depin_requests": depinRequests,
            "total_tokens_out": totalTokensOut,
            "tok_per_sec": String(format: "%.1f", lastTokPerSec),
            "uptime_seconds": Int(Date().timeIntervalSince(startTime))
        ]
    }
}
