#!/bin/bash

set -e

ENVIRONMENT=${1:-staging}

echo "🔄 Rolling back $ENVIRONMENT deployment"

if [ "$ENVIRONMENT" = "production" ]; then
    NAMESPACE="fastapi-production"
else
    NAMESPACE="fastapi-staging"
fi

echo "📍 Using namespace: $NAMESPACE"

if ! kubectl get deployment fastapi-deployment -n $NAMESPACE >/dev/null 2>&1; then
    echo "❌ Deployment not found in namespace $NAMESPACE"
    exit 1
fi

# Show current revision
echo "📊 Current revision:"
kubectl rollout history deployment/fastapi-deployment -n $NAMESPACE --revision=0

# Confirm rollback
read -p "🤔 Are you sure you want to rollback? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "❌ Rollback cancelled"
    exit 0
fi

echo "⏪ Rolling back to previous revision..."
kubectl rollout undo deployment/fastapi-deployment -n $NAMESPACE

echo "⏳ Waiting for rollback to complete..."
kubectl rollout status deployment/fastapi-deployment -n $NAMESPACE --timeout=300s

echo "✅ Checking deployment status:"
kubectl get pods -n $NAMESPACE -l app=fastapi-service

echo "🏥 Testing health endpoint..."
kubectl port-forward service/fastapi-service 8080:80 -n $NAMESPACE &
PID=$!
sleep 5

if curl -f http://localhost:8080/health >/dev/null 2>&1; then
    echo "✅ Health check passed"
else
    echo "❌ Health check failed"
fi

kill $PID 2>/dev/null || true

echo "🎉 Rollback completed successfully!"
echo "📊 New deployment status:"
kubectl rollout history deployment/fastapi-deployment -n $NAMESPACE --revision=0