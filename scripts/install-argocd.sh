#!/bin/bash

set -e  # Stop execution if there is an error

WITH_LOGIN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --WITH-LOGIN)
      WITH_LOGIN=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# Check for required tools
REQUIRED_TOOLS=("kind" "kubectl" "base64" "argocd")
MISSING_TOOLS=()

for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v $tool &> /dev/null; then
    MISSING_TOOLS+=("$tool")
  fi
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
  echo "The following required tools are missing: ${MISSING_TOOLS[*]}"
  echo "Please install them before running this script."
  exit 1
fi

echo "All required tools are installed. Proceeding with setup."

# ArgoCD version
ARGOCD_VERSION="v2.14.2"

# Version summary
echo "Using versions:"
echo "- Kind: $(kind version | head -n 1)"
echo "- Kubectl: $(kubectl version --client)"
echo "- ArgoCD CLI: $(argocd version --client --short)"
echo "- ArgoCD Server: $ARGOCD_VERSION"

# Create the Kind cluster
kind create cluster

echo "Kind cluster successfully created."

# Install ArgoCD in the cluster
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml

echo "ArgoCD version $ARGOCD_VERSION successfully installed."

while true; do
  # Get the list of running ArgoCD server pods
  PODS=$(kubectl get pods --namespace argocd -l app.kubernetes.io/name=argocd-server --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}')
  
  # If pods are found, break the loop
  if [ -n "$PODS" ]; then
    echo "ArgoCD pods are running, waiting for them to be ready..."
    kubectl wait --namespace argocd \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/name=argocd-server \
      --timeout=120s
    break
  fi

  echo "Waiting for ArgoCD pods to be running..."
  sleep 5
done

echo "ArgoCD is ready."

if [ "$WITH_LOGIN" = true ]; then
  # Perform login using ArgoCD CLI
  kubectl port-forward svc/argocd-server -n argocd 8080:80 &
  argocd login --insecure --grpc-web --username admin --password "$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)" localhost:8080
fi
