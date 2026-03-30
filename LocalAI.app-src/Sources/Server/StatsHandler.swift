import Foundation
import Hummingbird

struct StatsHandler {
    static func handle(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let snap = await RequestStats.shared.snapshot()
        let body = try JSONSerialization.data(withJSONObject: snap)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: body))
        )
    }
}
