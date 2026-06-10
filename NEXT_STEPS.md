# Thesis — What To Do Next

**Date:** June 10, 2026  
**Supervisor:** Lect. PhD. Horea-Bogdan Muresan

---

## Task List

1. Fix supervisor's name in `main.tex`
2. Remove TODO line from `chapter2_background.tex`
3. Expand or merge short sections 2.1–2.5 in the Background chapter
4. Convert Use Cases (3.7.1–3.7.4) from subsections to a table
5. Remove bare TODO from the "Open Issues" section in `chapter2.tex`
6. Create and add the missing architecture diagram
7. Rerun Step 2 (Clustering Quality) on TweetSentimentExtractionClustering
8. Rerun Step 3 (Algorithm Comparison) on TweetSentimentExtractionClustering
9. Build the Step 4 domain validation dataset and run it
10. Add Step 5: on-device efficiency measurements
11. Update the evaluation chapter with new results
12. Run the full LaTeX compile sequence and check the final PDF

---

## Task Details

---

### Task 1 — Fix supervisor's name in `main.tex`

**File:** `latex/main.tex`, line 9

**Current:**
```
\supervisor{Professor, Lect. Horea Muresan}
```

**Fix to:**
```
\supervisor{Lect. PhD. Horea-Bogdan Muresan}
```

One line change. Do this first — it affects the title page.

---

### Task 2 — Remove TODO line from `chapter2_background.tex`

**File:** `latex/chapters/chapter2_background.tex`, line 3

**Current:**
```
TODO: Not up to date, need rewrite of model names and some revision.
```

Delete that line. The chapter content is actually correct — the three models (MiniLM, Nomic, Apple NLEmbedding) are already named properly throughout the file. The TODO was a leftover note. Once deleted, the chapter is clean.

---

### Task 3 — Expand or merge short sections in the Background chapter

**Problem:** Sections 2.1, 2.3, 2.4, and 2.5 each have only 1–2 paragraphs, which is too thin for standalone sections. Supervisor flagged this.

**File:** `latex/chapters/chapter2_background.tex`

**What to do for each:**

**Section 2.1 — Digital Journaling and Self-Reflection:**  
Add 1–2 sentences naming concrete competing apps (Daylio, Reflectly, Journey) and what they lack compared to GJournal (cloud-based AI, no on-device processing, no knowledge graph). This sets up the novelty argument for your thesis.

Example addition after the second paragraph:
> Existing journaling apps such as Daylio, Reflectly, and Journey offer mood tracking and guided prompts, but rely on manual tagging or cloud-based NLP. GJournal differs in that all analysis runs on the device, eliminating the need to send personal text to a remote server.

**Section 2.3 — Matryoshka Representation Learning:**  
This section is fine in content but short. Add a sentence explaining why the nested loss works intuitively — the model is forced to pack the most discriminative information into the first few dimensions, so early dimensions alone form a useful subspace.

**Sections 2.4 and 2.5 — On-Device Machine Learning and Clustering:**  
These are each one paragraph. The simplest fix is to **merge them into one section** called "On-Device NLP and Clustering for Personal Data." The topics connect naturally: dense embeddings running locally feed directly into local clustering.

---

### Task 4 — Convert Use Cases to a table

**Problem:** Subsections 3.7.1–3.7.4 each have 1–3 sentences. Supervisor explicitly suggested reorganizing as a table.

**File:** `latex/chapters/chapter2.tex`, in the `\section{Use Cases and User Flows}` block

**Replace** the four `\subsection` blocks with this LaTeX table:

```latex
\section{Use Cases and User Flows}

Table~\ref{tab:use_cases} summarises the four primary use cases.

\begin{table}[h!]
\centering
\caption{Primary use cases.}
\label{tab:use_cases}
\begin{tabular}{p{0.13\textwidth} p{0.28\textwidth} p{0.46\textwidth}}
\hline
\textbf{ID} & \textbf{Trigger} & \textbf{System Response} \\
\hline
UC1 Create Entry   & User fills in Feel/Event/Action fields and taps Save & Entry stored; embedding and emotion label generated on-device; clusters updated; calendar, list, and graph views refreshed. \\
\hline
UC2 View Insights  & User opens the Graph or Insights screen & Clusters, representative entries, and emotion distribution displayed. Tapping a cluster reveals its member entries. \\
\hline
UC3 Edit Entry     & User edits an entry created on the same calendar day & Text updated; embedding and emotion label recomputed; cluster membership reassigned accordingly. \\
\hline
UC4 Delete Entry   & User deletes an entry & Entry soft-deleted and hidden immediately; permanently removed after the three-day grace period. \\
\hline
\end{tabular}
\end{table}
```

