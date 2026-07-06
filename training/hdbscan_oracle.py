#!/usr/bin/env python3
"""
HDBSCAN oracle for validating the Swift implementation.

Uses the same synthetic data as HDBSCANTests.swift to confirm the expected
structural clustering on well-separated 3-cluster data. Validates using
pairwise agreement rather than exact label matching.

Usage:
    python3 training/hdbscan_oracle.py

Requirements:
    pip install hdbscan  (tested with 0.8.44)
"""

import json
import numpy as np
import hdbscan


# ── Same points as HDBSCANTests.syntheticPoints ────────────────────────────
POINTS = np.array([
    # Cluster A
    [1.00, 0.05, 0.00, 0.00, 0.00],
    [0.95, 0.08, 0.10, 0.00, 0.00],
    [1.00, 0.00, 0.05, 0.05, 0.00],
    [0.92, 0.10, 0.00, 0.00, 0.05],
    [1.00, 0.03, 0.03, 0.03, 0.03],
    # Cluster B
    [0.05, 1.00, 0.00, 0.00, 0.00],
    [0.08, 0.95, 0.10, 0.00, 0.00],
    [0.00, 1.00, 0.05, 0.05, 0.00],
    [0.10, 0.92, 0.00, 0.00, 0.05],
    [0.03, 1.00, 0.03, 0.03, 0.03],
    # Cluster C
    [0.00, 0.05, 1.00, 0.00, 0.00],
    [0.08, 0.00, 0.95, 0.10, 0.00],
    [0.00, 0.05, 1.00, 0.05, 0.00],
    [0.10, 0.00, 0.92, 0.00, 0.05],
    [0.03, 0.03, 1.00, 0.03, 0.03],
    # Outliers — orthogonal to all three cluster directions
    [0.00, 0.00, 0.00, 1.00, 0.00],
    [0.00, 0.00, 0.00, 0.71, 0.71],
], dtype=np.float32)

MIN_PTS = 3
MIN_CLUSTER_SIZE = 3

# ── Precompute cosine distance matrix (metric parity with Swift) ────────────
def cosine_distance_matrix(X: np.ndarray) -> np.ndarray:
    """1 - normalised_dot, same formula as Swift cosineDistance()."""
    norms = np.linalg.norm(X, axis=1, keepdims=True)
    normed = X / np.maximum(norms, 1e-6)
    dot = normed @ normed.T
    return np.clip(1.0 - dot, 0.0, 2.0)


def pairwise_agreement(labels_a, labels_b):
    """Fraction of pairs where same-cluster-in-A == same-cluster-in-B."""
    n = len(labels_a)
    agree = total = 0
    for i in range(n):
        for j in range(i + 1, n):
            same_a = labels_a[i] == labels_a[j] and labels_a[i] != -1
            same_b = labels_b[i] == labels_b[j] and labels_b[i] != -1
            agree += int(same_a == same_b)
            total += 1
    return agree / total if total > 0 else 1.0


def run_oracle():
    dist = cosine_distance_matrix(POINTS).astype(np.float64)

    clusterer = hdbscan.HDBSCAN(
        min_samples=MIN_PTS,
        min_cluster_size=MIN_CLUSTER_SIZE,
        metric="precomputed",
        allow_single_cluster=False,
    )
    labels = clusterer.fit_predict(dist).tolist()

    n_clusters = max(labels) + 1 if max(labels) >= 0 else 0
    n_noise = labels.count(-1)

    groups = {
        "A": list(range(0, 5)),
        "B": list(range(5, 10)),
        "C": list(range(10, 15)),
    }

    group_labels = {k: [labels[i] for i in v] for k, v in groups.items()}
    group_ok = {
        k: len(set(v)) == 1 and v[0] != -1
        for k, v in group_labels.items()
    }

    result = {
        "labels": labels,
        "n_clusters": n_clusters,
        "n_noise": n_noise,
        "min_pts": MIN_PTS,
        "min_cluster_size": MIN_CLUSTER_SIZE,
        "group_labels": group_labels,
        "group_cohesion_ok": group_ok,
        "all_groups_correct": all(group_ok.values()),
        "note": (
            "Use structural (pairwise) agreement to compare with Swift output — "
            "label IDs may differ but group membership must match."
        ),
    }
    print(json.dumps(result, indent=2))

    # ── Guidance for Swift comparison ───────────────────────────────────────
    if result["all_groups_correct"]:
        print("\n✅ Oracle: all 3 groups correctly separated.")
    else:
        print("\n❌ Oracle: some groups not correctly separated — check minPts/minClusterSize.")
        for k, ok in group_ok.items():
            status = "✅" if ok else "❌"
            print(f"   {status} Group {k}: {group_labels[k]}")

    return result


if __name__ == "__main__":
    run_oracle()
