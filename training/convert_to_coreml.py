"""
Convert fine-tuned PyTorch models to Core ML (.mlpackage) for on-device inference.

Run on Mac (M1 or Intel) — coremltools works best on macOS.

Converts:
  1. GJournalEmbeddingMobileBERT.mlpackage  (from models/mobilebert-stsb/)
  2. GJournalEmbeddingDistilBERT.mlpackage  (from models/distilbert-stsb/)
  3. GJournalEmotionClassifier.mlpackage    (from models/emotion-classifier/)

Each model has 3 fallback paths:
  Path A: default ct.convert()
  Path B: convert_to="mlprogram"
  Path C: ONNX → CoreML

Pitfall refs: 09_AI_PITFALLS.md — Pitfalls 3.1, 3.2, 3.3, 8.1
"""

import shutil
from pathlib import Path

import numpy as np
import torch
import coremltools as ct
from transformers import AutoTokenizer, AutoModel, AutoModelForSequenceClassification
from sentence_transformers import SentenceTransformer

OUTPUT_DIR = Path("coreml_models")
OUTPUT_DIR.mkdir(exist_ok=True)

DUMMY_TEXT = "I felt anxious and overwhelmed today after the meeting."


# ── Helpers ───────────────────────────────────────────────────────────────────

def dummy_inputs(tokenizer, max_length=128):
    enc = tokenizer(
        DUMMY_TEXT,
        return_tensors="pt",
        padding="max_length",
        max_length=max_length,
        truncation=True,
    )
    return enc["input_ids"], enc["attention_mask"]


def convert_with_fallbacks(traced_model, input_names, output_name, save_path):
    """Try three conversion paths; return path of the saved .mlpackage or None."""
    inputs = [
        ct.TensorType(name=n, shape=(1, 128), dtype=np.int32)
        for n in input_names
    ]
    outputs = [ct.TensorType(name=output_name)]
    base_kwargs = dict(
        inputs=inputs,
        outputs=outputs,
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.ALL,
    )

    # Path A — default neuralnetwork format
    try:
        print("  Path A: default format...")
        mlmodel = ct.convert(traced_model, **base_kwargs)
        mlmodel.save(str(save_path))
        print(f"  ✓ Saved: {save_path}")
        return save_path
    except Exception as e:
        print(f"  Path A failed: {e}")

    # Path B — mlprogram format (better for newer architectures)
    try:
        print("  Path B: mlprogram format...")
        mlmodel = ct.convert(traced_model, convert_to="mlprogram", **base_kwargs)
        mlmodel.save(str(save_path))
        print(f"  ✓ Saved: {save_path}")
        return save_path
    except Exception as e:
        print(f"  Path B failed: {e}")

    # Path C — ONNX intermediate
    try:
        print("  Path C: ONNX → CoreML...")
        onnx_path = save_path.with_suffix(".onnx")
        torch.onnx.export(
            traced_model,
            (dummy_ids, dummy_mask),
            str(onnx_path),
            input_names=input_names,
            output_names=[output_name],
            opset_version=14,
            dynamic_axes=None,
        )
        mlmodel = ct.converters.onnx.convert(
            model=str(onnx_path),
            minimum_ios_deployment_target="17",
        )
        mlmodel.save(str(save_path))
        onnx_path.unlink(missing_ok=True)
        print(f"  ✓ Saved (via ONNX): {save_path}")
        return save_path
    except Exception as e:
        print(f"  Path C failed: {e}")

    print(f"  ✗ All paths failed for {save_path.name}")
    return None


# ── 1. Embedding: MobileBERT ──────────────────────────────────────────────────

