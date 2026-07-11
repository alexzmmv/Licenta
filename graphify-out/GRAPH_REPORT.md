# Graph Report - .  (2026-07-10)

## Corpus Check
- 109 files · ~146,998 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1206 nodes · 2563 edges · 65 communities (58 shown, 7 thin omitted)
- Extraction: 93% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 166 edges (avg confidence: 0.8)
- Token cost: 251,000 input · 20,200 output

## Community Hubs (Navigation)
- [[_COMMUNITY_GGM Estimator Service|GGM Estimator Service]]
- [[_COMMUNITY_Bit Data Model|Bit Data Model]]
- [[_COMMUNITY_Persistent Homology Engine|Persistent Homology Engine]]
- [[_COMMUNITY_Auth Manager & Biometrics|Auth Manager & Biometrics]]
- [[_COMMUNITY_AI Service Errors|AI Service Errors]]
- [[_COMMUNITY_Local Journal Repository|Local Journal Repository]]
- [[_COMMUNITY_CoreML Embedding Service|CoreML Embedding Service]]
- [[_COMMUNITY_Schema Migration|Schema Migration]]
- [[_COMMUNITY_Graph Physics Engine|Graph Physics Engine]]
- [[_COMMUNITY_HDBSCAN Clustering|HDBSCAN Clustering]]
- [[_COMMUNITY_App Entry Point|App Entry Point]]
- [[_COMMUNITY_DBSCAN Clustering|DBSCAN Clustering]]
- [[_COMMUNITY_Emotion Model|Emotion Model]]
- [[_COMMUNITY_Clustering Strategy Choice|Clustering Strategy Choice]]
- [[_COMMUNITY_Settings View & Export|Settings View & Export]]
- [[_COMMUNITY_Bit Collection Extensions|Bit Collection Extensions]]
- [[_COMMUNITY_Dashboard ContentView|Dashboard ContentView]]
- [[_COMMUNITY_Auth Crypto & Errors|Auth Crypto & Errors]]
- [[_COMMUNITY_AI Processing Manager|AI Processing Manager]]
- [[_COMMUNITY_Emotion Model Quantization|Emotion Model Quantization]]
- [[_COMMUNITY_Efficiency Benchmark|Efficiency Benchmark]]
- [[_COMMUNITY_AddEdit Entry View|Add/Edit Entry View]]
- [[_COMMUNITY_Competitor Research Notes|Competitor Research Notes]]
- [[_COMMUNITY_Trajectory Dashboard View|Trajectory Dashboard View]]
- [[_COMMUNITY_Graph Physics Tests|Graph Physics Tests]]
- [[_COMMUNITY_AddEdit View Animation|Add/Edit View Animation]]
- [[_COMMUNITY_Behavioral Tag Model|Behavioral Tag Model]]
- [[_COMMUNITY_Base Repository CRUD|Base Repository CRUD]]
- [[_COMMUNITY_Regulatory Compliance Concepts|Regulatory Compliance Concepts]]
- [[_COMMUNITY_Tag Processor Pipeline|Tag Processor Pipeline]]
- [[_COMMUNITY_ML Model Manifest|ML Model Manifest]]
- [[_COMMUNITY_GGM Math Concepts|GGM Math Concepts]]
- [[_COMMUNITY_Crisis Resources View|Crisis Resources View]]
- [[_COMMUNITY_Calendar View|Calendar View]]
- [[_COMMUNITY_HDBSCAN Math Concepts|HDBSCAN Math Concepts]]
- [[_COMMUNITY_Security & PH Concepts|Security & PH Concepts]]
- [[_COMMUNITY_AI Service Protocols|AI Service Protocols]]
- [[_COMMUNITY_Trajectory Research Paper|Trajectory Research Paper]]
- [[_COMMUNITY_Cluster Cards View|Cluster Cards View]]
- [[_COMMUNITY_Tag Engine Planning|Tag Engine Planning]]
- [[_COMMUNITY_Date Formatting Utilities|Date Formatting Utilities]]
- [[_COMMUNITY_Mock AI Service|Mock AI Service]]
- [[_COMMUNITY_Paywall & Entitlements|Paywall & Entitlements]]
- [[_COMMUNITY_Change PIN Flow|Change PIN Flow]]
- [[_COMMUNITY_Repository Query Methods|Repository Query Methods]]
- [[_COMMUNITY_Day Detail View|Day Detail View]]
- [[_COMMUNITY_Cluster Assignment Model|Cluster Assignment Model]]
- [[_COMMUNITY_Onboarding Flow|Onboarding Flow]]
- [[_COMMUNITY_PIN Keypad View|PIN Keypad View]]
- [[_COMMUNITY_Hybrid Search Concepts|Hybrid Search Concepts]]
- [[_COMMUNITY_Cluster Data Model|Cluster Data Model]]
- [[_COMMUNITY_NL Embedding Service|NL Embedding Service]]
- [[_COMMUNITY_Embedding Model Choice|Embedding Model Choice]]
- [[_COMMUNITY_Mental Health App Research|Mental Health App Research]]
- [[_COMMUNITY_GGM Python Oracle|GGM Python Oracle]]
- [[_COMMUNITY_Insights Purchase Flow|Insights Purchase Flow]]
- [[_COMMUNITY_Safety Filter & Crisis|Safety Filter & Crisis]]
- [[_COMMUNITY_Notification Transparency|Notification Transparency]]
- [[_COMMUNITY_Emotion Classifier Model|Emotion Classifier Model]]
- [[_COMMUNITY_Cluster Gating UI|Cluster Gating UI]]
- [[_COMMUNITY_ANE Compute Units|ANE Compute Units]]
- [[_COMMUNITY_App Icon (Dark)|App Icon (Dark)]]
- [[_COMMUNITY_App Icon (Default)|App Icon (Default)]]
- [[_COMMUNITY_App Icon (Tinted)|App Icon (Tinted)]]
- [[_COMMUNITY_Privacy Manifest|Privacy Manifest]]

