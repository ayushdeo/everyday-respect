# Part B: Automated Azure Deployment

This document explains the automated deployment of CVAT to an Azure Virtual Machine, optimized for reproducibility and ease of use in a challenge environment.

## 1. Infrastructure Overview

The deployment target is a single **Azure Virtual Machine** running **Ubuntu 24.04 LTS**.

### VM Specifications
- **SKU**: `Standard_D2s_v3` (2 vCPUs, 8 GiB RAM).
- **Resource Group**: `cvat-demo-rg`
- **Region**: `Central US` (selected for SKU availability within student subscriptions).
- **Access**: SSH (port 22) and HTTP (port 80).

---

## 2. Automated Setup Strategy (`setup.sh`)

Instead of manual configuration, we created a single, idempotent **`setup.sh`** script that handles the entire server lifecycle.

### Key Automation Features:
1.  **Dependency Management**: Installs **Docker 29.3.1**, **Docker Compose**, and **Node.js 20**.
2.  **Repo Setup**: Clones the `everyday-respect` fork and checks out the `develop` branch.
3.  **Environment Generation**:
    *   Generates a unique `DJANGO_SECRET_KEY`.
    *   **Auto-IP Detection**: Detects the VM's public IP and injects it into `CVAT_HOST`.
    *   **Security Configuration**: Injects `ALLOWED_HOSTS` to permit internal communication between **OPA (Open Policy Agent)** and **cvat-server**.
4.  **Production Overrides**: Merges `docker-compose.yml` with `deployment/azure/docker-compose.azure.yml` to:
    *   Expose **Traefik** on port 80.
    *   Disable development-only debug features.
    *   Configure CSRF trusted origins for the public VM IP.

---

## 3. Network Architecture (Traefik Ingress)

To simplify the user experience and avoid CORS issues, we utilized **Traefik** as a single-ingress gateway.

- **Unified Origin**: Both the React UI and the Django REST API are served on port 80.
- **Routing Logic**:
    *   Requests to `/` → routed to the `cvat_ui` container.
    *   Requests to `/api/*` → routed to the `cvat_server` container.
- **Benefit**: This architecture ensures the audio player can fetch data and upload files (TUS) without complex cross-origin proxy configurations needed in dev environments.

---

## 4. Scaling and Maintenance

The deployment is designed for **continuous updates**:
- **Updates**: A simple `git pull` followed by `docker compose up -d` is sufficient to roll out new features.
- **Persistence**: All database data (PostgreSQL) and media files are stored in Docker volumes (`cvat_db` and `cvat_data`), ensuring they survive VM restarts or container recreations.
