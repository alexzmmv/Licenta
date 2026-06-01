# GJournal AI Pipeline: A Comprehensive Machine Learning & On-Device Clustering Report

This report provides a thorough, beginner-friendly, and academically rigorous breakdown of the complete Artificial Intelligence (AI) and Machine Learning (ML) pipeline implemented in **GJournal**. Designed as a foundational reference for a Bachelor's thesis, it covers every conceptual definition, mathematical equation, and algorithmic step, mapping them directly to the corresponding Swift implementations in the codebase.

---

## 1. High-Level AI Pipeline Overview

The core value of GJournal is its ability to take raw, unstructured, and intimate human thoughts (journal entries) and automatically organize them into highly cohesive, thematic clusters (journal threads) with meaningful titles—all while running completely offline on the user's Apple device.

To achieve this, the application operates a sequential multi-stage AI pipeline:

```
[Raw Journal Text] (Title + Feel Text)
       │
       ▼
[WordPiece Tokenizer] (Subword parsing into token indices & attention masks)
       │
       ▼
[CoreML Embeddings] (On-device neural inference: MiniLM 384d or Nomic 768d)
       │
       ▼
[MRL Truncation & Normalisation] (Dimensionality slicing to 256d + L2 re-scaling)
       │
       ▼
[Accelerated Distance Computation] (vDSP-SIMD pre-computation of O(N²) Cosine matrix)
       │
       ▼
[Adaptive Parameter Calibration] (Adaptive minPts + Kneedle + Silhouette Grid Search)
       │
       ▼
[Calibrated DBSCAN Clustering] (Density-based theme grouping & noise extraction)
       │
       ▼
[NLP Parsing & TF-IDF Labeling] (NLTagger POS Tagging + corpus-wide TF-IDF naming)
       │
       ▼
[Evocative Named Threads] (e.g., "Anxiety & Career" or "Fitness & Growth")
```

This pipeline translates raw textual strings into a geometric vector manifold, measures their semantic proximity, separates dense thematic regions from background noise, and uses statistical natural language processing to title the resulting themes.

---

## 2. On-Device (Edge) ML vs. Cloud ML

Traditional modern applications rely heavily on **Cloud ML**, where user data is transmitted over the internet to a centralized server cluster (running models on OpenAI, AWS, or Google Cloud) which performs the calculations and returns the results. 

GJournal deliberately rejects this approach in favor of **On-Device ML** (also called **Edge AI**). Below is a comparative analysis of these paradigms, highlighting why Edge AI is critical for a personal journaling application:

| Feature | On-Device (Edge) ML | Cloud-Based ML |
| :--- | :--- | :--- |
| **Privacy & Security** | **Absolute**. Data never leaves the device. Zero risk of server-side data leaks. | **High Risk**. Private text must be sent to third-party APIs or storage. |
| **Latency** | **Sub-millisecond**. Local RAM and GPU execution bypasses network lag. | **Variable**. Subject to network latency, round-trip time, and server load. |
| **Offline Capability** | **100% Functional**. Works in airplane mode, remote locations, or bad signal. | **Inoperable**. Fails completely without an active internet connection. |
| **Operational Cost** | **$0.00**. Uses the hardware the user already owns (zero server API bills). | **Expensive**. Pay-per-token API pricing scales linearly with active users. |
| **Hardware Constraints** | Tight limits on RAM, battery usage, and thermal thresholds. | Practically infinite resources (scalable cloud clusters). |

### Implementation Context: CoreML & The Apple Neural Engine (ANE)
Apple provides the **CoreML** framework to execute deep neural networks locally on iOS and macOS devices. CoreML compiled model packages (`.mlmodelc`) are optimized to load weights into local memory and dispatch mathematical computations across three hardware engines:
1. **CPU**: High-latency, sequential processing (fallback for unsupported layers).
2. **GPU**: Moderate-latency, high-throughput parallel arithmetic (Metal-optimized).
3. **Apple Neural Engine (ANE)**: A specialized, energy-efficient energy coprocessor designed explicitly for highly parallel matrix multiplications (convolutions and attention mechanisms) using 8-bit or 16-bit float quantization.

In your codebase, both embedding and emotion classifiers are configured to run with:
```swift
let config = MLModelConfiguration()
config.computeUnits = .all // Allows CoreML to automatically orchestrate across CPU, GPU, and ANE
```
This ensures that the device’s dedicated AI hardware handles the heavy lifting, preventing battery drain and thermal throttling.