def convert_embedding(model_dir: Path, model_name: str, output_name: str):
    print(f"\n{'─'*60}")
    print(f"Converting embedding model: {model_name}")
    save_path = OUTPUT_DIR / f"{output_name}.mlpackage"

    if not model_dir.exists():
        print(f"  SKIP: {model_dir} not found (run training first)")
        return None

    st_model = SentenceTransformer(str(model_dir))
    inner_model = st_model[0].auto_model  # extract raw transformer (Pitfall 3.3)
    inner_model.eval()

    tokenizer = st_model.tokenizer
    global dummy_ids, dummy_mask
    dummy_ids, dummy_mask = dummy_inputs(tokenizer)

    try:
        traced = torch.jit.trace(inner_model, (dummy_ids, dummy_mask))
    except Exception as e:
        print(f"  Trace failed: {e}")
        return None

    result = convert_with_fallbacks(
        traced,
        input_names=["input_ids", "attention_mask"],
        output_name="last_hidden_state",
        save_path=save_path,
    )

    # Copy vocab.txt alongside the model
    vocab_src = model_dir / "tokenizer" / "vocab.txt"
    if not vocab_src.exists():
        vocab_src = model_dir / "vocab.txt"
    if vocab_src.exists():
        dest = OUTPUT_DIR / f"vocab_{model_name.lower().replace('-', '_')}.txt"
        shutil.copy(vocab_src, dest)
        print(f"  Vocab copied → {dest.name}")
    else:
        print("  WARNING: vocab.txt not found — run tokenizer.save_pretrained() after training")

    return result


# ── 2. Emotion Classifier ─────────────────────────────────────────────────────

def convert_emotion_classifier():
    print(f"\n{'─'*60}")
    print("Converting emotion classifier")
    model_dir = Path("models/emotion-classifier")
    save_path = OUTPUT_DIR / "GJournalEmotionClassifier.mlpackage"

    if not model_dir.exists():
        print(f"  SKIP: {model_dir} not found (run training first)")
        return None

    tokenizer = AutoTokenizer.from_pretrained(str(model_dir))
    model = AutoModelForSequenceClassification.from_pretrained(str(model_dir))
    model.eval()

    global dummy_ids, dummy_mask
    dummy_ids, dummy_mask = dummy_inputs(tokenizer)

    try:
        traced = torch.jit.trace(model, (dummy_ids, dummy_mask))
    except Exception as e:
        print(f"  Trace failed: {e}")
        return None

    result = convert_with_fallbacks(
        traced,
        input_names=["input_ids", "attention_mask"],
        output_name="logits",
        save_path=save_path,
    )

    # Save label ordering so Swift can map index → Emotion enum
    import json
    config_path = model_dir / "config.json"
    if config_path.exists():
        with open(config_path) as f:
            cfg = json.load(f)
        labels_path = OUTPUT_DIR / "emotion_labels.json"
        with open(labels_path, "w") as f:
            json.dump(cfg.get("id2label", {}), f, indent=2)
        print(f"  Label order saved → {labels_path.name}")

    # Copy vocab.txt
    vocab_src = model_dir / "vocab.txt"
    if vocab_src.exists():
        shutil.copy(vocab_src, OUTPUT_DIR / "vocab_emotion.txt")
        print(f"  Vocab copied → vocab_emotion.txt")

    return result


# ── 3. Size validation ────────────────────────────────────────────────────────

def report_sizes():
    print(f"\n{'─'*60}")
    print("Output sizes:")
    for p in sorted(OUTPUT_DIR.glob("*.mlpackage")):
        size_mb = sum(f.stat().st_size for f in p.rglob("*") if f.is_file()) / 1e6
        status = "✓" if size_mb < 100 else "⚠ > 100MB"
        print(f"  {status}  {p.name:<50s}  {size_mb:.1f} MB")


# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("=== GJournal Core ML Conversion ===")
    print(f"Output directory: {OUTPUT_DIR.resolve()}")

    results = {}

    results["mobilebert"] = convert_embedding(
        Path("models/mobilebert-stsb"),
        "MobileBERT",
        "GJournalEmbeddingMobileBERT",
    )
    results["distilbert"] = convert_embedding(
        Path("models/distilbert-stsb"),
        "DistilBERT",
        "GJournalEmbeddingDistilBERT",
    )
    results["emotion"] = convert_emotion_classifier()

    report_sizes()

    print(f"\n{'─'*60}")
    print("Summary:")
    for name, path in results.items():
        status = f"✓ {path}" if path else "✗ failed — use backup plan (see 09_AI_PITFALLS.md §8)"
        print(f"  {name:<15s}: {status}")

    print("\nNext step: Copy *.mlpackage and vocab_*.txt into the Xcode project bundle.")
