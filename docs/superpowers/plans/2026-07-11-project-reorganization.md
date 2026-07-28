# Project Reorganization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the entire GJournal iOS codebase, test files, and workspace planning files into a modular, clean, and granular directory structure to improve maintainability and discoverability.

**Architecture:** We use git moves (`git mv`) to physically relocate source, test, resource, and planning files. Since Xcode's workspace targets use modern file-system synchronized root groups (`PBXFileSystemSynchronizedRootGroup`), moving files on disk will automatically sync with the Xcode UI, preserving compile structures without requiring manual `.pbxproj` file reference updates.

**Tech Stack:** zsh (git command line), Swift 6, Xcode build tools (`xcodebuild`), graphify.

## Global Constraints
* iOS Simulator SDK platform version: 18.0 (Xcode 16+)
* Swift strict concurrency: Swift 6 compiler settings
* Clean build: The workspace must compile successfully with zero errors after every task.
* Test suite: The full 92+ test suite must compile and pass successfully after every code movement.

---

### Task 1: Root Workspace and Planning Cleanup
Relocate loose markdown planning files to `docs/planning/`, consolidate the isolated `tests/` folder by moving its contents into the unified unit testing target, and remove empty parent folders.

**Files:**
* Modify: (Delete) `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/tests`
* Modify: `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/plan.md` &rarr; `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/docs/planning/plan.md`
* Modify: `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/task_list.md` &rarr; `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/docs/planning/task_list.md`
* Modify: `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/temp.md` &rarr; `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/docs/planning/temp.md`
* Modify: `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/tests/AuthManagerSecurityTests.swift` &rarr; `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournalTests/Repository/AuthManagerSecurityTests.swift`

**Interfaces:**
* None

- [ ] **Step 1: Create the planning documents directory**
  Run: `mkdir -p docs/planning`

- [ ] **Step 2: Move planning documents with git**
  Run:
  ```bash
  git mv plan.md docs/planning/plan.md
  git mv task_list.md docs/planning/task_list.md
  git mv temp.md docs/planning/temp.md
  ```

- [ ] **Step 3: Move the security tests to GJournalTests/Repository**
  Run:
  ```bash
  mkdir -p GJournalTests/Repository
  git mv tests/AuthManagerSecurityTests.swift GJournalTests/Repository/AuthManagerSecurityTests.swift
  ```

- [ ] **Step 4: Remove the empty tests directory**
  Run: `rm -rf tests`

- [ ] **Step 5: Verify the baseline build still succeeds**
  Run: `xcodebuild -scheme GJournal -destination 'generic/platform=iOS Simulator' build`
  Expected: **BUILD SUCCEEDED**

- [ ] **Step 6: Commit the root changes**
  Run:
  ```bash
  git add docs/planning GJournalTests/Repository/AuthManagerSecurityTests.swift
  git commit -m "refactor: relocate planning docs and consolidate root tests folder"
  ```

---

### Task 2: Reorganize GJournal Models and Repositories
Relocate data model layer and repository layer files inside the new `GJournal/Sources/` subdirectory structure.

**Files:**
* Modify: Move files in `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Models`
* Modify: Move files in `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Repository`

**Interfaces:**
* None

- [ ] **Step 1: Create target folders**
  Run: `mkdir -p GJournal/Sources/Models/Database GJournal/Sources/Models/Configs GJournal/Sources/Repository`

- [ ] **Step 2: Relocate Database Models**
  Run:
  ```bash
  git mv GJournal/Models/BehavioralTag.swift GJournal/Sources/Models/Database/BehavioralTag.swift
  git mv GJournal/Models/Bit.swift GJournal/Sources/Models/Database/Bit.swift
  git mv GJournal/Models/Cluster.swift GJournal/Sources/Models/Database/Cluster.swift
  git mv GJournal/Models/SchemaVersions.swift GJournal/Sources/Models/Database/SchemaVersions.swift
  ```