## God Nodes (most connected - your core abstractions)
1. `View` - 75 edges
2. `Bit` - 56 edges
3. `AuthManager` - 49 edges
4. `Foundation` - 43 edges
5. `BaseJournalRepository` - 39 edges
6. `Emotion` - 38 edges
7. `Date` - 36 edges
8. `SwiftUI` - 28 edges
9. `HDBSCANClusterer` - 27 edges
10. `GGMEstimatorTests` - 26 edges

## Surprising Connections (you probably didn't know these)
- `GGMEstimatorTests.testLedoitWolfShrinkageIsZeroForLargeN (unrelated failing test)` --references--> `Services/GGMEstimator.swift`  [INFERRED]
  .superpowers/sdd/task-1-report.md → plan.md
- `Services/SeedDataManager.swift (personas)` --semantically_similar_to--> `TrajectoryPersonas (ruminator/explorer/recoverer)`  [INFERRED] [semantically similar]
  plan.md → task_list.md
- `GJournal — AI-Powered Micro-Journaling (app)` --conceptually_related_to--> `Rosebud (competitor app)`  [INFERRED]
  README.md → plan.md
- `GJournal — AI-Powered Micro-Journaling (app)` --conceptually_related_to--> `Stoic (competitor app)`  [INFERRED]
  README.md → plan.md
- `GraphPhysicsEngine.swift (extracted from ClusterGraphView)` --references--> `ClusterGraphView`  [EXTRACTED]
  plan.md → .superpowers/sdd/task-2-brief.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Interactive focus-mode graph rendering feature (Tasks 1+2)** — graphphysicsengine_forcedirectedlayout, graphphysicsengine_updatefocus, views_clustergraphview_clustergraphview, views_clustergraphview_drawnode [EXTRACTED 0.90]
- **GGM psychological network pillar (Pillar A)** — services_ggmestimator, services_insightengine, views_networkgraphview, models_networkvariable, models_behavioraltag_schemav2, concept_ledoit_wolf_shrinkage [EXTRACTED 0.90]
- **Topological trajectory biomarker pillar (Pillar B)** — services_persistenthomology, services_trajectoryservice, views_trajectoryview, trajectory_personas, concept_permutation_null_hypothesis_test [EXTRACTED 0.90]

## Communities (65 total, 7 thin omitted)

### Community 0 - "GGM Estimator Service"
Cohesion: 0.07
Nodes (28): GGMEstimator, NetworkVariable, emotion, tag, PsychNetworkEdge, PsychologicalNetwork, Bool, Double (+20 more)

### Community 1 - "Bit Data Model"
Cohesion: 0.05
Nodes (37): DateFormatter, Bit, Bool, Cluster, Data, Double, Float, Int (+29 more)

