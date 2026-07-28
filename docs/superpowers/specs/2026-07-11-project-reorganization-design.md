# Design Specification: Project Reorganization

**Date:** 2026-07-11
**Status:** Approved
**Strategy:** Granular Layered Architecture (Approach A)

---

## 1. Objectives
* Reduce clutter in `GJournal/Services` (28 files) and `GJournal/Views` (24 files) by grouping them into logically cohesive subdirectories.
* Clean up the root directory of loose markdown planning files.
* Remove the redundant `tests/` root directory and unify all unit tests under `GJournalTests/`.
* Reorganize `GJournalTests/` to mirror the production project structure.
* Keep agent-specific folders (`.agents/`, `.superpowers/`, `superpowers/`, `graphify-out/`) in the root to prevent breaking tool dependencies.
* Ensure the Xcode project is fully compatible with these changes. (Since the project uses `PBXFileSystemSynchronizedRootGroup`, moving files on disk will automatically update the files in the Xcode project.)

---

## 2. Target Directory Layout

### 2.1 Workspace Root Clean-up
* **Planning files**: Move loose root markdown files to `docs/planning/`:
  * `plan.md` &rarr; `docs/planning/plan.md`
  * `task_list.md` &rarr; `docs/planning/task_list.md`
  * `temp.md` &rarr; `docs/planning/temp.md`
* **Test consolidation**:
  * `tests/AuthManagerSecurityTests.swift` &rarr; `GJournalTests/Repository/AuthManagerSecurityTests.swift`
  * Delete `tests/` directory.

### 2.2 App Module (`GJournal/`)
We group the app files into three top-level directories: `Sources/`, `UI/`, and `Resources/`.

```
GJournal/
├── Sources/
│   ├── Models/
│   │   ├── Database/
│   │   └── Configs/
│   ├── Repository/
│   ├── Services/
│   │   ├── AI/
│   │   ├── Clustering/
│   │   ├── Math/
│   │   ├── Insight/
│   │   ├── Search/
│   │   └── Infrastructure/
│   ├── Utilities/
│   └── Extensions/
├── UI/
│   ├── Views/
│   │   ├── Auth/
│   │   ├── Journal/
│   │   ├── Insights/
│   │   ├── Settings/
│   │   ├── Onboarding/
│   │   └── Main/
│   ├── Assets.xcassets/
│   ├── Localizable.xcstrings
│   ├── GJournalApp.swift
│   └── ContentView.swift
└── Resources/
    ├── MLModels/
    ├── data/
    ├── GJournal.storekit
    └── PrivacyInfo.xcprivacy
```

### 2.3 Test Module (`GJournalTests/`)
We organize the test files into directories mirroring the production structure:

```
GJournalTests/
├── Services/
│   ├── AI/
│   ├── Math/
│   └── Insight/
├── Repository/
└── Core/
```

---

## 3. Detailed File Relocation Mapping

### 3.1 GJournal/Sources/Models/
* **Database Models (`Models/Database/`)**
  * `GJournal/Models/BehavioralTag.swift` &rarr; `GJournal/Sources/Models/Database/BehavioralTag.swift`
  * `GJournal/Models/Bit.swift` &rarr; `GJournal/Sources/Models/Database/Bit.swift`
  * `GJournal/Models/Cluster.swift` &rarr; `GJournal/Sources/Models/Database/Cluster.swift`
  * `GJournal/Models/SchemaVersions.swift` &rarr; `GJournal/Sources/Models/Database/SchemaVersions.swift`
* **Configuration Models (`Models/Configs/`)**
  * `GJournal/Models/ClusterAssignment.swift` &rarr; `GJournal/Sources/Models/Configs/ClusterAssignment.swift`
  * `GJournal/Models/ClusteringStrategyChoice.swift` &rarr; `GJournal/Sources/Models/Configs/ClusteringStrategyChoice.swift`
  * `GJournal/Models/EmbeddingModelChoice.swift` &rarr; `GJournal/Sources/Models/Configs/EmbeddingModelChoice.swift`
  * `GJournal/Models/Emotion.swift` &rarr; `GJournal/Sources/Models/Configs/Emotion.swift`
  * `GJournal/Models/EmotionProbability.swift` &rarr; `GJournal/Sources/Models/Configs/EmotionProbability.swift`

