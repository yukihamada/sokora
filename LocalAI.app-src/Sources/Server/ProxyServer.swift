import Foundation
import Hummingbird

actor ProxyServer {
    func start() async {
        let router = Router()
        // Health
        router.get("/health", use: HealthHandler.handle)
        // Anthropic API
        router.post("/v1/messages/count_tokens", use: ProxyHandler.handleCountTokens)
        router.post("/v1/messages", use: ProxyHandler.handleMessages)
        // OpenAI compatible
        router.post("/v1/chat/completions", use: ProxyHandler.handleChatCompletions)
        router.get("/v1/models", use: ProxyHandler.handleModels)
        // Dashboard
        router.get("/", use: DashboardHandler.handleRoot)
        router.get("/api/models", use: ModelsHandler.handleList)
        router.get("/api/logs", use: ModelsHandler.handleLogs)

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("0.0.0.0", port: ModelRegistry.proxyPort))
        )
        print("[Proxy] Starting on :\(ModelRegistry.proxyPort)")
        try? await app.run()
    }
}
