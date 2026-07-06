#!/usr/bin/env python3
"""
quantize_emotion.py
───────────────────
Quantize GJournalEmotionClassifier.mlpackage using coremltools 9.

Strategy (plan.md §1.3 item 5):
  1. Try linear int8 weight quantization (per-channel symmetric).
     Quality gate: top-1 agreement ≥ 95% AND softmax-MAE < 0.01.
  2. Fall back to fp16 if int8 fails the gate.
     (fp16 for mlProgram format is done via 4-bit palettize in float32
      — just uses float16 dtype trick via internal API; if that fails we
      report it and skip. mlProgram fp16 requires re-conversion from source.)
  3. If both fail → leave original unchanged.

Usage (from repo root):
    training/.venv/bin/python training/quantize_emotion.py

Outputs:
  GJournal/MLModels/GJournalEmotionClassifier_int8.mlpackage
  GJournal/MLModels/GJournalEmotionClassifier_fp16.mlpackage   (if produced)
  GJournal/MLModels/GJournalEmotionClassifier_fp32_backup.mlpackage
  training/quantization_report.json
"""

import json
import os
import shutil
import sys
import time
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────────
REPO_ROOT = Path(__file__).parent.parent
MODEL_SRC  = REPO_ROOT / "GJournal/MLModels/GJournalEmotionClassifier.mlpackage"
OUT_FP16   = REPO_ROOT / "GJournal/MLModels/GJournalEmotionClassifier_fp16.mlpackage"
OUT_INT8   = REPO_ROOT / "GJournal/MLModels/GJournalEmotionClassifier_int8.mlpackage"
BACKUP     = REPO_ROOT / "GJournal/MLModels/GJournalEmotionClassifier_fp32_backup.mlpackage"
REPORT     = REPO_ROOT / "training/quantization_report.json"

N_DUMMY     = 100    # random inputs for quality gate
TOP1_THRESH = 0.95   # minimum top-1 agreement with fp32
# MAE computed on SOFTMAX probabilities (bounded 0–1), not raw logits
SOFTMAX_MAE_THRESH = 0.01

# ── Imports ────────────────────────────────────────────────────────────────────
try:
    import coremltools as ct
    from coremltools.optimize.coreml import (
        OpLinearQuantizerConfig,
        OptimizationConfig,
        linear_quantize_weights,
    )
    import numpy as np
except ImportError as e:
    sys.exit(
        f"[ERROR] Missing dependency: {e}\n"
        f"Fix: training/.venv/bin/pip install coremltools numpy"
    )

print(f"coremltools {ct.__version__}  |  numpy {np.__version__}")


# ── Helpers ────────────────────────────────────────────────────────────────────

def model_size_mb(path: Path) -> float:
    return sum(f.stat().st_size for f in path.rglob("*") if f.is_file()) / 1_048_576


def load_model(path: Path) -> ct.models.MLModel:
    """Load an mlPackage model, handling mlProgram weights_dir requirement."""
    weights_dir = path / "Data" / "com.apple.CoreML"
    if weights_dir.is_dir():
        return ct.models.MLModel(
            str(path),
            weights_dir=str(weights_dir),
            compute_units=ct.ComputeUnit.CPU_ONLY,
        )
    return ct.models.MLModel(str(path), compute_units=ct.ComputeUnit.CPU_ONLY)


def get_input_spec(model: ct.models.MLModel) -> dict[str, list | None]:
    spec = model.get_spec()
    result = {}
    for inp in spec.description.input:
        ft = inp.type.WhichOneof("Type")
        if ft == "multiArrayType":
            result[inp.name] = list(inp.type.multiArrayType.shape)
        elif ft == "imageType":
            h, w = inp.type.imageType.height, inp.type.imageType.width
            result[inp.name] = [1, h, w]
        else:
            result[inp.name] = None
    return result


def make_dummy(input_spec: dict, rng: np.random.Generator) -> dict:
    dummy = {}
    for name, shape in input_spec.items():
        if shape is None:
            continue
        is_int = any(kw in name.lower() for kw in ("input_ids", "token", "mask", "segment", "ids"))
        if is_int:
            dummy[name] = rng.integers(0, 30522, size=shape, dtype=np.int32)
        else:
            dummy[name] = rng.standard_normal(shape).astype(np.float32)
    return dummy


