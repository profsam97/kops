#!/bin/bash

set -e

ENVIRONMENT=${1:-staging}
IMAGE_TAG=${2:-latest}
DOCKERHUB_USERNAME=${DOCKERHUB_USERNAME:-"your-dockerhub-username"}

echo "🚀 Deploying FastAPI service to $ENVIRONMENT"
echo "📦 Using image: $DOCKERHUB_USERNAME/fastapi-service:$IMAGE_TAG"

sed -i "s|your-dockerhub-username/fastapi-service:latest|$DOCKERHUB_USERNAME/fastapi-service:$IMAGE_TAG|g" k8s/deployment.yaml

if [ "$ENVIRONMENT" = "staging" ]; then
    NAMESPACE="fastapi-staging"
    sed -i "s|fastapi-production|fastapi-staging|g" k8s/*.yaml
else
    NAMESPACE="fastapi-production"
fi

echo "🔧 Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo "📋 Applying Kubernetes manifests..."
kubectl apply -f k8s/ -n $NAMESPACE

echo "⏳ Waiting for deployment to be ready..."
kubectl rollout status deployment/fastapi-deployment -n $NAMESPACE --timeout=300s

echo "✅ Deployment completed successfully!"
echo "🔍 Checking pods:"
kubectl get pods -n $NAMESPACE

echo "🌐 Service information:"
kubectl get service fastapi-service -n $NAMESPACE

echo ""
echo "🧪 To test the deployment:"
echo "kubectl port-forward service/fastapi-service 8080:80 -n $NAMESPACE"
echo "curl http://localhost:8080/health"