---

### Task 5 — Remove the bare TODO from "Open Issues"

**File:** `latex/chapters/chapter2.tex`, lines 134–135

**Current:**
```latex
\section{Open Issues and Decisions}
TODO: 
```

Either delete the entire section (it has no content) or replace it with one sentence acknowledging the schema migration issue:

```latex
\section{Open Issues}
The main open issue is SwiftData schema migration: the current implementation wipes stored data on model changes. A versioned migration policy is required before any production deployment.
```

---

### Task 6 — Create and add the architecture diagram

**File to create:** `latex/figures/architecture.pdf`

**Problem:** This file was deleted. `chapter2.tex` line 56 tries to include it and LaTeX throws a hard error, leaving a blank figure in the PDF.

**What the diagram should show:** Five boxes connected by arrows:
```
SwiftUI (UI Layer)
    ↓
Repository Layer
    ↓ ↑
AIProcessingManager
    ├── Inference Engine (Core ML)
    │       ├── EmbeddingService (MiniLM / Nomic / NLEmbedding)
    │       └── EmotionService (MobileBERT)
    └── Clustering Engine (DBSCAN)
    ↓
SwiftData (Persistence)
```

**How to make it:**
1. Open [diagrams.net](https://app.diagrams.net) in your browser (free, no install)
2. Draw the five boxes with arrows — 10 minutes of work
3. File → Export as → PDF
4. Save as `latex/figures/architecture.pdf`

Also remove the two TODO lines in `chapter2.tex` at lines 52–53:
```
TODO: add architecture diagram (figures/architecture.pdf) ...
TODO: update digram for dataflow ...
```

---

### Task 7 — Rerun Step 2 on TweetSentimentExtractionClustering

**Current dataset:** TwentyNewsgroupsClustering (news articles)  
**New dataset:** TweetSentimentExtractionClustering (short tweets, closer to journal entries)

**Why switch:** News article sentences are long and topically distinct, making clustering artificially easy. Tweets are short informal text like journal entries — this makes Step 2 a better proxy for how the models will behave in production.

**How to run it:**

The dataset is available through MTEB (Massive Text Embedding Benchmark). Install it if not already:

```bash
cd training
source venv/bin/activate
pip install mteb
```

Then in `evaluation/step2_clustering_quality.py`, replace the dataset loader:

```python
# Replace TwentyNewsgroupsClustering with:
from mteb import MTEB
task = MTEB(tasks=["TweetSentimentExtractionClustering"])
```

Or load it directly via Hugging Face:
```python
from datasets import load_dataset
ds = load_dataset("mteb/tweet_sentiment_extraction", split="test")
```

Run the same four models (MiniLM-384, Nomic-256, Nomic-768, Apple NLP-512) with the same adaptive DBSCAN logic. Record V-measure, ARI, NMI, Noise Ratio. Replace the results in `evaluation/results/step2_clustering_quality.csv`.

---

### Task 8 — Rerun Step 3 on TweetSentimentExtractionClustering

**Current:** Algorithm comparison ran on TwentyNewsgroups using Nomic-768.  
**New:** Same comparison on TweetSentimentExtractionClustering.

The four variants to compare stay the same:
- Vanilla DBSCAN (fixed eps=0.3, minPoints=3)
- Classic Adaptive (Kneedle + ε calibration)
- MRL-Adapted (same but with ε scaled by √(d/768))
- HDBSCAN

Just change the dataset in `evaluation/step3_algorithm_comparison.py` and rerun. This should take under an hour.

The results in `evaluation/results/step3_algorithm_comparison.csv` and the corresponding table in `latex/chapters/chapter4.tex` will need to be updated with the new numbers.

---

### Task 9 — Build the Step 4 domain validation dataset

**Current Step 4:** Used 100 manually labelled journal entries with adaptive DBSCAN.  
**Issue:** You cannot reuse TweetSentiment data for domain validation because it's the same source as Step 2 — that would be circular.

**Plan:**

1. **Write 20–30 seed entries by hand.** Short journal-style sentences grouped into 3–5 topics. For example:
   - Group A (work/study): "Had a difficult exam today. Spent 4 hours reviewing code."
   - Group B (fitness): "Went for a run in the park. Feeling sore but good."
   - Group C (family): "Had dinner with my parents. It was nice to catch up."

2. **Use an LLM to expand each group to ~20 entries.** Prompt Claude or ChatGPT:
   > "I have this journal entry: [entry]. Write 5 paraphrases that say the same thing in different words, keeping the same topic and roughly the same length."

3. **Label each entry with a ground-truth cluster ID** (just an integer: 0, 1, 2, 3...).

4. **Save as a CSV** with columns: `text, ground_truth_cluster`.

5. **Run the same pipeline** as the current step4 script: embed → adaptive DBSCAN → compare predicted clusters to ground truth. Metrics: V-measure, ARI, NMI, Noise Ratio.

Target size: 80–120 entries across 4–5 topics. That's enough for meaningful metrics without taking days to create.

---

### Task 10 — Add Step 5: on-device efficiency measurements

**This step does not exist yet.** The thesis mentions latency numbers in prose (20ms for Nomic, 120ms for MiniLM, 200ms for MobileBERT) but there is no dedicated efficiency table, no model size comparison, and no cold start or memory numbers.

**What to measure and how:**

| Metric | How to measure |
|--------|---------------|
| Inference latency (ms/entry) | Time `model.prediction()` in Swift using `Date()` before/after, average over 50 calls |
| Model size (MB) | `ls -lh` on each `.mlpackage` directory in Xcode |
| Cold start (ms) | Time `MLModel(contentsOf:)` load call — the first call before any inference |
| Peak memory (MB) | Instruments → Allocations instrument, trigger inference, read peak |

**Where to run it:** On-device on iPhone 14 or newer. Simulator numbers are not representative — Core ML uses the actual Neural Engine on device only.

**What to add to the thesis:** A new section in the evaluation chapter (Chapter 5) after the domain validation section:

```
\section{On-Device Efficiency}
Table X: Model | Latency (ms) | Model Size (MB) | Cold Start (ms) | Peak Memory (MB)
```

This is a strong addition because it directly answers the practical question of "is this usable on a real phone."

---

### Task 11 — Update the evaluation chapter with new results

After Tasks 7–10 produce new numbers:

- Update Table `tab:clustering_quality` (Step 2 results) in `latex/chapters/chapter4.tex`
- Update Table `tab:algorithm_comparison` (Step 3 results) in `latex/chapters/chapter4.tex`
- Update Table `tab:domain_validation` (Step 4 results) in `latex/chapters/chapter4.tex`
- Add new Table for Step 5 (on-device efficiency)
- Update the discussion section (Section 5.7) to reflect any changes in conclusions

Also update the abstract and conclusions chapter if the new numbers change the main findings.

---

### Task 12 — Run the full compile sequence and check the PDF

From the `latex/` directory:

```bash
pdflatex main.tex
bibtex main
pdflatex main.tex
pdflatex main.tex
```

Four commands. Running only `pdflatex` once gives undefined reference warnings. Running the full sequence resolves all cross-references and the bibliography.

**After compiling, open `main.pdf` and check:**
- Title page has the correct supervisor name
- Table of contents lists all chapters with correct page numbers
- Architecture figure appears (not blank)
- All tables render correctly — especially the evaluation tables in Chapter 5
- No `??` placeholders anywhere (these mean unresolved references)
- Bibliography section is populated at the end
- No TODO text visible anywhere in the document

---

## Order of Operations

```
Quick fixes (do today):
  Task 1  — Fix supervisor name               (1 line)
  Task 2  — Remove TODO from background ch.   (1 line)
  Task 5  — Remove TODO from open issues      (2 lines)

Writing fixes (a few hours):
  Task 3  — Expand/merge short sections       (1–2 paragraphs)
  Task 4  — Convert use cases to table        (replace 4 subsections)
  Task 6  — Create architecture diagram       (draw.io, ~30 min)

Evaluation reruns (half a day each):
  Task 7  — Rerun Step 2 on TweetSentiment
  Task 8  — Rerun Step 3 on TweetSentiment
  Task 9  — Build domain dataset + run Step 4
  Task 10 — On-device Instruments profiling

Final assembly:
  Task 11 — Update LaTeX tables with new results
  Task 12 — Full compile, read PDF end to end
```
