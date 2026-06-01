//
//  NLEmbeddingService.swift
//  GJournal
//
//  Apple NLEmbedding baseline — zero bundle size, ships with iOS.
//  Used as Backup C when no .mlpackage is present (see 09_AI_PITFALLS.md §8.1).
//

import Foundation
import NaturalLanguage

final class NLEmbeddingService: EmbeddingServiceProtocol {
    func generateEmbedding(for text: String) async throws -> [Float] {
        return try await Task.detached(priority: .utility) {
            guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
                throw AIServiceError.modelNotLoaded
            }
            guard let vector = embedding.vector(for: text) else {
                throw AIServiceError.embeddingGenerationFailed
            }
            let floats = vector.map { Float($0) }
            return await NLEmbeddingService.l2Normalize(floats)
        }.value
    }

    private static func l2Normalize(_ v: [Float]) -> [Float] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }
}
