import Foundation
import Hummingbird
import NIOCore

struct ProxyHandler {
    // MARK: - POST /v1/messages
    static func handleMessages(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let buf = try await request.body.collect(upTo: 50_000_000)
        guard let data = buf.getData(at: 0, length: buf.readableBytes),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Response(status: .badRequest)
        }
        let model = body["model"] as? String ?? "claude-sonnet-4-6"
        let stream = body["stream"] as? Bool ?? false
        let messages = body["messages"] as? [[String: Any]] ?? []
        let hasImg = hasImages(messages)
        let backend = ModelRegistry.backend(for: model, hasImages: hasImg)
        let mlxURL = URL(string: "http://127.0.0.1:\(backend.port)/v1/chat/completions")!

        print("[Proxy] POST /v1/messages model=\(model) -> \(backend.label) stream=\(stream)")

        var oaiBody: [String: Any] = [
            "model": backend.mlxModel,
            "messages": convertMessages(messages, system: body["system"]),
            "max_tokens": body["max_tokens"] as? Int ?? 4096,
            "chat_template_kwargs": ["enable_thinking": false],
        ]
        if let temp = body["temperature"] { oaiBody["temperature"] = temp }
        if let tools = body["tools"] as? [[String: Any]] {
            oaiBody["tools"] = convertTools(tools)
        }

