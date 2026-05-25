# Science Review — Psychology, Emotion Taxonomy & GoEmotions Mapping

---

## 1. Journaling Framework: CBT Comparison

### The Feel → Event → Action Model

GJournal uses a three-step micro-journaling framework:

| Step | Prompt | CBT Equivalent |
|:-----|:-------|:---------------|
| **Feel** | "How are you feeling right now?" | Consequence (C) — the emotional response |
| **Event** | "What happened today?" | Activating Event (A) — the external trigger |
| **Action** | "What will you do about it?" | Behavioral response — not in classic ABC |

### What's Missing: The Cognitive Appraisal

In **Cognitive Behavioral Therapy (CBT)**, the **ABC Model** (Ellis, 1962) states:

```
A (Activating Event) → B (Beliefs/Thoughts) → C (Consequences/Emotions)
```

The critical insight is that emotions (C) don't flow directly from events (A). They are mediated by our **beliefs and automatic thoughts** (B) — how we *interpret* the event.

**GJournal skips B entirely.** The user records what happened and how they feel, but never examines *what they told themselves* about the event.

### Academic Justification (for your thesis)

You can argue this is **intentional and appropriate** for a micro-journaling context:

1. **Pennebaker's Expressive Writing paradigm** (Pennebaker & Beall, 1986) shows that simply writing about emotional experiences produces measurable psychological benefits — without requiring cognitive restructuring.

2. **Behavioral Activation (BA)** theory (Jacobson et al., 1996) — the "Action" step directly implements BA by prompting the user to plan proactive behavior, which is an evidence-based intervention for depression.

3. **Micro-journaling** is intentionally brief. Adding a "Thoughts" step increases friction and may reduce adherence. The tradeoff between therapeutic depth and user engagement is a legitimate design choice.

> [!TIP]
> In your thesis, frame this as: *"GJournal prioritizes expressive writing and behavioral activation over cognitive restructuring, trading therapeutic depth for higher engagement and journaling consistency."*

---

## 2. Emotion Taxonomy Analysis

### Current 12 Emotions (Emotion.swift)

Your 12 emotions mix two psychological frameworks:

**Ekman's Basic Emotions** (Ekman, 1992):
- Joy, Sadness, Anger, Fear, Disgust, Surprise ✅ (all 6 present)

**Complex Affect States** (not basic emotions):
- Anxiety, Excitement, Gratitude, Hope, Guilt, Love

### Overlap Issues for Clustering

| Pair | Semantic Overlap | Impact on DBSCAN |
|:-----|:-----------------|:-----------------|
| Fear ↔ Anxiety | High (anxiety is chronic fear) | Entries may not separate into distinct clusters |
| Joy ↔ Excitement | Moderate (excitement is intense joy) | Overlapping clusters |
| Joy ↔ Hope | Moderate (hope is future-oriented joy) | Fuzzy boundaries |
| Sadness ↔ Guilt | Moderate (guilt involves self-directed sadness) | May merge |

### Academic Justification

These 12 emotions align well with **Plutchik's Wheel of Emotions** (Plutchik, 1980), which defines 8 primary emotions arranged in opposing pairs plus compound emotions formed by combining adjacent primaries.

**Your mapping to Plutchik:**

```
        Joy ←→ Sadness       (opposing pair)
      Anger ←→ Fear          (opposing pair)
    Disgust ←→ Love          (opposing pair — "acceptance" in Plutchik)
   Surprise ←→ Anxiety       (opposing pair — "anticipation" in Plutchik)
   
   Compound emotions:
   Excitement = Joy + Surprise
   Gratitude  = Joy + Love
   Hope       = Joy + Anticipation
   Guilt      = Sadness + Disgust (remorse in Plutchik)
```

> [!TIP]
> In your thesis, cite Plutchik to justify the taxonomy. The 12 emotions cover all 8 primary dimensions plus 4 commonly experienced compounds. This is a defensible, science-backed choice.

---

## 3. GoEmotions → 12-Label Mapping

The GoEmotions dataset (Demszky et al., 2020) has **27 emotions + neutral** (28 total). You need to map these down to your 12 GJournal labels for classifier training.

### Mapping Design

This mapping is based on **semantic similarity** and **Plutchik's dimensional alignment**:

| GJournal Label | GoEmotions Sources | Rationale |
|:---------------|:-------------------|:----------|
| **Joy** | `joy`, `amusement`, `approval`, `pride`, `relief` | All positive valence, high arousal states centered on pleasure |
| **Sadness** | `sadness`, `grief`, `disappointment` | Negative valence, low arousal states of loss/unfulfillment |
| **Anger** | `anger`, `annoyance`, `disapproval` | High arousal, negative valence states directed at external targets |
| **Fear** | `fear` | Pure basic emotion — kept narrow to distinguish from Anxiety |
| **Love** | `love`, `caring`, `admiration`, `desire` | Positive valence states directed toward specific attachment objects |
| **Surprise** | `surprise`, `realization`, `confusion` | Sudden cognitive shift states (confusion = negative surprise) |
| **Disgust** | `disgust` | Pure basic emotion |
| **Anxiety** | `nervousness` | Future-oriented apprehension (distinct from acute Fear) |
| **Excitement** | `excitement`, `curiosity` | High arousal, positive valence, anticipatory states |
| **Gratitude** | `gratitude` | Distinct prosocial emotion (one-to-one mapping) |
| **Hope** | `optimism` | Future-oriented positive expectation |
| **Guilt** | `remorse`, `embarrassment` | Self-conscious, inward-directed negative states |

