"""
Download and evaluate nomic-embed-text-v1 for sentence-level semantic similarity.
Output: training/models/nomic-mrl/

nomic-embed-text-v1 is pre-trained with Matryoshka Representation Learning (MRL),
meaning the first N dims of any embedding are useful at N ∈ {64, 128, 256, 512, 768}.

No fine-tuning is performed — the pre-trained model already supports MRL natively.
Run fine-tuning only if you want to adapt to journal-specific language.

Run: python train_embedding_nomic.py
Time: ~2 min (download + eval)

Nomic task prefixes (required for correct semantics):
  Clustering / retrieval docs : "clustering: {text}"
  Search queries              : "search_query: {text}"
  Search documents            : "search_document: {text}"
"""

import json
from pathlib import Path

import numpy as np
import torch
import datasets as hf_datasets
from scipy.stats import spearmanr
from sentence_transformers import SentenceTransformer

BASE_MODEL = "nomic-ai/nomic-embed-text-v1.5"
OUTPUT_DIR = Path("models/nomic-mrl")
MRL_DIMS   = [64, 128, 256, 512, 768]

device = (
    "cuda" if torch.cuda.is_available() else
    "mps"  if torch.backends.mps.is_available() else
    "cpu"
)
print(f"Device: {device}")
print(f"Model: {BASE_MODEL}")
print(f"Output: {OUTPUT_DIR}")

print("\nLoading STS-B dataset...")
stsb = hf_datasets.load_dataset("nyu-mll/glue", "stsb", cache_dir="./hf_cache")
val = stsb["validation"]
sentences1 = [r["sentence1"] for r in val]
sentences2 = [r["sentence2"] for r in val]
gt_scores  = np.array([r["label"] for r in val]) / 5.0
print(f"Validation pairs: {len(sentences1)}")

print(f"\nDownloading {BASE_MODEL}...")
model = SentenceTransformer(BASE_MODEL, device=device, trust_remote_code=True)
print("Done.")

# Nomic requires a task prefix — use "clustering" for journal use-case.
# For STS-B we test both "search_query" (symmetrical pairs) and "clustering"
# to show the effect of task prefix on Spearman correlation.
def encode_with_prefix(sents, prefix: str) -> np.ndarray:
    prefixed = [f"{prefix}: {s}" for s in sents]
    return model.encode(prefixed, show_progress_bar=False, normalize_embeddings=True)


print("\nEvaluating Spearman at each MRL truncation dimension...")
print(f"{'Prefix':<16}  {'Dim':>6}  {'Spearman':>9}")
print("-" * 36)

results = {}
for prefix in ("search_query", "clustering"):
    emb1_full = encode_with_prefix(sentences1, prefix)   # shape (N, 768)
    emb2_full = encode_with_prefix(sentences2, prefix)

    for dim in MRL_DIMS:
        e1 = emb1_full[:, :dim]
        e2 = emb2_full[:, :dim]
        # Re-normalise after truncation
        e1 = e1 / (np.linalg.norm(e1, axis=1, keepdims=True) + 1e-9)
        e2 = e2 / (np.linalg.norm(e2, axis=1, keepdims=True) + 1e-9)
        cos_sims = np.sum(e1 * e2, axis=1)
        corr, _ = spearmanr(cos_sims, gt_scores)
        key = f"{prefix}_{dim}"
        results[key] = corr
        print(f"{prefix:<16}  {dim:>6}  {corr:>9.4f}")

# Save the model
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
model.save(str(OUTPUT_DIR))

# Save evaluation results
Path("results").mkdir(exist_ok=True)
with open("results/nomic_mrl_stsb.json", "w") as f:
    json.dump(results, f, indent=2)

# Report best result for "clustering" prefix (the one used in the iOS app)
best_dim  = max(MRL_DIMS, key=lambda d: results[f"clustering_{d}"])
best_corr = results[f"clustering_{best_dim}"]
print(f"\nBest clustering Spearman: {best_corr:.4f} at dim={best_dim}")
print(f"Model saved to: {OUTPUT_DIR}")
if best_corr > 0.75:
    print("PASS ✓")
else:
    print("FAIL ✗ (expected > 0.75)")
