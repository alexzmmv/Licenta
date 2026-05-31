"""
Download and evaluate jinaai/jina-embeddings-v2-small-en for sentence-level semantic similarity.
Output: training/models/distilbert-stsb/

SLOT 2 model (100–200 MB): jinaai/jina-embeddings-v2-small-en
Selected per MTEB/STS-B analysis (2024-2026) as the top mean-pooling model in
the 100–200 MB window. BAAI/bge-small-en-v1.5 was disqualified: it uses CLS
pooling and applying mean pooling violates its contrastive objective.
Tokenizer: WordPiece. Pooling: mean (mandatory, architecturally enforced).
Architecture: JinaBERT with ALiBi attention. Embedding dim: 512. Size: 123.8 MB.

No fine-tuning needed — already trained on large English corpora.

Run: python train_embedding_distilbert.py
      python train_embedding_distilbert.py --test    (quick validation)
Time: ~1 min (download + eval only)

Comparison:
  DistilBERT (fine-tuned, 2019)            ~0.82 Spearman  250 MB
  BAAI/bge-small-en-v1.5 (CLS-pooled)     superior MTEB retrieval but CLS-pooled — disqualified
  jina-embeddings-v2-small-en (SLOT 2)     ~0.81 Spearman  123.8 MB  ← this script
"""

import json
import sys
from pathlib import Path

import torch
import datasets as hf_datasets
from sentence_transformers import SentenceTransformer
from sentence_transformers.evaluation import EmbeddingSimilarityEvaluator

TEST_MODE = "--test" in sys.argv
if TEST_MODE:
    print("⚡ TEST MODE: evaluating on first 100 pairs only")

BASE_MODEL = "jinaai/jina-embeddings-v2-small-en"
OUTPUT_DIR = Path("models/distilbert-stsb")

device = (
    "cuda" if torch.cuda.is_available() else
    "mps"  if torch.backends.mps.is_available() else
    "cpu"
)
print(f"Device: {device} | Model: {BASE_MODEL}")

print("Loading STS-B dataset...")
stsb = hf_datasets.load_dataset("glue", "stsb", cache_dir="./hf_cache")

val_rows = list(stsb["validation"])
if TEST_MODE:
    val_rows = val_rows[:100]
print(f"Val: {len(val_rows)} pairs")

print(f"\nDownloading {BASE_MODEL}...")
# Jina v2 ships custom model code; trust_remote_code is required
model = SentenceTransformer(BASE_MODEL, device=device, trust_remote_code=True)
print("Done.")

evaluator = EmbeddingSimilarityEvaluator(
    sentences1=[r["sentence1"] for r in val_rows],
    sentences2=[r["sentence2"] for r in val_rows],
    scores=[float(r["label"]) / 5.0 for r in val_rows],
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

pooling_cfg = OUTPUT_DIR / "1_Pooling" / "config.json"
if pooling_cfg.exists():
    with open(pooling_cfg) as f:
        cfg = json.load(f)
    mode = cfg.get("pooling_mode", cfg.get("pooling_mode_mean_tokens", False))
    is_mean = (mode == "mean") or (mode is True)
    print(f"\nPooling check — mode: {mode}")
    print("OK: Mean pooling confirmed." if is_mean else "WARNING: Not mean pooling.")

Path("results").mkdir(exist_ok=True)
with open("results/distilbert_stsb.txt", "w") as f:
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
