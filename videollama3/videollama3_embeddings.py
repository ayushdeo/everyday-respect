import os
import sys
import torch
import numpy as np
import cv2
from tqdm import tqdm

# Add the local videollama3 directory to sys.path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from videollama3.model import load_pretrained_model
from videollama3.mm_utils import load_video

class LongVideoEmbedder:
    def __init__(self, model_path, device="cuda"):
        print(f"Loading VideoLLaMA3 from {model_path}...")
        self.device = device
        # Load model components
        # Note: In a real environment, you'd provide a valid HF model path or local directory
        self.tokenizer, self.model, self.processor, self.context_len = load_pretrained_model(
            model_path, 
            model_base=None, 
            model_name="videollama3_qwen2",
            device_map=device
        )
        self.model.eval()

    def get_video_duration(self, video_path):
        cap = cv2.VideoCapture(video_path)
        fps = cap.get(cv2.CAP_PROP_FPS)
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        duration = frame_count / fps
        cap.release()
        return duration

    @torch.no_grad()
    def extract_window_embedding(self, video_path, start_time, end_time):
        """
        Extracts embeddings for a specific time window.
        Uses 1FPS sampling within the window (30 frames for a 30s window).
        """
        # load_video handles the sampling logic
        frames, timestamps = load_video(
            video_path,
            start_time=start_time,
            end_time=end_time,
            fps=1.0,         # Sample at 1 frame per second within the window
            max_frames=64    # Safety cap
        )
        
        # Preprocess frames into AnyRes grids
        inputs = self.processor(images=frames, return_tensors='pt')
        pixel_values = inputs['pixel_values'].to(self.device, dtype=self.model.dtype)
        grid_sizes = inputs['grid_sizes'].to(self.device)
        merge_sizes = inputs['merge_sizes'].to(self.device)

        # 1. Vision Encoder + Projector Pass
        # Following the exact pattern in videollama3_arch.py:encode_images
        vision_encoder = self.model.get_model().get_vision_encoder()
        mm_projector = self.model.get_model().mm_projector
        
        # Extract multimodal hidden states from the vision-language alignment stream
        # This tap is post-projector, ensuring features are aligned with 
        # the LLM's semantic space.
        mm_features = vision_encoder(
            pixel_values=pixel_values,
            grid_sizes=grid_sizes,
            merge_sizes=merge_sizes
        )
        # Project into LLM latent space
        mm_features = mm_projector(mm_features)
        
        # mm_features shape: [Total_Patches, Hidden_Dim]
        # We perform temporal mean pooling across all multimodal patches in this window
        window_embedding = mm_features.mean(dim=0).cpu().numpy()
        
        return window_embedding

    def get_video_embedding(self, window_embeddings, mode="mean", temperature=0.1):
        """
        Aggregates window embeddings using the specified pooling mode.
        """
        if not window_embeddings:
            return None
        
        window_embeddings = np.array(window_embeddings)
        
        if mode == "mean":
            print("Using uniform Mean Pooling (Baseline).")
            return np.mean(window_embeddings, axis=0)
            
        elif mode == "weighted":
            print(f"Using Heuristic Salience Weighting (Temperature={temperature})...")
            # 1. Compute Centroid
            centroid = np.mean(window_embeddings, axis=0)
            
            # 2. Compute Cosine Distance from Centroid for each window
            # distance = 1 - (A . B) / (||A|| * ||B||)
            dot_products = np.sum(window_embeddings * centroid, axis=1)
            norms = np.linalg.norm(window_embeddings, axis=1) * np.linalg.norm(centroid)
            similarities = dot_products / (norms + 1e-8)
            distances = 1.0 - similarities
            
            # 3. Apply Softmax to distances to get normalized weights
            # We subtract max for numerical stability
            exp_dist = np.exp((distances - np.max(distances)) / temperature)
            weights = exp_dist / np.sum(exp_dist)
            
            # Log the salience map (Top 3 distributional outliers)
            top_indices = np.argsort(weights)[-3:][::-1]
            print("\n[Salience Map] High-priority distributional outliers identified:")
            for idx in top_indices:
                time_s = idx * (30 - 5) # simplified index-to-time based on window/overlap
                print(f"  - Time: {time_s:.1f}s | Weight: {weights[idx]:.4f} (Centroid Distance: {distances[idx]:.4f})")
            
            # 4. Final Weighted Sum
            video_level_embedding = np.sum(window_embeddings * weights[:, np.newaxis], axis=0)
            return video_level_embedding
            
        else:
            raise ValueError(f"Unknown pooling mode: {mode}")

    def process_long_video(self, video_path, window_size=30, overlap=5, pooling="mean", temperature=0.1):
        """
        Processes a long video using a sliding window.
        """
        duration = self.get_video_duration(video_path)
        print(f"Processing video: {video_path} ({duration:.2f}s)")
        
        window_embeddings = []
        start = 0
        
        with tqdm(total=duration) as pbar:
            while start < duration:
                end = min(start + window_size, duration)
                print(f"\nExtracting segment: {start:.1f}s - {end:.1f}s")
                
                try:
                    embedding = self.extract_window_embedding(video_path, start, end)
                    window_embeddings.append(embedding)
                except Exception as e:
                    print(f"Error processing segment {start}-{end}: {e}")
                
                step = window_size - overlap
                start += step
                # tqdm handle
                pbar.update(step)
        
        return self.get_video_embedding(window_embeddings, mode=pooling, temperature=temperature)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Extract video-level embeddings using VideoLLaMA3")
    parser.add_argument("--video", type=str, required=True, help="Path to input video")
    parser.add_argument("--model", type=str, default="DAMO-NLP-SG/VideoLLaMA3-7B", help="Path to/ID of VideoLLaMA3 model")
    parser.add_argument("--output", type=str, default="video_embedding.npy", help="Output path for .npy embedding")
    parser.add_argument("--pooling", type=str, choices=["mean", "weighted"], default="mean", help="Aggregation strategy")
    parser.add_argument("--temperature", type=float, default=0.1, help="Softmax temperature for weighted pooling")
    
    args = parser.parse_args()
    
    # Check for GPU
    device = "cuda" if torch.cuda.is_available() else "cpu"
    
    # Initialize embedder
    embedder = LongVideoEmbedder(args.model, device=device)
    
    # Extract
    final_embedding = embedder.process_long_video(
        args.video, 
        pooling=args.pooling, 
        temperature=args.temperature
    )
    
    if final_embedding is not None:
        np.save(args.output, final_embedding)
        print(f"\nSuccess! Video-level embedding saved to {args.output}")
        print(f"Embedding Shape: {final_embedding.shape} | Pooling: {args.pooling}")
    else:
        print("\nFailed to extract embeddings.")
