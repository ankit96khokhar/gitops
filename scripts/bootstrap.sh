#!/bin/bash
set -e

echo "🚀 Rebuilding entire Minikube stack..."

# -------------------------------
# Namespaces
# -------------------------------
namespaces=(
  argo-rollouts
  argocd
  istio-ingress
  istio-system
  kubernetes-dashboard
  nginx-prod
  prod-app
  monitoring
  observability
)

for ns in "${namespaces[@]}"; do
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
done

# -------------------------------
# Helm repos
# -------------------------------
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm repo add kiali https://kiali.org/helm-charts
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update

# -------------------------------
# Istio
# -------------------------------
helm upgrade --install istio-base istio/base -n istio-system
helm upgrade --install istiod istio/istiod -n istio-system

# Istio Ingress Gateway
helm upgrade --install istio-ingress istio/gateway -n istio-ingress

# -------------------------------
# ArgoCD
# -------------------------------
helm upgrade --install argocd argo/argo-cd -n argocd

# -------------------------------
# Argo Rollouts
# -------------------------------
helm upgrade --install argo-rollouts argo/argo-rollouts -n argo-rollouts

# -------------------------------
# Prometheus
# -------------------------------
helm upgrade --install prometheus prometheus-community/prometheus -n monitoring

# -------------------------------
# Grafana
# -------------------------------
helm upgrade --install grafana grafana/grafana -n monitoring

# -------------------------------
# Jaeger
# -------------------------------
helm upgrade --install jaeger jaegertracing/jaeger -n observability

# -------------------------------
# Kiali
# -------------------------------
helm upgrade --install kiali-server kiali/kiali-server \
  -n istio-system \
  --set auth.strategy="anonymous"

# -------------------------------
# Kubernetes Dashboard
# -------------------------------
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  -n kubernetes-dashboard

echo "✅ Full stack restored!"

