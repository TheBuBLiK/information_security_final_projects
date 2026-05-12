# DDoS-Protected Multi-Pod Application on Kubernetes

A Kubernetes-deployed multi-pod application (React frontend + Flask backend) protected by a DDoS-hardened Nginx ingress gateway. This project combines **DDoS attack mitigation** with **Kubernetes container orchestration** into a single, unified architecture.

## Architecture

```
                    ┌──────────────────────────────────────────────┐
                    │            Kubernetes Cluster                 │
                    │                                              │
                    │  ┌────────────────────────────────────────┐  │
 Browser ──────────►│  │  Gateway (Nginx - DDoS Protected)      │  │
                    │  │  ├── gateway pod 1                     │  │
                    │  │  └── gateway pod 2                     │  │
                    │  │       │              │                  │  │
                    │  │  /api/* proxy   /* proxy               │  │
                    │  │       │              │                  │  │
                    │  │       ▼              ▼                  │  │
                    │  │  ┌─────────┐   ┌──────────┐            │  │
                    │  │  │ Backend │   │ Frontend │            │  │
                    │  │  │ (Flask) │   │ (React)  │            │  │
                    │  │  │ pod 1,2 │   │ pod 1,2  │            │  │
                    │  │  └─────────┘   └──────────┘            │  │
                    │  └────────────────────────────────────────┘  │
                    └──────────────────────────────────────────────┘
```

**All traffic enters through the DDoS-hardened Nginx gateway**, which then routes to internal services:
- `/api/*` → Backend Service (Flask REST API)
- `/*` → Frontend Service (React SPA)

## Components

| Component | Technology | Replicas | Service Type | Role |
|---|---|---|---|---|
| **Gateway** | Nginx (hardened) | 2 | NodePort (30080) | DDoS protection + reverse proxy |
| **Frontend** | React + Nginx | 2 | ClusterIP (internal) | User interface |
| **Backend** | Python Flask | 2 | ClusterIP (internal) | REST API |

## DDoS Protection (Gateway)

The Nginx gateway implements multiple layers of protection:

| Protection | Directive | Effect |
|---|---|---|
| **Rate Limiting** | `limit_req_zone` — 10r/s per IP | Excess requests get HTTP 429 |
| **Connection Limiting** | `limit_conn_zone` — 10 per IP | Excess connections get HTTP 429 |
| **Timeout Hardening** | `client_*_timeout 10s` | Prevents Slowloris attacks |
| **Buffer Limits** | `client_body_buffer_size 1k` | Rejects oversized payloads |
| **Bot Filtering** | `map $http_user_agent` | Blocks empty UAs, sqlmap, nikto, etc. |
| **Method Restriction** | `if ($request_method ...)` | Only GET, HEAD, POST allowed |
| **Version Hiding** | `server_tokens off` | Hides Nginx version |
| **Security Headers** | `add_header` | X-Frame-Options, XSS-Protection, etc. |

## Kubernetes Features Demonstrated

- **Namespace isolation** — All resources in `multi-pod-app` namespace
- **Multi-pod Deployments** — 3 Deployments with 2 replicas each (6 pods total)
- **Service types** — NodePort (gateway, external) + ClusterIP (frontend/backend, internal)
- **Service discovery** — Gateway reaches backend/frontend via Kubernetes DNS
- **Load balancing** — Requests distributed across pod replicas
- **Health checks** — Readiness and liveness probes on all deployments
- **Resource limits** — CPU and memory requests/limits on all containers

## Prerequisites

- Docker
- Minikube
- kubectl

## Quick Start

```bash
# Deploy everything (builds images + applies K8s manifests)
./deploy.sh

# Open the application in your browser
minikube service gateway-service -n multi-pod-app

# Run the DDoS simulation test suite against the gateway
./simulate_ddos.sh

# View all pods
kubectl -n multi-pod-app get pods -o wide

# View logs
kubectl -n multi-pod-app logs -l app=gateway
kubectl -n multi-pod-app logs -l app=backend
kubectl -n multi-pod-app logs -l app=frontend

# Tear down everything
./teardown.sh
```

## DDoS Simulation Tests

The `simulate_ddos.sh` script runs **8 automated tests** against the gateway:

| # | Test | What it proves |
|---|---|---|
| 1 | Normal requests | Frontend and backend are reachable through the gateway |
| 2 | 50 rapid-fire requests | Rate limiting returns HTTP 429 for excess traffic |
| 3 | 30 concurrent connections | Connection limiting rejects excess connections |
| 4 | Malicious user-agents | Bot filter blocks sqlmap, nikto, empty UAs |
| 5 | Blocked HTTP methods | DELETE, PUT, PATCH, OPTIONS are rejected |
| 6 | 8KB oversized header | Buffer limits reject oversized payloads |
| 7 | Server version check | `server_tokens off` hides version info |
| 8 | Backend load balancing | Requests are distributed across backend pods |

## Demonstrating Kubernetes Scaling & Self-Healing

```bash
# Scale backend to 4 replicas
kubectl -n multi-pod-app scale deployment/backend --replicas=4
kubectl -n multi-pod-app get pods -l app=backend

# Delete a pod — K8s recreates it automatically
kubectl -n multi-pod-app delete pod -l app=backend --wait=false
kubectl -n multi-pod-app get pods -w

# View gateway access logs (shows rate limiting in action)
kubectl -n multi-pod-app logs -l app=gateway --tail=50
```

## Project Structure

```
├── gateway/                    # DDoS-hardened Nginx ingress gateway
│   ├── Dockerfile
│   └── nginx.conf              # Rate limiting, bot filtering, timeouts, etc.
├── frontend/                   # React frontend
│   ├── Dockerfile
│   ├── nginx.conf
│   └── index.html
├── backend/                    # Flask REST API
│   ├── Dockerfile
│   ├── app.py
│   └── requirements.txt
├── k8s/                        # Kubernetes manifests
│   ├── namespace.yaml
│   ├── gateway-deployment.yaml
│   ├── gateway-service.yaml    # NodePort — single entry point
│   ├── frontend-deployment.yaml
│   ├── frontend-service.yaml   # ClusterIP — internal only
│   ├── backend-deployment.yaml
│   └── backend-service.yaml    # ClusterIP — internal only
├── deploy.sh                   # One-command deployment
├── teardown.sh                 # Clean up all resources
└── simulate_ddos.sh            # DDoS attack simulation tests
```

### Certificate

```
- amantai_akunov_certificate.jpg - course cerificate
```

### Demo Video demonstration

https://youtu.be/fq2WIvlC0vc

