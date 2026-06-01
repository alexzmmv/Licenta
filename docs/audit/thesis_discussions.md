# Thesis Discussions: The Anisotropy Problem in Contrastive Models

This document records key scientific findings to be included in the thesis discussion chapters, specifically regarding the clustering failure of the BGE model.

## 1. The Phenomenon: Catastrophic Chaining in DBSCAN

During on-device testing, a critical behavioral difference was observed between the two primary embedding models:
- **Model A (MiniLM / MobileBERT slot)**: Successfully separated journal entries into distinct, semantically meaningful clusters.
- **Model B (BGE-small-en-v1.5 / DistilBERT slot)**: Failed catastrophically, linking almost all journal entries into a single massive cluster (with a few entries marked as noise).

This occurred despite BGE having a higher STS-B Spearman correlation and being considered the state-of-the-art (SOTA) in its size class on the MTEB benchmark.

## 2. The Scientific Cause: Representation Degeneration (Anisotropy)

The root cause of this failure lies in the underlying architecture and training objectives of the two models:

### Contrastive Training and The Narrow Cone (BGE)
BGE is trained using a contrastive loss objective with `[CLS]` pooling. While contrastive learning excels at ranking tasks (pushing positive pairs slightly closer than negative pairs), it frequently suffers from **Representation Degeneration** (also known as **Anisotropy**). 
In an anisotropic space, the embedding vectors do not utilize the full spherical geometry of the vector space. Instead, they are squashed into a highly dense, narrow "cone". 
- Because all vectors point in roughly the same direction, the baseline cosine similarity between *any* two completely random sentences is exceptionally high (e.g., 0.80 to 0.90).
- Consequently, the distance space is compressed into a tight band. The density of points within this cone is virtually uniform.

### Knowledge Distillation and Isotropic Space (MiniLM)
MiniLM was trained via knowledge distillation with mean pooling. This approach naturally preserves a much more **isotropic** (spherical) embedding space.
- Unrelated sentences have cosine similarities near `0.0` or even negative.
- The space features highly dense semantic clusters separated by deep, empty "valleys".

## 3. Why DBSCAN Fails on Anisotropic Spaces

DBSCAN is a **density-based** clustering algorithm. It relies entirely on finding empty "valleys" of low density to determine where one cluster ends and another begins.

When applied to BGE's anisotropic cone:
1. The adaptive k-distance heuristic calculates a tight epsilon threshold (e.g., 0.10 distance).
2. Because the entire space is uniformly dense without valleys, Point A connects to Point B, B connects to C, and so on.
3. This triggers the **Chaining Effect**, where the algorithm simply walks across the entire dense cone, swallowing the entire dataset into a single cluster.

DBSCAN performs beautifully on MiniLM because the isotropic space has the deep valleys required to stop the chaining effect naturally.

## 4. Thesis Value and Conclusion

This is a highly valuable finding for the thesis because it demonstrates a critical real-world engineering tradeoff:
**Standardized benchmarks (like MTEB) do not guarantee production viability across all algorithmic pipelines.** 

While BGE scores higher on ranking/retrieval benchmarks, its highly anisotropic representation space makes it fundamentally incompatible with unsupervised density-based clustering algorithms like DBSCAN without applying post-processing corrections (such as Mean Centering/Whitening to force the space to be isotropic). 

MiniLM's isotropic space proved far superior and more robust for the specific task of unsupervised density clustering on mobile devices.
