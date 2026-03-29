# Challenge Submission: CVAT Audio & Azure Deployment

This document consolidates the implementation details, architectural decisions, and challenges encountered during the CVAT Audio Integration and Azure Deployment challenge.

---

## Part A: CVAT Audio Implementation

### 1. Codebase Exploration
To implement native audio, I explored three major layers of the CVAT architecture:
- **Backend Media Processing**: Investigated `cvat/apps/engine/media_extractors.py` to understand how CVAT handles video frame extraction and where the audio track is lost during processing.
- **REST API Layer**: Explored `cvat/apps/engine/views.py` to identify the correct patterns for serving task-specific binary data while maintaining IAM security.
- **Frontend Player Hierarchy**: Audited `cvat-ui/src/components/annotation-page/top-bar/` to integrate a new `AudioPlayer` component into the existing Redux-controlled video synchronization loop.

### 2. Implementation Achievement
I achieved integrated audio-video playback by implementing a **Browser-Native Hybrid Model**. Instead of relying on the HTML5 `<video>` element's internal track (which CVAT bypasses by using a frame-by-frame canvas renderer), I implemented a parallel **HTML5 `<audio>` stream**.

Key technical decisions included:
- **PyAV Demuxing**: Used `container.demux()` on the backend to efficiently stream the audio track into an AAC-encoded MP4 container without overloading server memory.
- **Blob Object URLs**: To bypass complex HTTP Range-request (206) issues in production proxies, the frontend fetches the entire audio file as a `Blob` and creates a local `Object URL` for instant, high-precision seeking.
- **Event-Driven "Scrub-Commit"**: To keep the UI fluid, the audio only performs a high-precision seek when the user *releases* the timeline slider (`onAfterChange`). During active playback, a "play-resume snapping" logic corrects the accumulation of drift caused by CVAT's chunked video loader.

### 3. Challenges & Overcoming Them
- **Drift during Buffer Stalls**: CVAT's video loader often stalls `frameNumber` while the `playing` state remains true. I solved this by implementing a **Sync-on-Resume** logic that snaps the `audio.currentTime` to the precise frame timestamp every time playback transitions from paused to playing.
- **Production Uploads (TUS)**: In the Azure production environment, the TUS protocol (used for large file uploads) failed due to missing CSRF integrity. I patched the `cvat-core/src/axios-tus.ts` client to explicitly pass `withCredentials` and the Django `X-CSRFTOKEN` header.

---

## Part B: Azure Deployment

### Deployment Approach
For this challenge, I utilized an **Azure Virtual Machine (Ubuntu 24.04)** orchestrated with **Docker Compose** and a **Traefik single-ingress gateway**. This "Single-VM-Host" approach was selected for its high reproducibility in a student/demo environment while providing production-grade features like automated dependency management, health checks, and persistent storage volumes for the PostgreSQL database and annotation data.

### Special Considerations
A primary consideration was **Network Security & Same-Origin Access**. By routing all UI and API traffic through Traefik on port 80, I eliminated CORS/CSRF complexity. Additionally, I implemented **Auto-IP Detection** in the `setup.sh` script to dynamically configure Django's `ALLOWED_HOSTS`. This resolved a critical issue where the internal **Open Policy Agent (OPA)** engine failed to communicate with the backend via the internal Docker network.

---

### Links & Credentials
- **Public URL**: [http://172.169.250.108](http://172.169.250.108)
- **Admin Username**: `admin`
- **Admin Password**: `cvatayush26`
- **GitHub Repository**: [https://github.com/ayushdeo/everyday-respect/tree/develop](https://github.com/ayushdeo/everyday-respect/tree/develop)