---

## 3. Text Embeddings: Semantic Vector Space

At the heart of the pipeline is the concept of a **Text Embedding**. A neural network cannot read text as a human does. Instead, it must convert text into a format it understands: **numbers**.

### What is a Text Embedding?
An embedding is a mathematical mapping that takes a variable-length string of text and projects it as a fixed-length vector (an array of real numbers) into a highly structured, multi-dimensional **semantic vector space**.

* **The Longitude/Latitude Analogy**: Imagine placing cities on a 2D map. "Chicago" and "New York" will have coordinates that are close together because they are geographically close. "Tokyo" will be far away.
* **Semantic Manifold**: In a text embedding space (which typically has 384 or 768 dimensions instead of 2), coordinates represent *concepts*. Words, sentences, or paragraphs with similar meanings are projected onto nearby coordinates, even if they share zero vocabulary words in common.
  * For example, the sentence *"I went for a run today and crushed my pace"* and *"My morning cardio training felt incredible"* share almost no words, yet they are placed extremely close to each other in the embedding space because their semantic meaning (exercise, fitness) is highly aligned.

### The WordPiece Tokenization Algorithm
Before text is fed into a CoreML transformer model, it must be broken down into discrete numerical units called **tokens**. GJournal implements a custom Swift-native **WordPiece Tokenizer** (`WordPieceTokenizer.swift`).

WordPiece is a subword tokenization algorithm that builds a vocabulary from a large text corpus. The algorithm works as follows:
1. It splits text into words, then recursively breaks words down into smaller subword units (characters or frequent character combinations).
2. Subwords that are not at the start of a word are prefixed with a special symbol (e.g., `##`).
3. If a word is unknown to the vocabulary, it is broken down into constituent subwords that *are* known. For example, `introspective` might be parsed as `intro` + `##spect` + `##ive`.
4. This ensures the model has a zero-out-of-vocabulary (OOV) rate: it can represent any string by breaking it down into raw characters if necessary.

The tokenizer converts a sentence into two critical arrays of size $L$ (where $L$ is the maximum sequence length, set in `WordPieceTokenizer.maxLength`):
* **Input IDs (`input_ids`)**: An array of vocabulary indices representing the parsed tokens.
* **Attention Mask (`attention_mask`)**: A binary array where $1$ indicates a real token and $0$ indicates padding tokens (since short sentences are padded with zeros to maintain a uniform input shape for the CoreML neural net).

### Model Comparisons in Your Thesis
Your Bachelor's thesis evaluates three specific embedding configurations across two distinct model architectures:

#### 1. MiniLM (represented by `all-MiniLM-L6-v2`)
* **Developer / Architecture**: Microsoft. It is a highly compressed, distilled version of the BERT (Bidirectional Encoder Representations from Transformers) architecture, optimized for speed.
* **Dimensions**: $384$ coordinates.
* **Characteristics**: Extremely lightweight ($~80$ MB), fast execution, low memory footprint. Ideal for legacy iOS devices, but has lower semantic density.
* **Pooling Strategy**: Mean pooling over real tokens.

#### 2. Nomic Embed (represented by `nomic-embed-text-v1.5`)
* **Developer / Architecture**: Nomic AI. A modern, high-performance open-weight model designed specifically for long-context retrieval and clustering tasks.
* **Dimensions**: $768$ coordinates (full weight configuration).
* **Characteristics**: Superior semantic capacity. It is trained with **task prefixes** to guide its attention heads. When clustering, the text is prepended with `"clustering: "` to instruct the model to organize its vector space specifically for grouping rather than information retrieval.
* **Code Implementation**:
  ```swift
  // NomicEmbeddingService.swift: Lines 56-57
  let prefixedText = "clustering: \(text)"
  let tokens = await tokenizer.tokenize(prefixedText)
  ```

---

## 4. Matryoshka Representation Learning (MRL)

When using high-performance models like Nomic, the resulting vector has $768$ dimensions. While this provides rich semantic representation, storing and clustering $768$-dimensional vectors requires significant computation and memory:
* A distance matrix for $N$ entries requires $N \times N$ calculations.
* At $768$ dimensions, these calculations grow expensive and slow on mobile hardware.

