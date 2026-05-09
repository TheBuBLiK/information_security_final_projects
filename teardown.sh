#!/usr/bin/env bash
# Remove all resources created by deploy.sh

set -euo pipefail

echo "Deleting multi-pod-app namespace and all resources..."
kubectl delete namespace multi-pod-app --ignore-not-found
echo "Done. All resources removed."