- [ ] **Step 3: Relocate Config Models**
  Run:
  ```bash
  git mv GJournal/Models/ClusterAssignment.swift GJournal/Sources/Models/Configs/ClusterAssignment.swift
  git mv GJournal/Models/ClusteringStrategyChoice.swift GJournal/Sources/Models/Configs/ClusteringStrategyChoice.swift
  git mv GJournal/Models/EmbeddingModelChoice.swift GJournal/Sources/Models/Configs/EmbeddingModelChoice.swift
  git mv GJournal/Models/Emotion.swift GJournal/Sources/Models/Configs/Emotion.swift
  git mv GJournal/Models/EmotionProbability.swift GJournal/Sources/Models/Configs/EmotionProbability.swift
  ```

- [ ] **Step 4: Clean up old Models directory**
  Run: `rm -rf GJournal/Models`

- [ ] **Step 5: Relocate Repositories**
  Run:
  ```bash
  git mv GJournal/Repository/AuthManager.swift GJournal/Sources/Repository/AuthManager.swift
  git mv GJournal/Repository/BaseJournalRepository.swift GJournal/Sources/Repository/BaseJournalRepository.swift
  git mv GJournal/Repository/JournalRepositoryProtocol.swift GJournal/Sources/Repository/JournalRepositoryProtocol.swift
  git mv GJournal/Repository/LocalJournalRepository.swift GJournal/Sources/Repository/LocalJournalRepository.swift
  ```

- [ ] **Step 6: Clean up old Repository directory**
  Run: `rm -rf GJournal/Repository`

- [ ] **Step 7: Verify project builds successfully**
  Run: `xcodebuild -scheme GJournal -destination 'generic/platform=iOS Simulator' build`
  Expected: **BUILD SUCCEEDED**

- [ ] **Step 8: Commit the changes**
  Run:
  ```bash
  git add GJournal/Sources/Models GJournal/Sources/Repository
  git commit -m "refactor: relocate Models and Repositories layers under Sources"
  ```

---

### Task 3: Reorganize GJournal Services
Divide the 28 service files under `GJournal/Services/` into 6 highly cohesive subdirectories under `GJournal/Sources/Services/`.

**Files:**
* Modify: Relocate files in `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Services`

**Interfaces:**
* None

- [ ] **Step 1: Create target subdirectories**
  Run: `mkdir -p GJournal/Sources/Services/AI GJournal/Sources/Services/Clustering GJournal/Sources/Services/Math GJournal/Sources/Services/Insight GJournal/Sources/Services/Search GJournal/Sources/Services/Infrastructure`

- [ ] **Step 2: Relocate AI & NLP Services**
  Run:
  ```bash
  git mv GJournal/Services/AIServiceProtocol.swift GJournal/Sources/Services/AI/AIServiceProtocol.swift
  git mv GJournal/Services/MockAIService.swift GJournal/Sources/Services/AI/MockAIService.swift
  git mv GJournal/Services/CoreMLEmbeddingService.swift GJournal/Sources/Services/AI/CoreMLEmbeddingService.swift
  git mv GJournal/Services/CoreMLEmotionService.swift GJournal/Sources/Services/AI/CoreMLEmotionService.swift
  git mv GJournal/Services/NLEmbeddingService.swift GJournal/Sources/Services/AI/NLEmbeddingService.swift
  git mv GJournal/Services/WordPieceTokenizer.swift GJournal/Sources/Services/AI/WordPieceTokenizer.swift
  git mv GJournal/Services/SemanticUtils.swift GJournal/Sources/Services/AI/SemanticUtils.swift
  git mv GJournal/Services/TextFlattener.swift GJournal/Sources/Services/AI/TextFlattener.swift
  git mv GJournal/Services/TagExtractor.swift GJournal/Sources/Services/AI/TagExtractor.swift
  git mv GJournal/Services/TagProcessor.swift GJournal/Sources/Services/AI/TagProcessor.swift
  ```