To solve this, modern AI uses a technique called **Matryoshka Representation Learning (MRL)**.

### The Russian Nesting Doll Analogy
A traditional embedding vector is like a house key: you need the entire key to unlock the door; if you cut off the bottom half of the key, it is useless.

An MRL embedding is like a **Matryoshka doll (Russian nesting doll)** or a **progressive JPEG image**:
* The outermost, largest doll represents the full vector ($768$ dimensions).
* If you open it, there is a smaller doll inside ($256$ dimensions). Inside that is a smaller one ($128$ dimensions), and so on.
* The model is trained specifically so that the **most critical, coarse-grained semantic information is packed into the first few dimensions**. As you add more dimensions, you add fine-grained details.
* Therefore, you can **truncate (slice)** the vector to a much smaller size (e.g., keeping only the first $256$ numbers of the $768$-dimensional vector) and retain over $95\%$ of the model's clustering performance while reducing computation and memory requirements by $3\times$.

### Mathematical Formulation of MRL & Re-Normalization
When we slice a vector, its length changes. In vector geometry, to measure angles (similarity) accurately, the vectors must reside on a **unit hypersphere**, meaning their geometric length (L2 norm) must equal exactly $1.0$. 

#### 1. Slicing
Let $\vec{x} = [x_1, x_2, \dots, x_{768}]$ be the original $768$-dimensional vector generated by Nomic. We truncate this vector to a dimension $d$ (where $d = 256$):
$$\vec{x}_{\text{truncated}} = [x_1, x_2, \dots, x_{d}]$$

#### 2. L2 Norm Calculation
The geometric length ($L_2$ norm) of this truncated vector is computed as the square root of the sum of its squared components:
$$\|\vec{x}_{\text{truncated}}\|_2 = \sqrt{\sum_{i=1}^{d} x_i^2}$$

#### 3. Vector Re-Normalization
To project the truncated vector back onto the unit hypersphere, we divide each component by the computed $L_2$ norm:
$$\vec{x}_{\text{normalized}} = \frac{\vec{x}_{\text{truncated}}}{\|\vec{x}_{\text{truncated}}\|_2}$$

### Code Mapping
In your project, the truncation and L2 re-normalization are executed in `NomicEmbeddingService.swift`:
```swift
// NomicEmbeddingService.swift: Lines 93-96 (Truncation)
let activeDim = min(self.truncateDim, fullDim)
if activeDim < embedding.count {
    embedding = Array(embedding.prefix(activeDim))
}

// NomicEmbeddingService.swift: Lines 102-111 (L2 Re-normalization using Accelerate)
private static func l2Normalize(_ v: [Float]) -> [Float] {
    var normSq: Float = 0
    vDSP_svesq(v, 1, &normSq, vDSP_Length(v.count)) // Sum of squares: ∑ x_i^2
    let norm = sqrt(normSq)                        // Square root to find length
    guard norm > 0 else { return v }
    var result = v
    var scalar: Float = 1.0 / norm
    vDSP_vsmul(v, 1, &scalar, &result, 1, vDSP_Length(v.count)) // Multiply vector by 1/norm
    return result
}
```

---

## 5. Distance Metrics & Hardware Acceleration (Apple vDSP)

Once journal entries are converted into normalise vectors, the application must compute how "similar" they are to one another.

### Why Euclidean Distance Fails (The Curse of Dimensionality)
**Euclidean Distance** measures the straight-line distance between two points in space:
$$d_{\text{Eucl}}(\vec{u}, \vec{v}) = \sqrt{\sum_{i=1}^{d} (u_i - v_i)^2}$$

In machine learning, high-dimensional spaces (such as $384$ or $768$ dimensions) suffer from the **Curse of Dimensionality**. As the number of dimensions increases, the volume of the space grows exponentially, causing all data points to become extremely sparse and far apart. The Euclidean distance between almost all pairs of vectors flattens out and converges, making it highly unreliable for separating true semantic similarities from differences.

