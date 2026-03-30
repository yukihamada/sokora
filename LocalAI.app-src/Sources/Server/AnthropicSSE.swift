import Foundation

/// Helpers to generate Anthropic SSE event strings
enum AnthropicSSE {
    static func event(_ type: String, _ data: [String: Any]) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: data))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "event: \(type)\ndata: \(json)\n\n"
    }

    static func messageStart(id: String, model: String) -> String {
        event("message_start", ["type": "message_start", "message": [
            "id": id, "type": "message", "role": "assistant", "model": model,
            "content": [], "stop_reason": NSNull(), "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 0, "output_tokens": 0,
                "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0
            ]
        ] as [String: Any]])
    }

    static func contentBlockStart(index: Int, type: String, id: String = "", name: String = "") -> String {
        var block: [String: Any] = ["type": type]
        if type == "tool_use" {
            block["id"] = id
            block["name"] = name
            block["input"] = [String: Any]()
        } else {
            block["text"] = ""
        }
        return event("content_block_start", [
            "type": "content_block_start",
            "index": index,
            "content_block": block
        ])
    }

    static func textDelta(index: Int, text: String) -> String {
        event("content_block_delta", [
            "type": "content_block_delta",
            "index": index,
            "delta": ["type": "text_delta", "text": text]
        ])
    }

    static func inputJsonDelta(index: Int, partial: String) -> String {
        event("content_block_delta", [
            "type": "content_block_delta",
            "index": index,
            "delta": ["type": "input_json_delta", "partial_json": partial]
        ])
    }

    static func contentBlockStop(index: Int) -> String {
        event("content_block_stop", ["type": "content_block_stop", "index": index])
    }

    static func messageDelta(stopReason: String) -> String {
        event("message_delta", [
            "type": "message_delta",
            "delta": ["stop_reason": stopReason, "stop_sequence": NSNull()] as [String: Any],
            "usage": ["output_tokens": 0]
        ])
    }

    static func messageStop() -> String {
        event("message_stop", ["type": "message_stop"])
    }
}
