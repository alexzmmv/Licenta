#!/usr/bin/env python3
"""
Persistent-Homology oracle for validating the Swift PersistentHomology implementation.

Uses ripser (Vietoris-Rips persistence) as the ground-truth reference. Emits, for a set
of DETERMINISTIC point-cloud fixtures, both the exact point coordinates and the resulting
H0/H1 persistence diagrams. The Swift unit tests use the *same* coordinates, compute their
own distance matrix, run the Swift VR pipeline, and assert the resulting bars match these
reference bars within tolerance.

Fixtures are chosen so their homology is analytically obvious:
  - two_points : H0 = {[0,d), [0,inf)}, H1 = {}                  (no loop)
  - triangle   : equilateral -> loop born and filled at the same scale -> H1 = {} (zero bar)
  - square     : unit square -> exactly one H1 loop [1, sqrt(2))  (classic hole)
  - octagon    : 8 pts on unit circle -> one prominent H1 loop     (circle -> one bar)
  - two_blobs  : two well-separated clusters -> H0 has a long gap, H1 = {}
  - noise      : random points -> only short H1 bars (no persistent loop)

Usage:
    training/.venv/bin/python training/ph_oracle.py

Requirements: ripser, numpy  (installed in training/.venv)
"""

import json
import numpy as np
from ripser import ripser

np.set_printoptions(precision=6, suppress=True)


def diagram(points, maxdim=1, thresh=np.inf):
    """Run ripser on a point cloud; return finite H0 bars, H1 bars, and inf-H0 count."""
    res = ripser(np.asarray(points, dtype=float), maxdim=maxdim, thresh=thresh)
    dgms = res["dgms"]
    h0 = dgms[0]
    h1 = dgms[1] if len(dgms) > 1 else np.empty((0, 2))
    h0_finite = sorted(float(d) for b, d in h0 if np.isfinite(d))
    h0_inf = int(np.sum(~np.isfinite(h0[:, 1])))
    h1_bars = sorted(([float(b), float(d)] for b, d in h1 if np.isfinite(d)),
                     key=lambda bd: (bd[1] - bd[0]), reverse=True)
    return {"h0_finite_deaths": [round(x, 6) for x in h0_finite],
            "h0_infinite_count": h0_inf,
            "h1_bars": [[round(b, 6), round(d, 6)] for b, d in h1_bars]}


# ── Deterministic fixtures ──────────────────────────────────────────────────────
FIXTURES = {}

# two points at distance 3
FIXTURES["two_points"] = [[0.0, 0.0], [3.0, 0.0]]

# equilateral triangle, side 1
FIXTURES["triangle"] = [[0.0, 0.0], [1.0, 0.0], [0.5, np.sqrt(3) / 2]]

# unit square
FIXTURES["square"] = [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]

# regular octagon on the unit circle
oct_pts = [[np.cos(2 * np.pi * k / 8), np.sin(2 * np.pi * k / 8)] for k in range(8)]
FIXTURES["octagon"] = oct_pts

# two well-separated blobs (5 pts each), deterministic
rng = np.random.default_rng(7)
blobA = rng.normal(loc=[0, 0], scale=0.15, size=(5, 2))
blobB = rng.normal(loc=[10, 0], scale=0.15, size=(5, 2))
FIXTURES["two_blobs"] = np.vstack([blobA, blobB]).tolist()

# random noise cloud (no structure)
FIXTURES["noise"] = rng.uniform(0, 1, size=(12, 2)).tolist()


def main():
    out = {}
    for name, pts in FIXTURES.items():
        pts = [[round(float(c), 6) for c in p] for p in pts]
        out[name] = {"points": pts, **diagram(pts)}

    print(json.dumps(out, indent=2))

    print("\n─── Swift paste-in reference ───")
    for name, d in out.items():
        h1 = d["h1_bars"]
        lp = round(sum(b[1] - b[0] for b in h1), 6)
        print(f"// {name}: H0_finite={d['h0_finite_deaths']} H0_inf={d['h0_infinite_count']} "
              f"H1={h1} LP={lp}")

    # ── Sanity assertions matching the analytic expectations ────────────────────
    assert out["two_points"]["h1_bars"] == [], "two_points should have no loop"
    assert out["two_points"]["h0_infinite_count"] == 1
    assert out["square"]["h1_bars"], "square must have one H1 loop"
    sq = out["square"]["h1_bars"][0]
    assert abs(sq[0] - 1.0) < 1e-6 and abs(sq[1] - np.sqrt(2)) < 1e-6, f"square loop {sq}"
    assert out["octagon"]["h1_bars"], "octagon must have a loop"
    assert out["two_blobs"]["h1_bars"] == [], "two_blobs should have no loop"
    print("\n✅ ripser fixtures consistent with analytic expectations")


if __name__ == "__main__":
    main()