- [ ] **Step 3: Relocate Clustering Services**
  Run:
  ```bash
  git mv GJournal/Services/DBSCANClusterer.swift GJournal/Sources/Services/Clustering/DBSCANClusterer.swift
  git mv GJournal/Services/HDBSCANClusterer.swift GJournal/Sources/Services/Clustering/HDBSCANClusterer.swift
  git mv GJournal/Services/ClusterNamer.swift GJournal/Sources/Services/Clustering/ClusterNamer.swift
  ```

- [ ] **Step 4: Relocate Math & Geometry Engines**
  Run:
  ```bash
  git mv GJournal/Services/GGMEstimator.swift GJournal/Sources/Services/Math/GGMEstimator.swift
  git mv GJournal/Services/PersistentHomology.swift GJournal/Sources/Services/Math/PersistentHomology.swift
  git mv GJournal/Services/GraphPhysicsEngine.swift GJournal/Sources/Services/Math/GraphPhysicsEngine.swift
  ```

- [ ] **Step 5: Relocate Insight & Trajectory Services**
  Run:
  ```bash
  git mv GJournal/Services/InsightEngine.swift GJournal/Sources/Services/Insight/InsightEngine.swift
  git mv GJournal/Services/TrajectoryEngine.swift GJournal/Sources/Services/Insight/TrajectoryEngine.swift
  git mv GJournal/Services/TrajectoryService.swift GJournal/Sources/Services/Insight/TrajectoryService.swift
  git mv GJournal/Services/TrajectoryPersonas.swift GJournal/Sources/Services/Insight/TrajectoryPersonas.swift
  ```

- [ ] **Step 6: Relocate Search Services**
  Run:
  ```bash
  git mv GJournal/Services/HybridSearchService.swift GJournal/Sources/Services/Search/HybridSearchService.swift
  ```

- [ ] **Step 7: Relocate Infrastructure & Diagnostic Services**
  Run:
  ```bash
  git mv GJournal/Services/ServiceContainer.swift GJournal/Sources/Services/Infrastructure/ServiceContainer.swift
  git mv GJournal/Services/AIProcessingManager.swift GJournal/Sources/Services/Infrastructure/AIProcessingManager.swift
  git mv GJournal/Services/EntitlementManager.swift GJournal/Sources/Services/Infrastructure/EntitlementManager.swift
  git mv GJournal/Services/CrashReporter.swift GJournal/Sources/Services/Infrastructure/CrashReporter.swift
  git mv GJournal/Services/EfficiencyBenchmark.swift GJournal/Sources/Services/Infrastructure/EfficiencyBenchmark.swift
  git mv GJournal/Services/ReminderScheduler.swift GJournal/Sources/Services/Infrastructure/ReminderScheduler.swift
  git mv GJournal/Services/SafetyFilter.swift GJournal/Sources/Services/Infrastructure/SafetyFilter.swift
  ```

- [ ] **Step 8: Clean up old Services folder**
  Run: `rm -rf GJournal/Services`

- [ ] **Step 9: Verify compilation**
  Run: `xcodebuild -scheme GJournal -destination 'generic/platform=iOS Simulator' build`
  Expected: **BUILD SUCCEEDED**

- [ ] **Step 10: Commit changes**
  Run:
  ```bash
  git add GJournal/Sources/Services
  git commit -m "refactor: reorganize services into AI, Clustering, Math, Insight, Search, and Infrastructure"
  ```

---

### Task 4: Reorganize GJournal Utilities and Extensions
Move helper extensions and shared diagnostic utilities under `GJournal/Sources/`.

**Files:**
* Modify: Relocate files in `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Utilities`
* Modify: Relocate files in `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Extensions`

**Interfaces:**
* None

- [ ] **Step 1: Create target folders**
  Run: `mkdir -p GJournal/Sources/Utilities GJournal/Sources/Extensions`

- [ ] **Step 2: Move Utilities**
  Run:
  ```bash
  git mv GJournal/Utilities/AppLogger.swift GJournal/Sources/Utilities/AppLogger.swift
  git mv GJournal/Utilities/UITestSupport.swift GJournal/Sources/Utilities/UITestSupport.swift
  ```

