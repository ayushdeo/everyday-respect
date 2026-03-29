# Part A: Native Audio Implementation in CVAT

This document details the technical implementation of browser-native audio playback within CVAT, focusing on synchronization, memory efficiency, and production-ready uploading.

## 1. Backend: Efficient Audio Extraction

The core challenge was extracting audio from uploaded videos in a format that supports high-precision seeking without crashing the server on large files.

### 2. Media Extraction (`media_extractors.py`)
- **Memory Optimization**: Switched from `container.decode()` to `container.demux()` in the `extract_audio` utility. This prevents the backend from holding full raw audio frames in memory, significantly reducing the memory footprint for long videos.
- **Fast Seeking**: Configured the output MP4 container with `movflags=faststart`. This moves the metadata (MOOV atom) to the beginning of the file, allowing the browser to begin playback and seek to any position immediately without downloading the entire file first.
- **Codec**: Standardized on **AAC** for universal browser compatibility.

### 3. Audio API (`views.py`)
- Implemented `GET /api/tasks/{id}/audio` within the `TaskViewSet`.
- The endpoint serves the extracted `audio.mp4` file directly from the task's data directory on disk, ensuring privacy and authentication are handled by CVAT's existing IAM layer.

---

## 2. Frontend: Robust Synchronization

Video playback in CVAT is frame-based and chunked, which naturally leads to "drift" when a continuous audio stream is played alongside it.

### 1. Drift Correction (`audio-player.tsx`)
- **Instant Snapping**: When the user clicks "Play", the audio player immediately calculates the exact timestamp of the current frame and snaps `audio.currentTime` to it.
- **Buffer Stall Handling**: If CVAT stalls while loading a new video chunk, the audio is automatically paused and re-synchronized upon resume, preventing the audio from "running ahead" of the video.

### 2. Precise Scrubbing (`player-navigation.tsx`)
- Standard sliders fire events on every pixel of movement, which causes "choppy" audio if synced in real-time.
- Implemented **Scrub-Commit**: The audio player ignores intermediate drag events and only performs a high-precision seek when the user releases the slider (`onAfterChange`). This ensures a smooth visual experience while maintaining perfect audio alignment.

### 3. Blob Preloading
- Instead of using the Audio element's native `src`, we fetch the audio as a `Blob` and create a local Object URL. 
- **Reasoning**: This bypasses `Range: bytes` (HTTP 206) issues common in complex proxy environments (like Traefik/Django splits), ensuring the audio is fully loaded and ready for instant seeking.

---

## 3. Production Hardening: TUS Protocol

Deploying to Azure revealed that the default TUS client in CVAT lacked the necessary credentials for production environments.

### The Fix (`cvat-core/src/axios-tus.ts`)
- Patched the TUS `AxiosHttpRequest` class to include:
    - `withCredentials: true`: Ensures session cookies are passed to the TUS server.
    - `X-CSRFTOKEN`: Injected the Django CSRF token into the TUS upload headers.
- **Result**: Large file uploads now work seamlessly in the Azure production environment behind the Traefik ingress.
