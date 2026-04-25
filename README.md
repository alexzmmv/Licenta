# GJournal — AI-Powered Micro-Journaling

GJournal is a modern, privacy-focused native iOS application designed to help users track their emotional well-being through micro-journaling and advanced AI analysis. It leverages on-device machine learning to discover patterns in thoughts, emotions, and behaviors without compromising user privacy.

## 🚀 Key Features

### 🧠 On-Device AI Pipeline
- **Emotion Recognition:** Uses Core ML models to analyze the sentiment and specific emotions (Joy, Anxiety, Anger, etc.) of every journal entry across three dimensions: *Feel*, *Event*, and *Action*.
- **BERT Embeddings:** Generates high-dimensional vector representations of journal entries using a local BERT model to understand semantic meaning.
- **DBSCAN Clustering:** Automatically groups related thoughts into clusters to reveal hidden patterns in the user's life (e.g., "Work Stress," "Social Connections").
- **Automatic Naming:** Uses NLP to dynamically generate human-readable titles for detected clusters.

### 🕸️ Knowledge Graph Visualization
- **Force-Directed Layout:** An interactive, physics-based graph that visualizes the connections between journal entries.
- **Relational Mapping:** Clusters appear as distinct "islands" of thought, allowing users to navigate their mind spatially.
- **Responsive Performance:** Physics simulations and clustering run on background threads to ensure a smooth, 60 FPS user interface.

### 📱 Premium User Experience
- **Micro-Journaling Interface:** A streamlined "Feel-Event-Action" framework to make journaling quick and consistent.
- **Advanced Filtering:** Search and filter by text, emotion, intensity, and AI-detected clusters.
- **Relational Persistence:** Built with **SwiftData**, utilizing a fully relational database schema for efficient storage and reactive UI updates.

## 🛠️ Technology Stack
- **Language:** Swift 6 (Strict Concurrency)
- **UI Framework:** SwiftUI
- **Persistence:** SwiftData (Relational Schema)
- **AI/ML:** Core ML, BERT, DBSCAN
- **Asynchronous Programming:** Swift Concurrency (Actors, Tasks)

## 🏗️ Architecture
The app follows a robust **Repository Pattern** to decouple the UI from the persistence layer:
- **Models:** Relational SwiftData models (`Bit`, `Cluster`).
- **Services:** Modular AI services (`EmbeddingService`, `ClusteringService`, `EmotionService`).
- **Repositories:** Centralized data access with background refresh synchronization.
- **Views:** Reactive SwiftUI views driven by `@Observable` state.

---

## 📈 Project Status
- [x] Implement BERT embeddings for semantic analysis.
- [x] Implement DBSCAN for clustering similar journal entries.
- [x] Implement Relational Database Schema (SwiftData).
- [x] Implement Knowledge Graph Visualization with physics-based layout.
- [x] Implement AI-driven Cluster Naming.
- [x] Support Background AI processing (NFR compliance).
- [ ] Implement LSTM/Transformer-based long-term sentiment trends.
- [ ] Behavioral Tagging (Contextual labeling).

---
*GJournal — Understanding yourself, one bit at a time.*