import Foundation
import Hummingbird

struct DashboardHandler {
    static func handleRoot(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let html = DashboardHTML.content
        return Response(
            status: .ok,
            headers: [.contentType: "text/html; charset=utf-8"],
            body: .init(byteBuffer: .init(string: html))
        )
    }
}
