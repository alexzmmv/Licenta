"""
step3_algorithm_comparison.py

Compare 3 clustering algorithms (+ HDBSCAN bonus) on the
TwentyNewsgroupsClustering benchmark using a FIXED embedding model
(Nomic-768, full dimensionality, normalised).

Algorithms:
  1. Vanilla DBSCAN  (eps=0.3, min_samples=3, cosine)
  2. Classic Adaptive DBSCAN  (calibrate_epsilon + adaptive_min_points)
  3. MRL-Adapted DBSCAN       (calibrate_epsilon_mrl)
  4. HDBSCAN                  (bonus, min_cluster_size=3, cosine)

Metrics per variant:
  - V-measure, ARI, NMI  (noise points excluded from extrinsic metrics)
  - Noise ratio
  - DBCV  (via hdbscan.validity_index, best-effort)
  - Number of clusters found

Results are printed as a table and saved to:
  results/step3_algorithm_comparison.csv
  results/step3_algorithm_comparison.txt
"""

import sys
import csv
import numpy as np
import torch
from pathlib import Path
from sentence_transformers import SentenceTransformer
from sklearn.cluster import DBSCAN
from sklearn.metrics import v_measure_score, adjusted_rand_score, homogeneity_score, completeness_score

# ── adaptive_dbscan must be importable (sibling module or on sys.path) ───────
sys.path.insert(0, str(Path(__file__).resolve().parent))
from adaptive_dbscan import calibrate_epsilon, adaptive_min_points, calibrate_epsilon_mrl

# ── device selection ─────────────────────────────────────────────────────────
device = (
    "cuda" if torch.cuda.is_available() else
    "mps" if torch.backends.mps.is_available() else
    "cpu"
)
print(f"Using device: {device}")

CACHE_FOLDER = str(Path(__file__).resolve().parent.parent / "training" / "hf_cache")


# ── helpers ──────────────────────────────────────────────────────────────────
def compute_metrics(true_labels, pred_labels, embeddings):
    """Compute extrinsic clustering metrics (excluding noise) + noise ratio + DBCV."""
    true_labels = np.asarray(true_labels)
    pred_labels = np.asarray(pred_labels)

    # Noise ratio
    noise_mask = pred_labels == -1
    noise_ratio = noise_mask.sum() / len(pred_labels)

    # Number of clusters (excluding noise)
    unique_clusters = set(pred_labels) - {-1}
    n_clusters = len(unique_clusters)

    # Extrinsic metrics – exclude noise points from BOTH predictions and ground truth
    valid_mask = ~noise_mask
    if valid_mask.sum() == 0:
        v_measure = ari = homog = compl = 0.0
    else:
        v_measure = v_measure_score(true_labels[valid_mask], pred_labels[valid_mask])
        ari = adjusted_rand_score(true_labels[valid_mask], pred_labels[valid_mask])
        homog = homogeneity_score(true_labels[valid_mask], pred_labels[valid_mask])
        compl = completeness_score(true_labels[valid_mask], pred_labels[valid_mask])

    # DBCV (best-effort)
    dbcv = None
    try:
        import hdbscan as _hdb
        if n_clusters >= 2:
            dbcv = _hdb.validity_index(embeddings.astype(np.float64), pred_labels, metric="cosine")
    except (ImportError, Exception) as exc:
        dbcv = None

    return {
        "V-measure": round(v_measure, 4),
        "ARI":       round(ari, 4),
        "Homog":     round(homog, 4),
        "Compl":     round(compl, 4),
        "Noise%":    round(noise_ratio * 100, 2),
        "DBCV":      round(dbcv, 4) if dbcv is not None else "N/A",
        "Clusters":  n_clusters,
    }


def load_dataset():
    """Load TwentyNewsgroupsClustering from mteb."""
    import mteb

    task = mteb.get_tasks(tasks=["TwentyNewsgroupsClustering"])[0]
    task.load_data()

    # Try primary access pattern
    try:
        test_data = task.dataset["test"][0]
        sentences = test_data["sentences"]
        labels = test_data["labels"]
        return sentences, labels
    except (KeyError, IndexError, TypeError):
        pass

    # Alternative: dataset might be a DatasetDict with a 'test' split directly
    try:
        test_split = task.dataset["test"]
        sentences = test_split["sentences"]
        labels = test_split["labels"]
        # If sentences is a list of lists, take the first
        if sentences and isinstance(sentences[0], list):
            return sentences[0], labels[0]
        return sentences, labels
    except (KeyError, TypeError):
        pass

    # Alternative: iterate and grab first item
    try:
        for item in task.dataset["test"]:
            return item["sentences"], item["labels"]
    except Exception:
        pass

    # Last resort: check metadata / samples
    try:
        samples = task.dataset["test"].to_list()
        first = samples[0]
        return first["sentences"], first["labels"]
    except Exception as exc:
        print(f"ERROR: Could not load dataset. Last exception: {exc}")
        sys.exit(1)


def embed_nomic_768(sentences):
    """Embed with Nomic-768, prefix 'clustering: ', normalise, full 768d."""
    model = SentenceTransformer(
        "nomic-ai/nomic-embed-text-v1.5",
        trust_remote_code=True,
        device=device,
        cache_folder=CACHE_FOLDER,
    )
    prefixed = [f"clustering: {s}" for s in sentences]
    embeddings = model.encode(
        prefixed,
        normalize_embeddings=True,
        show_progress_bar=True,
    )
    # Full 768d – no truncation
    return np.asarray(embeddings, dtype=np.float32)


