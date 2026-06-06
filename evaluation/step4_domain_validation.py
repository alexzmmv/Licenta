"""
step4_domain_validation.py

Evaluate 4 embedding models on the custom journal entries dataset using
adaptive DBSCAN clustering.

Models:
  1. MiniLM  (all-MiniLM-L6-v2, normalised)
  2. Nomic-256  (nomic-embed-text-v1.5, truncated to 256d, re-normalised)
  3. Nomic-768  (nomic-embed-text-v1.5, full 768d, normalised)
  4. Apple NLP  (pre-computed embeddings from JSON, if available)

Clustering: Adaptive DBSCAN via calibrate_epsilon + adaptive_min_points.

Metrics:
  - V-measure, ARI, NMI  (noise points excluded)
  - Noise ratio
  - Calibrated ε, calibrated minPoints, number of clusters found

Results are printed as a table and saved to:
  results/step4_domain_validation.csv
  results/step4_domain_validation.txt
"""

import sys
import csv
import json
import numpy as np
import torch
from pathlib import Path
from sentence_transformers import SentenceTransformer
from sklearn.cluster import DBSCAN
from sklearn.metrics import v_measure_score, adjusted_rand_score, homogeneity_score, completeness_score

# ── adaptive_dbscan must be importable (sibling module or on sys.path) ───────
sys.path.insert(0, str(Path(__file__).resolve().parent))
from adaptive_dbscan import calibrate_epsilon, adaptive_min_points

# ── device selection ─────────────────────────────────────────────────────────
device = (
    "cuda" if torch.cuda.is_available() else
    "mps" if torch.backends.mps.is_available() else
    "cpu"
)
print(f"Using device: {device}")

CACHE_FOLDER = str(Path(__file__).resolve().parent.parent / "training" / "hf_cache")
EVAL_DIR = Path(__file__).resolve().parent


# ── helpers ──────────────────────────────────────────────────────────────────
def compute_metrics(true_labels, pred_labels):
    """Compute extrinsic clustering metrics (excluding noise) + noise ratio."""
    true_labels = np.asarray(true_labels)
    pred_labels = np.asarray(pred_labels)

    noise_mask = pred_labels == -1
    noise_ratio = noise_mask.sum() / len(pred_labels)

    unique_clusters = set(pred_labels) - {-1}
    n_clusters = len(unique_clusters)

    valid_mask = ~noise_mask
    if valid_mask.sum() == 0:
        v_measure = ari = homog = compl = 0.0
    else:
        v_measure = v_measure_score(true_labels[valid_mask], pred_labels[valid_mask])
        ari = adjusted_rand_score(true_labels[valid_mask], pred_labels[valid_mask])
        homog = homogeneity_score(true_labels[valid_mask], pred_labels[valid_mask])
        compl = completeness_score(true_labels[valid_mask], pred_labels[valid_mask])

    return {
        "V-measure": round(v_measure, 4),
        "ARI":       round(ari, 4),
        "Homog":     round(homog, 4),
        "Compl":     round(compl, 4),
        "Noise%":    round(noise_ratio * 100, 2),
        "Clusters":  n_clusters,
    }


def load_journal_entries():
    """Load journal entries from datasets/journal_entries.json."""
    dataset_path = EVAL_DIR / "datasets" / "journal_entries.json"
    if not dataset_path.exists():
        print(f"ERROR: Dataset not found at {dataset_path}")
        sys.exit(1)

    with open(dataset_path, "r") as f:
        data = json.load(f)

    sentences = [e["text"] for e in data["entries"]]
    labels = [e["label"] for e in data["entries"]]
    return sentences, labels


def run_adaptive_dbscan(embeddings):
    """Calibrate and run adaptive DBSCAN on the given embeddings."""
    n = embeddings.shape[0]
    base_min_points = adaptive_min_points(n)
    calib = calibrate_epsilon(embeddings, base_min_points)

    eps = calib.epsilon
    mp = calib.min_points

    db = DBSCAN(eps=eps, min_samples=mp, metric="cosine")
    pred = db.fit_predict(embeddings)
    return pred, eps, mp


# ── embedding functions ──────────────────────────────────────────────────────
def embed_minilm(sentences):
    """MiniLM: all-MiniLM-L6-v2, normalised."""
    model = SentenceTransformer(
        "sentence-transformers/all-MiniLM-L6-v2",
        device=device,
        cache_folder=CACHE_FOLDER,
    )
    embeddings = model.encode(sentences, normalize_embeddings=True, show_progress_bar=True)
    return np.asarray(embeddings, dtype=np.float32)