### Community 2 - "Persistent Homology Engine"
Cohesion: 0.07
Nodes (24): Comparable, PersistenceBar, PersistentHomology, Bool, Double, Int, Int, TrajectoryPersonas (+16 more)

### Community 3 - "Auth Manager & Biometrics"
Cohesion: 0.07
Nodes (24): AuthManager, PINVerificationResult, correct, incorrect, lockedOut, Bool, Int, String (+16 more)

### Community 4 - "AI Service Errors"
Cohesion: 0.05
Nodes (36): Equatable, AIServiceError, clusteringFailed, embeddingGenerationFailed, emotionDetectionFailed, insufficientData, modelNotLoaded, SafetyResult (+28 more)

### Community 5 - "Local Journal Repository"
Cohesion: 0.07
Nodes (25): Decodable, ExportError, contextUnavailable, serializationFailed, LocalJournalRepository, SeedDataManager, SeedEntry, SeedFile (+17 more)

### Community 6 - "CoreML Embedding Service"
Cohesion: 0.08
Nodes (23): Character, CoreML, CoreMLEmbeddingService, PoolingMode, cls, mean, Float, MLModel (+15 more)

### Community 7 - "Schema Migration"
Cohesion: 0.07
Nodes (15): GJournal, GJournalMigrationPlan, SchemaV1, SchemaV2, ExportAndModelChoiceTests, String, GJournalUITests, MigrationStage (+7 more)

### Community 8 - "Graph Physics Engine"
Cohesion: 0.13
Nodes (23): ForceDirectedLayout, GraphEdge, GraphNode, Bool, CGFloat, CGPoint, CGSize, Float (+15 more)

### Community 9 - "HDBSCAN Clustering"
Cohesion: 0.14
Nodes (15): ClusterableEntry, Float, UUID, CondensedEdge, DendrogramMerge, HDBSCANClusterer, Bool, Double (+7 more)

### Community 10 - "App Entry Point"
Cohesion: 0.08
Nodes (17): App, GJournalApp, Error, ModelContainer, CrashReporter, EntitlementManager, Bool, Never (+9 more)

### Community 11 - "DBSCAN Clustering"
Cohesion: 0.25
Nodes (8): CustomStringConvertible, Bool, CalibrationResult, DBSCANClusterer, Double, Float, Int, String

### Community 12 - "Emotion Model"
Cohesion: 0.09
Nodes (24): Codable, Emotion, anger, anxiety, disgust, excitement, fear, gratitude (+16 more)

### Community 13 - "Clustering Strategy Choice"
Cohesion: 0.09
Nodes (16): CaseIterable, ClusteringStrategyChoice, classic, hdbscan, mrlAdapted, Notification.Name, EmbeddingModelChoice, appleNLP (+8 more)

### Community 14 - "Settings View & Export"
Cohesion: 0.10
Nodes (16): ActivityView, SettingsView, Any, Context, String, UIActivityViewController, URL, StoreRecoveryShareSheet (+8 more)

### Community 15 - "Bit Collection Extensions"
Cohesion: 0.11
Nodes (9): Accelerate, Combine, Foundation, Cluster, Collection, String, NaturalLanguage, os.log (+1 more)

### Community 16 - "Dashboard ContentView"
Cohesion: 0.15
Nodes (17): ContentView, FirstTimeWelcomeView, IdentifiableDate, InsightGateCard, InsightGatingSection, RecentEntryRow, Bool, CGFloat (+9 more)

### Community 17 - "Auth Crypto & Errors"
Cohesion: 0.12
Nodes (18): CommonCrypto, CryptoKit, AuthError, invalidName, keychainError, unauthorized, userAlreadyExists, userNotFound (+10 more)

### Community 18 - "AI Processing Manager"
Cohesion: 0.14
Nodes (11): JournalRepositoryProtocol, AIProcessingManager, ModelContainer, ModelContext, Never, String, Task, UUID (+3 more)

### Community 19 - "Emotion Model Quantization"
Cohesion: 0.22
Nodes (18): Path, get_input_spec(), infer(), load_model(), main(), make_dummy(), make_fp16(), make_int8() (+10 more)

### Community 20 - "Efficiency Benchmark"
Cohesion: 0.25
Nodes (11): Encodable, BenchmarkReport, EfficiencyBenchmark, EmbeddingBenchmarkResult, EmotionBenchmarkResult, Bool, Double, Int (+3 more)

