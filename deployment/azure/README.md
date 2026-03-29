# CVAT with Audio Playback — Azure Deployment Guide

## Architecture

**Azure VM (Standard_B2s) + Docker Compose**

```
Internet
    │  port 80
    ▼
┌─────────────────────────────────────┐
│  Azure VM (Ubuntu 22.04, B2s)       │
│                                     │
│  Traefik :80                        │
│   ├── /api/*  → cvat_server :8080   │
│   ├── /admin* → cvat_server :8080   │
│   └── /*      → cvat_ui :8000       │
│                                     │
│  cvat_server (Django + audio API)   │
│  cvat_worker_import (PyAV audio)    │
│  cvat_worker_export                 │
│  cvat_db (PostgreSQL)               │
│  cvat_redis_*                       │
│  cvat_opa (permissions)             │
└─────────────────────────────────────┘
```

**Why this architecture?**

| Option | Pros | Cons |
|---|---|---|
| **Azure VM + Docker Compose** ✅ | Simple, cheap (~$35/mo B2s), zero new infra concepts, identical to local dev | Manual VM management |
| Azure Container Instances | No VM management | Complex multi-container networking, TUS state issues |
| Azure Kubernetes Service | Scalable | Extreme overkill for a student demo |

In production Compose mode, Traefik serves **both the UI and backend on port 80** — the `localhost:3000` / `localhost:8081` dev split disappears entirely. This means TUS uploads, CSRF, and the audio endpoint all work on the same origin with zero extra configuration.

---

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed locally
- Azure student subscription (free credits)
- SSH key pair (generated automatically by the script)

---

## Deploy to Azure (One Command)

```powershell
# From the repo root, on Windows PowerShell:
.\deployment\azure\provision.ps1
```

This will:
1. Create a resource group `cvat-demo-rg` in `eastus`
2. Provision a `Standard_B2s` VM with Ubuntu 22.04
3. Open port 80
4. SSH in and run `setup.sh` automatically
5. Print the public URL when done

**Total time: ~10–15 minutes**

---

## Deploy Manually (SSH)

If you already have a VM running Ubuntu 22.04:

```bash
# 1. SSH into your VM
ssh azureuser@<YOUR_VM_IP>

# 2. Download and run the setup script
curl -fsSL https://raw.githubusercontent.com/ayushdeo/everyday-respect/develop/deployment/azure/setup.sh | bash
```

---

## Configuration

Edit `.env` on the VM (`/opt/cvat/.env`) before running Compose:

```bash
# Required
CVAT_HOST=<your-vm-public-ip-or-domain>    # e.g. 20.123.45.67
DJANGO_SECRET_KEY=<random-32-char-hex>     # generate with: python3 -c "import secrets; print(secrets.token_hex(32))"
```

---

## Start / Stop

```bash
cd /opt/cvat

# Start
docker compose -f docker-compose.yml -f deployment/azure/docker-compose.azure.yml --env-file .env up -d

# Stop
docker compose -f docker-compose.yml -f deployment/azure/docker-compose.azure.yml down

# View logs
docker compose logs -f cvat_server cvat_worker_import
```

---

## Demo Credentials

| Field | Value |
|---|---|
| URL | `http://<VM_PUBLIC_IP>` |
| Username | `admin` |
| Password | `cvat2024demo` |

---

## Demo End-to-End Test

After deployment, verify the full Part A + B pipeline:

1. Open `http://<VM_IP>` → log in as `admin`
2. Create a new task → upload a video with audio (e.g. an MP4)
3. Wait for processing (~30s) — audio file extracted by `cvat_worker_import`
4. Open the annotation job
5. Click ▶ Play — audio should play in sync with frames
6. Drag the timeline slider — audio should seek to the correct position on release
7. Click 🔊 mute button — audio stops

To verify audio extraction happened:
```bash
docker exec cvat_worker_import ls /home/django/data/tasks/<TASK_ID>/audio.mp4
```

---

## Part B Write-Up

### Azure Architecture Decision

For this demo deployment I chose an **Azure Virtual Machine (Standard_B2s, 2 vCPU / 4 GB RAM) running Docker Compose on Ubuntu 22.04 LTS**. This mirrors the local development environment exactly: the same `docker-compose.yml` is used, extended by a thin `docker-compose.azure.yml` override that remaps Traefik's HTTP port from `8081` to `80` and injects the VM's public IP as `CVAT_HOST`.

The key architectural benefit is **same-origin serving**: in production Compose mode, Traefik routes both the React UI and the Django REST API through a single port 80 endpoint. This eliminates the `localhost:3000` / `localhost:8081` split that existed during development, meaning the Webpack proxy rewrites, TUS credential patching, and CSRF trusted-origin hacks are **completely unnecessary in production** — the browser never makes cross-origin requests. The custom audio endpoint (`GET /api/tasks/{id}/audio`), TUS chunk uploads, and OPA-gated permissions all work identically to the local environment without modification.

The tradeoff of this approach versus managed services (Azure Container Apps or AKS) is operational simplicity over scalability: a single VM cannot horizontally scale worker pods or survive VM restarts without manual intervention. For a reproducible student demo this is an acceptable constraint. The total estimated cost is approximately $0.05/hour ($35/month) on a B2s instance — well within free Azure student credit limits — and the entire stack can be torn down with a single `az group delete` command.

---

## Clean Up

```powershell
# Delete ALL resources (VM, IP, disk, NIC) in one command:
az group delete --name cvat-demo-rg --yes --no-wait
```
