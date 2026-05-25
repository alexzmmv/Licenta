"""
Backup emotion classifier: TF-IDF + LogisticRegression → Core ML.

Use this if the MobileBERT/DistilBERT GoEmotions training fails or
the resulting .mlpackage won't load on the target device.

Output: coreml_models/GJournalEmotionClassifier_simple.mlpackage
        results/emotion_simple_report.txt

Run: python backup/train_emotion_simple.py
Time: < 5 minutes on any hardware. No GPU needed.
Expected accuracy: ~50-55% (lower than BERT ~65%, but always works)

Pitfall ref: 09_AI_PITFALLS.md §8.2
"""

from pathlib import Path
from collections import Counter

import numpy as np
import datasets
from sklearn.pipeline import Pipeline
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report
import coremltools as ct

# ── Same label mapping as the main classifier ─────────────────────────────────
LABEL_MAP = {
    "joy":"Joy","amusement":"Joy","approval":"Joy","pride":"Joy","relief":"Joy",
    "sadness":"Sadness","grief":"Sadness","disappointment":"Sadness",
    "anger":"Anger","annoyance":"Anger","disapproval":"Anger",
    "fear":"Fear",
    "love":"Love","caring":"Love","admiration":"Love","desire":"Love",
    "surprise":"Surprise","realization":"Surprise","confusion":"Surprise",
    "disgust":"Disgust",
    "nervousness":"Anxiety",
    "excitement":"Excitement","curiosity":"Excitement",
    "gratitude":"Gratitude",
    "optimism":"Hope",
    "remorse":"Guilt","embarrassment":"Guilt",
}
TARGET_LABELS = [
    "Joy","Sadness","Anger","Fear","Love","Surprise",
    "Disgust","Anxiety","Excitement","Gratitude","Hope","Guilt",
]
LABEL2ID = {l: i for i, l in enumerate(TARGET_LABELS)}

# ── Load and remap GoEmotions ──────────────────────────────────────────────────
print("Loading GoEmotions...")
raw = datasets.load_dataset(
    "google-research-datasets/go_emotions", "simplified",
    cache_dir="../hf_cache", trust_remote_code=True,
)
label_feature = raw["train"].features["labels"].feature

def build_xy(split_name):
    texts, labels = [], []
    for ex in raw[split_name]:
        for lid in ex["labels"]:
            go_label = label_feature.int2str(lid)
            mapped = LABEL_MAP.get(go_label)
            if mapped:
                texts.append(ex["text"])
                labels.append(LABEL2ID[mapped])
    return texts, labels

X_train, y_train = build_xy("train")
X_test,  y_test  = build_xy("test")
print(f"Train: {len(X_train)} | Test: {len(X_test)}")
print(f"Class distribution: {Counter(y_train)}")

# ── Fit sklearn pipeline ──────────────────────────────────────────────────────
pipeline = Pipeline([
    ("tfidf", TfidfVectorizer(
        max_features=15000,
        ngram_range=(1, 2),
        min_df=2,
        sublinear_tf=True,
    )),
    ("clf", LogisticRegression(
        max_iter=500,
        class_weight="balanced",
        C=1.0,
        solver="lbfgs",
        multi_class="multinomial",
    )),
])

print("Training TF-IDF + LogisticRegression...")
pipeline.fit(X_train, y_train)

y_pred = pipeline.predict(X_test)
report = classification_report(y_test, y_pred, target_names=TARGET_LABELS, digits=3)
print(report)

Path("../results").mkdir(exist_ok=True)
with open("../results/emotion_simple_report.txt", "w") as f:
    f.write("Backup classifier: TF-IDF + LogisticRegression\n\n")
    f.write(report)

# ── Export to Core ML ─────────────────────────────────────────────────────────
print("Converting to Core ML...")
Path("../coreml_models").mkdir(exist_ok=True)

try:
    mlmodel = ct.converters.sklearn.convert(
        pipeline,
        input_features=[("text", ct.models.datatypes.String())],
        output_feature_names=TARGET_LABELS,
    )
    save_path = "../coreml_models/GJournalEmotionClassifier_simple.mlpackage"
    mlmodel.save(save_path)
    print(f"Saved: {save_path}")
    print("NOTE: This model takes raw text — Swift must call predict({text: entry}) directly.")
    print("      No tokenizer needed. No vocab.txt needed.")
    print("      Accuracy ~50-55% vs ~65% for BERT — use only as last resort.")
except Exception as e:
    print(f"CoreML export failed: {e}")
    print("Saving sklearn model as .pkl for manual inspection:")
    import joblib
    joblib.dump(pipeline, "../results/emotion_simple.pkl")
    print("Saved to results/emotion_simple.pkl")