- [ ] **Step 3: Clean up old Utilities directory**
  Run: `rm -rf GJournal/Utilities`

- [ ] **Step 4: Move Extensions**
  Run:
  ```bash
  git mv GJournal/Extensions/Collection+Bits.swift GJournal/Sources/Extensions/Collection+Bits.swift
  git mv GJournal/Extensions/Date+Formatting.swift GJournal/Sources/Extensions/Date+Formatting.swift
  ```

- [ ] **Step 5: Clean up old Extensions directory**
  Run: `rm -rf GJournal/Extensions`

- [ ] **Step 6: Verify compilation**
  Run: `xcodebuild -scheme GJournal -destination 'generic/platform=iOS Simulator' build`
  Expected: **BUILD SUCCEEDED**

- [ ] **Step 7: Commit changes**
  Run:
  ```bash
  git add GJournal/Sources/Utilities GJournal/Sources/Extensions
  git commit -m "refactor: relocate utilities and extensions to Sources/"
  ```

---

### Task 5: Reorganize GJournal UI and Views
Group views into 6 subdirectories representing domains (Auth, Journal, Insights, Settings, Onboarding, Main) under the unified UI directory `GJournal/UI/`. Move assets, string catalogs, and application entrypoints into the same `UI` directory.

**Files:**
* Modify: Relocate files in `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Views`
* Modify: Relocate root files in `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal`

**Interfaces:**
* None

- [ ] **Step 1: Create target UI folders**
  Run: `mkdir -p GJournal/UI/Views/Auth GJournal/UI/Views/Journal GJournal/UI/Views/Insights GJournal/UI/Views/Settings GJournal/UI/Views/Onboarding GJournal/UI/Views/Main`

- [ ] **Step 2: Relocate Authentication Views**
  Run:
  ```bash
  git mv GJournal/Views/LoginView.swift GJournal/UI/Views/Auth/LoginView.swift
  git mv GJournal/Views/BiometricLockView.swift GJournal/UI/Views/Auth/BiometricLockView.swift
  git mv GJournal/Views/PINKeypadView.swift GJournal/UI/Views/Auth/PINKeypadView.swift
  git mv GJournal/Views/ChangePINView.swift GJournal/UI/Views/Auth/ChangePINView.swift
  ```

- [ ] **Step 3: Relocate Journal Entry Views**
  Run:
  ```bash
  git mv GJournal/Views/BitsListView.swift GJournal/UI/Views/Journal/BitsListView.swift
  git mv GJournal/Views/BitCard.swift GJournal/UI/Views/Journal/BitCard.swift
  git mv GJournal/Views/AddEditBitView.swift GJournal/UI/Views/Journal/AddEditBitView.swift
  git mv GJournal/Views/DayDetailView.swift GJournal/UI/Views/Journal/DayDetailView.swift
  git mv GJournal/Views/RecentlyDeletedView.swift GJournal/UI/Views/Journal/RecentlyDeletedView.swift
  git mv GJournal/Views/CalendarView.swift GJournal/UI/Views/Journal/CalendarView.swift
  ```

- [ ] **Step 4: Relocate Insight Views**
  Run:
  ```bash
  git mv GJournal/Views/ClusterGraphView.swift GJournal/UI/Views/Insights/ClusterGraphView.swift
  git mv GJournal/Views/NetworkGraphView.swift GJournal/UI/Views/Insights/NetworkGraphView.swift
  git mv GJournal/Views/ClusterCardsView.swift GJournal/UI/Views/Insights/ClusterCardsView.swift
  git mv GJournal/Views/EmotionDetailView.swift GJournal/UI/Views/Insights/EmotionDetailView.swift
  git mv GJournal/Views/TopEmotionsView.swift GJournal/UI/Views/Insights/TopEmotionsView.swift
  git mv GJournal/Views/TrajectoryView.swift GJournal/UI/Views/Insights/TrajectoryView.swift
  ```

