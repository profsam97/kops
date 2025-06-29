#!/bin/bash

set -e

ENVIRONMENT=${1:-production}
NAMESPACE="fastapi-$ENVIRONMENT"
PORT=${2:-8080}

echo "🏥 Running health checks for $ENVIRONMENT environment"

if ! kubectl get deployment fastapi-deployment -n $NAMESPACE >/dev/null 2>&1; then
    echo "❌ Deployment not found in namespace $NAMESPACE"
    exit 1
fi

echo "📊 Checking deployment status..."
kubectl get deployment fastapi-deployment -n $NAMESPACE

# Check pod status
echo "🐳 Checking pod status..."
kubectl get pods -n $NAMESPACE -l app=fastapi-service

READY_PODS=$(kubectl get pods -n $NAMESPACE -l app=fastapi-service --field-selector=status.phase=Running --no-headers | wc -l)
if [ $READY_PODS -eq 0 ]; then
    echo "❌ No running pods found"
    exit 1
fi
echo "✅ Found $READY_PODS running pod(s)"

echo "🔌 Setting up port forward on port $PORT..."
kubectl port-forward service/fastapi-service $PORT:80 -n $NAMESPACE &
PF_PID=$!

sleep 5

# Cleanup function
cleanup() {
    echo "🧹 Cleaning up port forward..."
    kill $PF_PID >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "🧪 Testing health endpoint..."
if curl -f -s http://localhost:$PORT/health >/dev/null; then
    echo "✅ Health check passed"
else
    echo "❌ Health check failed"
    exit 1
fi

echo "🧪 Testing readiness endpoint..."
if curl -f -s http://localhost:$PORT/health/ready >/dev/null; then
    echo "✅ Readiness check passed"
else
    echo "❌ Readiness check failed"
    exit 1
fi

echo "🧪 Testing items endpoint..."
if curl -f -s http://localhost:$PORT/items >/dev/null; then
    echo "✅ Items endpoint test passed"
else
    echo "❌ Items endpoint test failed"
    exit 1
fi

echo "🧪 Testing metrics endpoint..."
if curl -f -s http://localhost:$PORT/metrics >/dev/null; then
    echo "✅ Metrics endpoint test passed"
else
    echo "❌ Metrics endpoint test failed"
    exit 1
fi

echo ""
echo "✅ All health checks passed successfully!"
echo "🚀 Service is healthy and ready to serve traffic"