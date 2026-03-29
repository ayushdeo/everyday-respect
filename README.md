# CVAT Audio Challenge Submission

This repository contains a modified fork of CVAT (Computer Vision Annotation Tool) featuring **Native Browser Audio Playback** and **Automated Azure Deployment**.

## Public Deployment
- **URL**: [http://172.169.250.108](http://172.169.250.108)
- **Username**: `admin`
- **Password**: `cvatayush26`

---

## Part A: Audio Implementation
Implemented a browser-native audio extraction and playback system for synchronized video annotation.

### Key Logic:
- **Backend**: Memory-efficient extraction using `PyAV` with `demux()` based seeking and `movflags=faststart`.
- **Frontend**: Precise synchronization with drift correction and blob preloading to bypass range-request limitations.
- **Protocol**: Patched the TUS client to support production cross-origin accessibility and CSRF integrity.

[Read the Full Technical Write-Up (Part A & Part B)](CHALLENGE_WRITEUP.md)

---

## Part B: Azure Deployment
Established a robust, automated deployment pipeline for Microsoft Azure Cloud.

### Architecture:
- **Provider**: Azure Virtual Machine (Ubuntu 24.04).
- **Automation**: Idempotent `setup.sh` for dependency management and server lifecycle.
- **Ingress**: Traefik-based same-origin routing on port 80 for simplified networking.

[Read the Full Technical Write-Up (Part A & Part B)](CHALLENGE_WRITEUP.md)

---

## Part C: VideoLLaMA3 Long-Video Embeddings
Completed a deep-dive architecture audit and implemented a high-performance embedding extraction strategy for Vision-Language Models.

### Key Deliverables:
- **Architecture Audit**: Comprehensive analysis of Qwen2-VL internals, multimodal projectors, and temporal token compression logic.
- **Heuristic Salience Weighting**: An advanced embedding extraction script featuring centroid-based distance scoring to identify distributional outliers in long-form videos.
- **Note on Execution**: Due to the significant GPU VRAM and specific CUDA environment requirements of VideoLLaMA3 (e.g., Flash Attention 2), these implementation files represent **architectural enhancements and code-level suggestions**. They have been semantically verified against the model's source but not executed due to local compute limitations.

[Read the Full Technical Write-Up (Part C)](videollama3/CHALLENGE_PART_C.md)

---

## Reproducibility

### Local Execution (Docker)
To run the project locally with all modifications:
```bash
docker compose up -d
```
Access the UI at `http://localhost:8080`.

### Azure Deployment (Manual)
To deploy this fork to a clean Ubuntu VM:
1. Create a `Standard_D2s_v3` VM in Azure.
2. Ensure ports 80 and 22 are open in the Network Security Group.
3. SSH into the VM and run:
   ```bash
   curl -sSL https://raw.githubusercontent.com/ayushdeo/everyday-respect/develop/deployment/azure/setup.sh | bash -s -- <YOUR_VM_PUBLIC_IP>
   ```

---

*Note: The original CVAT project documentation has been moved to [README_CVAT.md](README_CVAT.md).*
