"""
Adaptive DBSCAN calibration pipeline — Python port of DBSCANClusterer.swift.

Provides automatic epsilon and minPoints selection for clustering journal-entry
embeddings.  The calibration uses a grid search over candidate epsilon values
drawn from k-distance and pairwise-distance percentiles, scored by a weighted
objective (45 % silhouette + 35 % coverage + 20 % diversity).

All distance computations use **cosine distance** (1 − cos θ).

Public API
----------
- adaptive_min_points(n)
- kneedle_epsilon(sorted_k_distances)
- build_sorted_k_distances(embeddings, min_points)
- calibrate_epsilon(embeddings, min_points)
- calibrate_epsilon_mrl(embeddings, base_min_points)
- run_dbscan(embeddings, eps, min_samples)
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import List

import numpy as np
from scipy.spatial.distance import cdist
from sklearn.cluster import DBSCAN
from sklearn.metrics import silhouette_score


# ── Data class for calibration diagnostics ────────────────────────────────────

@dataclass
class CalibrationResult:
    """Diagnostic information returned from epsilon calibration."""
    epsilon: float
    min_points: int
    cluster_count: int
    noise_count: int
    total_points: int
    silhouette_score_val: float

    @property
    def noise_fraction(self) -> float:
        return self.noise_count / self.total_points if self.total_points > 0 else 0.0

    def __repr__(self) -> str:
        nf = f"{self.noise_fraction * 100:.1f}%"
        return (
            f"ε={self.epsilon:.4f} minPts={self.min_points} → "
            f"{self.cluster_count} clusters, "
            f"{self.noise_count}/{self.total_points} noise ({nf}), "
            f"silhouette={self.silhouette_score_val:.4f}"
        )


# ── 1. Adaptive minPoints ────────────────────────────────────────────────────

def adaptive_min_points(n: int) -> int:
    """Adaptive minPts for a dataset of *n* entries.

    Uses ``ceil(1.5 × ln(N))``, clamped to ``[3, max(3, N / 5)]``.

    This provides denser neighbourhood requirements than ``floor(ln(N))``,
    preventing DBSCAN from chain-linking distant entries through sparse
    transitivity bridges.

    Examples: N=10→4, N=20→5, N=40→6, N=100→7, N=200→8, N=1000→11.
    """
    raw = int(math.ceil(1.5 * math.log(max(3, n))))
    return max(3, min(raw, max(3, n // 5)))


# ── 2. Kneedle epsilon ───────────────────────────────────────────────────────

def kneedle_epsilon(sorted_k_distances: np.ndarray) -> float:
    """O(N) max-curvature finder on a sorted k-distance array.

    Normalises the curve to the unit square and returns the k-distance
    value at the index where ``y_norm − x_norm`` is maximised (i.e. the
    point of greatest deviation from the diagonal — the "knee").

    Parameters
    ----------
    sorted_k_distances : array-like
        Monotonically non-decreasing k-distance values.

    Returns
    -------
    float
        The epsilon value at the detected knee point.
    """
    kd = np.asarray(sorted_k_distances, dtype=np.float64)
    if len(kd) < 2:
        return float(kd[-1]) if len(kd) == 1 else 0.3

    y_min, y_max = kd[0], kd[-1]
    if y_max <= y_min:
        return float(kd[-1])

    n = len(kd)
    x_norm = np.arange(n, dtype=np.float64) / (n - 1)
    y_norm = (kd - y_min) / (y_max - y_min)
    diff = y_norm - x_norm
    best_index = int(np.argmax(diff))
    return float(kd[best_index])


# ── 3. Build sorted k-distances ──────────────────────────────────────────────

def build_sorted_k_distances(embeddings: np.ndarray, min_points: int) -> np.ndarray:
    """Build a sorted k-distance array (k = *min_points*).

    Each element is the cosine distance from point *i* to its k-th nearest
    neighbour.  The full pairwise distance matrix is computed once (O(N²)),
    then the k-th column of the sorted rows is extracted and returned in
    ascending order.

    Parameters
    ----------
    embeddings : np.ndarray, shape (n, d)
        Row-normalised embedding vectors.
    min_points : int
        The *k* in "k-th nearest neighbour distance".

    Returns
    -------
    np.ndarray
        Sorted k-distance values, length *n*.
    """
    dist_matrix = cdist(embeddings, embeddings, metric="cosine")
    np.fill_diagonal(dist_matrix, np.inf)  # exclude self
    k = min_points
    # For each point, sort distances and pick the k-th nearest (index k-1)
    k_distances = np.sort(dist_matrix, axis=1)[:, min(k - 1, dist_matrix.shape[1] - 1)]
    k_distances.sort()
    return k_distances


# ── 4. Calibrate epsilon (grid search) ────────────────────────────────────────

def calibrate_epsilon(embeddings: np.ndarray, min_points: int) -> CalibrationResult:
    """Full calibration pipeline with silhouette-validated grid search.

    Steps
    -----
    1. Build sorted k-distance array (O(N²)).
    2. Compute full pairwise cosine-distance matrix.
    3. Generate candidate ε values from:
       - k-distance percentiles (5–95, step 2)
       - pairwise distance percentiles (10–90, step 5)
    4. Run sklearn DBSCAN for each candidate, score by weighted objective:
       - 45 % silhouette score  (cohesion & separation)
       - 35 % coverage          (penalise excessive noise)
       - 20 % cluster diversity  (bonus for more clusters, up to 5)
    5. Reject single-cluster solutions and solutions with >60 % noise.
    6. Fall back to Kneedle ε if no valid solution exists.

    Parameters
    ----------
    embeddings : np.ndarray, shape (n, d)
        Embedding vectors (will be L2-normalised internally).
    min_points : int
        DBSCAN ``min_samples`` parameter.

    Returns
    -------
    CalibrationResult
    """
    n = len(embeddings)
    if n < min_points:
        return CalibrationResult(
            epsilon=0.3, min_points=min_points,
            cluster_count=0, noise_count=n, total_points=n,
            silhouette_score_val=0.0,
        )

    # L2-normalise
    norms = np.linalg.norm(embeddings, axis=1, keepdims=True)
    norms = np.where(norms > 0, norms, 1.0)
    normed = embeddings / norms

    sorted_k_dist = build_sorted_k_distances(normed, min_points)
    if len(sorted_k_dist) == 0:
        return CalibrationResult(
            epsilon=0.3, min_points=min_points,
            cluster_count=0, noise_count=n, total_points=n,
            silhouette_score_val=0.0,
        )

    # Full pairwise distance matrix (reused for all probes)
    dist_matrix = cdist(normed, normed, metric="cosine")

    # ── Generate candidate ε values ──
    candidates: set[float] = set()

    # From k-distance percentiles
    for pct in range(5, 96, 2):
        idx = min(int(len(sorted_k_dist) * pct / 100.0), len(sorted_k_dist) - 1)
        candidates.add(float(sorted_k_dist[idx]))

    # From pairwise distance percentiles
    triu_indices = np.triu_indices(n, k=1)
    all_pair_dists = np.sort(dist_matrix[triu_indices])
    for pct in range(10, 91, 5):
        idx = min(int(len(all_pair_dists) * pct / 100.0), len(all_pair_dists) - 1)
        candidates.add(float(all_pair_dists[idx]))

    # ── Grid search ──
    best_score = -float("inf")
    fallback_eps = kneedle_epsilon(sorted_k_dist)
    best_result = CalibrationResult(
        epsilon=fallback_eps, min_points=min_points,
        cluster_count=1, noise_count=0, total_points=n,
        silhouette_score_val=0.0,
    )

    for eps in sorted(candidates):
        labels = DBSCAN(eps=eps, min_samples=min_points, metric="precomputed").fit_predict(dist_matrix)
        unique_labels = set(labels)
        unique_labels.discard(-1)
        n_clusters = len(unique_labels)
        noise_count = int(np.sum(labels == -1))
        noise_frac = noise_count / n

        # Reject single-cluster or excessive-noise solutions
        if n_clusters < 2:
            continue
        if noise_frac > 0.60:
            continue

        # Silhouette (only on clustered points)
        if n_clusters >= 2 and noise_count < n:
            sil = float(silhouette_score(dist_matrix, labels, metric="precomputed"))
        else:
            sil = 0.0

        # Weighted objective
        score = (
            sil * 0.45
            + (1.0 - noise_frac) * 0.35
            + min(n_clusters / 5.0, 1.0) * 0.20
        )

        if score > best_score:
            best_score = score
            best_result = CalibrationResult(
                epsilon=eps, min_points=min_points,
                cluster_count=n_clusters, noise_count=noise_count,
                total_points=n, silhouette_score_val=sil,
            )

    return best_result


# ── 5. MRL-aware calibration ─────────────────────────────────────────────────

def calibrate_epsilon_mrl(embeddings: np.ndarray, base_min_points: int) -> CalibrationResult:
    """Multi-minPts wrapper for MRL-truncated embeddings.

    MRL truncation (e.g. 768 → 256 dims) compresses cosine distances into a
    narrower range, making the single-minPts Kneedle approach unreliable.
    This variant probes ``minPts ∈ {max(3, base−2) … base+2}`` and returns
    the configuration that maximises the weighted objective.

    Parameters
    ----------
    embeddings : np.ndarray, shape (n, d)
        Embedding vectors.
    base_min_points : int
        Baseline ``min_samples`` (typically from :func:`adaptive_min_points`).

    Returns
    -------
    CalibrationResult
    """
    min_pts_low = max(3, base_min_points - 2)
    min_pts_high = base_min_points + 2

    best_result = CalibrationResult(
        epsilon=0.3, min_points=base_min_points,
        cluster_count=0, noise_count=len(embeddings),
        total_points=len(embeddings), silhouette_score_val=0.0,
    )
    best_score = -float("inf")

    for mp in range(min_pts_low, min_pts_high + 1):
        result = calibrate_epsilon(embeddings, mp)
        noise_frac = result.noise_fraction
        score = (
            result.silhouette_score_val * 0.45
            + (1.0 - noise_frac) * 0.35
            + min(result.cluster_count / 5.0, 1.0) * 0.20
        )
        if score > best_score and result.cluster_count >= 2:
            best_score = score
            best_result = result

    return best_result


# ── 6. DBSCAN wrapper ────────────────────────────────────────────────────────

def run_dbscan(embeddings: np.ndarray, eps: float, min_samples: int) -> np.ndarray:
    """Run DBSCAN clustering on embedding vectors using cosine distance.

    Parameters
    ----------
    embeddings : np.ndarray, shape (n, d)
        Embedding vectors.
    eps : float
        The maximum cosine distance between two samples for them to be
        considered neighbours.
    min_samples : int
        Minimum number of neighbours to form a dense region.

    Returns
    -------
    np.ndarray
        Cluster labels (−1 = noise, 0+ = cluster ID), length *n*.
    """
    return DBSCAN(eps=eps, min_samples=min_samples, metric="cosine").fit_predict(embeddings)