### Community 21 - "Add/Edit Entry View"
Cohesion: 0.35
Nodes (16): View, ActionStepView, EditFormView, EditSection, EventStepView, FeelStepView, IntensityStepView, ProgressIndicator (+8 more)

### Community 22 - "Competitor Research Notes"
Cohesion: 0.13
Nodes (17): Rosebud (competitor app), Stoic (competitor app), vocab_gjournalembeddingminilm.txt (MiniLM embedding vocabulary), Bit model, Cluster model, Automatic Cluster Naming (NLP), BERT Embeddings, DBSCAN Clustering (+9 more)

### Community 23 - "Trajectory Dashboard View"
Cohesion: 0.34
Nodes (6): TrajectoryMetrics, MetricCard, Color, Double, String, TrajectoryView

### Community 24 - "Graph Physics Tests"
Cohesion: 0.17
Nodes (16): GGMEstimatorTests.testLedoitWolfShrinkageIsZeroForLargeN (unrelated failing test), ForceDirectedLayout.focusedEdgeIDs, ForceDirectedLayout.focusedNeighborIDs, ForceDirectedLayout class, ForceDirectedLayout.updateFocus(to:), GraphPhysicsEngine.swift (extracted from ClusterGraphView), Obsidian Graph Focus Mode Progress Ledger, Task 1: Engine State & Focus Calculation (complete) (+8 more)

### Community 25 - "Add/Edit View Animation"
Cohesion: 0.17
Nodes (11): AddEditBitView, CGFloat, Double, TherapyStep, actionPlan, eventExplore, feelCheck, intensity (+3 more)

### Community 26 - "Behavioral Tag Model"
Cohesion: 0.19
Nodes (11): BehavioralTag, Bool, Data, Float, Int, String, TagCategory, action (+3 more)

### Community 27 - "Base Repository CRUD"
Cohesion: 0.20
Nodes (6): BaseJournalRepository, Bool, ModelContext, UUID, DeletedEntryRow, RecentlyDeletedView

### Community 28 - "Regulatory Compliance Concepts"
Cohesion: 0.14
Nodes (14): SafetyFilter + CrisisResourcesView (crisis safety), String Catalog / accessibility migration, SwiftData migration failure recovery (no silent wipe), EU Medical Device Regulation (MDR) / SaMD classification boundary, GJournalApp.makeModelContainer, GJournalUITests smoke tests, SchemaVersions.swift (SchemaV1 + GJournalMigrationPlan), GJournal Production-Ready Innovative MVP Plan (+6 more)

### Community 29 - "Tag Processor Pipeline"
Cohesion: 0.21
Nodes (7): Float, ModelContext, String, TagProcessor, ModelContext, TagProcessorTests, MainActor

### Community 30 - "ML Model Manifest"
Cohesion: 0.14
Nodes (13): author, description, name, path, author, description, name, path (+5 more)

### Community 31 - "GGM Math Concepts"
Cohesion: 0.19
Nodes (13): 12-class GoEmotions-based emotion classifier, Ledoit-Wolf shrinkage regularization, Partial correlation psychological network (shrinkage + thresholded), Softmax compositionality artifact fix: binarize emotion probabilities at historical median, Tier 2: Ledoit-Wolf GGM partial correlation network, EU AI Act Article 5(1)(f) Emotion Recognition Prohibition, GoEmotions dataset (58k Reddit comments), NetworkSnapshot model (SchemaV2 cache) (+5 more)

### Community 32 - "Crisis Resources View"
Cohesion: 0.15
Nodes (7): CrisisResourcesView, Color, String, URL, EmotionDetailView, NetworkGraphLoadingView, SwiftUI

### Community 33 - "Calendar View"
Cohesion: 0.17
Nodes (9): CalendarView, DayCell, MonthYearPickerView, Binding, Bool, Int, Set, String (+1 more)

### Community 34 - "HDBSCAN Math Concepts"
Cohesion: 0.18
Nodes (11): Adaptive HDBSCAN mathematical rationale (mutual reachability distance), GLOSH outlier score (Bayesian soft cluster assignment), HDBSCAN algorithm (mutual reachability, MST, condensed tree, EOM extraction), evaluation/ Python harness (correctness oracle), HDBSCANClusterer.swift, cosine_distance_matrix(), pairwise_agreement(), ndarray (+3 more)

