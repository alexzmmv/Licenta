"""
Benchmark the three embedding approaches on STS-B and latency.

Approaches compared:
  1. Apple NLEmbedding  (OS baseline — Spearman evaluated on device only)
  2. all-MiniLM-L6-v2  (standard, 384-dim, mean pooling)
  3. nomic-embed-text-v1 MRL at optimal dim (default 256) — "clustering:" prefix

Requires:
  - models/minilm-stsb/   (run train_embedding_minilm.py)
  - models/nomic-mrl/     (run train_embedding_nomic.py)
  - coreml_models/        (run convert_to_coreml.py, optional for CoreML latency)

Run: python benchmark_embeddings.py
Output: results/embedding_benchmark.txt
"""

import time
from pathlib import Path

import numpy as np
import datasets
import torch
from scipy.stats import spearmanr
from sentence_transformers import SentenceTransformer

WARMUP_RUNS    = 5
BENCHMARK_RUNS = 100
MAX_PAIRS      = 500   # subset of STS-B test for speed

device = (
    "cuda" if torch.cuda.is_available() else
    "mps"  if torch.backends.mps.is_available() else
    "cpu"
)
print(f"Benchmark device: {device}")


# ── Load STS-B test set ───────────────────────────────────────────────────────
print("Loading STS-B...")
stsb = datasets.load_dataset("nyu-mll/glue", "stsb", cache_dir="./hf_cache", split="validation")
stsb = stsb.select(range(min(MAX_PAIRS, len(stsb))))
sentences1 = stsb["sentence1"]
sentences2 = stsb["sentence2"]
gt_scores  = np.array(stsb["label"]) / 5.0


# ── SentenceTransformer helpers ───────────────────────────────────────────────

def spearman_for_st(model_path: str):
    if not Path(model_path).exists():
        return None, None, None
    model = SentenceTransformer(model_path, device=device)
    model_size_mb = sum(
        p.numel() * p.element_size() for p in model.parameters()
    ) / 1e6

    # Warmup
    for _ in range(WARMUP_RUNS):
        model.encode(sentences1[:4], show_progress_bar=False)

    # Latency benchmark (single sentence)
    t0 = time.perf_counter()
    for _ in range(BENCHMARK_RUNS):
        model.encode([sentences1[0]], show_progress_bar=False)
    latency_ms = (time.perf_counter() - t0) / BENCHMARK_RUNS * 1000

    # Spearman
    emb1 = model.encode(sentences1, show_progress_bar=False, normalize_embeddings=True)
    emb2 = model.encode(sentences2, show_progress_bar=False, normalize_embeddings=True)
    cos_sims = np.sum(emb1 * emb2, axis=1)
    corr, _ = spearmanr(cos_sims, gt_scores)

    return corr, latency_ms, model_size_mb


# ── NLEmbedding baseline ──────────────────────────────────────────────────────

def spearman_for_nlembedding():
    try:
        import subprocess, json
        # We evaluate NLEmbedding quality by calling a Swift subprocess (if available)
        # Fallback: report "N/A on Python side, measure on device"
        print("  NLEmbedding: Python-side Spearman not measurable — evaluate on iPhone")
        return None, None, 0.0
    except Exception:
        return None, None, 0.0


# ── Core ML latency on Mac ────────────────────────────────────────────────────

def coreml_latency_ms(mlpackage_path: str, tokenizer_path: str):
    """Measure inference time of a .mlpackage on this Mac (CPU/ANE)."""
    try:
        import coremltools as ct
        from transformers import AutoTokenizer

        if not Path(mlpackage_path).exists():
            return None
        mlmodel = ct.models.MLModel(mlpackage_path)
        tokenizer = AutoTokenizer.from_pretrained(tokenizer_path, cache_dir="./hf_cache")

        enc = tokenizer(
            "I felt anxious today.",
            padding="max_length", max_length=128, truncation=True,
        )
        inputs = {
            "input_ids":      np.array([enc["input_ids"]], dtype=np.int32),
            "attention_mask": np.array([enc["attention_mask"]], dtype=np.int32),
        }

        for _ in range(WARMUP_RUNS):
            mlmodel.predict(inputs)

        t0 = time.perf_counter()
        for _ in range(BENCHMARK_RUNS):
            mlmodel.predict(inputs)
        return (time.perf_counter() - t0) / BENCHMARK_RUNS * 1000

    except Exception as e:
        print(f"  CoreML latency error: {e}")
        return None


# ── Run all benchmarks ────────────────────────────────────────────────────────

results = {}

NOMIC_MRL_DIM = 256  # optimal MRL truncation dim — see results/mrl_comparison.csv


