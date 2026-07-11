# GJournal: Local Gemma LLM Integration Research Brief

This document serves as a comprehensive technical brief to copy-paste into Gemini Web (or other AI research systems) to investigate running a **local Gemma LLM** (or similar lightweight model) on iOS within a privacy-first, local-only micro-journaling application.

---

## 1. Project Context & Technical Stack
*   **Application Name:** GJournal (AI-Powered Micro-Journaling)
*   **Core Principle:** 100% on-device local processing. Zero-knowledge privacy. No raw text or embeddings ever leave the host device.
*   **Platform:** iOS 18.0+, SwiftUI, Swift 6 (Strict Concurrency).
*   **Persistence Layer:** SwiftData (fully relational schema).
*   **Target Devices:** iPhone 13 / 13 Pro, iPhone 14 / 14 Pro, and newer.
    *   *Base iPhone 13 / 13 mini:* **4GB RAM** (Strict Jetsam limit is the primary constraint).
    *   *iPhone 13 Pro, iPhone 14, and newer:* **6GB to 8GB RAM**.
*   **Current AI Pipeline:**
    *   **Embeddings:** MiniLM-L6-v2 (~43MB) via CoreML for semantic search and cluster preparation.
    *   **Emotion Classifier:** Palettized / int8 quantized CoreML model (~25MB) predicting 12 distinct continuous emotion probabilities.
    *   **Clustering:** Natively implemented DBSCAN/HDBSCAN in Swift.
    *   **Psychological Network Graph:** A Gaussian Graphical Model (GGM) computed via Ledoit-Wolf shrinkage and partial correlation math in Swift, mapping emotional and behavioral variables (lemma-extracted tags) with FDR q=0.10 filtering.
    *   **Topological Data Analysis (TDA):** Vietoris-Rips Persistent Homology (H0 & H1) to identify and gate rumination loops.

---

## 2. Target Models & Integration Goals
*   **Model Goal:** Gemma 2 2B Instruction-Tuned (4-bit quantized, ~1.4GB–1.7GB size) or ultra-lightweight alternatives (e.g., Qwen-1.5-1.8B, SmolLM-1.7B).
*   **Features to Explore:**
    *   *Dynamic Reflection Prompts:* Generating 2-3 tailored journal prompts based on the current context and historical network/clusters.
    *   *Weekly/Monthly Summaries:* Synthesizing recent logs, identified clusters, and network correlations into a supportive, conversational text analysis.
    *   *Behavioral Recommendations:* Recommending lifestyle adjustments or journaling exercises based on detected correlations (e.g., a strong negative partial correlation between "working late" and "joy").
*   **Regulatory & Safety Boundaries:**
    *   **EU MDR (Medical Device Regulations):** Must strictly remain a wellness product. It must not diagnose, treat, or act as a clinical therapist.
    *   **EU AI Act:** Must avoid biometric emotion recognition (which is prohibited in certain settings). Since GJournal processes text semantics (and not voice or facial biometrics), it is exempt from biometric restrictions but must satisfy transparency requirements.

---

## 3. Local SwiftData Graph Representation
The application maps user entries as **Bits** and **Clusters** with semantic tags.

### Core Persistence Schemas
1.  **Bit Model (`Bit.swift`):**
    *   `feel: String` (Text describing emotion)
    *   `event: String` (Text describing context)
    *   `action: String` (Text describing user response)
    *   `emotionProbabilities: [String: Float]` (JSON-mapped dictionary of 12 emotion strengths)
    *   `tagLemmas: [String]` (Extracted noun/verb lemmas, e.g., `["work", "meeting", "sleep"]`)
    *   `cluster: Cluster?` (Optional relationship to parent Cluster)
2.  **Cluster Model (`Cluster.swift`):**
    *   `index: Int`
    *   `name: String`
    *   `bits: [Bit]` (Reverse relationship)
3.  **BehavioralTag Model (`BehavioralTag.swift`):**
    *   `lemma: String`
    *   `category: TagCategory` (`.event` or `.action`)
    *   `count: Int`
4.  **Psychological Network Graph:**
    *   Generated dynamically by analyzing continuous emotion probabilities and binary behavioral-tag presence. Output is a list of node variables and partial correlation edges.

---

## 4. Key Technical Questions for Gemini Web

When researching, paste the prompt below to ask Gemini Web:

```text
I am developing GJournal, a privacy-first iOS app (iOS 18+, Swift 6, SwiftData) targeting iPhone 13, 14, and newer devices. 
I want to run a local Gemma 2 2B (or similar 1.5B–2B LLM) on-device to offer context-aware journal summaries and reflection prompts based on a local knowledge graph of entries, clusters, and tag correlations.

Please research and provide detailed guidance on the following:

1. iOS Local LLM Runtimes: 
   Compare Google's MediaPipe LLM Inference API (which supports Gemma 2 2B on iOS using Metal) against llama.cpp (with Swift bindings) and Apple's MLX Swift. 
   Which runtime offers the best performance, easiest integration with SwiftData, and lowest memory footprint on iOS?

2. Low-Memory Lifecycle Management (4GB RAM Constraints):
   Given that the base iPhone 13 has only 4GB of RAM and strict Jetsam limits, how can we load a 1.4GB–1.7GB model into RAM, perform inference, and aggressively deallocate it without crashing the app or causing background memory jetsams? 
   Please provide a Swift actor or manager pattern for load-infer-unload lifecycle management.

3. Structured Output & Safety Guardrails:
   How can we enforce Gemma 2 2B to output strict JSON schemas (e.g. for structured recommendations) on-device without high CPU overhead? 
   What system prompt guidelines and runtime safety filters should we implement to ensure the LLM strictly respects the "wellness-only" frame (avoiding EU MDR clinical device classification) and never gives clinical advice?

4. Prompt Engineering & Graph Serialization:
   How should we serialize a local knowledge graph (containing Bit models, Cluster groupings, and GGM partial correlation edges) into a text-based context prompt for a 2B LLM? 
   Provide an example prompt template that merges this graph context with the user's latest journal entries.
```
