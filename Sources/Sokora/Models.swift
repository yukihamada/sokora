import Foundation

// MARK: - Chat Message

struct ChatMessage: Codable, Sendable {
    let role: String
    let content: String
}

// MARK: - Request

struct ChatCompletionRequest: Codable, Sendable {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int?
    let temperature: Double?
    let topP: Double?
    let stream: Bool?
    let stop: StopSequence?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, stop
        case maxTokens = "max_tokens"
        case topP = "top_p"
    }

    // stop can be a string or array of strings
    enum StopSequence: Codable, Sendable {
        case single(String)
        case multiple([String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let str = try? container.decode(String.self) {
                self = .single(str)
            } else if let arr = try? container.decode([String].self) {
                self = .multiple(arr)
            } else {
                self = .multiple([])
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .single(let s): try container.encode(s)
            case .multiple(let a): try container.encode(a)
            }
        }

        var values: [String] {
            switch self {
            case .single(let s): return [s]
            case .multiple(let a): return a
            }
        }
    }
}

// MARK: - Usage

struct UsageInfo: Codable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Non-streaming Response

struct ChatCompletionChoice: Codable, Sendable {
    let index: Int
    let message: ChatMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct ChatCompletionResponse: Codable, Sendable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [ChatCompletionChoice]
    let usage: UsageInfo
}

// MARK: - Streaming Response (SSE chunks)

struct ChatCompletionDelta: Codable, Sendable {
    let role: String?
    let content: String?
}

struct ChatCompletionChunkChoice: Codable, Sendable {
    let index: Int
    let delta: ChatCompletionDelta
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

struct ChatCompletionChunk: Codable, Sendable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [ChatCompletionChunkChoice]
}

// MARK: - Models list

struct ModelObject: Codable, Sendable {
    let id: String
    let object: String
    let created: Int
    let ownedBy: String

    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
    }
}

struct ModelsListResponse: Codable, Sendable {
    let object: String
    let data: [ModelObject]
}

// MARK: - Node Registration

struct SokoraRegisterRequest: Codable, Sendable {
    let nodeId: String
    let tunnelUrl: String
    let ramGb: Double
    let modelsJson: [String]
    let version: String

    enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
        case tunnelUrl = "tunnel_url"
        case ramGb = "ram_gb"
        case modelsJson = "models_json"
        case version
    }
}

// MARK: - Error Response

struct ErrorDetail: Codable, Sendable {
    let message: String
    let type: String
    let code: String?
}

struct ErrorResponse: Codable, Sendable {
    let error: ErrorDetail
}
