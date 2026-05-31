"""
Convert trained PyTorch models to Core ML (.mlpackage) for on-device inference.

>>> RUN THIS ON THE MAC (M1/Intel). <<<
coremltools cannot load or validate models on Linux/WSL (libcoremlpython is
macOS-only), and torch >2.7 on the PC is ahead of what coremltools supports.

Converts:
  1. GJournalEmbeddingMobileBERT.mlpackage  (from models/mobilebert-stsb/, all-MiniLM-L6-v2, mean pooling)
  2. GJournalEmbeddingDistilBERT.mlpackage  (from models/distilbert-stsb/, bge-small-en-v1.5, CLS pooling)
  3. GJournalEmotionClassifier.mlpackage    (from models/emotion-classifier/checkpoint-*/)

Pooling is done in Swift, NOT baked into the graph — each embedding model
exports the raw transformer's last_hidden_state.

Key conversion fixes (see 09_AI_PITFALLS.md §3, §8):
  - Wrapper passes explicit token_type_ids=zeros to avoid the BERT embeddings
    buffer-slicing op that coremltools cannot fold ("embeddings/26" int error).
  - Wrapper returns a plain tensor (not a ModelOutput dict) so tracing is clean.
  - Models reloaded with attn_implementation="eager" (SDPA traces badly).

Pitfall refs: 09_AI_PITFALLS.md — Pitfalls 3.1, 3.2, 3.3, 8.1, 8.2
"""

import json
import shutil
from pathlib import Path

import numpy as np
import torch
import coremltools as ct
from transformers import AutoTokenizer, AutoModel, AutoModelForSequenceClassification

OUTPUT_DIR = Path("coreml_models")
OUTPUT_DIR.mkdir(exist_ok=True)

DUMMY_TEXT = "I felt anxious and overwhelmed today after the meeting."
MAX_LENGTH = 128


# ── Wrappers ──────────────────────────────────────────────────────────────────
# Passing explicit token_type_ids=zeros skips the `self.token_type_ids[:, :seq]`
# buffer-slicing branch in BertEmbeddings that emits an op coremltools 9 cannot
# constant-fold. Returning a plain tensor avoids dict-output tracing problems.

class EmbeddingWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, attention_mask):
        token_type_ids = torch.zeros_like(input_ids)
        out = self.model(
            input_ids=input_ids,
            attention_mask=attention_mask,
            token_type_ids=token_type_ids,
        )
        return out.last_hidden_state


class ClassifierWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, attention_mask):
        token_type_ids = torch.zeros_like(input_ids)
        out = self.model(
            input_ids=input_ids,
            attention_mask=attention_mask,
            token_type_ids=token_type_ids,
        )
        return out.logits


# ── Helpers ───────────────────────────────────────────────────────────────────

def dummy_inputs(tokenizer):
    enc = tokenizer(
        DUMMY_TEXT,
        return_tensors="pt",
        padding="max_length",
        max_length=MAX_LENGTH,
        truncation=True,
    )
    return enc["input_ids"].to(torch.int32), enc["attention_mask"].to(torch.int32)


def export_vocab(tokenizer, dest: Path):
    """Write vocab.txt (one token per line, ordered by ID) for the Swift tokenizer."""
    vocab = tokenizer.get_vocab()
    ordered = sorted(vocab.items(), key=lambda kv: kv[1])
    with open(dest, "w", encoding="utf-8") as f:
        for token, _ in ordered:
            f.write(token + "\n")
    print(f"  Vocab exported → {dest.name} ({len(ordered)} tokens)")


def convert_with_fallbacks(wrapper, example_inputs, input_names, output_name, save_path):
    """Trace the wrapper and try conversion paths; return saved path or None."""
    try:
        traced = torch.jit.trace(wrapper, example_inputs)
    except Exception as e:
        print(f"  Trace failed: {e}")
        return None

    inputs = [ct.TensorType(name=n, shape=(1, MAX_LENGTH), dtype=np.int32) for n in input_names]
    outputs = [ct.TensorType(name=output_name)]
    base_kwargs = dict(
        inputs=inputs,
        outputs=outputs,
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.ALL,
    )

    # Path A — mlprogram (default for iOS15+; best for newer architectures)
    try:
        print("  Path A: mlprogram format...")
        mlmodel = ct.convert(traced, convert_to="mlprogram", **base_kwargs)
        mlmodel.save(str(save_path))
        print(f"  ✓ Saved: {save_path}")
        return save_path
    except Exception as e:
        print(f"  Path A failed: {e}")

    # Path B — neuralnetwork format (older, broader op support)
    try:
        print("  Path B: neuralnetwork format...")
        nn_kwargs = dict(base_kwargs)
        nn_kwargs.pop("compute_precision", None)  # not supported by neuralnetwork
        mlmodel = ct.convert(traced, convert_to="neuralnetwork", **nn_kwargs)
        mlmodel.save(str(save_path))
        print(f"  ✓ Saved: {save_path}")
        return save_path
    except Exception as e:
        print(f"  Path B failed: {e}")

    print(f"  ✗ All paths failed for {save_path.name}")
    return None