def embed_nomic(sentences, dim):
    """Nomic-embed-text-v1.5 with prefix, truncated to `dim`d, re-normalised."""
    model = SentenceTransformer(
        "nomic-ai/nomic-embed-text-v1.5",
        trust_remote_code=True,
        device=device,
        cache_folder=CACHE_FOLDER,
    )
    prefixed = [f"clustering: {s}" for s in sentences]
    embeddings = model.encode(prefixed, normalize_embeddings=True, show_progress_bar=True)
    embeddings = np.asarray(embeddings, dtype=np.float32)

    if dim < embeddings.shape[1]:
        embeddings = embeddings[:, :dim]
        # Re-normalise after truncation
        norms = np.linalg.norm(embeddings, axis=1, keepdims=True)
        norms = np.where(norms == 0, 1, norms)
        embeddings = embeddings / norms

    return embeddings


def load_apple_nlp_embeddings():
    """Load pre-computed Apple NLP embeddings from JSON, if available."""
    emb_path = EVAL_DIR / "datasets" / "apple_nlp_journal_embeddings.json"
    if not emb_path.exists():
        return None

    with open(emb_path, "r") as f:
        data = json.load(f)

    # Expect a list of embedding vectors (list of lists)
    if isinstance(data, list):
        return np.asarray(data, dtype=np.float32)
    elif isinstance(data, dict) and "embeddings" in data:
        return np.asarray(data["embeddings"], dtype=np.float32)
    else:
        print("  ⚠ Unexpected Apple NLP embeddings format, skipping.")
        return None


# ── main ─────────────────────────────────────────────────────────────────────
def main():
    print("=" * 70)
    print("Step 4 – Domain Validation on Custom Journal Entries")
    print("=" * 70)

    # 1. Load dataset
    print("\n[1/3] Loading journal entries …")
    sentences, labels = load_journal_entries()
    print(f"  → {len(sentences)} entries, {len(set(labels))} ground-truth clusters")

    # 2. Define model pipeline
    models = {
        "MiniLM":    lambda: embed_minilm(sentences),
        "Nomic-256": lambda: embed_nomic(sentences, 256),
        "Nomic-768": lambda: embed_nomic(sentences, 768),
    }

    # 3. Evaluate each model
    print("\n[2/3] Evaluating models …")
    results = {}

    for model_name, embed_fn in models.items():
        print(f"\n  ▸ {model_name}")
        embeddings = embed_fn()
        print(f"    embedding shape: {embeddings.shape}")

        pred, eps, mp = run_adaptive_dbscan(embeddings)
        metrics = compute_metrics(labels, pred)
        metrics["Epsilon"] = round(eps, 4)
        metrics["MinPts"] = mp
        results[model_name] = metrics

        print(f"    calibrated ε = {eps:.4f},  minPoints = {mp},  clusters = {metrics['Clusters']}")

    # 4. Apple NLP (pre-computed, optional)
    print("\n  ▸ Apple NLP (pre-computed)")
    apple_emb = load_apple_nlp_embeddings()
    if apple_emb is not None:
        print(f"    embedding shape: {apple_emb.shape}")
        pred, eps, mp = run_adaptive_dbscan(apple_emb)
        metrics = compute_metrics(labels, pred)
        metrics["Epsilon"] = round(eps, 4)
        metrics["MinPts"] = mp
        results["Apple NLP"] = metrics
        print(f"    calibrated ε = {eps:.4f},  minPoints = {mp},  clusters = {metrics['Clusters']}")
    else:
        print("    ⚠ Apple NLP embeddings not found, skipping.")

    # ── Display results ──
    print("\n" + "=" * 70)
    print("RESULTS")
    print("=" * 70)

    metric_keys = ["V-measure", "ARI", "Homog", "Compl", "Noise%", "Epsilon", "MinPts", "Clusters"]
    header = f"{'Model':<16}" + "".join(f"{k:>12}" for k in metric_keys)
    separator = "-" * len(header)
    print(header)
    print(separator)
    for model_name, m in results.items():
        row = f"{model_name:<16}"
        for k in metric_keys:
            val = m[k]
            row += f"{val:>12}"
        print(row)
    print(separator)

    # ── Save results ──
    out_dir = Path(__file__).resolve().parent / "results"
    out_dir.mkdir(exist_ok=True)

    # CSV
    csv_path = out_dir / "step4_domain_validation.csv"
    with open(csv_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["Model"] + metric_keys)
        for model_name, m in results.items():
            writer.writerow([model_name] + [m[k] for k in metric_keys])
    print(f"\n✓ CSV saved to {csv_path}")

    # TXT
    txt_path = out_dir / "step4_domain_validation.txt"
    with open(txt_path, "w") as f:
        f.write("Step 4 – Domain Validation on Custom Journal Entries\n")
        f.write("Clustering: Adaptive DBSCAN (calibrate_epsilon + adaptive_min_points)\n")
        f.write("=" * 70 + "\n\n")
        f.write(header + "\n")
        f.write(separator + "\n")
        for model_name, m in results.items():
            row = f"{model_name:<16}"
            for k in metric_keys:
                val = m[k]
                row += f"{val:>12}"
            f.write(row + "\n")
        f.write(separator + "\n")
    print(f"✓ TXT saved to {txt_path}")


if __name__ == "__main__":
    main()