        if stream {
            return try await handleAnthropicStream(oaiBody: oaiBody, model: model, mlxURL: mlxURL)
        } else {
            return try await handleAnthropicNonStream(oaiBody: oaiBody, model: model, mlxURL: mlxURL)
        }
    }

    // MARK: - POST /v1/chat/completions (OpenAI passthrough for Aider)
    static func handleChatCompletions(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let buf = try await request.body.collect(upTo: 50_000_000)
        guard let data = buf.getData(at: 0, length: buf.readableBytes),
              var body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Response(status: .badRequest)
        }
        let model = body["model"] as? String ?? "qwen3.5-122b"
        let stream = body["stream"] as? Bool ?? false
        let messages = body["messages"] as? [[String: Any]] ?? []
        let backend = ModelRegistry.backendOpenAI(for: model)
        let mlxURL = URL(string: "http://127.0.0.1:\(backend.port)/v1/chat/completions")!

        print("[Proxy] POST /v1/chat/completions model=\(model) -> \(backend.label) stream=\(stream)")

        body["model"] = backend.mlxModel
        body["chat_template_kwargs"] = ["enable_thinking": false] as [String: Any]

        // Merge system messages to front
        if let msgs = body["messages"] as? [[String: Any]] {
            let sysParts = msgs.filter { $0["role"] as? String == "system" }.compactMap { $0["content"] as? String }
            let nonSys = msgs.filter { $0["role"] as? String != "system" }
            if !sysParts.isEmpty {
                body["messages"] = [["role": "system", "content": sysParts.joined(separator: "\n\n")]] + nonSys
            } else {
                body["messages"] = nonSys
            }
        }
        // Remove litellm-specific fields
        for key in ["user", "logprobs", "top_logprobs", "n"] { body.removeValue(forKey: key) }

        let fwdData = try JSONSerialization.data(withJSONObject: body)
        var req = URLRequest(url: mlxURL)
        req.httpMethod = "POST"
        req.httpBody = fwdData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 600

        if !stream {
            let (respData, httpResp) = try await URLSession.shared.data(for: req)
            var respBody = (try? JSONSerialization.jsonObject(with: respData)) as? [String: Any] ?? [:]
            respBody["model"] = model
            let outData = try JSONSerialization.data(withJSONObject: respBody)
            let status = HTTPResponse.Status(
                code: (httpResp as? HTTPURLResponse)?.statusCode ?? 200
            )
            return Response(
                status: status,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(data: outData))
            )
        }

        return try await passthroughStream(req: req)
    }

    // MARK: - GET /v1/models
    static func handleModels(_ request: Request, _ context: some RequestContext) async throws -> Response {
        var models: [[String: Any]] = []
        for m in ModelRegistry.anthropicRoutes.keys {
            models.append(["id": m, "object": "model", "created": 1677610602, "owned_by": "anthropic"])
        }
        for (prefix, _) in ModelRegistry.openaiPrefixes {
            models.append(["id": prefix, "object": "model", "created": 1677610602, "owned_by": "local-mlx"])
        }
        for (_, cfg) in ModelRegistry.backends {
            models.append(["id": cfg.mlxModel, "object": "model", "created": 1677610602, "owned_by": "local-mlx"])
        }
        let out = try JSONSerialization.data(withJSONObject: ["data": models, "object": "list"])
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: out))
        )
    }

    // MARK: - POST /v1/messages/count_tokens
    static func handleCountTokens(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let buf = try await request.body.collect(upTo: 10_000_000)
        guard let data = buf.getData(at: 0, length: buf.readableBytes),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Response(status: .badRequest)
        }
        let msgs = convertMessages(body["messages"] as? [[String: Any]] ?? [], system: body["system"])
        let total = msgs.reduce(0) { acc, m in
            acc + ((m["content"] as? String)?.count ?? 0) / 4
        }
        let out = try JSONSerialization.data(withJSONObject: ["input_tokens": total])
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: out))
        )
    }

    // MARK: - Non-streaming Anthropic
    private static func handleAnthropicNonStream(
        oaiBody: [String: Any],
        model: String,
        mlxURL: URL
    ) async throws -> Response {
        let fwdData = try JSONSerialization.data(withJSONObject: oaiBody)
        var req = URLRequest(url: mlxURL)
        req.httpMethod = "POST"
        req.httpBody = fwdData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 600
        let (respData, _) = try await URLSession.shared.data(for: req)
        guard let oaiResp = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] else {
            return Response(status: .internalServerError)
        }
        let anthropicResp = oaiResponseToAnthropic(oaiResp, model: model)
        let out = try JSONSerialization.data(withJSONObject: anthropicResp)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: out))
        )
    }

    // MARK: - Streaming Anthropic (SSE)
    private static func handleAnthropicStream(
        oaiBody: [String: Any],
        model: String,
        mlxURL: URL
    ) async throws -> Response {
        var streamBody = oaiBody
        streamBody["stream"] = true
        let fwdData = try JSONSerialization.data(withJSONObject: streamBody)
        var req = URLRequest(url: mlxURL)
        req.httpMethod = "POST"
        req.httpBody = fwdData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 600

        let msgId = "msg_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24))"
        let capturedModel = model
        let (asyncBytes, _) = try await URLSession.shared.bytes(for: req)

        let responseBody = ResponseBody { writer in
            let startEvt = AnthropicSSE.messageStart(id: msgId, model: capturedModel)
            try await writer.write(ByteBuffer(string: startEvt))

            var contentIndex = 0
            var textBlockStarted = false
            struct ToolCall {
                var id: String
                var name: String
                var args: String
                var blockIdx: Int
            }
            var toolCalls: [Int: ToolCall] = [:]

            for try await line in asyncBytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let dataStr = String(line.dropFirst(6))
                if dataStr == "[DONE]" { break }
                guard
                    let chunkData = dataStr.data(using: .utf8),
                    let chunk = try? JSONSerialization.jsonObject(with: chunkData) as? [String: Any],
                    let choices = chunk["choices"] as? [[String: Any]],
                    let delta = choices.first?["delta"] as? [String: Any]
                else { continue }

                // Text delta
                if let text = delta["content"] as? String, !text.isEmpty {
                    if !textBlockStarted {
                        let blkStart = AnthropicSSE.contentBlockStart(index: contentIndex, type: "text")
                        try await writer.write(ByteBuffer(string: blkStart))
                        textBlockStarted = true
                    }
                    let textEvt = AnthropicSSE.textDelta(index: contentIndex, text: text)
                    try await writer.write(ByteBuffer(string: textEvt))
                }

                // Tool calls
                if let tcs = delta["tool_calls"] as? [[String: Any]] {
                    for tc in tcs {
                        let idx = tc["index"] as? Int ?? 0
                        let func_ = tc["function"] as? [String: Any] ?? [:]
                        if toolCalls[idx] == nil {
                            if textBlockStarted {
                                let blkStop = AnthropicSSE.contentBlockStop(index: contentIndex)
                                try await writer.write(ByteBuffer(string: blkStop))
                                contentIndex += 1
                                textBlockStarted = false
                            }
                            let toolId = "toolu_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24))"
                            let toolName = func_["name"] as? String ?? ""
                            let blkStart = AnthropicSSE.contentBlockStart(
                                index: contentIndex, type: "tool_use", id: toolId, name: toolName
                            )
                            try await writer.write(ByteBuffer(string: blkStart))
                            toolCalls[idx] = ToolCall(id: toolId, name: toolName, args: "", blockIdx: contentIndex)
                            contentIndex += 1
                        }
                        if let args = func_["arguments"] as? String, !args.isEmpty {
                            let blkIdx = toolCalls[idx]!.blockIdx
                            toolCalls[idx]!.args += args
                            let jsonDelta = AnthropicSSE.inputJsonDelta(index: blkIdx, partial: args)
                            try await writer.write(ByteBuffer(string: jsonDelta))
                        }
                    }
                }
            }

            // Close open blocks
            if textBlockStarted {
                let stopIdx = contentIndex
                let blkStop = AnthropicSSE.contentBlockStop(index: stopIdx)
                try await writer.write(ByteBuffer(string: blkStop))
            }
            for (_, tc) in toolCalls {
                let blkStop = AnthropicSSE.contentBlockStop(index: tc.blockIdx)
                try await writer.write(ByteBuffer(string: blkStop))
            }

            let stopReason = toolCalls.isEmpty ? "end_turn" : "tool_use"
            let msgDelta = AnthropicSSE.messageDelta(stopReason: stopReason)
            try await writer.write(ByteBuffer(string: msgDelta))
            let msgStop = AnthropicSSE.messageStop()
            try await writer.write(ByteBuffer(string: msgStop))
            try await writer.finish(nil)
        }

        return Response(
            status: .ok,
            headers: [.contentType: "text/event-stream", .cacheControl: "no-cache"],
            body: responseBody
        )
    }

    // MARK: - Passthrough stream for OpenAI
    private static func passthroughStream(req: URLRequest) async throws -> Response {
        let (asyncBytes, _) = try await URLSession.shared.bytes(for: req)
        let responseBody = ResponseBody { writer in
            for try await line in asyncBytes.lines {
                if !line.isEmpty {
                    try await writer.write(ByteBuffer(string: line + "\n"))
                }
            }
            try await writer.finish(nil)
        }
        return Response(
            status: .ok,
            headers: [.contentType: "text/event-stream", .cacheControl: "no-cache"],
            body: responseBody
        )
    }

    // MARK: - Conversion helpers

    static func hasImages(_ messages: [[String: Any]]) -> Bool {
        for msg in messages {
            if let content = msg["content"] as? [[String: Any]] {
                for block in content {
                    let t = block["type"] as? String ?? ""
                    if t == "image" || t == "image_url" { return true }
                }
            }
        }
        return false
    }

    static func convertMessages(_ messages: [[String: Any]], system: Any?) -> [[String: Any]] {
        var oai: [[String: Any]] = []
        if let sys = system {
            var sysText = ""
            if let s = sys as? String { sysText = s }
            else if let arr = sys as? [[String: Any]] {
                sysText = arr.compactMap { $0["text"] as? String }.joined(separator: " ")
            }
            if !sysText.isEmpty { oai.append(["role": "system", "content": sysText]) }
        }
        for msg in messages {
            let role = msg["role"] as? String ?? "user"
            let content = msg["content"]

            if let s = content as? String {
                oai.append(["role": role, "content": s])
                continue
            }
            guard let arr = content as? [[String: Any]] else { continue }

            var textParts: [String] = []
            var imageParts: [[String: Any]] = []
            var toolCalls: [[String: Any]] = []
            var toolResults: [[String: Any]] = []

            for block in arr {
                let t = block["type"] as? String ?? ""
                switch t {
                case "text":
                    textParts.append(block["text"] as? String ?? "")
                case "image":
                    if let src = block["source"] as? [String: Any] {
                        if src["type"] as? String == "base64",
                           let mt = src["media_type"] as? String,
                           let d = src["data"] as? String {
                            imageParts.append([
                                "type": "image_url",
                                "image_url": ["url": "data:\(mt);base64,\(d)"]
                            ])
                        } else if src["type"] as? String == "url", let u = src["url"] as? String {
                            imageParts.append([
                                "type": "image_url",
                                "image_url": ["url": u]
                            ])
                        }
                    }
                case "tool_use":
                    let args: Any = block["input"] ?? [String: Any]()
                    let argsStr: String
                    if let d = try? JSONSerialization.data(withJSONObject: args) {
                        argsStr = String(data: d, encoding: .utf8) ?? "{}"
                    } else { argsStr = "{}" }
                    toolCalls.append([
                        "id": block["id"] as Any,
                        "type": "function",
                        "function": ["name": block["name"] as Any, "arguments": argsStr]
                    ])
                case "tool_result":
                    var trContent = ""
                    if let s = block["content"] as? String { trContent = s }
                    else if let arr2 = block["content"] as? [[String: Any]] {
                        trContent = arr2.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    }
                    toolResults.append([
                        "role": "tool",
                        "tool_call_id": block["tool_use_id"] as Any,
                        "content": trContent
                    ])
                default: break
                }
            }

            if role == "assistant" {
                var m: [String: Any] = ["role": "assistant", "content": textParts.joined(separator: "\n")]
                if !toolCalls.isEmpty { m["tool_calls"] = toolCalls }
                oai.append(m)
            } else if role == "user" {
                if !imageParts.isEmpty {
                    var mc: [[String: Any]] = imageParts
                    if !textParts.isEmpty {
                        mc.append(["type": "text", "text": textParts.joined(separator: "\n")])
                    }
                    oai.append(["role": "user", "content": mc])
                } else if !textParts.isEmpty {
                    oai.append(["role": "user", "content": textParts.joined(separator: "\n")])
                }
                oai.append(contentsOf: toolResults)
            }
        }
        return oai
    }

    static func convertTools(_ tools: [[String: Any]]) -> [[String: Any]] {
        tools.map { t in
            ["type": "function", "function": [
                "name": t["name"] as Any,
                "description": t["description"] as Any,
                "parameters": t["input_schema"] as Any
            ]]
        }
    }

    static func oaiResponseToAnthropic(_ data: [String: Any], model: String) -> [String: Any] {
        let choice = (data["choices"] as? [[String: Any]])?.first ?? [:]
        let message = choice["message"] as? [String: Any] ?? [:]
        let usage = data["usage"] as? [String: Any] ?? [:]
        let finish = choice["finish_reason"] as? String ?? "stop"

        var contentBlocks: [[String: Any]] = []
        if let text = message["content"] as? String, !text.isEmpty {
            contentBlocks.append(["type": "text", "text": text])
        }
        for tc in (message["tool_calls"] as? [[String: Any]]) ?? [] {
            let func_ = tc["function"] as? [String: Any] ?? [:]
            let argsStr = func_["arguments"] as? String ?? "{}"
            let input = (try? JSONSerialization.jsonObject(
                with: argsStr.data(using: .utf8) ?? Data()
            )) ?? [String: Any]()
            contentBlocks.append([
                "type": "tool_use",
                "id": "toolu_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24))",
                "name": func_["name"] as Any,
                "input": input
            ])
        }
        let stopReason = finish == "tool_calls" ? "tool_use" : "end_turn"
        return [
            "id": "msg_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24))",
            "type": "message",
            "role": "assistant",
            "model": model,
            "content": contentBlocks.isEmpty ? [["type": "text", "text": ""]] : contentBlocks,
            "stop_reason": stopReason,
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": usage["prompt_tokens"] ?? 0,
                "output_tokens": usage["completion_tokens"] ?? 0,
                "cache_creation_input_tokens": 0,
                "cache_read_input_tokens": 0,
            ] as [String: Any]
        ]
    }
}
