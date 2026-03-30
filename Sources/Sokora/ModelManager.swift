import MLXLMCommon
import MLXLLM
import MLX
import Foundation
import Logging

// MARK: - Errors

enum SokoraError: Error, Sendable {
    case modelNotLoaded
    case invalidRequest(String)
    case generationFailed(String)
}

// MARK: - ModelManager Actor

/// Owns the loaded MLX model container and serialises all inference calls.
actor ModelManager {
    private var container: ModelContainer?
    private let config: SokoraConfig
    let logger: Logger

    init(config: SokoraConfig, logger: Logger) {
        self.config = config
        self.logger = logger
    }

    // MARK: - Load

    func load() async throws {
        logger.info("Loading model: \(config.model)")
        let modelConfig = ModelConfiguration(id: config.model)
        container = try await LLMModelFactory.shared.loadContainer(
            configuration: modelConfig
        ) { [logger] progress in
            logger.info("Download: \(Int(progress.fractionCompleted * 100))%")
        }
        logger.info("Model loaded: \(config.model)")
    }

    // MARK: - Generate

    /// Run inference over `messages`, calling `onToken` (synchronously) for each new token.
    /// Returns (promptTokens, completionTokens) on completion.
    func generate(
        messages: [[String: String]],
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        onToken: @Sendable (String) -> Void
    ) async throws -> (promptTokens: Int, completionTokens: Int) {
        guard let container else { throw SokoraError.modelNotLoaded }

        let userInput = UserInput(messages: messages)
        let params = GenerateParameters(temperature: temperature, topP: topP)
        let capturedMaxTokens = maxTokens

        // container.perform serialises access to the model actor.
        let result: GenerateResult = try await container.perform { context in
            let lmInput = try await context.processor.prepare(input: userInput)
            var tokenCount = 0
            // MLXLMCommon.generate — module-qualify to avoid ambiguity with actor method
            return try MLXLMCommon.generate(
                input: lmInput,
                parameters: params,
                context: context
            ) { tokens in
                guard let lastToken = tokens.last else { return .more }
                let decoded = context.tokenizer.decode(tokens: [lastToken])
                onToken(decoded)
                tokenCount += 1
                return tokenCount >= capturedMaxTokens ? .stop : .more
            }
        }

        let promptTokens = result.inputText.tokens.size
        let completionTokens = result.tokens.count
        return (promptTokens: promptTokens, completionTokens: completionTokens)
    }
}
