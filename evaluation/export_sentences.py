"""
export_sentences.py

Exports STS-B and TwentyNewsgroups sentence text to JSON so the Swift
embed_apple_nlp.swift script can read them without any Python dependencies.

Run once from evaluation/:
    python export_sentences.py
"""

import json
import sys
from pathlib import Path

# ── STS-B ─────────────────────────────────────────────────────────────────────

def export_stsb():
    import datasets as hf_datasets
    print("Loading STS-B validation set...")
    stsb = hf_datasets.load_dataset(
        "nyu-mll/glue", "stsb",
        cache_dir="../training/hf_cache",
        split="validation",
    )
    out = {
        "sentence1": list(stsb["sentence1"]),
        "sentence2": list(stsb["sentence2"]),
        "scores":    [float(s) / 5.0 for s in stsb["label"]],
    }
    path = Path("datasets/stsb_sentences.json")
    path.write_text(json.dumps(out))
    print(f"  {len(out['sentence1'])} pairs → {path}")


# ── TwentyNewsgroups ──────────────────────────────────────────────────────────

def export_twentynews():
    import mteb
    import numpy as np
    print("Loading TwentyNewsgroupsClustering...")
    task = mteb.get_tasks(tasks=["TwentyNewsgroupsClustering"])[0]
    task.load_data()

    try:
        test_data = task.dataset["test"][0]
        sentences = list(test_data["sentences"])
        labels    = [int(l) for l in test_data["labels"]]
    except (KeyError, TypeError, IndexError) as exc:
        print(f"  Primary access failed ({exc}), trying alternative...")
        ds = task.dataset["test"]
        if hasattr(ds, "features"):
            sentences = list(ds["sentences"])
            labels    = [int(l) for l in ds["labels"]]
        else:
            sentences = list(ds[0]["sentences"])
            labels    = [int(l) for l in ds[0]["labels"]]

    out = {"sentences": sentences, "labels": labels}
    path = Path("datasets/twentynews_sentences.json")
    path.write_text(json.dumps(out))
    print(f"  {len(sentences)} sentences, {len(set(labels))} labels → {path}")


# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    Path("datasets").mkdir(exist_ok=True)
    export_stsb()
    export_twentynews()
    print("\nDone. Run: swift embed_apple_nlp.swift")
