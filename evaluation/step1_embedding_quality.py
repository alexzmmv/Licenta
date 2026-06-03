"""
Step 1 — Embedding Quality (Spearman on STS-B)

Evaluate Spearman correlation between cosine-similarity of model embeddings
and human-annotated similarity scores from the STS Benchmark (validation split).

Models compared:
  1. all-MiniLM-L6-v2          (384-dim, mean pooling)
  2. nomic-embed-text-v1.5     (MRL truncated to 256-dim)
  3. nomic-embed-text-v1.5     (full 768-dim)
  4. Apple NLEmbedding         (pre-exported from Swift as JSON)

Run:  python step1_embedding_quality.py
"""

import json
from pathlib import Path

import datasets
import numpy as np
import torch
from scipy.stats import spearmanr
from sentence_transformers import SentenceTransformer

# ── Device detection ──────────────────────────────────────────────────────────
device = (
    "cuda" if torch.cuda.is_available() else
    "mps"  if torch.backends.mps.is_available() else
    "cpu"
)
print(f"Device: {device}")

# ── Load STS-B validation set (ALL pairs) ─────────────────────────────────────
print("Loading STS-B validation set...")
stsb = datasets.load_dataset(
    "nyu-mll/glue", "stsb",
    cache_dir="../training/hf_cache",
    split="validation",
)
sentences1 = stsb["sentence1"]
sentences2 = stsb["sentence2"]
gt_scores  = np.array(stsb["label"]) / 5.0          # normalise to [0, 1]
print(f"  {len(sentences1)} sentence pairs loaded.\n")


# ── Helper: compute Spearman from pre-computed embeddings ─────────────────────

def spearman_from_embeddings(emb1: np.ndarray, emb2: np.ndarray) -> float:
    """Cosine similarity → Spearman correlation with ground-truth scores."""
    cos_sims = np.sum(emb1 * emb2, axis=1)
    corr, _ = spearmanr(cos_sims, gt_scores)
    return corr


# ── 1. MiniLM ─────────────────────────────────────────────────────────────────

def evaluate_minilm() -> dict:
    print("── MiniLM-L6-v2 (384d) ──────────────────────────────────────────")
    model = SentenceTransformer(
        "sentence-transformers/all-MiniLM-L6-v2",
        device=device,
        cache_folder="../training/hf_cache",
    )
    emb1 = model.encode(sentences1, show_progress_bar=True, normalize_embeddings=True)
    emb2 = model.encode(sentences2, show_progress_bar=True, normalize_embeddings=True)
    corr = spearman_from_embeddings(emb1, emb2)
    print(f"  Spearman: {corr:.4f}\n")
    return {"model": "MiniLM-L6-v2", "dim": 384, "spearman": corr}


# ── 2 & 3. Nomic (256d / 768d) ────────────────────────────────────────────────

def evaluate_nomic(dim: int) -> dict:
    print(f"── Nomic-embed-text-v1.5 ({dim}d) ───────────────────────────────")
    model = SentenceTransformer(
        "nomic-ai/nomic-embed-text-v1.5",
        device=device,
        trust_remote_code=True,
        cache_folder="../training/hf_cache",
    )

    def _encode(sents, prefix: str):
        prefixed = [f"{prefix}: {s}" for s in sents]
        embs = model.encode(prefixed, show_progress_bar=True, normalize_embeddings=True)
        embs = embs[:, :dim]
        embs = embs / (np.linalg.norm(embs, axis=1, keepdims=True) + 1e-9)
        return embs

    # STS uses search prefixes: query for s1, document for s2
    emb1 = _encode(sentences1, "search_query")
    emb2 = _encode(sentences2, "search_document")
    corr = spearman_from_embeddings(emb1, emb2)
    print(f"  Spearman: {corr:.4f}\n")
    return {"model": f"Nomic-v1.5", "dim": dim, "spearman": corr}


# ── 4. Apple NLEmbedding ──────────────────────────────────────────────────────

APPLE_JSON = Path("datasets/apple_nlp_embeddings.json")

def evaluate_apple() -> dict | None:
    print("── Apple NLEmbedding ────────────────────────────────────────────")
    if not APPLE_JSON.exists():
        print(f"  ⚠  {APPLE_JSON} not found.")
        print("  Export from Swift with the following JSON format:")
        print('  {"sentence1_embeddings": [[...], ...], "sentence2_embeddings": [[...], ...]}')
        print("  Then re-run this script.\n")
        return None

    with open(APPLE_JSON, "r") as f:
        data = json.load(f)

    emb1 = np.array(data["sentence1_embeddings"], dtype=np.float32)
    emb2 = np.array(data["sentence2_embeddings"], dtype=np.float32)

    # Normalise just in case
    emb1 = emb1 / (np.linalg.norm(emb1, axis=1, keepdims=True) + 1e-9)
    emb2 = emb2 / (np.linalg.norm(emb2, axis=1, keepdims=True) + 1e-9)

    dim = emb1.shape[1]
    corr = spearman_from_embeddings(emb1, emb2)
    print(f"  Dimension: {dim}")
    print(f"  Spearman:  {corr:.4f}\n")
    return {"model": "Apple NLEmbedding", "dim": dim, "spearman": corr}


# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    Path("results").mkdir(exist_ok=True)

    rows = []
    rows.append(evaluate_minilm())
    rows.append(evaluate_nomic(256))
    rows.append(evaluate_nomic(768))

    apple_row = evaluate_apple()
    if apple_row is not None:
        rows.append(apple_row)

    # ── Pretty-print table ────────────────────────────────────────────────
    header = f"{'Model':<22}  {'Dim':>5}  {'Spearman':>9}"
    sep    = "-" * len(header)

    lines = [
        "Step 1 — Embedding Quality (Spearman on STS-B)",
        "=" * len(header),
        f"Device: {device}",
        f"Pairs:  {len(sentences1)}",
        "",
        header,
        sep,
    ]
    for r in rows:
        lines.append(f"{r['model']:<22}  {r['dim']:>5}  {r['spearman']:>9.4f}")
    lines.append(sep)

    report = "\n".join(lines)
    print("\n" + report)

    # ── Save CSV ──────────────────────────────────────────────────────────
    csv_path = Path("results/step1_embedding_quality.csv")
    with open(csv_path, "w") as f:
        f.write("model,dim,spearman\n")
        for r in rows:
            f.write(f"{r['model']},{r['dim']},{r['spearman']:.6f}\n")
    print(f"\nCSV  saved → {csv_path}")

    # ── Save TXT ──────────────────────────────────────────────────────────
    txt_path = Path("results/step1_embedding_quality.txt")
    with open(txt_path, "w") as f:
        f.write(report + "\n")
    print(f"Text saved → {txt_path}")
