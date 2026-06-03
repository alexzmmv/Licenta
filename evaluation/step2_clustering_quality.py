"""
Step 2 — Clustering Quality (V-measure / ARI / NMI on TweetSentimentExtractionClustering)

Embed tweets with each model, run DBSCAN (eps=0.3, min_samples=3, cosine),
then measure extrinsic clustering metrics — excluding noise points (label=-1).

Models compared:
  1. all-MiniLM-L6-v2          (384-dim, mean pooling)
  2. nomic-embed-text-v1.5     (MRL truncated to 256-dim, "clustering:" prefix)
  3. nomic-embed-text-v1.5     (full 768-dim, "clustering:" prefix)
  4. Apple NLEmbedding         (pre-exported from Swift as JSON)

Run:  python step2_clustering_quality.py
"""

import json
from pathlib import Path

import mteb
import numpy as np
import torch
from sentence_transformers import SentenceTransformer
from sklearn.cluster import DBSCAN
from sklearn.metrics import (
    adjusted_rand_score,
    normalized_mutual_info_score,
    v_measure_score,
)

# ── Device detection ──────────────────────────────────────────────────────────
device = (
    "cuda" if torch.cuda.is_available() else
    "mps"  if torch.backends.mps.is_available() else
    "cpu"
)
print(f"Device: {device}")

# ── Load TweetSentimentExtractionClustering ───────────────────────────────────
print("Loading TweetSentimentExtractionClustering...")
task = mteb.get_tasks(tasks=["TweetSentimentExtractionClustering"])[0]
task.load_data()

# Navigate the dataset structure with fallbacks
try:
    test_data = task.dataset["test"][0]
    sentences = test_data["sentences"]
    labels    = test_data["labels"]
except (KeyError, TypeError, IndexError) as exc:
    print(f"  Primary access failed ({exc}), trying alternatives...")
    try:
        # Some MTEB versions expose .dataset differently
        ds = task.dataset["test"]
        if hasattr(ds, "features"):
            sentences = ds["sentences"]
            labels    = ds["labels"]
        else:
            # Might be a list of dicts
            sentences = ds[0]["sentences"]
            labels    = ds[0]["labels"]
    except Exception as exc2:
        print(f"  Alternative access also failed ({exc2}).")
        print(f"  Dataset structure: {type(task.dataset)}")
        if hasattr(task.dataset, "keys"):
            print(f"  Keys: {list(task.dataset.keys())}")
            for k in task.dataset:
                v = task.dataset[k]
                print(f"    [{k}] type={type(v)}, len={len(v) if hasattr(v, '__len__') else '?'}")
                if hasattr(v, '__getitem__') and len(v) > 0:
                    print(f"      first item type={type(v[0])}")
                    if isinstance(v[0], dict):
                        print(f"      first item keys={list(v[0].keys())}")
        raise SystemExit("Could not load dataset. See debug info above.")

labels = np.array(labels)
print(f"  {len(sentences)} sentences, {len(np.unique(labels))} unique labels.\n")


# ── Clustering + metrics helper ───────────────────────────────────────────────

def cluster_and_score(embeddings: np.ndarray, true_labels: np.ndarray) -> dict:
    """Run DBSCAN and compute extrinsic metrics (noise points excluded)."""
    predictions = DBSCAN(eps=0.3, min_samples=3, metric="cosine").fit_predict(embeddings)

    noise_ratio = float(np.sum(predictions == -1)) / len(predictions)

    # Exclude noise points from extrinsic metrics
    mask = predictions != -1
    if mask.sum() == 0:
        return {
            "v_measure":   0.0,
            "ari":         0.0,
            "nmi":         0.0,
            "noise_ratio": noise_ratio,
        }

    gt_filtered   = true_labels[mask]
    pred_filtered = predictions[mask]

    return {
        "v_measure":   v_measure_score(gt_filtered, pred_filtered),
        "ari":         adjusted_rand_score(gt_filtered, pred_filtered),
        "nmi":         normalized_mutual_info_score(gt_filtered, pred_filtered),
        "noise_ratio": noise_ratio,
    }


# ── 1. MiniLM ─────────────────────────────────────────────────────────────────

