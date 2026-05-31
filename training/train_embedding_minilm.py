"""
Download and evaluate all-MiniLM-L6-v2 for sentence-level semantic similarity.
Output: training/models/minilm-stsb/

No fine-tuning needed — this model is already trained on STS-B and similar tasks.
Run: python train_embedding_minilm.py
Time: ~1 min (download + eval only)

all-MiniLM-L6-v2 vs alternatives:
  MobileBERT (fine-tuned)  ~0.78 Spearman  96MB
  DistilBERT (fine-tuned)  ~0.82 Spearman  250MB
  all-MiniLM-L6-v2         ~0.88 Spearman  80MB  ← best balance for mobile
"""

import json
from pathlib import Path

import torch
import datasets as hf_datasets
from sentence_transformers import SentenceTransformer
from sentence_transformers.sentence_transformer.evaluation import EmbeddingSimilarityEvaluator

BASE_MODEL = "sentence-transformers/all-MiniLM-L6-v2"
OUTPUT_DIR = Path("models/minilm-stsb")

device = (
    "cuda" if torch.cuda.is_available() else
    "mps"  if torch.backends.mps.is_available() else
    "cpu"
)
print(f"Device: {device}")
print(f"Model: {BASE_MODEL}")
print(f"Output: {OUTPUT_DIR}")

print("\nLoading STS-B dataset...")
stsb = hf_datasets.load_dataset("glue", "stsb", cache_dir="./hf_cache")
print(f"Val: {len(stsb['validation'])} pairs")

print(f"\nDownloading {BASE_MODEL}...")
model = SentenceTransformer(BASE_MODEL, device=device)
print("Done.")

evaluator = EmbeddingSimilarityEvaluator(
    sentences1=[r["sentence1"] for r in stsb["validation"]],
    sentences2=[r["sentence2"] for r in stsb["validation"]],
    scores=[float(r["label"]) / 5.0 for r in stsb["validation"]],
    name="stsb-val",
)

print("\nEvaluating on STS-B validation set...")
score_raw = evaluator(model)

if isinstance(score_raw, dict):
    spearman = score_raw.get("spearman_cosine", next(iter(score_raw.values())))
else:
    spearman = float(score_raw)

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
model.save(str(OUTPUT_DIR))

# Verify pooling config
pooling_cfg = OUTPUT_DIR / "1_Pooling" / "config.json"
if pooling_cfg.exists():
    with open(pooling_cfg) as f:
        cfg = json.load(f)
    mode = cfg.get("pooling_mode", cfg.get("pooling_mode_mean_tokens", False))
    print(f"\nPooling check — mode: {mode}")
    if mode not in ("mean", True):
        print("WARNING: Model is NOT using mean pooling. Swift tokenizer must match.")
    else:
        print("OK: Mean pooling confirmed.")

Path("results").mkdir(exist_ok=True)
with open("results/minilm_stsb.txt", "w") as f:
    f.write(f"Model: {BASE_MODEL}\n")
    f.write(f"Device: {device}\n")
    f.write(f"Fine-tuned: No (pre-trained)\n")
    f.write(f"STS-B Spearman correlation: {spearman:.4f}\n")

print(f"\nFinal STS-B Spearman: {spearman:.4f} (target > 0.75)")
print(f"Model saved to: {OUTPUT_DIR}")
if spearman > 0.75:
    print("PASS ✓")
else:
    print("FAIL ✗")
