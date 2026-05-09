#!/usr/bin/env bash
# =============================================================================
# Deploy the DDoS-Protected Multi-Pod Application to Kubernetes (Minikube)
# =============================================================================

set -euo pipefail

BOLD="\033[1m"
GREEN="\033[32m"
CYAN="\033[36m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${BOLD}${CYAN}=================================================${RESET}"
echo -e "${BOLD}${CYAN}  DDoS-Protected K8s App - Deployment Script     ${RESET}"
echo -e "${BOLD}${CYAN}=================================================${RESET}"
echo ""

# -------------------------------------------------------------------------
# Step 1: Check prerequisites
# -------------------------------------------------------------------------
echo -e "${BOLD}[1/5] Checking prerequisites...${RESET}"

for cmd in docker minikube kubectl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${RED}ERROR: '$cmd' is not installed. Please install it first.${RESET}"
        exit 1
    fi
done
echo -e "${GREEN}  docker, minikube, kubectl are available.${RESET}"

if ! minikube status | grep -q "Running" 2>/dev/null; then
    echo -e "${YELLOW}  Minikube is not running. Starting it...${RESET}"
    minikube start
fi
echo -e "${GREEN}  Minikube is running.${RESET}"
echo ""

# -------------------------------------------------------------------------
# Step 2: Point Docker to Minikube's Docker daemon
# -------------------------------------------------------------------------
echo -e "${BOLD}[2/5] Configuring Docker to use Minikube's daemon...${RESET}"
eval $(minikube docker-env)
echo -e "${GREEN}  Docker is now using Minikube's daemon.${RESET}"
echo ""

# -------------------------------------------------------------------------
# Step 3: Build Docker images (gateway + frontend + backend)
# -------------------------------------------------------------------------
echo -e "${BOLD}[3/5] Building Docker images...${RESET}"

echo "  Building gateway image (DDoS-hardened Nginx)..."
docker build -t multi-pod-gateway:latest "$SCRIPT_DIR/gateway"
echo -e "${GREEN}  Gateway image built.${RESET}"

echo "  Building backend image (Flask API)..."
docker build -t multi-pod-backend:latest "$SCRIPT_DIR/backend"
echo -e "${GREEN}  Backend image built.${RESET}"

echo "  Building frontend image (React)..."
docker build -t multi-pod-frontend:latest "$SCRIPT_DIR/frontend"
echo -e "${GREEN}  Frontend image built.${RESET}"
echo ""

# -------------------------------------------------------------------------
# Step 4: Apply Kubernetes manifests
# -------------------------------------------------------------------------
echo -e "${BOLD}[4/5] Applying Kubernetes manifests...${RESET}"

kubectl apply -f "$SCRIPT_DIR/k8s/namespace.yaml"
kubectl apply -f "$SCRIPT_DIR/k8s/backend-deployment.yaml"
kubectl apply -f "$SCRIPT_DIR/k8s/backend-service.yaml"
kubectl apply -f "$SCRIPT_DIR/k8s/frontend-deployment.yaml"
kubectl apply -f "$SCRIPT_DIR/k8s/frontend-service.yaml"
kubectl apply -f "$SCRIPT_DIR/k8s/gateway-deployment.yaml"
kubectl apply -f "$SCRIPT_DIR/k8s/gateway-service.yaml"

kubectl -n multi-pod-app rollout restart deployment/backend
kubectl -n multi-pod-app rollout restart deployment/frontend
kubectl -n multi-pod-app rollout restart deployment/gateway

echo -e "${GREEN}  All manifests applied.${RESET}"
echo ""

# -------------------------------------------------------------------------
# Step 5: Wait for pods and display status
# -------------------------------------------------------------------------
echo -e "${BOLD}[5/5] Waiting for pods to be ready...${RESET}"

kubectl -n multi-pod-app rollout status deployment/backend --timeout=120s
kubectl -n multi-pod-app rollout status deployment/frontend --timeout=120s
kubectl -n multi-pod-app rollout status deployment/gateway --timeout=120s

echo ""
echo -e "${BOLD}${CYAN}=================================================${RESET}"
echo -e "${BOLD}${CYAN}  Deployment Complete!                            ${RESET}"
echo -e "${BOLD}${CYAN}=================================================${RESET}"
echo ""

echo -e "${BOLD}Pod Status:${RESET}"
kubectl -n multi-pod-app get pods -o wide
echo ""

echo -e "${BOLD}Services:${RESET}"
kubectl -n multi-pod-app get services
echo ""

MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "")
NODE_PORT=$(kubectl -n multi-pod-app get service gateway-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
if [ -n "$MINIKUBE_IP" ] && [ -n "$NODE_PORT" ]; then
    GATEWAY_URL="http://$MINIKUBE_IP:$NODE_PORT"
    echo -e "${BOLD}${GREEN}Access the application at: $GATEWAY_URL${RESET}"
    echo ""
    echo "Run the DDoS simulation test:"
    echo "  ./simulate_ddos.sh $GATEWAY_URL"
else
    echo -e "${BOLD}To access the application, run:${RESET}"
    echo "  minikube service gateway-service -n multi-pod-app"
fi