def softmax(x: np.ndarray) -> np.ndarray:
    e = np.exp(x - np.max(x))
    return e / e.sum()


def infer(model: ct.models.MLModel, inputs: dict) -> np.ndarray:
    """Run model and return the first numeric output flattened."""
    preds = model.predict(inputs)
    for v in preds.values():
        arr = np.array(v, dtype=np.float64).flatten()
        if arr.size > 0:
            return arr
    raise RuntimeError("Model produced no numeric output")


def quality_gate(
    ref_model: ct.models.MLModel,
    cand_model: ct.models.MLModel,
    input_spec: dict,
    n: int = N_DUMMY,
) -> tuple[bool, dict]:
    """
    Gate: compare softmax-normalized logits (bounded 0–1) for MAE,
    and top-1 class agreement.
    """
    rng = np.random.default_rng(42)
    top1_ok  = 0
    mae_sum  = 0.0

    for i in range(n):
        inp        = make_dummy(input_spec, rng)
        ref_logits = infer(ref_model, inp)
        cand_logits = infer(cand_model, inp)

        # Normalize to probabilities before computing MAE
        ref_probs  = softmax(ref_logits)
        cand_probs = softmax(cand_logits)

        top1_ok += int(np.argmax(ref_probs) == np.argmax(cand_probs))
        mae_sum += float(np.mean(np.abs(ref_probs - cand_probs)))

        if (i + 1) % 25 == 0:
            print(f"    [{i+1}/{n}] top1_ok={top1_ok}  "
                  f"running_softmax_mae={mae_sum/(i+1):.6f}")

    top1_rate = top1_ok / n
    mean_mae  = mae_sum / n
    passed    = (top1_rate >= TOP1_THRESH) and (mean_mae <= SOFTMAX_MAE_THRESH)

    return passed, {
        "top1_agreement":        round(top1_rate, 4),
        "mean_softmax_mae":      round(mean_mae, 7),
        "n_samples":             n,
        "top1_threshold":        TOP1_THRESH,
        "softmax_mae_threshold": SOFTMAX_MAE_THRESH,
        "passed":                passed,
    }


# ── Quantization routines ──────────────────────────────────────────────────────

def make_int8(src: Path, dst: Path) -> ct.models.MLModel:
    """Linear per-channel symmetric int8 weight quantization."""
    if dst.exists():
        shutil.rmtree(dst)
    print("  → Applying int8 linear weight quantization …")
    model = load_model(src)
    config = OptimizationConfig(
        global_config=OpLinearQuantizerConfig(
            mode="linear_symmetric",
            dtype="int8",
            granularity="per_channel",
        )
    )
    q_model = linear_quantize_weights(model, config)
    q_model.save(str(dst))
    return load_model(dst)


def make_fp16(src: Path, dst: Path) -> ct.models.MLModel:
    """
    Attempt int4 palettize as a proxy for fp16 size (often smaller).
    mlProgram format does not support the legacy neural_network fp16 API.
    Falls back gracefully.
    """
    if dst.exists():
        shutil.rmtree(dst)
    print("  → Applying int4 palettize (fp16 proxy for mlProgram format) …")
    from coremltools.optimize.coreml import OpPalettizerConfig, palettize_weights

    model = load_model(src)
    config = OptimizationConfig(
        global_config=OpPalettizerConfig(
            mode="kmeans",
            nbits=4,
            granularity="per_grouped_channel",
            group_size=16,
        )
    )
    q_model = palettize_weights(model, config)
    q_model.save(str(dst))
    return load_model(dst)


# ── Main ───────────────────────────────────────────────────────────────────────

