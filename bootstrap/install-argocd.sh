#!/usr/bin/env bash
# One-time Argo CD install. This is the ONLY component installed via raw
# kubectl apply in this whole project — everything after this point is
# managed by Argo CD watching this Git repo.

set -euo pipefail

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for Argo CD server to be ready..."
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

echo ""
echo "Argo CD installed. To reach the UI:"
echo "  kubectl -n argocd port-forward svc/argocd-server 8080:443"
echo "  open https://localhost:8080  (user: admin)"
echo ""
echo "Get the initial admin password with:"
echo '  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d'
echo ""
echo "Next: kubectl apply -f bootstrap/root-app.yaml"
