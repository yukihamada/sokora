import Foundation
import Hummingbird
import Logging

// MARK: - Server Entry Point

func runServer(
    config: SokoraConfig,
    modelManager: ModelManager,
    logger: Logger
) async throws {
    let handler = ChatHandler(modelManager: modelManager, config: config, logger: logger)
    let router = buildRouter(config: config, handler: handler, logger: logger)

    let app = Application(
        router: router,
        configuration: ApplicationConfiguration(
            address: .hostname(config.host, port: config.port),
            serverName: "Sokora/1.0"
        ),
        logger: logger
    )

    logger.info("Sokora server listening on \(config.host):\(config.port)")
    try await app.runService()
}

// MARK: - Router

private func buildRouter(
    config: SokoraConfig,
    handler: ChatHandler,
    logger: Logger
) -> Router<BasicRequestContext> {
    let router = Router(context: BasicRequestContext.self)

    // Request logging middleware
    router.middlewares.add(LogRequestsMiddleware(.info))

    // MARK: Health check
    router.get("/health") { _, _ -> Response in
        let body = #"{"status":"ok","model":"\#(config.model)","version":"1.0.0-swift"}"#
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(string: body))
        )
    }

    // MARK: OpenAI /v1/models
    router.get("/v1/models") { _, _ -> Response in
        let created = Int(Date().timeIntervalSince1970)
        let modelsResponse = ModelsListResponse(
            object: "list",
            data: [
                ModelObject(
                    id: config.model,
                    object: "model",
                    created: created,
                    ownedBy: "sokora"
                )
            ]
        )
        let encoder = JSONEncoder()
        let data = (try? encoder.encode(modelsResponse)) ?? Data()
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(data: data))
        )
    }

    // MARK: Chat completions
    router.post("/v1/chat/completions") { request, context -> Response in
        try await handler.handle(request, context: context)
    }

    // MARK: Root info
    router.get("/") { _, _ -> Response in
        let body = #"{"service":"sokora","description":"Apple Silicon LLM inference node","docs":"/v1/models"}"#
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(string: body))
        )
    }

    return router
}