### 3.2 GJournal/Sources/Repository/
* `GJournal/Repository/AuthManager.swift` &rarr; `GJournal/Sources/Repository/AuthManager.swift`
* `GJournal/Repository/BaseJournalRepository.swift` &rarr; `GJournal/Sources/Repository/BaseJournalRepository.swift`
* `GJournal/Repository/JournalRepositoryProtocol.swift` &rarr; `GJournal/Sources/Repository/JournalRepositoryProtocol.swift`
* `GJournal/Repository/LocalJournalRepository.swift` &rarr; `GJournal/Sources/Repository/LocalJournalRepository.swift`

### 3.3 GJournal/Sources/Services/
* **AI & NLP Services (`Services/AI/`)**
  * `GJournal/Services/AIServiceProtocol.swift` &rarr; `GJournal/Sources/Services/AI/AIServiceProtocol.swift`
  * `GJournal/Services/MockAIService.swift` &rarr; `GJournal/Sources/Services/AI/MockAIService.swift`
  * `GJournal/Services/CoreMLEmbeddingService.swift` &rarr; `GJournal/Sources/Services/AI/CoreMLEmbeddingService.swift`
  * `GJournal/Services/CoreMLEmotionService.swift` &rarr; `GJournal/Sources/Services/AI/CoreMLEmotionService.swift`
  * `GJournal/Services/NLEmbeddingService.swift` &rarr; `GJournal/Sources/Services/AI/NLEmbeddingService.swift`
  * `GJournal/Services/WordPieceTokenizer.swift` &rarr; `GJournal/Sources/Services/AI/WordPieceTokenizer.swift`
  * `GJournal/Services/SemanticUtils.swift` &rarr; `GJournal/Sources/Services/AI/SemanticUtils.swift`
  * `GJournal/Services/TextFlattener.swift` &rarr; `GJournal/Sources/Services/AI/TextFlattener.swift`
  * `GJournal/Services/TagExtractor.swift` &rarr; `GJournal/Sources/Services/AI/TagExtractor.swift`
  * `GJournal/Services/TagProcessor.swift` &rarr; `GJournal/Sources/Services/AI/TagProcessor.swift`
* **Clustering (`Services/Clustering/`)**
  * `GJournal/Services/DBSCANClusterer.swift` &rarr; `GJournal/Sources/Services/Clustering/DBSCANClusterer.swift`
  * `GJournal/Services/HDBSCANClusterer.swift` &rarr; `GJournal/Sources/Services/Clustering/HDBSCANClusterer.swift`
  * `GJournal/Services/ClusterNamer.swift` &rarr; `GJournal/Sources/Services/Clustering/ClusterNamer.swift`
* **Math & Geometry (`Services/Math/`)**
  * `GJournal/Services/GGMEstimator.swift` &rarr; `GJournal/Sources/Services/Math/GGMEstimator.swift`
  * `GJournal/Services/PersistentHomology.swift` &rarr; `GJournal/Sources/Services/Math/PersistentHomology.swift`
  * `GJournal/Services/GraphPhysicsEngine.swift` &rarr; `GJournal/Sources/Services/Math/GraphPhysicsEngine.swift`
* **Insight Generation (`Services/Insight/`)**
  * `GJournal/Services/InsightEngine.swift` &rarr; `GJournal/Sources/Services/Insight/InsightEngine.swift`
  * `GJournal/Services/TrajectoryEngine.swift` &rarr; `GJournal/Sources/Services/Insight/TrajectoryEngine.swift`
  * `GJournal/Services/TrajectoryService.swift` &rarr; `GJournal/Sources/Services/Insight/TrajectoryService.swift`
  * `GJournal/Services/TrajectoryPersonas.swift` &rarr; `GJournal/Sources/Services/Insight/TrajectoryPersonas.swift`
* **Vector & Hybrid Search (`Services/Search/`)**
  * `GJournal/Services/HybridSearchService.swift` &rarr; `GJournal/Sources/Services/Search/HybridSearchService.swift`