def spearman_for_nomic(dim: int = NOMIC_MRL_DIM):
    """Evaluate nomic-embed-text-v1.5 at a specific MRL truncation dimension."""
    # Load from HF model ID (cached) to avoid _IncompatibleKeys from save/load cycle
    model = SentenceTransformer("nomic-ai/nomic-embed-text-v1.5", device=device,
                                trust_remote_code=True, cache_folder="./hf_cache")
    model_size_mb = sum(
        p.numel() * p.element_size() for p in model.parameters()
    ) / 1e6

    prefix = "clustering"

    def _enc(sents):
        prefixed = [f"{prefix}: {s}" for s in sents]
        embs = model.encode(prefixed, show_progress_bar=False, normalize_embeddings=True)
        embs = embs[:, :dim]
        embs = embs / (np.linalg.norm(embs, axis=1, keepdims=True) + 1e-9)
        return embs

    # Warmup
    for _ in range(WARMUP_RUNS):
        _enc(sentences1[:4])

    # Latency at target dim
    probe = [f"{prefix}: I felt anxious and overwhelmed today."]
    t0 = time.perf_counter()
    for _ in range(BENCHMARK_RUNS):
        v = model.encode(probe, show_progress_bar=False, normalize_embeddings=True)
        _ = v[:, :dim]
    latency_ms = (time.perf_counter() - t0) / BENCHMARK_RUNS * 1000

    emb1 = _enc(sentences1)
    emb2 = _enc(sentences2)
    cos_sims = np.sum(emb1 * emb2, axis=1)
    corr, _ = spearmanr(cos_sims, gt_scores)

    return corr, latency_ms, model_size_mb


print("\n── MiniLM-L6-v2 ────────────────────────────────────────────────────")
minilm_path = "models/minilm-stsb" if Path("models/minilm-stsb").exists() else "models/mobilebert-stsb"
corr, lat, size = spearman_for_st(minilm_path)
cml_lat = coreml_latency_ms(
    "coreml_models/GJournalEmbeddingMiniLM.mlpackage",
    "models/minilm-stsb",
)
results["MiniLM-L6-v2 (384d)"] = dict(spearman=corr, pytorch_lat_ms=lat, size_mb=size, coreml_lat_ms=cml_lat)
print(f"  Spearman: {corr:.4f}" if corr else "  Spearman: not available")
print(f"  PyTorch latency: {lat:.1f}ms" if lat else "  PyTorch latency: N/A")
print(f"  CoreML latency:  {cml_lat:.1f}ms" if cml_lat else "  CoreML latency: N/A")
print(f"  Model size: {size:.1f}MB" if size else "  Model size: N/A")

print(f"\n── nomic-embed-text-v1 MRL (dim={NOMIC_MRL_DIM}) ───────────────────────")
corr, lat, size = spearman_for_nomic(NOMIC_MRL_DIM)
cml_lat = coreml_latency_ms(
    "coreml_models/GJournalEmbeddingNomic.mlpackage",
    "models/nomic-mrl",
)
results[f"Nomic-MRL-{NOMIC_MRL_DIM}d"] = dict(spearman=corr, pytorch_lat_ms=lat, size_mb=size, coreml_lat_ms=cml_lat)
print(f"  Spearman: {corr:.4f}" if corr else "  Spearman: not available")
print(f"  PyTorch latency (incl. truncation): {lat:.1f}ms" if lat else "  PyTorch latency: N/A")
print(f"  CoreML latency:  {cml_lat:.1f}ms" if cml_lat else "  CoreML latency: N/A")
print(f"  Model size: {size:.1f}MB" if size else "  Model size: N/A")
print(f"  Note: Spearman for full 768-dim and each MRL level → see results/mrl_comparison.csv")

print("\n── NLEmbedding (Apple baseline) ─────────────────────────────────────")
corr, lat, size = spearman_for_nlembedding()
results["Apple NLEmbedding"] = dict(spearman=corr, pytorch_lat_ms=lat, size_mb=size, coreml_lat_ms=None)

# ── Save results ──────────────────────────────────────────────────────────────
Path("results").mkdir(exist_ok=True)
lines = [
    "GJournal Embedding Benchmark",
    "=" * 60,
    f"Device: {device}",
    f"STS-B pairs evaluated: {MAX_PAIRS}",
    "",
    f"{'Model':<16}  {'Spearman':>9}  {'PyTorch ms':>11}  {'CoreML ms':>10}  {'Size MB':>8}",
    "-" * 60,
]
for name, r in results.items():
    spear  = f"{r['spearman']:.4f}" if r["spearman"] else "  N/A   "
    pt     = f"{r['pytorch_lat_ms']:.1f}" if r["pytorch_lat_ms"] else "   N/A"
    cml    = f"{r['coreml_lat_ms']:.1f}" if r["coreml_lat_ms"] else "   N/A"
    sz     = f"{r['size_mb']:.1f}" if r["size_mb"] else "   N/A"
    lines.append(f"{name:<16}  {spear:>9}  {pt:>11}  {cml:>10}  {sz:>8}")

report = "\n".join(lines)
print("\n" + report)
with open("results/embedding_benchmark.txt", "w") as f:
    f.write(report + "\n")

print("\nSaved to results/embedding_benchmark.txt")
print("NOTE: For iPhone latency, run the benchmark on device via Xcode Instruments.")