# ── main ─────────────────────────────────────────────────────────────────────
def main():
    print("=" * 70)
    print("Step 3 – Algorithm Comparison on TwentyNewsgroupsClustering")
    print("=" * 70)

    # 1. Load data
    print("\n[1/3] Loading dataset …")
    sentences, labels = load_dataset()
    print(f"  → {len(sentences)} sentences, {len(set(labels))} ground-truth clusters")

    # 2. Embed
    print("\n[2/3] Embedding with Nomic-768 (full dimensionality) …")
    embeddings = embed_nomic_768(sentences)
    print(f"  → Embedding shape: {embeddings.shape}")

    # 3. Clustering
    print("\n[3/3] Running clustering variants …")
    results = {}

    # ── Variant 1: Vanilla DBSCAN ──
    print("\n  ▸ Vanilla DBSCAN (eps=0.3, min_samples=3, cosine)")
    db_vanilla = DBSCAN(eps=0.3, min_samples=3, metric="cosine")
    pred_vanilla = db_vanilla.fit_predict(embeddings)
    results["Vanilla DBSCAN"] = compute_metrics(labels, pred_vanilla, embeddings)

    # ── Variant 2: Classic Adaptive DBSCAN ──
    n = len(sentences)
    base_min_points = adaptive_min_points(n)
    calib = calibrate_epsilon(embeddings, base_min_points)
    eps_classic = calib.epsilon
    mp_classic = calib.min_points
    print(f"\n  ▸ Classic Adaptive DBSCAN")
    print(f"    calibrated ε = {eps_classic:.4f},  minPoints = {mp_classic}")
    db_classic = DBSCAN(eps=eps_classic, min_samples=mp_classic, metric="cosine")
    pred_classic = db_classic.fit_predict(embeddings)
    results["Classic Adaptive"] = compute_metrics(labels, pred_classic, embeddings)

    # ── Variant 3: MRL-Adapted DBSCAN ──
    calib_mrl = calibrate_epsilon_mrl(embeddings, base_min_points)
    eps_mrl = calib_mrl.epsilon
    mp_mrl = calib_mrl.min_points
    print(f"\n  ▸ MRL-Adapted DBSCAN")
    print(f"    calibrated ε = {eps_mrl:.4f},  minPoints = {mp_mrl}")
    db_mrl = DBSCAN(eps=eps_mrl, min_samples=mp_mrl, metric="cosine")
    pred_mrl = db_mrl.fit_predict(embeddings)
    results["MRL-Adapted"] = compute_metrics(labels, pred_mrl, embeddings)

    # ── Variant 4: HDBSCAN (bonus) ──
    try:
        import hdbscan
        from scipy.spatial.distance import cdist as _cdist
        print("\n  ▸ HDBSCAN (min_cluster_size=3, cosine)")
        dist_mat = _cdist(embeddings, embeddings, metric="cosine").astype(np.float64)
        clusterer = hdbscan.HDBSCAN(min_cluster_size=3, metric="precomputed")
        hdb_labels = clusterer.fit_predict(dist_mat)
        results["HDBSCAN"] = compute_metrics(labels, hdb_labels, embeddings)
    except ImportError:
        print("\n  ▸ HDBSCAN — skipped (hdbscan not installed)")

    # ── Display results ──
    print("\n" + "=" * 70)
    print("RESULTS")
    print("=" * 70)

    metric_keys = ["V-measure", "ARI", "Homog", "Compl", "Noise%", "DBCV", "Clusters"]
    header = f"{'Algorithm':<22}" + "".join(f"{k:>12}" for k in metric_keys)
    separator = "-" * len(header)
    print(header)
    print(separator)
    for algo, m in results.items():
        row = f"{algo:<22}"
        for k in metric_keys:
            val = m[k]
            row += f"{val:>12}"
        print(row)
    print(separator)

    # ── Save results ──
    out_dir = Path(__file__).resolve().parent / "results"
    out_dir.mkdir(exist_ok=True)

    # CSV
    csv_path = out_dir / "step3_algorithm_comparison.csv"
    with open(csv_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["Algorithm"] + metric_keys)
        for algo, m in results.items():
            writer.writerow([algo] + [m[k] for k in metric_keys])
    print(f"\n✓ CSV saved to {csv_path}")

    # TXT
    txt_path = out_dir / "step3_algorithm_comparison.txt"
    with open(txt_path, "w") as f:
        f.write("Step 3 – Algorithm Comparison on TwentyNewsgroupsClustering\n")
        f.write("Embedding model: Nomic-768 (full dimensionality, normalised)\n")
        f.write("=" * 70 + "\n\n")
        f.write(header + "\n")
        f.write(separator + "\n")
        for algo, m in results.items():
            row = f"{algo:<22}"
            for k in metric_keys:
                val = m[k]
                row += f"{val:>12}"
            f.write(row + "\n")
        f.write(separator + "\n")

        # Calibration details
        f.write("\n\nCalibration Details:\n")
        f.write(f"  Classic Adaptive: ε = {eps_classic:.4f}, minPoints = {mp_classic}\n")
        f.write(f"  MRL-Adapted:      ε = {eps_mrl:.4f}, minPoints = {mp_mrl}\n")
    print(f"✓ TXT saved to {txt_path}")


if __name__ == "__main__":
    main()