### Cosine Similarity & Cosine Distance
To bypass this, we use **Cosine Similarity**, which measures the *angle* between two vectors rather than their distance. It evaluates whether the vectors are pointing in the same semantic direction, regardless of their magnitude:
$$\text{CosineSimilarity}(\vec{u}, \vec{v}) = \frac{\vec{u} \cdot \vec{v}}{\|\vec{u}\|_2 \|\vec{v}\|_2} = \frac{\sum_{i=1}^{d} u_i v_i}{\sqrt{\sum_{i=1}^{d} u_i^2} \sqrt{\sum_{i=1}^{d} v_i^2}}$$

**Cosine Distance** is the complement of Cosine Similarity, representing how *dissimilar* two entries are (ranging from $0.0$ for identical meaning, up to $2.0$ for completely opposite meanings):
$$d_{\text{Cosine}}(\vec{u}, \vec{v}) = 1.0 - \text{CosineSimilarity}(\vec{u}, \vec{v})$$

### Pre-Normalization Optimization
Because GJournal pre-normalizes every embedding vector to unit length ($L_2$ norm $= 1.0$) immediately upon generation (refer to Section 4), the vector lengths $\|\vec{u}\|_2$ and $\|\vec{v}\|_2$ both equal $1.0$.

This mathematically simplifies the Cosine Distance equation into a simple **dot product**:
$$d_{\text{Cosine}}(\vec{u}, \vec{v}) = 1.0 - (\vec{u} \cdot \vec{v}) = 1.0 - \sum_{i=1}^{d} u_i v_i$$
This simplification is highly advantageous for mobile devices, as calculating a dot product is orders of magnitude faster than computing divisions, square roots, and magnitudes for millions of vector pairs.

### Hardware Acceleration via Apple's Accelerate (vDSP)
To run these dot products instantly on iOS/macOS, GJournal leverages **SIMD (Single Instruction Multiple Data)** instructions through Apple's **Accelerate** framework and its **vDSP** (Digital Signal Processing) library. 

Instead of using slow, sequential CPU loops to multiply vectors coordinate-by-coordinate, vDSP dispatches operations to hardware vector registers that multiply multiple floating-point coordinates in a single CPU cycle.

* `vDSP_svesq`: Computes the sum of squared elements in an array. Used to calculate vector lengths.
* `vDSP_vsmul`: Multiplies an entire vector by a scalar. Used to scale vector coordinates during normalization.
* `vDSP_dotpr`: Computes the dot product of two vectors using dedicated hardware execution pipelines.

### Code Mapping
```swift
// DBSCANClusterer.swift: Lines 443-448
private static func cosineDistanceAccelerate(_ a: [Float], _ b: [Float]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return 2.0 }
    var dot: Float = 0
    // Extremely fast hardware-level dot product computation:
    vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count)) 
    return Double(max(0, 1.0 - dot))
}
```

---

## 6. DBSCAN Clustering Concepts & Definitions

After constructing a pairwise distance matrix of size $N \times N$, the application groups entries using **DBSCAN** (*Density-Based Spatial Clustering of Applications with Noise*).

### Why DBSCAN?
Unlike **K-Means** (the most common clustering algorithm in beginner ML textbooks), which requires the developer to hardcode the exact number of clusters $K$ in advance, DBSCAN is ideal for journaling because:
1. **Dynamic Clusters**: It does not need to know the number of clusters beforehand. It discovers how many themes exist based solely on the density of the user's entries.
2. **Noise Isolation**: It isolates anomalous entries (e.g., a one-off grocery list, a singular medical appointment) as **Noise** ($-\text{1}$), preventing them from contaminating real semantic clusters.
3. **Arbitrary Shapes**: It can discover non-spherical, complex thematic shapes that wind through the semantic space.

### Core Definitions and Mathematical Conditions
Let $D$ be the dataset of journal entries, $\epsilon$ (Epsilon) be the maximum semantic distance, and `minPoints` be the minimum neighborhood density threshold.

#### 1. $\epsilon$-Neighborhood (Epsilon Neighborhood)
The neighborhood of a point $p$, denoted as $N_{\epsilon}(p)$, is the set of all points in the dataset whose Cosine Distance to $p$ is less than or equal to $\epsilon$:
$$N_{\epsilon}(p) = \{q \in D \mid d_{\text{Cosine}}(p, q) \le \epsilon\}$$

#### 2. Core Point
A point $p$ is classified as a **Core Point** if its $\epsilon$-neighborhood contains at least the minimum density threshold of points (`minPoints`):
$$|N_{\epsilon}(p)| \ge \text{minPoints}$$