### Community 35 - "Security & PH Concepts"
Cohesion: 0.21
Nodes (11): Bootstrap resampling edge stability filter (8/10 resamples), Escalating attempt lockout mechanism (Keychain-persisted), PBKDF2 (CCKeyDerivationPBKDF, ~210k iterations, 16-byte salt) hardening, Tier 1: FDR-controlled pairwise association network (Benjamini-Hochberg q=0.10), Vietoris-Rips β0/β1 persistence, AuthManager PBKDF2 PIN (350k iterations, salt, lockout), Architectural, Psychological, and Regulatory Evaluation of the GJournal Digital Therapy Platform (research doc), Services/PersistentHomology.swift (+3 more)

### Community 36 - "AI Service Protocols"
Cohesion: 0.35
Nodes (8): ClusteringServiceProtocol, EmbeddingServiceProtocol, EmotionDetectionServiceProtocol, SafetyFilterServiceProtocol, MockClusteringService, MockEmbeddingService, MockEmotionDetectionService, ServiceContainer

### Community 37 - "Trajectory Research Paper"
Cohesion: 0.24
Nodes (11): Chandra et al., "The Topology of Recovery: Using Persistent Homology to Map Individual Mental Health Journeys in Online Communities", Algorithmic apophenia mitigation via permutation null-hypothesis testing, Flare Index / Exploration metric, Permutation null hypothesis test (200 temporal shuffles, 95th percentile gate), Rumination metric (β1 loop persistence LP), Semantic Recovery Velocity (SRV), Services/SeedDataManager.swift (personas), TrajectoryEngine (@Observable) (+3 more)

### Community 38 - "Cluster Cards View"
Cohesion: 0.20
Nodes (9): Element, Array, ClusterCard, ClusterCardsView, CGFloat, Cluster, Int, String (+1 more)

### Community 39 - "Tag Engine Planning"
Cohesion: 0.20
Nodes (11): SchemaV2 @Model BehavioralTag, AIProcessingManager (pipeline), Services/TagExtractor.swift, TagProcessor (extract→embed→merge), GJournal Task List (Tiered), Tier 1: Essential Foundation (complete), Tier 2: High Necessity Innovation Core (complete), Tier 3: Moderate Necessity — Launch & Polish (+3 more)

### Community 40 - "Date Formatting Utilities"
Cohesion: 0.28
Nodes (4): Date, formatter(), String, Set

### Community 41 - "Mock AI Service"
Cohesion: 0.33
Nodes (5): SeededRandomNumberGenerator, Float, String, UInt64, RandomNumberGenerator

### Community 42 - "Paywall & Entitlements"
Cohesion: 0.29
Nodes (5): PaywallView, Color, String, Observation, StoreKit

### Community 43 - "Change PIN Flow"
Cohesion: 0.32
Nodes (7): ChangePINStep, confirmNew, enterNew, success, verifyOld, ChangePINView, String

### Community 44 - "Repository Query Methods"
Cohesion: 0.43
Nodes (3): ClosedRange, Int, String

### Community 45 - "Day Detail View"
Cohesion: 0.38
Nodes (5): DayDetailView, RelatedEntryRow, Bool, Float, String

### Community 46 - "Cluster Assignment Model"
Cohesion: 0.33
Nodes (4): ClusterAssignment, Bool, Int, UUID

### Community 47 - "Onboarding Flow"
Cohesion: 0.40
Nodes (5): OnboardingPageView, OnboardingView, Color, String, Void

### Community 48 - "PIN Keypad View"
Cohesion: 0.33
Nodes (4): PINKeypadView, Int, String, Void

### Community 49 - "Hybrid Search Concepts"
Cohesion: 0.40
Nodes (5): BM25-lite in-memory inverted index, Reciprocal Rank Fusion (RRF, k=60), Services/HybridSearchService.swift, BitsListView, DayDetailView

### Community 50 - "Cluster Data Model"
Cohesion: 0.60
Nodes (3): Cluster, Int, String

### Community 51 - "NL Embedding Service"
Cohesion: 0.60
Nodes (3): NLEmbeddingService, Float, String

