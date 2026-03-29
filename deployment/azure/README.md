# CVAT with Audio Playback — Azure Deployment (Part B)

## Architecture

**Azure VM (Standard D2s_v3, Ubuntu 24.04) + Docker Compose**

```
Internet : port 80
    |
    v
Azure VM  172.166.250.100  (Central US)
    |
  Traefik :80
    |-- /api/*        --> cvat_server  :8080  (Django + audio endpoint)
    |-- /admin/*      --> cvat_server  :8080
    `-- /*            --> cvat_ui      :8000  (React, audio player built in)

  cvat_worker_import  (PyAV audio extraction)
  cvat_worker_export
  cvat_db             (PostgreSQL)
  cvat_redis_inmem
  cvat_redis_ondisk
  cvat_opa            (permissions)
```

In production Compose mode, **Traefik serves all traffic on port 80**.
There is no localhost:3000 / localhost:8081 split.
TUS uploads, CSRF, and the audio endpoint all work on the same origin.

---

## VM Details

| Field | Value |
|---|---|
| VM Name | myVm |
| Public IP | 172.166.250.100 |
| OS | Ubuntu 24.04 LTS |
| Size | Standard D2s_v3 (2 vCPU, 8 GB RAM) |
| Region | Central US |
| Resource Group | cvat-demo-rg |
| Created via | Azure Portal (manual) |

---

## How to Run Setup on the VM

### Step 1 — SSH into the VM

```bash
ssh azureuser@172.166.250.100
```

Enter the password you set when creating the VM in the Azure Portal.

### Step 2 — Run the setup script

**Option A — One-liner (no manual file copy needed):**
```bash
curl -fsSL https://raw.githubusercontent.com/ayushdeo/everyday-respect/develop/deployment/azure/setup.sh | sudo bash
```

**Option B — Manual copy:**
```bash
# On your local machine:
scp deployment/azure/setup.sh azureuser@172.166.250.100:~/setup.sh

# On the VM:
sudo bash ~/setup.sh
```

The script takes **10-15 minutes** and does everything automatically:
- Installs Docker, Docker Compose, Node.js 20, ffmpeg
- Clones the repo (`develop` branch)
- Detects the VM public IP and writes `.env`
- Builds `cvat/server:dev` and `cvat/ui:dev` images
- Starts all CVAT services via Docker Compose
- Creates the admin superuser

### Step 3 — Verify CVAT is running

```bash
# On the VM:
cd /opt/cvat
docker compose ps
```

All services should show `running`. Then open in your browser:
```
http://172.166.250.100
```

---

## Demo Credentials

| Field | Value |
|---|---|
| URL | http://172.166.250.100 |
| Username | admin |
| Password | cvat2024demo |

---

## End-to-End Audio Feature Test

1. Log in as `admin`
2. Create a new task → upload any MP4 with audio
3. Wait ~30 seconds for processing (audio extraction runs in `cvat_worker_import`)
4. Open the annotation job
5. Press **Play** — audio plays in sync with frames
6. Drag the timeline slider — audio seeks to the correct position on pointer-up
7. Click the **mute icon** — audio stops

To confirm audio extraction happened:
```bash
docker exec cvat_worker_import ls /home/django/data/tasks/<TASK_ID>/audio.mp4
```

---

## Useful Commands on the VM

```bash
cd /opt/cvat

# View live logs
docker compose logs -f cvat_server cvat_worker_import

# Restart a specific service
docker compose restart cvat_worker_import

# Stop everything
docker compose -f docker-compose.yml -f deployment/azure/docker-compose.azure.yml down

# Start again
docker compose -f docker-compose.yml -f deployment/azure/docker-compose.azure.yml --env-file .env up -d

# Re-run setup after a git pull (picks up Part A changes)
sudo bash /opt/cvat/deployment/azure/setup.sh
```

---

## How to Run CVAT Locally (Development)

```bash
# Terminal 1 — Backend (Docker)
docker compose up -d

# Terminal 2 — Frontend dev server with hot reload
cd d:\Ms CS\everyday-respect\cvat
corepack yarn start:cvat-ui --env API_URL=http://localhost:8081
```

Open http://localhost:3000 for the UI (proxied to backend at :8081).

---

## Part B Write-Up

### Azure Architecture Decision

For this student demo deployment I chose an **Azure Virtual Machine (Standard D2s_v3, 2 vCPU / 8 GB RAM) running Ubuntu 24.04 with Docker Compose**, provisioned manually through the Azure Portal. The VM is in the Central US region, which is one of five regions permitted by the Azure for Students subscription policy (`centralus`, `eastus2`, `westus2`, `canadacentral`, `southcentralus`).

The deployment model mirrors the local development environment exactly: the same `docker-compose.yml` is extended by a thin `docker-compose.azure.yml` override that remaps Traefik's HTTP listener from port 8081 to port 80 and injects the VM's public IP as `CVAT_HOST`. In production Compose mode, Traefik acts as the single ingress, routing `/api/*` requests to the Django backend and all other paths to the React UI — both served on port 80 from the same origin. This eliminates the `localhost:3000` / `localhost:8081` split used during development, meaning the Webpack proxy rewrites, TUS CSRF credential patches, and CORS trusted-origin overrides configured in Part A are **not active in production** — they are development-only safety nets. The custom audio endpoint (`GET /api/tasks/{id}/audio`), TUS chunk uploads, and OPA-gated permissions all work identically to the local environment without any additional configuration.

The primary tradeoff of a single VM versus managed services (Azure Container Apps, AKS) is operational simplicity over scalability: a single VM cannot horizontally scale worker processes and requires manual intervention on instance failure. For a reproducible student demo this is the correct choice — it requires zero Kubernetes knowledge, costs approximately $0.10/hour (~$70/month) on a D2s_v3, and the entire stack can be reproduced on any Ubuntu 24.04 machine by running a single `setup.sh` script. The VM was created manually via the Azure Portal after automated provisioning via `az vm create` encountered capacity restrictions (`SkuNotAvailable`) across multiple allowed regions and sizes — a known transient limitation of Azure for Students subscriptions during peak hours.

---

## File Reference

```
deployment/azure/
  setup.sh                   <-- Run this on the VM via SSH
  docker-compose.azure.yml   <-- Compose override (port 80, CVAT_HOST, CSRF)
  .env.example               <-- Template (auto-generated by setup.sh)
  README.md                  <-- This file
  provision.ps1              <-- Automated provisioning script (optional)
```