#### 3. Border Point
A point $p$ is a **Border Point** if it is not a Core Point, but it falls inside the $\epsilon$-neighborhood of some Core Point $q$:
$$|N_{\epsilon}(p)| < \text{minPoints} \quad \text{and} \quad \exists q \in D \text{ such that } |N_{\epsilon}(q)| \ge \text{minPoints} \text{ and } p \in N_{\epsilon}(q)$$

#### 4. Noise Point
A point $p$ is a **Noise Point** (labeled as $-1$) if it is neither a Core Point nor a Border Point:
$$|N_{\epsilon}(p)| < \text{minPoints} \quad \text{and} \quad \forall q \in D \text{ where } |N_{\epsilon}(q)| \ge \text{minPoints}, \ p \notin N_{\epsilon}(q)$$

```
        (Core Point) ────────┐
          │  ●               │
          │ / \              ▼
          │●   ● ───► (Border Point)
          │ \ /
          └─●                ● (Noise Point - isolated)
```

#### 5. Directly Density-Reachable
A point $p$ is *directly density-reachable* from a point $q$ if $p$ is within the $\epsilon$-neighborhood of $q$ and $q$ is a Core Point:
$$p \in N_{\epsilon}(q) \quad \text{and} \quad |N_{\epsilon}(q)| \ge \text{minPoints}$$

#### 6. Density-Reachable
A point $p$ is *density-reachable* from $q$ if there is a chain of intermediate points $p_1, p_2, \dots, p_n$ (where $p_1 = q$ and $p_n = p$) such that each $p_{i+1}$ is directly density-reachable from $p_i$.

#### 7. Density-Connected
Two points $p$ and $q$ are *density-connected* if there exists a common anchor point $o \in D$ such that both $p$ and $q$ are density-reachable from $o$. A DBSCAN cluster is formally defined as a maximal set of density-connected points.

### The Chain-Linking Effect
Because points are clustered transitively via density-connectivity, DBSCAN can link long, winding structures. However, this introduces a major risk in high dimensions: if the radius $\epsilon$ is too large, or if the `minPoints` density requirement is too small, a single "bridge" entry (e.g., an entry talking about both work and family) can connect two completely different themes together. 

This causes the entire dataset to collapse into **one giant, meaningless cluster** (a common failure mode in uncalibrated systems).

### Code Mapping
The core expansion logic is implemented in `DBSCANClusterer.swift`:
```swift
// DBSCANClusterer.swift: Lines 78-119 (DBSCAN main loop)
for i in 0..<n {
    guard !visited[i] else { continue }
    visited[i] = true

    let neighbors = regionQuery(index: i, distances: distances) // Get N_ε(i)
    if neighbors.count < minPoints {
        continue // Mark as Noise (-1)
    }

    labels[i] = currentCluster // Start a new cluster
    var seedSet = neighbors
    var seedMembership = Set(neighbors)
    var j = 0
    while j < seedSet.count { // Transitively expand density-reachable points
        let q = seedSet[j]
        if !visited[q] {
            visited[q] = true
            let qNeighbors = regionQuery(index: q, distances: distances)
            if qNeighbors.count >= minPoints { // If q is also a Core Point
                for neighbor in qNeighbors {
                    if seedMembership.insert(neighbor).inserted {
                        seedSet.append(neighbor) // Expand queue
                    }
                }
            }
        }
        if labels[q] == -1 { labels[q] = currentCluster }
        j += 1
    }
    currentCluster += 1
}
```

---

## 7. Adaptive Calibration & Silhouette Grid Search

A major issue in practical ML applications is that a static $\epsilon$ is highly fragile. 
* A static $\epsilon = 0.3$ might work perfectly for $40$ journal entries, but as the user logs $500$ entries, the density of the vector space increases, causing all clusters to chain-link together into a single cluster.
* Furthermore, Nomic's truncated $256$-dimensional MRL distance manifold is much more tightly compressed than MiniLM's $384$-dimensional manifold.

To solve this, GJournal implements an automated **Adaptive Calibration Pipeline**.