### Community 52 - "Embedding Model Choice"
Cohesion: 0.40
Nodes (5): EmbeddingModelChoice enum (MiniLM/AppleNLP), LocalJournalRepository (versioned JSON export), NomicEmbeddingService.swift (deleted), DebugSettingsView (#if DEBUG), SettingsView

### Community 53 - "Mental Health App Research"
Cohesion: 0.40
Nodes (5): MoodWheel assessment tool, PsyPills app (EMA stress management), REThink therapeutic online game, Babeș-Bolyai University DATA Lab (Prof. Oana David), International Institute for the Advanced Studies of Psychotherapy and Applied Mental Health (Prof. Daniel David)

### Community 55 - "Insights Purchase Flow"
Cohesion: 0.67
Nodes (3): GJournal Insights non-consumable purchase, Services/EntitlementManager.swift (StoreKit 2), Views/PaywallView.swift

### Community 56 - "Safety Filter & Crisis"
Cohesion: 1.00
Nodes (3): SafetyFilter.isSelfHarmSignal (static), AddEditBitView, CrisisResourcesView

### Community 57 - "Notification Transparency"
Cohesion: 0.67
Nodes (3): EU AI Act Article 50(3) Transparency Requirement, Services/ReminderScheduler.swift, Views/OnboardingView.swift

### Community 58 - "Emotion Classifier Model"
Cohesion: 0.67
Nodes (3): vocab_emotion.txt (emotion model vocabulary), GJournalEmotionClassifier model, training/quantize_emotion.py (int8 palettization)

## Ambiguous Edges - Review These
- `Services/PersistentHomology.swift` → `Architectural, Psychological, and Regulatory Evaluation of the GJournal Digital Therapy Platform (research doc)`  [AMBIGUOUS]
  plan.md · relation: rationale_for

## Knowledge Gaps
- **128 isolated node(s):** `classic`, `mrlAdapted`, `hdbscan`, `Notification.Name`, `appleNLP` (+123 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Services/PersistentHomology.swift` and `Architectural, Psychological, and Regulatory Evaluation of the GJournal Digital Therapy Platform (research doc)`?**
  _Edge tagged AMBIGUOUS (relation: rationale_for) - confidence is low._
- **Why does `Foundation` connect `Bit Collection Extensions` to `GGM Estimator Service`, `Bit Data Model`, `Persistent Homology Engine`, `AI Service Errors`, `Local Journal Repository`, `CoreML Embedding Service`, `Schema Migration`, `App Entry Point`, `Emotion Model`, `Clustering Strategy Choice`, `Auth Crypto & Errors`, `AI Processing Manager`, `Efficiency Benchmark`, `Behavioral Tag Model`, `Tag Processor Pipeline`, `Crisis Resources View`, `AI Service Protocols`, `Date Formatting Utilities`, `Cluster Assignment Model`, `Cluster Data Model`?**
  _High betweenness centrality (0.133) - this node is a cross-community bridge._
- **Why does `View` connect `Add/Edit Entry View` to `GGM Estimator Service`, `Bit Data Model`, `Auth Manager & Biometrics`, `AI Service Errors`, `Graph Physics Engine`, `Emotion Model`, `Clustering Strategy Choice`, `Settings View & Export`, `Dashboard ContentView`, `AI Processing Manager`, `Trajectory Dashboard View`, `Add/Edit View Animation`, `Behavioral Tag Model`, `Base Repository CRUD`, `Crisis Resources View`, `Calendar View`, `Cluster Cards View`, `Paywall & Entitlements`, `Change PIN Flow`, `Day Detail View`, `Onboarding Flow`, `PIN Keypad View`?**
  _High betweenness centrality (0.129) - this node is a cross-community bridge._
- **Why does `Bit` connect `Bit Data Model` to `GGM Estimator Service`, `Crisis Resources View`, `AI Service Errors`, `Local Journal Repository`, `Cluster Cards View`, `Date Formatting Utilities`, `Graph Physics Engine`, `Emotion Model`, `Repository Query Methods`, `Day Detail View`, `Dashboard ContentView`, `Cluster Data Model`, `Add/Edit View Animation`, `Base Repository CRUD`?**
  _High betweenness centrality (0.121) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `Bit` (e.g. with `.createBit()` and `.generateSeedData()`) actually correct?**
  _`Bit` has 7 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `AuthManager` (e.g. with `GJournalApp` and `.testClearPINRemovesAllMaterial()`) actually correct?**
  _`AuthManager` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `BaseJournalRepository` (e.g. with `HybridSearchService` and `.nodeDetailCard()`) actually correct?**
  _`BaseJournalRepository` has 4 INFERRED edges - model-reasoned connections that need verification._