# ── 1/2. Embedding models ──────────────────────────────────────────────────────

def convert_embedding(model_dir: Path, model_name: str, output_name: str):
    print(f"\n{'─'*60}")
    print(f"Converting embedding model: {model_name}")
    save_path = OUTPUT_DIR / f"{output_name}.mlpackage"

    if not model_dir.exists():
        print(f"  SKIP: {model_dir} not found (run training first)")
        return None

    tokenizer = AutoTokenizer.from_pretrained(str(model_dir))

    # Load the raw transformer with eager attention (SDPA traces badly)
    inner_model = AutoModel.from_pretrained(str(model_dir), attn_implementation="eager")
    inner_model.eval().cpu()
    wrapper = EmbeddingWrapper(inner_model).eval()

    ids, mask = dummy_inputs(tokenizer)
    result = convert_with_fallbacks(
        wrapper, (ids, mask),
        input_names=["input_ids", "attention_mask"],
        output_name="last_hidden_state",
        save_path=save_path,
    )

    export_vocab(tokenizer, OUTPUT_DIR / f"vocab_{output_name.lower()}.txt")
    return result


# ── 3. Emotion classifier ───────────────────────────────────────────────────────

def latest_checkpoint(model_dir: Path):
    cks = list(model_dir.glob("checkpoint-*"))
    if not cks:
        return None
    return max(cks, key=lambda p: int(p.name.split("-")[1]))


def convert_emotion_classifier():
    print(f"\n{'─'*60}")
    print("Converting emotion classifier")
    model_dir = Path("models/emotion-classifier")
    save_path = OUTPUT_DIR / "GJournalEmotionClassifier.mlpackage"

    # Trainer saves to checkpoint-*/, not the root — find the best/latest one
    src = model_dir if (model_dir / "model.safetensors").exists() else latest_checkpoint(model_dir)
    if src is None:
        print(f"  SKIP: no model found in {model_dir} or its checkpoints")
        return None
    print(f"  Loading from: {src}")

    # Tokenizer isn't saved with the classifier — load from the base model
    tokenizer = AutoTokenizer.from_pretrained(
        "google/mobilebert-uncased", cache_dir="./hf_cache", use_fast=False
    )
    model = AutoModelForSequenceClassification.from_pretrained(
        str(src), attn_implementation="eager"
    )
    model.eval().cpu()
    wrapper = ClassifierWrapper(model).eval()

    ids, mask = dummy_inputs(tokenizer)
    result = convert_with_fallbacks(
        wrapper, (ids, mask),
        input_names=["input_ids", "attention_mask"],
        output_name="logits",
        save_path=save_path,
    )

    # Save label ordering so Swift can map index → Emotion
    cfg_path = src / "config.json"
    if cfg_path.exists():
        with open(cfg_path) as f:
            cfg = json.load(f)
        with open(OUTPUT_DIR / "emotion_labels.json", "w") as f:
            json.dump(cfg.get("id2label", {}), f, indent=2)
        print("  Label order saved → emotion_labels.json")

    export_vocab(tokenizer, OUTPUT_DIR / "vocab_emotion.txt")
    return result


# ── Size validation ──────────────────────────────────────────────────────────

def report_sizes():
    print(f"\n{'─'*60}")
    print("Output sizes:")
    for p in sorted(OUTPUT_DIR.glob("*.mlpackage")):
        size_mb = sum(f.stat().st_size for f in p.rglob("*") if f.is_file()) / 1e6
        status = "✓" if size_mb < 100 else "⚠ > 100MB"
        print(f"  {status}  {p.name:<45s}  {size_mb:.1f} MB")


# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("=== GJournal Core ML Conversion ===")
    print(f"Output directory: {OUTPUT_DIR.resolve()}")

    results = {}
    results["mobilebert"] = convert_embedding(
        Path("models/mobilebert-stsb"), "MiniLM-L6 (SLOT 1)", "GJournalEmbeddingMobileBERT",
    )
    results["distilbert"] = convert_embedding(
        Path("models/distilbert-stsb"), "BGE-small (SLOT 2)", "GJournalEmbeddingDistilBERT",
    )
    results["emotion"] = convert_emotion_classifier()

    report_sizes()

    print(f"\n{'─'*60}")
    print("Summary:")
    for name, path in results.items():
        status = f"✓ {path}" if path else "✗ failed — see 09_AI_PITFALLS.md §8"
        print(f"  {name:<15s}: {status}")

    print("\nNext: copy *.mlpackage + vocab_*.txt + emotion_labels.json into the Xcode bundle.")