def evaluate_minilm() -> dict:
    print("── MiniLM-L6-v2 (384d) ──────────────────────────────────────────")
    model = SentenceTransformer(
        "sentence-transformers/all-MiniLM-L6-v2",
        device=device,
        cache_folder="../training/hf_cache",
    )
    embs = model.encode(sentences, show_progress_bar=True, normalize_embeddings=True)
    scores = cluster_and_score(embs, labels)
    print(f"  V-measure: {scores['v_measure']:.4f}  ARI: {scores['ari']:.4f}  "
          f"NMI: {scores['nmi']:.4f}  Noise: {scores['noise_ratio']:.2%}\n")
    return {"model": "MiniLM-L6-v2", "dim": 384, **scores}


# ── 2 & 3. Nomic (256d / 768d) ────────────────────────────────────────────────

def evaluate_nomic(dim: int) -> dict:
    print(f"── Nomic-embed-text-v1.5 ({dim}d) ───────────────────────────────")
    model = SentenceTransformer(
        "nomic-ai/nomic-embed-text-v1.5",
        device=device,
        trust_remote_code=True,
        cache_folder="../training/hf_cache",
    )

    prefixed = [f"clustering: {s}" for s in sentences]
    embs = model.encode(prefixed, show_progress_bar=True, normalize_embeddings=True)
    embs = embs[:, :dim]
    embs = embs / (np.linalg.norm(embs, axis=1, keepdims=True) + 1e-9)

    scores = cluster_and_score(embs, labels)
    print(f"  V-measure: {scores['v_measure']:.4f}  ARI: {scores['ari']:.4f}  "
          f"NMI: {scores['nmi']:.4f}  Noise: {scores['noise_ratio']:.2%}\n")
    return {"model": "Nomic-v1.5", "dim": dim, **scores}


# ── 4. Apple NLEmbedding ──────────────────────────────────────────────────────

APPLE_JSON = Path("datasets/apple_nlp_embeddings_clustering.json")

def evaluate_apple() -> dict | None:
    print("── Apple NLEmbedding ────────────────────────────────────────────")
    if not APPLE_JSON.exists():
        print(f"  ⚠  {APPLE_JSON} not found.")
        print("  Export from Swift with JSON format:")
        print('  {"embeddings": [[...], ...]}')
        print("  Then re-run this script.\n")
        return None

    with open(APPLE_JSON, "r") as f:
        data = json.load(f)

    embs = np.array(data["embeddings"], dtype=np.float32)
    embs = embs / (np.linalg.norm(embs, axis=1, keepdims=True) + 1e-9)

    dim = embs.shape[1]
    scores = cluster_and_score(embs, labels)
    print(f"  Dimension: {dim}")
    print(f"  V-measure: {scores['v_measure']:.4f}  ARI: {scores['ari']:.4f}  "
          f"NMI: {scores['nmi']:.4f}  Noise: {scores['noise_ratio']:.2%}\n")
    return {"model": "Apple NLEmbedding", "dim": dim, **scores}


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
    header = (f"{'Model':<22}  {'Dim':>5}  {'V-measure':>10}  "
              f"{'ARI':>8}  {'NMI':>8}  {'Noise %':>8}")
    sep    = "-" * len(header)

    table_lines = [
        "Step 2 — Clustering Quality (TweetSentimentExtractionClustering)",
        "=" * len(header),
        f"Device:    {device}",
        f"Sentences: {len(sentences)}",
        f"DBSCAN:    eps=0.3, min_samples=3, metric=cosine",
        "",
        header,
        sep,
    ]
    for r in rows:
        table_lines.append(
            f"{r['model']:<22}  {r['dim']:>5}  {r['v_measure']:>10.4f}  "
            f"{r['ari']:>8.4f}  {r['nmi']:>8.4f}  {r['noise_ratio']:>7.2%}"
        )
    table_lines.append(sep)

    report = "\n".join(table_lines)
    print("\n" + report)

    # ── Save CSV ──────────────────────────────────────────────────────────
    csv_path = Path("results/step2_clustering_quality.csv")
    with open(csv_path, "w") as f:
        f.write("model,dim,v_measure,ari,nmi,noise_ratio\n")
        for r in rows:
            f.write(f"{r['model']},{r['dim']},"
                    f"{r['v_measure']:.6f},{r['ari']:.6f},"
                    f"{r['nmi']:.6f},{r['noise_ratio']:.6f}\n")
    print(f"\nCSV  saved → {csv_path}")

    # ── Save TXT ──────────────────────────────────────────────────────────
    txt_path = Path("results/step2_clustering_quality.txt")
    with open(txt_path, "w") as f:
        f.write(report + "\n")
    print(f"Text saved → {txt_path}")