### 1. Dynamic Density: Adaptive minPoints
Instead of keeping `minPoints` static, the app automatically scales the density threshold as a logarithmic function of the total number of journal entries $N$, preventing cluster chain-linking in dense datasets:
$$\text{minPoints} = \max\left(3, \min\left(\lceil 1.5 \ln(N) \rceil, \max\left(3, \frac{N}{5}\right)\right)\right)$$
* At $N = 10$, `minPoints` $= 4$.
* At $N = 40$, `minPoints` $= 6$.
* At $N = 200$, `minPoints` $= 8$.
* *Code Location*: `DBSCANClusterer.swift: Lines 134-137 (adaptiveMinPoints)`

### 2. Initial Estimate: The Kneedle Algorithm
Before running a grid search, the app must estimate a reasonable starting range for $\epsilon$. It uses the **Kneedle Algorithm** to locate the point of maximum curvature (the "elbow") on a sorted $k$-distance graph:
1. For each point, calculate its distance to its $k$-th nearest neighbor (where $k = \text{minPoints}$).
2. Sort these distances in ascending order.
3. Normalize both the indices ($X$-axis) and the distances ($Y$-axis) to the range $[0.0, 1.0]$.
4. The "elbow" represents the boundary where points transition from dense local clusters (flat area) to sparse noise points (steep climb). This is found by finding the index $i$ that maximizes:
   $$D(i) = Y_{\text{norm}}(i) - X_{\text{norm}}(i)$$
* *Code Location*: `DBSCANClusterer.swift: Lines 162-179 (kneedleEpsilon)`

### 3. Structural Evaluation: The Silhouette Coefficient
To choose the absolute best clustering configuration, we need a mathematical metric to evaluate how "good" a clustering result is. GJournal implements the **Silhouette Coefficient**.

For each classified non-noise point $i$:
1. **Intra-cluster Cohesion ($a_i$)**: The average distance from point $i$ to all other points in the same cluster $C$:
   $$a_i = \frac{1}{|C| - 1} \sum_{j \in C, j \neq i} d_{\text{Cosine}}(i, j)$$
2. **Inter-cluster Separation ($b_i$)**: The average distance from point $i$ to all points in the nearest neighboring cluster $G$ (of which $i$ is not a member):
   $$b_i = \min_{G \neq C} \left( \frac{1}{|G|} \sum_{k \in G} d_{\text{Cosine}}(i, k) \right)$$
3. **Silhouette Score ($s_i$)**: Measures how well aligned a point is to its own cluster versus neighboring clusters, ranging from $-1.0$ (poorly clustered) to $+1.0$ (perfectly separated):
   $$s_i = \frac{b_i - a_i}{\max(a_i, b_i)}$$

The overall **Silhouette Score** of the dataset is the average of $s_i$ across all non-noise points.
* *Code Location*: `DBSCANClusterer.swift: Lines 373-401 (silhouetteScoreFromMatrix)`

### 4. Multi-Objective Calibration Score
Using a pure Silhouette Score can sometimes lead to poor clustering configurations in real-world scenarios: the algorithm might maximize the score by marking $95\%$ of the entries as "Noise" to keep the remaining $5\%$ in two highly distinct, isolated clusters.

To prevent this, GJournal's grid search optimizes a **Weighted Multi-Objective Score** that balances structure, user coverage, and thematic diversity:
$$\text{Calibration Score} = 0.45 \cdot S + 0.35 \cdot (1.0 - \text{NoiseFraction}) + 0.20 \cdot \min\left(\frac{C}{5.0}, 1.0\right)$$
Where:
* **$S$ (45% Weight)**: The overall Silhouette Score, ensuring clean thematic boundaries.
* **$1.0 - \text{NoiseFraction}$ (35% Weight)**: The coverage fraction, heavily penalizing configurations that orphan too many journal entries as noise.
* **$\min(C/5.0, 1.0)$ (20% Weight)**: A diversity bonus that rewards finding multiple themes, capping its maximum bonus at $5$ clusters.

*Code Location*: `DBSCANClusterer.swift: Lines 257-260 (calibrateEpsilon)`

---

## 8. POS Tagging & TF-IDF Thematic Cluster Naming

Once DBSCAN separates your journal entries into distinct clusters, the application must name them. Simply naming them "Cluster 1" or "Cluster 2" is not helpful for user introspection. GJournal uses **Natural Language Processing (NLP)** and **TF-IDF (Term Frequency-Inverse Document Frequency)** to generate names like *"Gym & Training"* or *"Career & Interview"*.