* **Infrastructure & Diagnostics (`Services/Infrastructure/`)**
  * `GJournal/Services/ServiceContainer.swift` &rarr; `GJournal/Sources/Services/Infrastructure/ServiceContainer.swift`
  * `GJournal/Services/AIProcessingManager.swift` &rarr; `GJournal/Sources/Services/Infrastructure/AIProcessingManager.swift`
  * `GJournal/Services/EntitlementManager.swift` &rarr; `GJournal/Sources/Services/Infrastructure/EntitlementManager.swift`
  * `GJournal/Services/CrashReporter.swift` &rarr; `GJournal/Sources/Services/Infrastructure/CrashReporter.swift`
  * `GJournal/Services/EfficiencyBenchmark.swift` &rarr; `GJournal/Sources/Services/Infrastructure/EfficiencyBenchmark.swift`
  * `GJournal/Services/ReminderScheduler.swift` &rarr; `GJournal/Sources/Services/Infrastructure/ReminderScheduler.swift`
  * `GJournal/Services/SafetyFilter.swift` &rarr; `GJournal/Sources/Services/Infrastructure/SafetyFilter.swift`

### 3.4 GJournal/Sources/Utilities/
* `GJournal/Utilities/AppLogger.swift` &rarr; `GJournal/Sources/Utilities/AppLogger.swift`
* `GJournal/Utilities/UITestSupport.swift` &rarr; `GJournal/Sources/Utilities/UITestSupport.swift`

### 3.5 GJournal/Sources/Extensions/
* `GJournal/Extensions/Collection+Bits.swift` &rarr; `GJournal/Sources/Extensions/Collection+Bits.swift`
* `GJournal/Extensions/Date+Formatting.swift` &rarr; `GJournal/Sources/Extensions/Date+Formatting.swift`

### 3.6 GJournal/UI/Views/
* **Security & Auth (`Views/Auth/`)**
  * `GJournal/Views/LoginView.swift` &rarr; `GJournal/UI/Views/Auth/LoginView.swift`
  * `GJournal/Views/BiometricLockView.swift` &rarr; `GJournal/UI/Views/Auth/BiometricLockView.swift`
  * `GJournal/Views/PINKeypadView.swift` &rarr; `GJournal/UI/Views/Auth/PINKeypadView.swift`
  * `GJournal/Views/ChangePINView.swift` &rarr; `GJournal/UI/Views/Auth/ChangePINView.swift`
* **Journal Entries (`Views/Journal/`)**
  * `GJournal/Views/BitsListView.swift` &rarr; `GJournal/UI/Views/Journal/BitsListView.swift`
  * `GJournal/Views/BitCard.swift` &rarr; `GJournal/UI/Views/Journal/BitCard.swift`
  * `GJournal/Views/AddEditBitView.swift` &rarr; `GJournal/UI/Views/Journal/AddEditBitView.swift`
  * `GJournal/Views/DayDetailView.swift` &rarr; `GJournal/UI/Views/Journal/DayDetailView.swift`
  * `GJournal/Views/RecentlyDeletedView.swift` &rarr; `GJournal/UI/Views/Journal/RecentlyDeletedView.swift`
  * `GJournal/Views/CalendarView.swift` &rarr; `GJournal/UI/Views/Journal/CalendarView.swift`
* **Insights & Graphs (`Views/Insights/`)**
  * `GJournal/Views/ClusterGraphView.swift` &rarr; `GJournal/UI/Views/Insights/ClusterGraphView.swift`
  * `GJournal/Views/NetworkGraphView.swift` &rarr; `GJournal/UI/Views/Insights/NetworkGraphView.swift`
  * `GJournal/Views/ClusterCardsView.swift` &rarr; `GJournal/UI/Views/Insights/ClusterCardsView.swift`
  * `GJournal/Views/EmotionDetailView.swift` &rarr; `GJournal/UI/Views/Insights/EmotionDetailView.swift`
  * `GJournal/Views/TopEmotionsView.swift` &rarr; `GJournal/UI/Views/Insights/TopEmotionsView.swift`
  * `GJournal/Views/TrajectoryView.swift` &rarr; `GJournal/UI/Views/Insights/TrajectoryView.swift`
* **Settings & Config (`Views/Settings/`)**
  * `GJournal/Views/SettingsView.swift` &rarr; `GJournal/UI/Views/Settings/SettingsView.swift`
  * `GJournal/Views/DebugSettingsView.swift` &rarr; `GJournal/UI/Views/Settings/DebugSettingsView.swift`
  * `GJournal/Views/StoreRecoveryView.swift` &rarr; `GJournal/UI/Views/Settings/StoreRecoveryView.swift`
  * `GJournal/Views/TagManagementView.swift` &rarr; `GJournal/UI/Views/Settings/TagManagementView.swift`
  * `GJournal/Views/PaywallView.swift` &rarr; `GJournal/UI/Views/Settings/PaywallView.swift`
  * `GJournal/Views/CrisisResourcesView.swift` &rarr; `GJournal/UI/Views/Settings/CrisisResourcesView.swift`
