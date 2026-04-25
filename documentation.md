UNIVERSITATEA BABES¸ -BOLYAI CLUJ-NAPOCA
ˇ
ˇ
FACULTATEA DE MATEMATIC
A S¸ I INFORMATIC
A
SPECIALIZAREA INFORMATICA
LUCRARE DE LICENT¸
˘
A
AI-Based Microjournaling for
Self-Reflection using Emotion
Detection and Clustering
Conduc˘ator s
tiint
ific
,
,
Professor, Lect. Horea Muresan
Absolvent
Dumitrascu Constantin-Alexandru
2026
ABSTRACT
Abstract: un rezumat ˆ ın limba englez˘ a cu prezentarea, pe scurt, a cont,
inutului
pe capitole, punˆ and accent pe contribut, iile proprii s, i originalitate
i
Cuprins
1 Introduction 1
2 Background and Related Work 2
2.1 Digital Journaling and Self-Reflection . . . . . . . . . . . . . . . . . . 2
2.2 Natural Language Processing in Personal Well-Being . . . . . . . . . 2
2.3 On-Device Machine Learning . . . . . . . . . . . . . . . . . . . . . . . 3
2.4 Clustering and Semantic Analysis . . . . . . . . . . . . . . . . . . . . 3
2.5 Mobile Hardware for On-Device AI . . . . . . . . . . . . . . . . . . . 3
2.5.1 Evolution of Mobile NPUs . . . . . . . . . . . . . . . . . . . . . 3
2.5.2 Implications for On-Device NLP . . . . . . . . . . . . . . . . . 4
2.5.3 Privacy and Energy Considerations . . . . . . . . . . . . . . . 5
2.6 Summary . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 5
3 System Requirements and Specification 6
3.1 3.2 3.3 Scope and Objectives . . . . . . . . . . . . . . . . . . . . . . . . . . . . 6
Assumptions and Constraints . . . . . . . . . . . . . . . . . . . . . . . 6
Functional Requirements . . . . . . . . . . . . . . . . . . . . . . . . . . 7
3.3.1 Core Functionality . . . . . . . . . . . . . . . . . . . . . . . . . 7
3.3.2 Editing and Deletion Policies . . . . . . . . . . . . . . . . . . . 8
3.4 3.5 Non-Functional Requirements . . . . . . . . . . . . . . . . . . . . . . . 8
System Architecture . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 8
3.5.1 Components . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 9
3.5.2 Architecture Diagram . . . . . . . . . . . . . . . . . . . . . . . 9
3.6 3.7 Data Flow and Processing Pipeline . . . . . . . . . . . . . . . . . . . . 9
Use Cases and User Flows . . . . . . . . . . . . . . . . . . . . . . . . . 10
3.7.1 Use Case UC1: Create Entry . . . . . . . . . . . . . . . . . . . . 10
3.7.2 Use Case UC2: View Insights . . . . . . . . . . . . . . . . . . . 11
3.7.3 Use Case UC3: Edit Entry . . . . . . . . . . . . . . . . . . . . . 11
3.7.4 Use Case UC4: Delete Entry . . . . . . . . . . . . . . . . . . . . 11
3.7.5 Use Case UC5: Notification for Reflection . . . . . . . . . . . . 11
3.8 Model Selection and Formats . . . . . . . . . . . . . . . . . . . . . . . 11
ii
CUPRINS
3.9 Clustering Strategy . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 3.10 Security and Privacy . . . . . . . . . . . . . . . . . . . . . . . . . . . . 3.11 Performance Targets and Testing . . . . . . . . . . . . . . . . . . . . . 3.12 Acceptance Criteria . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 3.13 Implementation Plan and Milestones . . . . . . . . . . . . . . . . . . . 3.14 Traceability Matrix . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 3.15 Open Issues and Decisions . . . . . . . . . . . . . . . . . . . . . . . . . 3.16 Summary . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 12
12
12
13
13
13
14
14
4 Implementation 15
5 Concluzii 16
Bibliografie 17
iii
Capitolul 1
Introduction
Personal journaling has evolved from simple note-taking into a practice suppor-
ted by digital tools that encourage self-reflection and emotional awareness. Recent
advances in mobile hardware and on-device machine learning make it possible to
analyze personal text privately, without relying on cloud services. This thesis explo-
res how such capabilities can be used to support individuals who journal regularly
or who seek to better understand their thoughts, emotions, and behavioral patterns.
The project proposes a mobile microjournaling system that processes short user
entries directly on the device using compact language models, emotion detection
techniques, and clustering algorithms. By extracting semantic representations of
journal entries and grouping them based on similarity, the system aims to reveal
recurring themes and emotional trends that may otherwise remain unnoticed. Ru-
nning all computation locally ensures that sensitive personal data remains private
while still enabling meaningful insights.
The methodology builds on prior work in emotion recognition on edge devices
[PRA+21], efficient clustering for mobile processors [AH22], and NLP-assisted jour-
naling systems [MBS+23]. In addition, recent developments in lightweight transfor-
mer architectures such as MobileBERT [SYS+20], DistilBERT [SDCW19], and Tiny-
BERT [JYS+20] demonstrate that high-quality language understanding can be achi-
eved with significantly reduced computational cost, making them suitable for mo-
dern smartphone NPUs.
The goal of this bachelor thesis is to provide a technical contribution to the design
and implementation of an on-device AI system for personal reflection. The chapters
that follow present the theoretical foundations, the rationale behind the chosen mo-
dels and algorithms, the system architecture, and the practical implementation of
the mobile application.
1
Capitolul 2
Background and Related Work
This chapter reviews the theoretical foundations and prior work relevant to the
development of an on-device microjournaling system. The discussion covers four
main areas: digital journaling and self-reflection tools, natural language processing
techniques used in personal well-being applications, on-device machine learning
and clustering, and the evolution of mobile hardware that enables efficient local
inference.
2.1 Digital Journaling and Self-Reflection
Digital journaling platforms have become increasingly popular as tools for emo-
tional awareness, habit tracking, and personal development. Systems such as reflec-
tive writing assistants, mood trackers, and guided journaling applications aim to
support users in understanding their thoughts and behaviors. Prior research shows
that structured journaling can improve emotional regulation and self-awareness [?].
Recent work has explored AI-assisted journaling, where natural language proces-
sing is used to extract insights from user text [MBS+23]. These systems demonstrate
the potential of automated analysis to enhance personal reflection, but most rely on
cloud-based processing, raising privacy concerns.
2.2 Natural Language Processing in Personal Well-Being
NLP techniques have been widely applied to sentiment analysis, emotion detec-
tion, and mental health monitoring. Transformer-based models have become the
dominant approach due to their strong contextual understanding. However, full-
size models such as BERT are computationally expensive and unsuitable for mo-
bile deployment. Lightweight transformer variants such as DistilBERT [SDCW19],
TinyBERT [JYS+20], and MobileBERT [SYS+20] enable on-device processing while
2
CAPITOLUL 2. BACKGROUND AND RELATED WORK
maintaining competitive accuracy. These models are particularly relevant for appli-
cations involving sensitive personal data, where local inference is preferred over
cloud-based computation.
2.3 On-Device Machine Learning
On-device machine learning has gained traction due to improvements in mo-
bile NPUs and the need for privacy-preserving computation. Research on edge-
based emotion detection [PRA+21] and optimized clustering algorithms for mobile
processors [AH22] demonstrates that meaningful analysis can be performed loca-
lly. Frameworks such as Core ML and TensorFlow Lite further support efficient de-
ployment of compact models on smartphones, enabling real-time inference without
network connectivity.
2.4 Clustering and Semantic Analysis
Clustering algorithms are widely used to group semantically similar text en-
tries. Density-based methods such as DBSCAN [EKSX96] are particularly suitable
for small, irregular datasets like personal journals, as they do not require specifying
the number of clusters in advance and can identify noise points. Recent work com-
bining transformer embeddings with clustering has shown promising results for
topic discovery and personal data organization. These techniques form the basis for
grouping microjournal entries into meaningful themes.
2.5 Mobile Hardware for On-Device AI
The feasibility of running NLP models directly on mobile devices has increased
significantly due to advances in smartphone hardware. Modern devices integrate
specialized Neural Processing Units (NPUs) capable of performing billions of ope-
rations per second, enabling efficient execution of compact transformer models.
2.5.1 Evolution of Mobile NPUs
Early smartphones relied primarily on CPUs and GPUs for machine learning
workloads, which resulted in high latency, limited throughput, and significant energy
consumption. The introduction of dedicated NPUs fundamentally changed this lan-
dscape. Modern mobile chipsets, such as Apple’s A-series and M-series processors
3
CAPITOLUL 2. BACKGROUND AND RELATED WORK
and Qualcomm’s Snapdragon 8-series platforms, integrate specialized hardware op-
timized for matrix multiplication, low-precision arithmetic, and transformer infe-
rence.
Table 2.1 and Table 2.2 summarize the evolution of NPU performance (measured
in TOPS—tera operations per second) across recent Apple and Qualcomm chip ge-
nerations. The data shows a rapid increase in available compute, with Apple’s A17
Pro reaching 35 TOPS and Qualcomm’s Snapdragon 8 Gen 3 achieving 45 TOPS.
Estimated values are included where manufacturers did not publish official TOPS
figures.
Tabela 2.1: NPU performance in Apple A-series and M-series chips (2019–2025).
Year Chip Device TOPS
2019 A13 Bionic iPhone 11∼6 (est.)
2020 A14 Bionic iPhone 12 11
2020 M1 MacBook Air/Pro 11
2021 A15 Bionic iPhone 13 15.8
2022 A16 Bionic iPhone 14 Pro / 15 17
2022 M2 MacBook Air (M2) 15.8
2023 A17 Pro iPhone 15 Pro 35
2023 M3 MacBook Pro (M3) 18
2024 A18 / A18 Pro iPhone 16 series 35
2024 M4 iPad Pro / MacBook Pro 38
2025 A19 Pro iPhone 17 Pro Max∼38 (est.)
Tabela 2.2: NPU performance in Qualcomm Snapdragon flagship chips (2021–2025).
Year Chip Device TOPS
2021 Snapdragon 888 Galaxy S21 26
2022 Snapdragon 8 Gen 1 Galaxy S22∼32 (est.)
2023 Snapdragon 8 Gen 2 Galaxy S23∼40 (est.)
2024 Snapdragon 8 Gen 3 Galaxy S24 45
2024/25 Snapdragon 8 Elite Galaxy S25∼65 (est.)
Figure 2.1 visualizes the growth trend of NPU performance across these chip fa-
milies. The rapid increase in TOPS over the past five years highlights the feasibility
of running transformer-based NLP models directly on mobile devices.
2.5.2 Implications for On-Device NLP
The increased computational capacity of modern NPUs allows for real-time infe-
rence of lightweight transformer models such as MobileBERT, DistilBERT, and Tiny-
BERT. These models benefit from:
• reduced memory footprint,
4
CAPITOLUL 2. BACKGROUND AND RELATED WORK
Evolution of Mobile NPU Performance (TOPS/s)
Apple A-series (iPhone)
Qualcomm Snapdragon 8-series
NPU Performance (TOPS)
60
50
40
30
20
10
2019 2020 2021 2022 2023 2024 2025
Year
Figura 2.1: Growth of NPU performance (TOPS/s) across recent Apple and Qual-
comm chipsets. Data aggregated from public specifications and industry estimates.
• lower latency,
• compatibility with 8-bit and 16-bit quantization,
• efficient execution on NPU hardware.
As a result, tasks such as semantic embedding, emotion detection, and clustering
can be performed entirely on the device without requiring cloud-based processing.
2.5.3 Privacy and Energy Considerations
On-device processing offers strong privacy guarantees, as user data never leaves
the device. This is essential for journaling applications, where entries may contain
highly personal information. Additionally, modern NPUs are designed for energy-
efficient computation, reducing the battery impact of background tasks such as em-
bedding generation and clustering.
2.6 Summary
This chapter reviewed the theoretical foundations and technological context for
building an on-device microjournaling system. Prior work demonstrates the value
of journaling for self-reflection, the effectiveness of transformer-based NLP models,
and the feasibility of performing inference directly on mobile devices. The rapid
evolution of mobile NPUs further strengthens the case for on-device processing,
enabling privacy-preserving, low-latency analysis of personal text data.
5
Capitolul 3
System Requirements and
Specification
This chapter defines the practical requirements, system specification, and design
constraints for the on-device microjournaling application. It translates user goals
into functional and non-functional requirements, describes the high-level architec-
ture and data flow, and lists acceptance criteria and test targets for the prototype
implementation.
3.1 Scope and Objectives
The application targets iOS, iPadOS, and macOS and performs all natural langu-
age processing locally on the device. The primary objectives are:
• Provide a secure micro-journaling experience with short text entries.
• Generate semantic embeddings and detect emotion for each entry on device.
• Group entries into semantically coherent clusters and present them via list,
calendar, and graph visualizations.
• Preserve user privacy by avoiding cloud storage or remote inference.
• Maintain acceptable interactive performance on devices from iPhone 11 and
newer.
3.2 Assumptions and Constraints
The following assumptions and constraints are used throughout the specifica-
tion:
6
CAPITOLUL 3. SYSTEM REQUIREMENTS AND SPECIFICATION
• Target platforms: iOS, iPadOS, macOS.
• All NLP inference and clustering run on device; cloud sync is not supported.
• Entry length is limited to approximately 500–600 characters.
• Minimum supported device class: iPhone 11 or equivalent NPU capability.
• Development stack: Swift + SwiftUI, Core ML for inference, SwiftData for local
persistence, Python (RTX2070) for model fine-tuning and conversion.
• Models will be quantized and converted to Core ML format to reduce size and
improve inference speed.
• Where user input is incomplete, reasonable defaults are chosen and documen-
ted in this chapter.
3.3 Functional Requirements
Each functional requirement is identified by an ID for traceability.
3.3.1 Core Functionality
FR1 User authentication and local security. The app must support biometric au-
thentication (Face ID / Touch ID) and a fallback PIN to protect access to journal
content.
FR2 Create micro-journal entry. The user can create a short text entry. The entry
editor opens a focused input screen that ”takes the story” from the user.
FR3 Entry views. The user can view entries in a calendar view, a chronological list
view, and a graph view that visualizes clusters and relationships.
FR4 On-device analysis. Immediately after saving an entry, the system generates a
semantic embedding and runs an emotion classifier locally.
FR5 Clustering. The system groups entries into clusters using an on-device clus-
tering algorithm. Clustering runs incrementally on new entries and can be
re-computed in batch.
FR6 Search and filtering. The user can search entries by text and filter by date,
detected emotion, and cluster membership.
FR7 Local storage and export. All data is stored locally. The user can export an
encrypted local backup file to the device file system.
7
CAPITOLUL 3. SYSTEM REQUIREMENTS AND SPECIFICATION
FR8 Notifications (optional). The app may send optional local notifications to
prompt reflection when the system detects a need for review.
3.3.2 Editing and Deletion Policies
FR9 Edit policy. The user may edit entries created on the same calendar day. Edits
update embeddings and cluster assignments.
FR10 Deletion policy. The user may delete entries. Deleted entries are soft-deleted
and retained for a configurable grace period (default three days) before per-
manent removal.
3.4 Non-Functional Requirements
NFR1 Privacy. No user text or embeddings leave the device. No cloud services are
used for inference or storage.
NFR2 Security. Local data at rest must be encrypted using platform APIs. Biome-
tric/PIN gating is required for app access.
NFR3 Performance. Interactive analysis latency should be under five seconds on
the minimum target device for a single entry; background batch clustering
may take longer.
NFR4 Model footprint. Individual on-device models should be quantized and kept
as small as practical; a soft target is under 100 MB combined for core models.
NFR5 Battery and resource usage. Background processing must be scheduled to
minimize battery impact; heavy tasks should run when the device is idle or
charging.
NFR6 Reliability. The app must handle model failures gracefully and fall back to
a degraded mode that preserves user data and basic UI functionality.
NFR7 Accessibility. The UI must follow platform accessibility guidelines (dynamic
type, VoiceOver support).
3.5 System Architecture
This section describes the high-level components and their responsibilities.
8
CAPITOLUL 3. SYSTEM REQUIREMENTS AND SPECIFICATION
3.5.1 Components
• UI Layer (SwiftUI). Entry editor, calendar view, list view, graph view, settings,
and authentication screens.
• Persistence Layer (SwiftData). Local database for entries, embeddings, clus-
ter metadata, and user settings. Data encryption at rest is applied here.
• Inference Engine (Core ML). On-device models for embedding generation
and emotion classification. Models are loaded and executed via Core ML APIs.
• Clustering Engine. Local implementation of a density-aware clustering al-
gorithm (DBSCAN or similar) optimized for small datasets and incremental
updates.
• Scheduler / Background Worker. Manages periodic batch clustering, model
updates, and low-priority maintenance tasks.
• Export / Backup Module. Creates encrypted local backups and restores from
backups.
3.5.2 Architecture Diagram
Include a component diagram illustrating the UI, Persistence, Inference Engine,
Clustering Engine, and Background Worker. Place the diagram file at figures/architecture.
and reference it here.
3.6 Data Flow and Processing Pipeline
The canonical data flow for a new entry is:
1. User creates an entry in the editor and saves it.
2. The Persistence Layer stores the raw text and metadata.
3. The Inference Engine generates a semantic embedding and an emotion label
for the entry.
4. The embedding and label are stored alongside the entry.
5. The Clustering Engine performs an incremental update to cluster assignments.
6. The UI updates calendar, list, and graph views to reflect the new entry and
cluster membership.
9
CAPITOLUL 3. SYSTEM REQUIREMENTS AND SPECIFICATION
High-level system architecture for the on-device microjournaling application
Device Security
(Biometric / PIN)
UI
(SwiftUI)
data flow
Scheduler /
Background Worker
Persistence
(SwiftData)
cluster updates
embeddings
data flow
background tasks backup data
Clustering Engine
Data Store
(Encrypted DB)
Export /
Backup Module
data flow
Inference Engine
(Core ML)
embeddings + labels
Legend
Data flow
(dashed) Control / Security
Figura 3.1: High-level system architecture showing major components and data
flow.
A periodic batch job re-computes clusters and cluster summaries during idle
time or when the device is charging.
3.7 Use Cases and User Flows
This section lists primary use cases and step-by-step flows.
3.7.1 Use Case UC1: Create Entry
• Actor: Authenticated user.
• Precondition: App unlocked.
• Flow: User opens editor, types entry (400, 150 per field), taps Save. System
stores entry, runs inference, updates clusters, and refreshes views.
• Postcondition: Entry visible in calendar/list/graph with detected emotion
and cluster assignment.
10
CAPITOLUL 3. SYSTEM REQUIREMENTS AND SPECIFICATION
3.7.2 Use Case UC2: View Insights
• Actor: Authenticated user.
• Flow: User opens Insights or Graph view. System displays clusters, represen-
tative entries, and emotion distribution. User can tap a cluster to see member
entries.
3.7.3 Use Case UC3: Edit Entry
• Actor: Authenticated user.
• Constraint: Editing allowed only for entries created on the same calendar day.
• Flow: User edits entry; system re-computes embedding and updates cluster
membership.
3.7.4 Use Case UC4: Delete Entry
• Actor: Authenticated user.
• Flow: User deletes entry. Entry is soft-deleted and retained for a configurable
grace period (default three days) before permanent removal.
3.7.5 Use Case UC5: Notification for Reflection
• Actor: System (scheduler).
• Flow: Scheduler evaluates cluster activity and user patterns; if conditions are
met and notifications are enabled, a local notification prompts the user to re-
view recent clusters or entries.
3.8 Model Selection and Formats
Recommended model strategy for on-device inference:
• Embedding model: A compact sentence embedding model derived from a
distilled transformer (MobileBERT or TinyBERT family) fine-tuned for seman-
tic similarity. Convert to Core ML and apply 8-bit quantization where possible.
• Emotion classifier: A lightweight classifier (distilled transformer or small CNN
on top of embeddings) converted to Core ML and quantized.
• Training and conversion: Fine-tune models in Python on an RTX2070, then
convert to Core ML using coremltools. Validate accuracy before deployment.
11
CAPITOLUL 3. SYSTEM REQUIREMENTS AND SPECIFICATION
3.9 Clustering Strategy
• Use a density-based algorithm (DBSCAN or HDBSCAN variant) for robust-
ness to noise and variable cluster sizes.
• Maintain an index of embeddings in the local database to support incremental
clustering.
• Provide parameters exposed in settings (minimum samples, epsilon) with safe
defaults tuned for short personal entries.
• Support a nightly batch re-clustering job to refine cluster boundaries and com-
pute cluster summaries.
3.10 Security and Privacy
• Local encryption: Use platform keychain and file encryption APIs to protect
data at rest.
• Authentication: Require biometric or PIN to unlock the app.
• No network transmission: By default, the app must not transmit journal text,
embeddings, or cluster metadata off device.
• Backup: Exported backups must be encrypted and stored only in user-controlled
locations.
3.11 Performance Targets and Testing
• Interactive inference latency: Target under 5 seconds on iPhone 11 for embe-
dding + emotion classification.
• Incremental clustering latency: Target under 2 seconds for updating cluster
membership when adding a single entry.
• Batch clustering: Acceptable to run for up to several minutes during idle/charging
periods.
• Memory and storage: Keep combined model size under 100 MB where possi-
ble; journal database should remain responsive under 200 MB of stored entries.
• Testing plan: Measure latency, memory, and battery impact on representative
devices (iPhone 11, iPhone 15, Macbook Pro M1). Evaluate clustering quality
12
CAPITOLUL 3. SYSTEM REQUIREMENTS AND SPECIFICATION
using internal metrics (silhouette, ARI) on synthetic and anonymized sample
datasets.
3.12 Acceptance Criteria
The prototype is acceptable when:
• FR1–FR8 are implemented and demonstrable.
• On-device inference completes within the performance targets on the mini-
mum device.
• Data remains local and encrypted; biometric/PIN gating functions correctly.
• Clustering produces coherent groups for a sample dataset and the graph view
reflects cluster structure.
• Export and restore of encrypted backups succeed without data loss.
3.13 Implementation Plan and Milestones
1. Step 1: Project scaffolding, SwiftUI prototypes for editor, calendar, list, and
graph views.
2. Step 2: Integrate persistence (SwiftData) and local security (biometric/PIN).
3. Step 3: Convert and integrate Core ML models for embedding and emotion
detection; implement inference pipeline.
4. Step 4: Implement clustering engine, incremental updates, and graph visuali-
zation.
5. Step 5: Performance tuning, quantization, and device testing; prepare delive-
rables for Lab 4.
3.14 Traceability Matrix
Provide a table mapping functional requirements to implementation compo-
nents and acceptance tests. Place this table in the appendix as Table 3.1.
13
CAPITOLUL 3. SYSTEM REQUIREMENTS AND SPECIFICATION
Tabela 3.1: Requirement traceability (excerpt).
Requirement Implementation Compo-
nent
Acceptance Test
FR1 Authenti-
cation
FR2 Create en-
try
FR4 On-device
analysis
Platform biometric APIs,
Keychain
SwiftUI editor, SwiftData Unlock app with Face ID /
PIN
Save entry and verify sto-
red text
Core ML models, infe-
Embedding and emotion
rence pipeline
label present after save
FR5 Clustering Local clustering engine New entry assigned to
cluster within target la-
tency
3.15 Open Issues and Decisions
The following items require confirmation or further refinement:
• Exact model size budget and acceptable quantization level.
• Fine-tuning dataset and privacy guarantees for training data.
• Detailed notification rules for prompting reflection.
• Retention policy and user controls for soft-deleted entries.
3.16 Summary
This chapter specified the functional and non-functional requirements, the high-level
architecture, data flow, and acceptance criteria for the on-device microjournaling
system. The next chapter will describe the implementation details, model conver-
sion steps, and the evaluation methodology used to validate the prototype.
14
Capitolul 4
Implementation
15
Capitolul 5
Concluzii
Concluzii ...
16
Bibliografie
[AH22] Fouad H Awad and Murtadha M Hamad. Improved k-means clustering
algorithm for big data based on distributed smartphone neural engine
processor. Electronics, 11(6):883, 2022.
[EKSX96] Martin Ester, Hans-Peter Kriegel, J¨ org Sander, and Xiaowei Xu. A
density-based algorithm for discovering clusters in large spatial data-
bases with noise. In KDD, 1996.
[Inc23a] Apple Inc. Apple neural engine performance overview, 2023. Available
online: https://developer.apple.com/machine-learning/.
[Inc23b] Qualcomm Technologies Inc. Qualcomm hexagon processor: Ai perfor-
mance overview, 2023. Available online: https://www.qualcomm.
com/.
[JYS+20] Xiaoqi Jiao, Yichun Yin, Lifeng Shang, Xin Jiang, Xiao Chen, Linlin Li,
Fang Wang, and Qun Liu. Tinybert: Distilling bert for natural language
understanding. In EMNLP, 2020.
[MBS+23] Amit Kumar Mishra, Krishna Kant Bhartiy, Jagendra Singh, Srinivas
Aluvala, Prabhishek Singh, and Kaushal Kishor. Unlocking the power of
natural language processing through journaling with the assistance. In
2023 3rd International Conference on Innovative Sustainable Computational
Technologies (CISCT), 2023.
[PRA+21] Vlad Pandelea, Edoardo Ragusa, Tommaso Apicella, Paolo Gastaldo,
and Erik Cambria. Emotion recognition on edge devices: Training and
deployment. Sensors, 21(13):4496, 2021.
[SDCW19] Victor Sanh, Lysandre Debut, Julien Chaumond, and Thomas Wolf. Dis-
tilbert, a distilled version of bert: smaller, faster, cheaper and lighter. In
NeurIPS Workshop, 2019.
[Siv22] Lakshmi Priya Kenday Sivaram. Healthy me: Exploring personal health
journaling with visual analytics for self-reflection and knowledge sha-
17
BIBLIOGRAFIE
[SYS+20] ring. Master of science thesis, Simon Fraser University, Canada, 2022.
Available online: https://summit.sfu.ca/item/22212.
Zhiqing Sun, Hongkun Yu, Xiaodan Song, Renjie Liu, Yiming Yang, and
Denny Zhou. Mobilebert: a compact task-agnostic bert for resource-
limited devices. In ACL, 2020.
18