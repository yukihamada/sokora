import Foundation
import Hummingbird

struct HealthHandler {
    static func handle(_ request: Request, _ context: some RequestContext) async throws -> Response {
        var models: [String: Bool] = [:]
        await withTaskGroup(of: (String, Bool).self) { group in
            for (name, cfg) in ModelRegistry.backends {
                group.addTask {
                    let alive = await isAlive(port: cfg.port)
                    return (name, alive)
                }
            }
            for await (name, alive) in group {
                models[name] = alive
            }
        }
        let body = try JSONSerialization.data(withJSONObject: ["status": "ok", "models": models])
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: body))
        )
    }

    static func isAlive(port: Int) async -> Bool {
        do {
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/models")!)
            req.timeoutInterval = 3
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
