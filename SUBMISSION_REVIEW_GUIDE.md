# Submission Review Guide

This guide provides direct links to the implementation for Parts A, B, and C.  
The repository includes both documentation and code; this file highlights the key code paths and changes for efficient review.

---

## 🧩 Part A: CVAT Customization (Audio Playback)

### Frontend (Audio Sync + Controls)
- [audio-player.tsx](cvat-ui/src/components/annotation-page/top-bar/audio-player.tsx)  
  → Integrated audio playback with frame synchronization
- [player-navigation.tsx](cvat-ui/src/components/annotation-page/top-bar/player-navigation.tsx)  
  → Mute/unmute button and sync controls added to top control bar

### Backend (Audio Extraction & Serving)
- [media_extractors.py](cvat/apps/engine/media_extractors.py)  
  → Audio extraction from uploaded video using PyAV
- [base.py](cvat/settings/base.py)  
  → Configuration updates for audio handling

### Key Idea
Audio is extracted server-side and synchronized with frame playback in the React player without introducing a separate UI component.

---

## ☁️ Part B: Azure Deployment

### Deployment Scripts
- [setup.sh](deployment/azure/setup.sh)  
  → Idempotent VM setup (Docker + CVAT)
- [provision.ps1](deployment/azure/provision.ps1)  
  → Azure CLI provisioning script

### Infrastructure Notes
- Uses Azure VM (Ubuntu 24.04)
- Traefik reverse proxy exposed on port 80

### Key Idea
Minimal, reproducible deployment using a single VM and Docker Compose for simplicity and cost control.

---

## 🤖 Part C: VideoLLaMA3 Long-Video Embeddings

### Core Script
- [videollama3_embeddings.py](videollama3/videollama3_embeddings.py)  
  → Sliding-window embedding extraction with salience-weighted pooling

### Architecture Reference
- [modeling_videollama3.py](videollama3/modeling_videollama3.py)  
  → Vision encoder + projector + LLM pipeline

### Write-Up
- [CHALLENGE_PART_C.md](videollama3/CHALLENGE_PART_C.md)  
  → Detailed explanation of architecture and long-video strategy

### Key Idea
Long videos are processed via sliding windows with unsupervised salience weighting to preserve semantically important segments while staying within model limits.

---

## 🔍 Where to Start

If reviewing quickly:

1. **Part A** → Check frontend sync logic in `cvat-ui` and extraction in `media_extractors.py`.
2. **Part B** → Review `setup.sh` for the deployment flow.
3. **Part C** → Start with `videollama3_embeddings.py` for the core contribution.

---

## 🔗 Key Commits

- **Part A implementation:** `ca6da0a`
- **Part B deployment:** `4df64c`
- **Part C embedding pipeline:** `520b846`, `ccca664`

---
*Generated for submission review efficiency.*