def main() -> None:
    report: dict = {
        "timestamp":      time.strftime("%Y-%m-%dT%H:%M:%S"),
        "source_model":   str(MODEL_SRC.name),
        "source_size_mb": round(model_size_mb(MODEL_SRC), 2),
        "coremltools":    ct.__version__,
    }

    print(f"\n{'='*60}")
    print(f"  GJournalEmotionClassifier Quantization")
    print(f"{'='*60}")
    print(f"  Source   : {MODEL_SRC.name}")
    print(f"  Size     : {report['source_size_mb']:.1f} MB")
    print(f"  Gate     : top1 ≥ {TOP1_THRESH*100:.0f}%  |  softmax-MAE < {SOFTMAX_MAE_THRESH}")
    print(f"  NOTE     : MAE computed on softmax probabilities (not raw logits)")
    print(f"{'='*60}\n")

    # Load fp32 reference
    print("Loading fp32 reference model …")
    fp32 = load_model(MODEL_SRC)
    spec = get_input_spec(fp32)
    print(f"  Inputs  : {spec}\n")

    # ── INT8 ──────────────────────────────────────────────────────────────────
    int8_ok = False
    print("[1/2] INT8 weight quantization")
    t0 = time.time()
    try:
        int8_mdl  = make_int8(MODEL_SRC, OUT_INT8)
        int8_size = model_size_mb(OUT_INT8)
        print(f"  Saved   : {int8_size:.1f} MB  ({time.time()-t0:.1f}s)")
        print(f"  Running quality gate ({N_DUMMY} samples) …")
        int8_ok, int8_metrics = quality_gate(fp32, int8_mdl, spec)
        report["int8"] = {"size_mb": round(int8_size, 2), "gate": int8_metrics}
        status = "PASS ✓" if int8_ok else "FAIL ✗"
        print(f"  Result  : top1={int8_metrics['top1_agreement']:.3f}  "
              f"softmax-MAE={int8_metrics['mean_softmax_mae']:.6f}  → {status}")
    except Exception as exc:
        print(f"  ERROR   : {exc}")
        report["int8"] = {"error": str(exc)}

    # ── FP16 / int4 palettize ─────────────────────────────────────────────────
    fp16_ok = False
    print("\n[2/2] FP16-proxy (int4 palettize) quantization")
    t0 = time.time()
    try:
        fp16_mdl  = make_fp16(MODEL_SRC, OUT_FP16)
        fp16_size = model_size_mb(OUT_FP16)
        print(f"  Saved   : {fp16_size:.1f} MB  ({time.time()-t0:.1f}s)")
        print(f"  Running quality gate ({N_DUMMY} samples) …")
        fp16_ok, fp16_metrics = quality_gate(fp32, fp16_mdl, spec)
        report["fp16_proxy_int4"] = {"size_mb": round(fp16_size, 2), "gate": fp16_metrics}
        status = "PASS ✓" if fp16_ok else "FAIL ✗"
        print(f"  Result  : top1={fp16_metrics['top1_agreement']:.3f}  "
              f"softmax-MAE={fp16_metrics['mean_softmax_mae']:.6f}  → {status}")
    except Exception as exc:
        print(f"  ERROR   : {exc}")
        report["fp16_proxy_int4"] = {"error": str(exc)}

    # ── Decision ──────────────────────────────────────────────────────────────
    print(f"\n{'='*60}")
    print("  DECISION")
    print(f"{'='*60}")

    if int8_ok:
        winner, winner_path = "int8", OUT_INT8
        print("  ✅  INT8 passes gate — shipping int8 (best size + ANE speed).")
    elif fp16_ok:
        winner, winner_path = "int4_palettize", OUT_FP16
        print("  ⚠️   INT8 failed; int4-palettize passes — shipping that.")
    else:
        winner, winner_path = "none", None
        print("  ❌  Both quantizations failed — keeping original fp32.")

    report["winner"] = winner

    if winner_path is not None:
        winner_size = model_size_mb(winner_path)
        reduction   = (1 - winner_size / report["source_size_mb"]) * 100
        report["winning_size_mb"]    = round(winner_size, 2)
        report["size_reduction_pct"] = round(reduction, 1)

        # Back up original (once)
        if not BACKUP.exists():
            print(f"\n  Backing up original → {BACKUP.name} …")
            shutil.copytree(MODEL_SRC, BACKUP)

        # Replace original with winner
        print(f"  Replacing {MODEL_SRC.name} with {winner} model …")
        shutil.rmtree(MODEL_SRC)
        shutil.copytree(winner_path, MODEL_SRC)

        print(f"\n  ✅  Done.")
        print(f"      Before : {report['source_size_mb']:.1f} MB")
        print(f"      After  : {winner_size:.1f} MB  (-{reduction:.0f}%)")
    else:
        print("\n  Original model unchanged.")

    # ── Report ─────────────────────────────────────────────────────────────────
    REPORT.parent.mkdir(exist_ok=True)
    with open(REPORT, "w") as f:
        json.dump(report, f, indent=2)
    print(f"\n  Report → training/quantization_report.json")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    main()
