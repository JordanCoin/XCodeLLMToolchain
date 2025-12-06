import Foundation
import FoundationModels

/// Protocol so the Xcode app can swap in a different LLM backend while the core stays open-source.
public protocol LLMClient {
    func respond(to prompt: String) async throws -> String
}

/// Default on-device client using Apple's Foundation Models.
public struct FoundationModelClient: LLMClient {
    private let session = LanguageModelSession()

    public init() {}

    public func respond(to prompt: String) async throws -> String {
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