### 1. POS Tagging with Apple's NLTagger
First, the app extracts the combined textual content (Title + Feel fields) of all entries belonging to a specific cluster. To generate a high-quality name, we must discard meaningless connector words (e.g., *"and"*, *"the"*, *"with"*) and keep only content-rich words.

The app uses Apple's **Natural Language** framework and **`NLTagger`** to perform **Part-of-Speech (POS) Tagging**:
* It parses the text and identifies the linguistic class of every word.
* It filters the words, retaining only **Nouns**, **Verbs**, and **Adjectives**.
* It runs the words through a custom **Stop-Word Filter** containing over 70 journal-specific filler words (such as *"felt"*, *"think"*, *"today"*, *"just"*, *"really"*) to strip out vocabulary that does not convey thematic meaning.

*Code Location*: `ClusterNamer.swift: Lines 83-109 (extractWords)`

### 2. TF-IDF Formulation
How do we find words that represent the *unique* identity of a cluster? 
If we just count the most frequent words in Cluster 1, we might get *"day"*, *"work"*, and *"happy"*. But those words are likely highly frequent across *all* clusters, making them useless for distinguishing what makes Cluster 1 unique.

We solve this using **TF-IDF** (Term Frequency-Inverse Document Frequency).

#### A. Term Frequency (TF)
Measures how frequently a term $t$ appears in the specific cluster $C$. If a cluster is filled with entries about a dog, "dog" will have a high TF score inside that cluster:
$$\text{TF}(t, C) = \frac{\text{Count of term } t \text{ in cluster } C}{\text{Total number of extracted words in cluster } C}$$

#### B. Inverse Document Frequency (IDF)
Measures how common or rare a term $t$ is across the *entire* journal corpus (all journal entries, $D$). If "dog" only appears in Cluster 1, it will have a very high IDF score. If the word "work" appears in every single journal entry across the entire database, its IDF score will be close to $1.0$ (crushing its final score):
$$\text{IDF}(t, D) = \ln\left( \frac{N_{\text{total}} + 1}{\text{DF}(t) + 1} \right) + 1$$
Where:
* $N_{\text{total}}$ is the total number of journal entries in the database.
* $\text{DF}(t)$ is the **Document Frequency**: the number of journal entries in the entire database that contain the term $t$.

#### C. TF-IDF Score
The final weight is the product of these two terms. A term receives a high score only if it is highly frequent within this cluster *and* relatively rare across the rest of your journal history:
$$\text{TF-IDF}(t, C, D) = \text{TF}(t, C) \times \text{IDF}(t, D)$$

### 3. Evocative Grouping
The app calculates the TF-IDF scores for all extracted words in a cluster, sorts them in descending order, selects the **top 2 highest-scoring words**, capitalizes them, and joins them using an ampersand (e.g., *"Interview & Anxiety"* or *"Beach & Relax"*).

* *Code Location*: `ClusterNamer.swift: Lines 115-150 (tfidfTopWords)`

---

## Technical Summary of the Thesis Pipeline Comparison

For your Bachelor's thesis, the two methodologies comparison is structured as follows:

1. **Classic Pipeline**:
   * **Embedding**: Microsoft’s `all-MiniLM-L6-v2` generating 384-dimensional vectors.
   * **Distance**: Cosine distance pre-normalized via Accelerate.
   * **Clustering**: Standard DBSCAN using the `calibrateEpsilon` pipeline. Epsilon is calibrated using a standard $k$-distance plot on the 384-dimensional vector space.

2. **Modern/Adapted Pipeline**:
   * **Embedding**: Nomic's `nomic-embed-text-v1.5` generating 768-dimensional vectors with task prefix `"clustering: "`.
   * **MRL Compression**: Sliced down to a compressed 256-dimensional vector space, then L2-renormalized.
   * **Clustering**: MRL-Adapted DBSCAN using the `calibrateEpsilonMRL` pipeline.
   * **MRL Multi-Grid Tuning**: Because the MRL truncation compresses the cosine distances into a narrow, compact band, a single Kneedle search is highly unstable. The calibration pipeline actively sweeps through multiple values of `minPoints` (from $\text{baseMinPoints} - 2$ up to $\text{baseMinPoints} + 2$) and $\epsilon$ to locate the absolute mathematical sweet spot that maximizes the multi-objective calibration score.
