import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Result types

struct EmbeddingBenchmarkResult: Encodable {
    let model: String
    let choice: String
    let dimension: Int
    let coldStartMs: Double
    let meanLatencyMs: Double
    let p50LatencyMs: Double
    let p95LatencyMs: Double
    let modelSizeMB: Double
}

struct EmotionBenchmarkResult: Encodable {
    let coldStartMs: Double
    let meanLatencyMs: Double
    let p50LatencyMs: Double
    let p95LatencyMs: Double
    let modelSizeMB: Double
}

struct BenchmarkReport: Encodable {
    let benchmarkDate: String
    let device: String
    let iosVersion: String
    let onSimulator: Bool
    let testText: String
    let warmupRuns: Int
    let measureRuns: Int
    let embeddings: [EmbeddingBenchmarkResult]
    let emotion: EmotionBenchmarkResult
}

// MARK: - Runner

actor EfficiencyBenchmark {

    private let warmupRuns = 5
    private let measureRuns = 50
    private let testText = "Feeling anxious about the upcoming presentation at work."

    func run(progress: @escaping @Sendable (String) async -> Void) async throws -> BenchmarkReport {
        var embeddingResults: [EmbeddingBenchmarkResult] = []

        let configs: [(choice: EmbeddingModelChoice, label: String, dim: Int, bundleName: String?)] = [
            (.miniLM,    "MiniLM-L6-v2",            384, "GJournalEmbeddingMiniLM"),
            (.appleNLP,  "Apple NLEmbedding",          -1, nil),
        ]

        for cfg in configs {
            await progress("Benchmarking \(cfg.label)…")

            let service = makeEmbeddingService(for: cfg.choice)
            let sizeMB = cfg.bundleName.map { bundleSize(forResource: $0) } ?? 0.0

            let coldMs = try await measureOnce { _ = try await service.generateEmbedding(for: self.testText) }

            for _ in 0 ..< warmupRuns {
                _ = try await service.generateEmbedding(for: testText)
            }

            var samples: [Double] = []
            for _ in 0 ..< measureRuns {
                let ms = try await measureOnce { _ = try await service.generateEmbedding(for: self.testText) }
                samples.append(ms)
            }

            let dim = cfg.dim > 0 ? cfg.dim : (try await service.generateEmbedding(for: testText)).count

            embeddingResults.append(EmbeddingBenchmarkResult(
                model: cfg.label,
                choice: cfg.choice.rawValue,
                dimension: dim,
                coldStartMs: coldMs,
                meanLatencyMs: mean(samples),
                p50LatencyMs: percentile(samples, 50),
                p95LatencyMs: percentile(samples, 95),
                modelSizeMB: sizeMB
            ))
        }

        await progress("Benchmarking emotion classifier…")

        let emotionService = await CoreMLEmotionService(modelName: "GJournalEmotionClassifier")
        let emotionSizeMB = bundleSize(forResource: "GJournalEmotionClassifier")

        let emotionColdMs = try await measureOnce { _ = try await emotionService.detectEmotions(for: self.testText) }

        for _ in 0 ..< warmupRuns {
            _ = try await emotionService.detectEmotions(for: testText)
        }

        var emotionSamples: [Double] = []
        for _ in 0 ..< measureRuns {
            let ms = try await measureOnce { _ = try await emotionService.detectEmotions(for: self.testText) }
            emotionSamples.append(ms)
        }

        let emotionResult = EmotionBenchmarkResult(
            coldStartMs: emotionColdMs,
            meanLatencyMs: mean(emotionSamples),
            p50LatencyMs: percentile(emotionSamples, 50),
            p95LatencyMs: percentile(emotionSamples, 95),
            modelSizeMB: emotionSizeMB
        )

        await progress("Assembling report…")

        let onSim: Bool
        #if targetEnvironment(simulator)
        onSim = true
        #else
        onSim = false
        #endif

        #if canImport(UIKit)
        let deviceModel = await UIDevice.current.model
        let iosVersion = await UIDevice.current.systemVersion
        #else
        let deviceModel = "Mac"
        let iosVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #endif

        return BenchmarkReport(
            benchmarkDate: ISO8601DateFormatter().string(from: Date()),
            device: deviceModel,
            iosVersion: iosVersion,
            onSimulator: onSim,
            testText: testText,
            warmupRuns: warmupRuns,
            measureRuns: measureRuns,
            embeddings: embeddingResults,
            emotion: emotionResult
        )
    }

    // MARK: - Helpers

    private func makeEmbeddingService(for choice: EmbeddingModelChoice) -> EmbeddingServiceProtocol {
        switch choice {
        case .miniLM:    return CoreMLEmbeddingService(modelName: "GJournalEmbeddingMiniLM", poolingMode: .mean)
        case .appleNLP:  return NLEmbeddingService()
        }
    }

    private func measureOnce(_ block: () async throws -> Void) async throws -> Double {
        let start = Date()
        try await block()
        return Date().timeIntervalSince(start) * 1000
    }

    private func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func percentile(_ values: [Double], _ p: Int) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = max(0, min(sorted.count - 1, Int(Double(p) / 100.0 * Double(sorted.count - 1))))
        return sorted[index]
    }

    private func bundleSize(forResource name: String) -> Double {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
            total += size
        }
        return Double(total) / 1_000_000
    }
}
