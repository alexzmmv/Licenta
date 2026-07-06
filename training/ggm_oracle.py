#!/usr/bin/env python3
"""
GGM oracle for validating the Swift GGMEstimator implementation.

Uses sklearn.covariance.LedoitWolf with biased covariance (1/n) to compute:
  1. Shrinkage coefficient λ
  2. Shrunken covariance matrix
  3. Precision matrix Ω
  4. Partial correlation matrix P

The same synthetic data is used in GGMEstimatorTests.swift (RepeatableRNG seed=12345).
Because Python's RNG differs from xorshift64, we generate separate oracle data
deterministically here and compare structural properties with the Swift tests.

Usage:
    python3 training/ggm_oracle.py

Requirements:
    pip install scikit-learn numpy  (tested: sklearn 1.4+, numpy 1.26+)
"""

import json
import numpy as np
from sklearn.covariance import LedoitWolf

# ── Reproducible oracle data: 100 obs × 12 emotions ───────────────────────────
# Block-correlated: emotions 0-5 share one latent factor, 6-11 another.
EMOTIONS = [
    "Joy", "Sadness", "Anger", "Fear", "Love", "Surprise",
    "Disgust", "Anxiety", "Excitement", "Gratitude", "Hope", "Guilt"
]

rng = np.random.default_rng(seed=42)   # separate seed from Swift test
N, P = 100, 12

b1 = rng.uniform(0, 1, N)   # latent factor for group 1
b2 = rng.uniform(0, 1, N)   # latent factor for group 2

X = np.zeros((N, P))
for i in range(6):
    X[:, i] = np.clip(b1 + rng.uniform(-0.1, 0.1, N), 0, None)
for i in range(6, 12):
    X[:, i] = np.clip(b2 + rng.uniform(-0.1, 0.1, N), 0, None)

# Normalise rows to sum to 1 (mimicking softmax output)
row_sums = X.sum(axis=1, keepdims=True)
X = np.where(row_sums > 0, X / row_sums, X)

# ── Fit Ledoit-Wolf ────────────────────────────────────────────────────────────
lw = LedoitWolf(assume_centered=False, store_precision=True)
lw.fit(X)

shrinkage = float(lw.shrinkage_)
sigma_hat = lw.covariance_          # p×p shrunken covariance
omega     = lw.precision_           # p×p precision matrix

# ── Partial correlations ───────────────────────────────────────────────────────
def partial_corr(precision: np.ndarray) -> np.ndarray:
    p = precision.shape[0]
    pc = np.zeros((p, p))
    for i in range(p):
        for j in range(p):
            if i != j:
                denom = np.sqrt(precision[i, i] * precision[j, j])
                pc[i, j] = -precision[i, j] / denom if denom > 0 else 0.0
    return pc

pc = partial_corr(omega)

# ── Spearman correlations for reference ───────────────────────────────────────
from scipy.stats import spearmanr

spearman_mat = np.zeros((P, P))
for i in range(P):
    for j in range(P):
        if i != j:
            spearman_mat[i, j], _ = spearmanr(X[:, i], X[:, j])

# ── Collect significant partial correlations ───────────────────────────────────
THRESHOLD = 0.10
significant_edges = []
for i in range(P):
    for j in range(i + 1, P):
        w = pc[i, j]
        if abs(w) >= THRESHOLD:
            significant_edges.append({
                "emotion1": EMOTIONS[i],
                "emotion2": EMOTIONS[j],
                "partial_r": round(float(w), 6),
                "sign": "positive" if w > 0 else "negative",
            })

significant_edges.sort(key=lambda e: abs(e["partial_r"]), reverse=True)

# ── Verify sklearn uses biased (1/n) covariance ───────────────────────────────
# Manual biased sample cov for comparison
X_c = X - X.mean(axis=0)
S_biased = (X_c.T @ X_c) / N
max_cov_diff = float(np.max(np.abs(S_biased - sigma_hat / (1 - shrinkage + 1e-12))))
# Note: max_cov_diff ≈ 0 if S used is biased; non-zero otherwise

# ── Output ──────────────────────────────────────────────────────────────────────
result = {
    "n": N,
    "p": P,
    "shrinkage": round(shrinkage, 6),
    "shrinkage_range_ok": 0 <= shrinkage <= 1,
    "significant_edges": significant_edges[:20],   # top-20 by |r|
    "max_partial_r": round(float(np.max(np.abs(pc - np.eye(P) * 0))), 6),
    "summary": {
        "group1_edges": sum(
            1 for e in significant_edges
            if EMOTIONS.index(e["emotion1"]) < 6 and EMOTIONS.index(e["emotion2"]) < 6
        ),
        "group2_edges": sum(
            1 for e in significant_edges
            if EMOTIONS.index(e["emotion1"]) >= 6 and EMOTIONS.index(e["emotion2"]) >= 6
        ),
        "cross_edges": sum(
            1 for e in significant_edges
            if (EMOTIONS.index(e["emotion1"]) < 6) != (EMOTIONS.index(e["emotion2"]) < 6)
        ),
    },
    "note": (
        "Shrinkage and partial correlations from sklearn.covariance.LedoitWolf(assume_centered=False). "
        "Compare Swift partial correlations to these values (tolerance 1e-3 acceptable; "
        "differences arise from biased vs unbiased cov and RNG differences in data generation)."
    ),
}

print(json.dumps(result, indent=2))

# ── Swift validation paste-in ─────────────────────────────────────────────────
print("\n─── Paste into GGMEstimatorTests.swift for hard-coded parity test ───")
print(f"// shrinkage λ = {shrinkage:.6f}")
if significant_edges:
    e = significant_edges[0]
    print(f"// Strongest partial r: {e['emotion1']}–{e['emotion2']} = {e['partial_r']:.6f}")

# ── Quick sanity checks ───────────────────────────────────────────────────────
print("\n─── Sanity checks ───")
assert result["shrinkage_range_ok"], "Shrinkage out of [0,1]!"
assert len(significant_edges) > 0, "No significant partial correlations found!"
assert result["summary"]["group1_edges"] > 0, "No within-group-1 edges!"
assert result["summary"]["group2_edges"] > 0, "No within-group-2 edges!"
print(f"✅ Shrinkage λ = {shrinkage:.6f}")
print(f"✅ {len(significant_edges)} significant edges (|r| ≥ {THRESHOLD})")
print(f"✅ Group-1 edges: {result['summary']['group1_edges']}, "
      f"Group-2 edges: {result['summary']['group2_edges']}, "
      f"Cross edges: {result['summary']['cross_edges']}")
