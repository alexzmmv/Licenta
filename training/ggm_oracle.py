#!/usr/bin/env python3
"""
GGM oracle for validating the Swift GGMEstimator against sklearn.

Emits a FIXED data matrix plus the exact sklearn Ledoit-Wolf shrinkage coefficient and
partial-correlation matrix, formatted as Swift literals. The Swift parity test uses the
identical matrix, so the ported Ledoit-Wolf shrinkage and partial correlations must match
these values to within 1e-6.

Also cross-checks a hand-ported (non-blocked) LW formula against sklearn's `shrinkage_` to
confirm the exact port that lives in GGMEstimator.swift.

Usage:  training/.venv/bin/python training/ggm_oracle.py
"""

import json
import numpy as np
from sklearn.covariance import LedoitWolf, ledoit_wolf_shrinkage

np.set_printoptions(precision=8, suppress=True)

# ── Fixed, reproducible data: 40 obs × 6 correlated variables ────────────────────
rng = np.random.default_rng(seed=20260707)
N, P = 40, 6
f1 = rng.normal(size=N)        # latent factor for vars 0,1,2
f2 = rng.normal(size=N)        # latent factor for vars 3,4,5
X = np.zeros((N, P))
for i in range(3):
    X[:, i] = f1 + 0.35 * rng.normal(size=N)
for i in range(3, 6):
    X[:, i] = f2 + 0.35 * rng.normal(size=N)
X = np.round(X, 4)              # round so the Swift literal is exact


def ported_lw_shrinkage(X):
    """Non-blocked port of sklearn.ledoit_wolf_shrinkage — must match GGMEstimator.swift."""
    Xc = X - X.mean(0)
    n, p = Xc.shape
    S = Xc.T @ Xc / n
    mu = np.trace(S) / p
    normS2 = float(np.sum(S * S))                     # ||S||_F^2
    row_norm4 = float(np.sum(np.sum(Xc**2, axis=1) ** 2))  # sum_t ||x_t||^4
    delta = (normS2 - 2 * mu * np.trace(S) + p * mu**2) / p
    beta = (1.0 / (p * n)) * (row_norm4 / n - normS2)
    beta = min(beta, delta)
    return 0.0 if beta == 0 else beta / delta, mu


def partial_corr(precision):
    p = precision.shape[0]
    pc = np.zeros((p, p))
    for i in range(p):
        for j in range(p):
            if i != j:
                d = np.sqrt(precision[i, i] * precision[j, j])
                pc[i, j] = -precision[i, j] / d if d > 0 else 0.0
    return pc


lw = LedoitWolf(assume_centered=False, store_precision=True).fit(X)
sklearn_shrinkage = float(lw.shrinkage_)
ported_shrinkage, mu = ported_lw_shrinkage(X)
sk_func = float(ledoit_wolf_shrinkage(X))

pc = partial_corr(lw.precision_)

print(f"sklearn LedoitWolf.shrinkage_   = {sklearn_shrinkage:.10f}")
print(f"sklearn ledoit_wolf_shrinkage() = {sk_func:.10f}")
print(f"ported (non-blocked) shrinkage  = {ported_shrinkage:.10f}")
print(f"|ported - sklearn|              = {abs(ported_shrinkage - sklearn_shrinkage):.2e}")
assert abs(ported_shrinkage - sklearn_shrinkage) < 1e-9, "PORT MISMATCH"
print("✅ ported formula matches sklearn to <1e-9\n")

# ── Emit Swift fixture ───────────────────────────────────────────────────────────
print("─── Paste into GGMEstimatorTests.swift ───")
print(f"// N={N} P={P}, sklearn LedoitWolf(assume_centered=False)")
rows = ",\n".join("            [" + ", ".join(f"{v:.4f}" for v in X[t]) + "]" for t in range(N))
print("let fixtureMatrix: [[Float]] = [\n" + rows + "\n        ]")
print(f"let expectedShrinkage = {sklearn_shrinkage:.8f}")
# strongest partial correlations
edges = []
for i in range(P):
    for j in range(i + 1, P):
        edges.append((i, j, float(pc[i, j])))
edges.sort(key=lambda e: abs(e[2]), reverse=True)
print("// strongest partial correlations (i, j, r):")
for i, j, r in edges[:6]:
    print(f"//   ({i},{j}) = {r:+.6f}")
print(f"let expectedPartialR_0_1 = {pc[0,1]:.6f}")
print(f"let expectedPartialR_0_3 = {pc[0,3]:.6f}")

out = {
    "n": N, "p": P,
    "shrinkage": round(sklearn_shrinkage, 8),
    "within_block_group_edges": sum(1 for i, j, r in edges if (i < 3) == (j < 3) and abs(r) >= 0.1),
    "cross_block_edges": sum(1 for i, j, r in edges if (i < 3) != (j < 3) and abs(r) >= 0.1),
}
print("\n" + json.dumps(out, indent=2))
