#!/usr/bin/env swift
// embed_apple_nlp.swift
//
// Embeds STS-B pairs, TwentyNewsgroups sentences, and journal entries using
// Apple NLEmbedding.sentenceEmbedding — the same API used in the GJournal app.
//
// Run from evaluation/:
//   swift embed_apple_nlp.swift
//
// Inputs (must exist):
//   datasets/stsb_sentences.json
//   datasets/twentynews_sentences.json
//   datasets/journal_entries.json
//
// Outputs:
//   datasets/apple_nlp_embeddings.json              (step 1 — STS-B)
//   datasets/apple_nlp_embeddings_clustering.json   (step 2 — TwentyNewsgroups)
//   datasets/apple_nlp_journal_embeddings.json      (step 4 — journal entries)

import Foundation
import NaturalLanguage

// ── Helpers ───────────────────────────────────────────────────────────────────

func l2Normalize(_ v: [Float]) -> [Float] {
    let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
    guard norm > 1e-9 else { return v }
    return v.map { $0 / norm }
}

func embed(_ text: String, using embedding: NLEmbedding) -> [Float] {
    guard let vector = embedding.vector(for: text) else {
        // Fallback: zero vector — will be down-weighted by L2 norm check in Python
        return Array(repeating: 0.0, count: embedding.dimension)
    }
    return l2Normalize(vector.map { Float($0) })
}

func embedBatch(_ texts: [String], using embedding: NLEmbedding, label: String) -> [[Float]] {
    var result: [[Float]] = []
    result.reserveCapacity(texts.count)
    for (i, text) in texts.enumerated() {
        result.append(embed(text, using: embedding))
        if (i + 1) % 100 == 0 || i + 1 == texts.count {
            print("  \(label): \(i + 1)/\(texts.count)")
        }
    }
    return result
}

func readJSON(_ path: String) -> Any {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url),
          let obj  = try? JSONSerialization.jsonObject(with: data) else {
        fatalError("Cannot read \(path)")
    }
    return obj
}

func writeJSON(_ obj: Any, to path: String) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else {
        fatalError("Cannot serialise JSON for \(path)")
    }
    let url = URL(fileURLWithPath: path)
    try! data.write(to: url)
    print("  → \(path) (\(data.count / 1024) KB)")
}

// ── Load embedding model ──────────────────────────────────────────────────────

print("Loading NLEmbedding.sentenceEmbedding(for: .english)...")
guard let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english) else {
    fatalError("NLEmbedding.sentenceEmbedding not available on this system.")
}
print("  Dimension: \(sentenceEmbedding.dimension)\n")

let datasetsDir = "datasets"

// ── Step 1: STS-B ─────────────────────────────────────────────────────────────

print("=== STS-B (step 1) ===")
let stsb = readJSON("\(datasetsDir)/stsb_sentences.json") as! [String: Any]
let s1   = stsb["sentence1"] as! [String]
let s2   = stsb["sentence2"] as! [String]

let emb1 = embedBatch(s1, using: sentenceEmbedding, label: "sentence1")
let emb2 = embedBatch(s2, using: sentenceEmbedding, label: "sentence2")

writeJSON([
    "sentence1_embeddings": emb1,
    "sentence2_embeddings": emb2,
], to: "\(datasetsDir)/apple_nlp_embeddings.json")

// ── Step 2: TwentyNewsgroups ──────────────────────────────────────────────────

print("\n=== TwentyNewsgroups (step 2) ===")
let news      = readJSON("\(datasetsDir)/twentynews_sentences.json") as! [String: Any]
let sentences = news["sentences"] as! [String]

let newsEmb = embedBatch(sentences, using: sentenceEmbedding, label: "sentences")

writeJSON(["embeddings": newsEmb],
          to: "\(datasetsDir)/apple_nlp_embeddings_clustering.json")

// ── Step 4: Journal entries ───────────────────────────────────────────────────

print("\n=== Journal entries (step 4) ===")
let journal  = readJSON("\(datasetsDir)/journal_entries.json") as! [String: Any]
let entries  = journal["entries"] as! [[String: Any]]
let texts    = entries.map { $0["text"] as! String }

let journalEmb = embedBatch(texts, using: sentenceEmbedding, label: "entries")

writeJSON(["embeddings": journalEmb],
          to: "\(datasetsDir)/apple_nlp_journal_embeddings.json")

print("\nDone. Now run:")
print("  python step1_embedding_quality.py")
print("  python step2_clustering_quality.py")
print("  python step4_domain_validation.py")