- [ ] **Step 5: Relocate Settings Views**
  Run:
  ```bash
  git mv GJournal/Views/SettingsView.swift GJournal/UI/Views/Settings/SettingsView.swift
  git mv GJournal/Views/DebugSettingsView.swift GJournal/UI/Views/Settings/DebugSettingsView.swift
  git mv GJournal/Views/StoreRecoveryView.swift GJournal/UI/Views/Settings/StoreRecoveryView.swift
  git mv GJournal/Views/TagManagementView.swift GJournal/UI/Views/Settings/TagManagementView.swift
  git mv GJournal/Views/PaywallView.swift GJournal/UI/Views/Settings/PaywallView.swift
  git mv GJournal/Views/CrisisResourcesView.swift GJournal/UI/Views/Settings/CrisisResourcesView.swift
  ```

- [ ] **Step 6: Relocate Onboarding and Main Dashboard shells**
  Run:
  ```bash
  git mv GJournal/Views/OnboardingView.swift GJournal/UI/Views/Onboarding/OnboardingView.swift
  git mv GJournal/Views/MainAppView.swift GJournal/UI/Views/Main/MainAppView.swift
  ```

- [ ] **Step 7: Clean up old Views folder**
  Run: `rm -rf GJournal/Views`

- [ ] **Step 8: Move GJournal root UI entry files**
  Run:
  ```bash
  git mv GJournal/ContentView.swift GJournal/UI/ContentView.swift
  git mv GJournal/GJournalApp.swift GJournal/UI/GJournalApp.swift
  git mv GJournal/Assets.xcassets GJournal/UI/Assets.xcassets
  git mv GJournal/Localizable.xcstrings GJournal/UI/Localizable.xcstrings
  ```

- [ ] **Step 9: Verify compilation**
  Run: `xcodebuild -scheme GJournal -destination 'generic/platform=iOS Simulator' build`
  Expected: **BUILD SUCCEEDED**

- [ ] **Step 10: Commit changes**
  Run:
  ```bash
  git add GJournal/UI
  git commit -m "refactor: relocate UI components, assets, and views into UI subdirectories"
  ```

---

### Task 6: Reorganize GJournal Resources
Consolidate CoreML models, seed data, Storekit simulator receipts, and privacy catalog settings under `GJournal/Resources/`.

**Files:**
* Modify: Relocate files in `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/MLModels`
* Modify: Relocate files in `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/data`
* Modify: Relocate root settings in `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal`

**Interfaces:**
* None

- [ ] **Step 1: Create target folders**
  Run: `mkdir -p GJournal/Resources`

- [ ] **Step 2: Relocate ML models and files**
  Run: `git mv GJournal/MLModels GJournal/Resources/MLModels`

- [ ] **Step 3: Relocate seed data**
  Run: `git mv GJournal/data GJournal/Resources/data`

- [ ] **Step 4: Relocate StoreKit and Privacy configuration files**
  Run:
  ```bash
  git mv GJournal/GJournal.storekit GJournal/Resources/GJournal.storekit
  git mv GJournal/PrivacyInfo.xcprivacy GJournal/Resources/PrivacyInfo.xcprivacy
  ```

- [ ] **Step 5: Verify build compiles and resources are loaded correctly**
  Run: `xcodebuild -scheme GJournal -destination 'generic/platform=iOS Simulator' build`
  Expected: **BUILD SUCCEEDED**

- [ ] **Step 6: Commit changes**
  Run:
  ```bash
  git add GJournal/Resources
  git commit -m "refactor: consolidate MLModels, data, Storekit, and privacy resources under Resources/"
  ```

---

### Task 7: Mirror Reorganization in GJournalTests
Mirror the production subdirectory tree under `GJournalTests/` to clean up the flat folder and keep related tests close to each other.

**Files:**
* Modify: Relocate files in `/Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournalTests`