### Dropped Labels

| GoEmotions Label | Reason |
|:-----------------|:-------|
| `neutral` | No emotional content — skip during training (or use as a 13th "calm" class) |

### Implementation (Python)

```python
GOEMOTION_TO_GJOURNAL = {
    # Joy cluster
    'joy': 'Joy', 'amusement': 'Joy', 'approval': 'Joy',
    'pride': 'Joy', 'relief': 'Joy',
    # Sadness cluster
    'sadness': 'Sadness', 'grief': 'Sadness', 'disappointment': 'Sadness',
    # Anger cluster
    'anger': 'Anger', 'annoyance': 'Anger', 'disapproval': 'Anger',
    # Fear (narrow)
    'fear': 'Fear',
    # Love cluster
    'love': 'Love', 'caring': 'Love', 'admiration': 'Love', 'desire': 'Love',
    # Surprise cluster
    'surprise': 'Surprise', 'realization': 'Surprise', 'confusion': 'Surprise',
    # Disgust (narrow)
    'disgust': 'Disgust',
    # Anxiety (narrow)
    'nervousness': 'Anxiety',
    # Excitement cluster
    'excitement': 'Excitement', 'curiosity': 'Excitement',
    # Gratitude (1:1)
    'gratitude': 'Gratitude',
    # Hope (1:1)
    'optimism': 'Hope',
    # Guilt cluster
    'remorse': 'Guilt', 'embarrassment': 'Guilt',
}

TARGET_LABELS = [
    'Joy', 'Sadness', 'Anger', 'Fear', 'Love', 'Surprise',
    'Disgust', 'Anxiety', 'Excitement', 'Gratitude', 'Hope', 'Guilt'
]
```

### Class Imbalance Warning

After mapping, some classes will have far more examples than others:

| Class | Estimated GoEmotions examples | Risk |
|:------|:----------------------------:|:-----|
| Joy | ~8,000 (5 sources) | Over-represented |
| Anger | ~5,500 (3 sources) | OK |
| Sadness | ~3,000 (3 sources) | OK |
| Anxiety | ~500 (1 source: nervousness) | 🔴 **Severely under-represented** |
| Disgust | ~600 (1 source) | 🔴 **Under-represented** |
| Gratitude | ~1,200 (1 source) | Borderline |

**Fix**: Use class-weighted loss during training:

```python
from sklearn.utils.class_weight import compute_class_weight
import numpy as np

class_weights = compute_class_weight(
    'balanced', 
    classes=np.arange(12), 
    y=train_labels  # integer labels
)
# Pass to Trainer via custom loss or use the `class_weight` parameter
```

---

## 4. Safety Filter — Academic Position

The keyword-based `SafetyFilter.swift` is sufficient for personal use but is not ML-backed. For your thesis:

- **Frame it as a lightweight first-pass filter** designed for on-device efficiency
- Note that a production system would use a fine-tuned classifier (e.g., Perspective API architecture)
- The key thesis argument is that the filter **doesn't block journaling** — it only excludes flagged entries from clustering/recommendations, which is therapeutically appropriate (users should be able to express distress freely)

---

## 🎓 PhD Review

1. **The GoEmotions mapping is a thesis contribution**. You're designing a dimensional reduction from 28 fine-grained emotions to 12 clinically-informed categories. Frame it as: *"We propose a mapping from the GoEmotions taxonomy to a reduced set of 12 emotions aligned with Plutchik's model, optimized for micro-journaling contexts."*
2. **Class imbalance handling** shows methodological awareness. Report the class distribution before and after mapping, and justify the weighted loss approach citing King & Zeng (2001) or Japkowicz & Stephen (2002).
3. **The CBT comparison** demonstrates interdisciplinary thinking (CS + psychology). A thesis committee will appreciate this. Cite Pennebaker (1986), Ellis (1962), and Jacobson et al. (1996).
4. **The Plutchik alignment** gives you a visual diagram opportunity in the thesis. Draw the wheel with your 12 emotions mapped onto it — this is visually impactful and immediately shows the taxonomy is grounded in theory.
5. **Consider a confusion matrix** for the classifier: which emotions are most often confused? This reveals whether the Anxiety↔Fear and Joy↔Excitement overlaps are real problems or theoretical concerns.

## 🔴 Red-Hat Review

1. **Anxiety has only ~500 training examples** (mapped from "nervousness" alone). This will likely produce poor recall. Consider: (a) augmenting with "confusion" examples that lean anxious, (b) using data augmentation (back-translation, synonym replacement), or (c) accepting lower Anxiety recall and documenting it honestly.
2. **The multi-label problem**: GoEmotions allows an entry to have multiple emotion labels (e.g., both "joy" and "gratitude"). Taking only the first label discards valid signal. If an entry is labeled [joy, gratitude], you're training the model that this text is ONLY joy, which teaches it that gratitude looks like joy. **Consider multi-label training with sigmoid output per class**.
3. **"Confusion" mapped to Surprise** is debatable. Confusion is cognitively closer to Anxiety (uncertainty, disorientation) than to Surprise (sudden unexpected event). Test both mappings and see which produces better classifier F1.
4. **The safety filter's "flag but don't block" design** is therapeutically correct but legally untested. For a thesis this is fine. In a real app, consult with a mental health professional about how to handle crisis content (e.g., suicidal ideation should trigger a helpline resource, not just a flag).
