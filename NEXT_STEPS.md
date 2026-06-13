# Thesis — What To Do Next

**Date:** June 10, 2026  
**Supervisor:** Lect. PhD. Horea-Bogdan Muresan

---

## Task List

1. Fix supervisor's name in `main.tex`
2. Remove TODO line from `chapter2_background.tex`
3. ~~Expand or merge short sections 2.1–2.5 in the Background chapter~~ **DONE**
4. ~~Convert Use Cases (3.7.1–3.7.4) from subsections to a table~~ **DONE**
5. Remove bare TODO from the "Open Issues" section in `chapter2.tex`
6. ~~Create and add the missing architecture diagram~~ **DONE** (PlantUML, `figures/architecture.pdf`)
7. ~~Add on-device efficiency measurements~~ **DONE** (benchmark button + thesis section updated)
8. Run the full LaTeX compile sequence and check the final PDF

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

### Task 3 — ~~Expand or merge short sections in the Background chapter~~ DONE

Sections 2.4 and 2.5 merged into "On-Device NLP and Clustering for Personal Data."  
Section 2.1 expanded with comparison to Daylio/Reflectly/Journey.  
Section 2.3 (MRL) expanded with an intuitive explanation of the nested loss.

---

### Task 4 — ~~Convert Use Cases to a table~~ DONE

Four `\subsection` blocks replaced with a single `\begin{table}` in `chapter2.tex`.

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

### Task 6 — ~~Create and add the missing architecture diagram~~ DONE

`latex/figures/architecture.pdf` generated from PlantUML (`latex/figures/architecture.puml`).  
Shows all four layers: SwiftUI → Repository → Service Layer (AIProcessingManager, Core ML Inference Engine, DBSCANClusterer, SafetyFilter) → SwiftData.  
The two TODO lines in `chapter2.tex` were removed at the same time.

---

### Task 7 — ~~Add on-device efficiency measurements~~ DONE

- Button added to Settings → "Thesis" section in the iOS app (`GJournal/Services/EfficiencyBenchmark.swift` + `SettingsView.swift`)
- Benchmark ran on device (iPhone, iOS 26.5): 50 warm runs + cold start per model
- New `\section{On-Device Efficiency}` added to `chapter4.tex` with full results table
- Abstract, conclusions, and MRL prose updated from 20 ms (Python/MPS) to 32 ms (Core ML on-device)
- MiniLM bundle size corrected from 43 MB to 45 MB throughout

---

### Task 8 — Run the full LaTeX compile sequence and check the final PDF

From the `latex/` directory:

```bash
pdflatex main.tex
bibtex main
pdflatex main.tex
pdflatex main.tex
```

**After compiling, open `main.pdf` and check:**
- Title page has the correct supervisor name
- Table of contents lists all chapters with correct page numbers
- Architecture figure appears (not blank)
- All tables render correctly
- No `??` placeholders anywhere
- Bibliography section is populated at the end
- No TODO text visible anywhere in the document

---

## Order of Operations

```
Quick fixes (do today):
  Task 1  — Fix supervisor name               (1 line)
  Task 2  — Remove TODO from background ch.   (1 line)
  Task 5  — Remove TODO from open issues      (2 lines)

Writing fix:
  Task 4  — Convert use cases to table        (replace 4 subsections)

Final:
  Task 8  — Full compile, read PDF end to end
```