**Interfaces:**
* None

- [ ] **Step 1: Create target subdirectory folders**
  Run: `mkdir -p GJournalTests/Services/AI GJournalTests/Services/Math GJournalTests/Services/Insight GJournalTests/Repository GJournalTests/Core`

- [ ] **Step 2: Relocate AI & NLP service tests**
  Run:
  ```bash
  git mv GJournalTests/SemanticUtilsTests.swift GJournalTests/Services/AI/SemanticUtilsTests.swift
  git mv GJournalTests/WordPieceTokenizerTests.swift GJournalTests/Services/AI/WordPieceTokenizerTests.swift
  git mv GJournalTests/TagExtractorTests.swift GJournalTests/Services/AI/TagExtractorTests.swift
  git mv GJournalTests/TagProcessorTests.swift GJournalTests/Services/AI/TagProcessorTests.swift
  ```

- [ ] **Step 3: Relocate Mathematical and Geometric service tests**
  Run:
  ```bash
  git mv GJournalTests/GGMEstimatorTests.swift GJournalTests/Services/Math/GGMEstimatorTests.swift
  git mv GJournalTests/PersistentHomologyTests.swift GJournalTests/Services/Math/PersistentHomologyTests.swift
  git mv GJournalTests/ForceDirectedLayoutTests.swift GJournalTests/Services/Math/ForceDirectedLayoutTests.swift
  ```

- [ ] **Step 4: Relocate Insight and Trajectory tests**
  Run:
  ```bash
  git mv GJournalTests/TrajectoryServiceTests.swift GJournalTests/Services/Insight/TrajectoryServiceTests.swift
  git mv GJournalTests/HDBSCANTests.swift GJournalTests/Services/Insight/HDBSCANTests.swift
  ```

- [ ] **Step 5: Relocate Repository tests**
  Run: `git mv GJournalTests/AuthManagerTests.swift GJournalTests/Repository/AuthManagerTests.swift`
  *(Note: AuthManagerSecurityTests.swift was already moved here in Task 1)*

- [ ] **Step 6: Relocate Core module and smoke tests**
  Run:
  ```bash
  git mv GJournalTests/ExportAndModelChoiceTests.swift GJournalTests/Core/ExportAndModelChoiceTests.swift
  git mv GJournalTests/MigrationSmokeTests.swift GJournalTests/Core/MigrationSmokeTests.swift
  ```

- [ ] **Step 7: Verify test targets build correctly**
  Run: `xcodebuild -scheme GJournal -destination 'generic/platform=iOS Simulator' build-for-testing`
  Expected: **BUILD SUCCEEDED**

- [ ] **Step 8: Commit changes**
  Run:
  ```bash
  git add GJournalTests
  git commit -m "refactor: reorganize unit tests to mirror the production structure"
  ```

---

### Task 8: Full Build, Test Run, and Graphify Update
Run a clean compile and test verification loop to make sure all 92+ tests pass, and rebuild the Graphify knowledge graph.

**Files:**
* Modify: graphify-out knowledge graph

**Interfaces:**
* None

- [ ] **Step 1: Clean build the project**
  Run: `xcodebuild clean build -scheme GJournal -destination 'generic/platform=iOS Simulator'`
  Expected: **BUILD SUCCEEDED**

- [ ] **Step 2: Run the full test suite**
  Run: `xcodebuild test -scheme GJournal -destination 'generic/platform=iOS Simulator'`
  Expected: All 92+ tests pass, test output displays **TEST SUCCEEDED** or similar pass confirmations.

- [ ] **Step 3: Run graphify update command to sync the AST graph**
  Run: `graphify update .`
  Expected: Successful completion, updates graphify-out files.

- [ ] **Step 4: Verify git status is clean**
  Run: `git status`
  Expected: `nothing to commit, working tree clean`

- [ ] **Step 5: Verify the final git log**
  Run: `git log -n 10 --oneline`
  Expected: Lists the sequential commits for each reorganization task.
