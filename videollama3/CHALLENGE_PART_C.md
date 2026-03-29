# Part C: Long-Form Video Embedding with VideoLLaMA3

This document provides a high-level overview of the VideoLLaMA3 architecture and details the implementation of a robust embedding extraction strategy for long-form body-worn camera videos.

## 1. Model Architecture & Inference Workflow

VideoLLaMA3 is based on the **Qwen2-VL** architecture, enhanced with several key components optimized for video understanding.

### Component Breakdown:
- **Vision Encoder**: Utilizes a high-capacity vision backbone (like InternViT or SigLIP) with **Any-Resolution** support. Frames are processed as grids of varying sizes depending on their aspect ratio, preserving fine-grained spatial features.
- **Multimodal Projector**: A set of gated MLP layers that map high-dimensional visual features into the semantic token space of the language model (Qwen2).
- **Temporal Token Compressor**: A novel feature in VideoLLaMA3 that calculates pixel differences between adjacent frames and dynamically drops redundant visual patches (where the temporal difference is below a threshold, typically 0.1). This significantly reduces the total token count.
- **Backbone**: A Qwen2-based Causal LLM that processes the interleaved sequence of visual and text tokens to generate context-aware embeddings or natural language responses.

### Inference Workflow:
1.  **Preprocessing**: Decord/FFmpeg samples a series of frames from the video.
2.  **Grid Tiling**: Each frame is tiled into patches based on its resolution.
3.  **Vision Encoding**: Each patch is encoded into a high-dimensional feature vector.
4.  **Temporal Compression**: Redundant patches are masked out using the pixel-diff criterion.
5.  **LLM Embedding**: The remaining visual tokens are concatenated with text prompts and passed through the LLM to produce hidden states.

---

## 2. Long-Video Embedding Strategy

### The Problem: Temporal Aliasing & Information Loss
Standard VLMs typically sample a fixed budget of frames (e.g., 64, 128, or 768) uniformly across the entire video. For a 10-minute video, uniform sampling into 128 frames provides only **1 frame every 4.6 seconds**. For body-worn camera footage, this misses critical high-frequency events (e.g., rapid movements, interactions).

### The Solution: Heuristic Salience Weighting
I implemented a **Sliding Window** strategy combined with an **Unsupervised Salience Weighting** mechanism to maximize temporal resolution while staying within the model's memory and context limits.

#### Design Choices:
1.  **Local-Dense Sampling**: The video is divided into 30-second windows with a 5-second overlap. Each window is sampled at 1.0 FPS, capturing far more detail than uniform sampling.
2.  **Unsupervised Salience Scoring**: 
    We use unsupervised salience weighting at inference time to reduce the influence of repetitive or low-information segments in long body-worn videos. Segment embeddings are scored by deviation from the global centroid, then normalized with softmax and pooled into a final video-level embedding. This preserves salient events better than uniform averaging while remaining label-free.
3.  **Stability**: Mean-pooling is preserved as a stable fallback baseline, while weighted pooling is exposed as a high-performance option for event-driven analysis.

#### Extraction Point:
We extract **multimodal hidden states from the LLM backbone**. Specifically, the implementation taps the model at the **post-projector representation level**, ensuring that the extracted features are already aligned with the LLM's semantic latent space before or after potential fusion with text tokens.

#### Calculation Logic:
- **Centroid**: Compute the global "average" state of the video ($\bar{e}$).
- **Distributional Outliers**: Calculate the Cosine Distance of each segment $e_i$ from $\bar{e}$. This approach assumes that semantically important events induce **distributional shifts** in the embedding space, making them separable from routine background segments. Segments with higher cosine distance from the centroid are treated as **distributional outliers** and assigned higher importance weights.
- **Normalization**: A Softmax function with a configurable temperature ($\tau = 0.1$) converts distances into a probability distribution of weights.

#### Trade-offs & Limitations:
- **Temporal Ordering Loss**: The final aggregation (mean or weighted pooling) discards temporal ordering between segments, which may limit performance for tasks requiring sequence reasoning (e.g., escalation patterns in interactions). 
- **Future Work**: Future work could incorporate **sequence-aware aggregation** (e.g., transformer-based pooling over segment embeddings) to preserve temporal dynamics while maintaining a compact global representation.
