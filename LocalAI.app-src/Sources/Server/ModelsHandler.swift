import Foundation
import Hummingbird

struct ModelsHandler {
    static func handleList(_ request: Request, _ context: some RequestContext) async throws -> Response {
        var result: [[String: Any]] = []
        await withTaskGroup(of: (String, BackendConfig, Bool).self) { group in
            for (name, cfg) in ModelRegistry.backends {
                group.addTask {
                    let alive = await HealthHandler.isAlive(port: cfg.port)
                    return (name, cfg, alive)
                }
            }
            for await (name, cfg, alive) in group {
                result.append([
                    "name": name,
                    "model": cfg.mlxModel,
                    "port": cfg.port,
                    "label": cfg.label,
                    "running": alive
                ])
            }
        }
        result.sort { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
        let out = try JSONSerialization.data(withJSONObject: result)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: out))
        )
    }

    static func handleLogs(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("proxy.log")
        let content = (try? String(contentsOf: logPath, encoding: .utf8)) ?? ""
        let lines = content.components(separatedBy: "\n").suffix(100)
        let sseLines = lines.map { "data: \($0)\n" }.joined() + "\n"
        return Response(
            status: .ok,
            headers: [.contentType: "text/event-stream"],
            body: .init(byteBuffer: .init(string: sseLines))
        )
    }
}