* **Onboarding (`Views/Onboarding/`)**
  * `GJournal/Views/OnboardingView.swift` &rarr; `GJournal/UI/Views/Onboarding/OnboardingView.swift`
* **Dashboard / Root Flow (`Views/Main/`)**
  * `GJournal/Views/MainAppView.swift` &rarr; `GJournal/UI/Views/Main/MainAppView.swift`

### 3.7 GJournal/UI/ Root Files
* `GJournal/ContentView.swift` &rarr; `GJournal/UI/ContentView.swift`
* `GJournal/GJournalApp.swift` &rarr; `GJournal/UI/GJournalApp.swift`
* `GJournal/Assets.xcassets/` &rarr; `GJournal/UI/Assets.xcassets/`
* `GJournal/Localizable.xcstrings` &rarr; `GJournal/UI/Localizable.xcstrings`

### 3.8 GJournal/Resources/
* `GJournal/MLModels/` &rarr; `GJournal/Resources/MLModels/`
* `GJournal/data/seed_data.json` &rarr; `GJournal/Resources/data/seed_data.json`
* `GJournal/GJournal.storekit` &rarr; `GJournal/Resources/GJournal.storekit`
* `GJournal/PrivacyInfo.xcprivacy` &rarr; `GJournal/Resources/PrivacyInfo.xcprivacy`

### 3.9 GJournalTests/
* **Services Tests (`GJournalTests/Services/`)**
  * `GJournalTests/SemanticUtilsTests.swift` &rarr; `GJournalTests/Services/AI/SemanticUtilsTests.swift`
  * `GJournalTests/WordPieceTokenizerTests.swift` &rarr; `GJournalTests/Services/AI/WordPieceTokenizerTests.swift`
  * `GJournalTests/TagExtractorTests.swift` &rarr; `GJournalTests/Services/AI/TagExtractorTests.swift`
  * `GJournalTests/TagProcessorTests.swift` &rarr; `GJournalTests/Services/AI/TagProcessorTests.swift`
  * `GJournalTests/GGMEstimatorTests.swift` &rarr; `GJournalTests/Services/Math/GGMEstimatorTests.swift`
  * `GJournalTests/PersistentHomologyTests.swift` &rarr; `GJournalTests/Services/Math/PersistentHomologyTests.swift`
  * `GJournalTests/ForceDirectedLayoutTests.swift` &rarr; `GJournalTests/Services/Math/ForceDirectedLayoutTests.swift`
  * `GJournalTests/TrajectoryServiceTests.swift` &rarr; `GJournalTests/Services/Insight/TrajectoryServiceTests.swift`
  * `GJournalTests/HDBSCANTests.swift` &rarr; `GJournalTests/Services/Insight/HDBSCANTests.swift`
* **Repository Tests (`GJournalTests/Repository/`)**
  * `GJournalTests/AuthManagerTests.swift` &rarr; `GJournalTests/Repository/AuthManagerTests.swift`
  * `tests/AuthManagerSecurityTests.swift` *[from root tests/]* &rarr; `GJournalTests/Repository/AuthManagerSecurityTests.swift`
* **Core Module Tests (`GJournalTests/Core/`)**
  * `GJournalTests/ExportAndModelChoiceTests.swift` &rarr; `GJournalTests/Core/ExportAndModelChoiceTests.swift`
  * `GJournalTests/MigrationSmokeTests.swift` &rarr; `GJournalTests/Core/MigrationSmokeTests.swift`

---

## 4. Verification Plan
1. Move the files using `git mv` to preserve commit history.
2. Clean up empty folders (`tests/`, original root directories of moved targets).
3. Validate that Xcode project registers the folders correctly via filesystem synchronization.
4. Run `xcodebuild -scheme GJournal -destination 'generic/platform=iOS Simulator' build` to ensure the project compiles successfully.
5. Run tests `xcodebuild test -scheme GJournal -destination 'generic/platform=iOS Simulator'` to verify that all 92+ unit tests are discovered in their new locations and pass.
6. Run `graphify update .` to update the knowledge graph.
