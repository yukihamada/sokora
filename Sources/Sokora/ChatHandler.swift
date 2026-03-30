import Foundation
import Hummingbird
import Logging

// MARK: - JSON Helpers

private let jsonEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = []
    return e
}()

private let jsonDecoder = JSONDecoder()

// MARK: - Sendable encoder helper

/// Encodes a ChatCompletionChunk to an SSE `data:` line ByteBuffer.
/// Declared as a free function so it can be `@Sendable`-captured safely.
private func sseBuffer(for chunk: ChatCompletionChunk) -> ByteBuffer? {
    guard let data = try? jsonEncoder.encode(chunk),
          let json = String(data: data, encoding: .utf8)
    else { return nil }
    return ByteBuffer(string: "data: \(json)\n\n")
}

// MARK: - Chat Completion Handler

/// Handles POST /v1/chat/completions
/// Supports both streaming (SSE) and non-streaming responses.
struct ChatHandler: Sendable {
    let modelManager: ModelManager
    let config: SokoraConfig
    let logger: Logger

    // MARK: - Entry Point

    func handle(_ request: Request, context: some RequestContext) async throws -> Response {
        // Collect request body bytes
        var collected = ByteBuffer()
        for try await chunk in request.body {
            var mutableChunk = chunk
            collected.writeBuffer(&mutableChunk)
        }

        let chatRequest: ChatCompletionRequest
        do {
            chatRequest = try jsonDecoder.decode(ChatCompletionRequest.self, from: collected)
        } catch {
            return errorResponse(
                message: "Invalid request: \(error.localizedDescription)",
                status: .badRequest
            )
        }

        guard !chatRequest.messages.isEmpty else {
            return errorResponse(message: "messages array must not be empty", status: .badRequest)
        }

        let messages = chatRequest.messages.map { ["role": $0.role, "content": $0.content] }
        let maxTokens = chatRequest.maxTokens ?? config.maxTokens
        let temperature = Float(chatRequest.temperature ?? config.temperature)
        let topP = Float(chatRequest.topP ?? config.topP)
        let completionId = "chatcmpl-\(UUID().uuidString)"
        let modelName = chatRequest.model.isEmpty ? config.model : chatRequest.model
        let created = Int(Date().timeIntervalSince1970)
        let isStream = chatRequest.stream ?? false

        if isStream {
            return streamingResponse(
                completionId: completionId,
                modelName: modelName,
                created: created,
                messages: messages,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP
            )
        } else {
            return try await blockingResponse(
                completionId: completionId,
                modelName: modelName,
                created: created,
                messages: messages,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP
            )
        }
    }

    // MARK: - Non-streaming

    private func blockingResponse(
        completionId: String,
        modelName: String,
        created: Int,
        messages: [[String: String]],
        maxTokens: Int,
        temperature: Float,
        topP: Float
    ) async throws -> Response {
        // Use an actor-isolated accumulator to safely collect tokens from the
        // Sendable callback without data races.
        let accumulator = TokenAccumulator()

        let stats: (promptTokens: Int, completionTokens: Int)
        do {
            stats = try await modelManager.generate(
                messages: messages,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP
            ) { token in
                accumulator.append(token)
            }
        } catch {
            logger.error("Inference error: \(error)")
            return errorResponse(
                message: "Inference failed: \(error.localizedDescription)",
                status: .internalServerError
            )
        }

        let fullText = accumulator.text

        let response = ChatCompletionResponse(
            id: completionId,
            object: "chat.completion",
            created: created,
            model: modelName,
            choices: [
                ChatCompletionChoice(
                    index: 0,
                    message: ChatMessage(role: "assistant", content: fullText),
                    finishReason: "stop"
                )
            ],
            usage: UsageInfo(
                promptTokens: stats.promptTokens,
                completionTokens: stats.completionTokens,
                totalTokens: stats.promptTokens + stats.completionTokens
            )
        )

        let data: Data
        do {
            data = try jsonEncoder.encode(response)
        } catch {
            return errorResponse(message: "Encoding failed", status: .internalServerError)
        }

        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(data: data))
        )
    }

    // MARK: - Streaming (SSE)

    private func streamingResponse(
        completionId: String,
        modelName: String,
        created: Int,
        messages: [[String: String]],
        maxTokens: Int,
        temperature: Float,
        topP: Float
    ) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        headers[.connection] = "keep-alive"

        // Capture all values the inference task needs
        let capturedManager = modelManager
        let capturedLogger = logger
        let capturedId = completionId
        let capturedModel = modelName
        let capturedCreated = created

        // Create a back-pressure-safe AsyncStream
        let (stream, continuation) = AsyncStream<ByteBuffer>.makeStream()

        // First chunk announces the assistant role
        let firstChunk = ChatCompletionChunk(
            id: capturedId,
            object: "chat.completion.chunk",
            created: capturedCreated,
            model: capturedModel,
            choices: [
                ChatCompletionChunkChoice(
                    index: 0,
                    delta: ChatCompletionDelta(role: "assistant", content: nil),
                    finishReason: nil
                )
            ]
        )
        if let buf = sseBuffer(for: firstChunk) {
            continuation.yield(buf)
        }

        // Launch inference detached so we return the Response without waiting
        Task.detached {
            do {
                _ = try await capturedManager.generate(
                    messages: messages,
                    maxTokens: maxTokens,
                    temperature: temperature,
                    topP: topP
                ) { token in
                    let tokenChunk = ChatCompletionChunk(
                        id: capturedId,
                        object: "chat.completion.chunk",
                        created: capturedCreated,
                        model: capturedModel,
                        choices: [
                            ChatCompletionChunkChoice(
                                index: 0,
                                delta: ChatCompletionDelta(role: nil, content: token),
                                finishReason: nil
                            )
                        ]
                    )
                    if let buf = sseBuffer(for: tokenChunk) {
                        continuation.yield(buf)
                    }
                }
            } catch {
                capturedLogger.error("Streaming inference error: \(error)")
            }

            // Final chunk: finish_reason = stop
            let finalChunk = ChatCompletionChunk(
                id: capturedId,
                object: "chat.completion.chunk",
                created: capturedCreated,
                model: capturedModel,
                choices: [
                    ChatCompletionChunkChoice(
                        index: 0,
                        delta: ChatCompletionDelta(role: nil, content: nil),
                        finishReason: "stop"
                    )
                ]
            )
            if let buf = sseBuffer(for: finalChunk) {
                continuation.yield(buf)
            }

            continuation.yield(ByteBuffer(string: "data: [DONE]\n\n"))
            continuation.finish()
        }

        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(asyncSequence: stream)
        )
    }

    // MARK: - Error helper

    private func errorResponse(message: String, status: HTTPResponse.Status) -> Response {
        let errorResp = ErrorResponse(
            error: ErrorDetail(message: message, type: "server_error", code: nil)
        )
        let data = (try? jsonEncoder.encode(errorResp))
            ?? Data(#"{"error":{"message":"unknown","type":"server_error"}}"#.utf8)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: status,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(data: data))
        )
    }
}

// MARK: - Thread-safe token accumulator

/// A class (reference type) used to safely collect tokens from a
/// non-isolated `@Sendable` callback via a lock.
final class TokenAccumulator: @unchecked Sendable {
    private var _text: String = ""
    private let lock = NSLock()

    func append(_ token: String) {
        lock.lock()
        defer { lock.unlock() }
        _text += token
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return _text
    }
}
