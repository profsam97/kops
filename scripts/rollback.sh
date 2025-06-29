#!/bin/bash

# Rollback script for FastAPI service
# Usage: ./rollback.sh [environment] [--to-revision=N] [--confirm]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEFAULT_ENVIRONMENT="staging"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [ENVIRONMENT] [OPTIONS]

ENVIRONMENT: staging, production (default: staging)

OPTIONS:
  --to-revision=N    Rollback to specific revision number
  --confirm          Skip confirmation prompt
  --list-revisions   List available revisions and exit
  --help, -h         Show this help message

Examples:
  $0                          # Rollback staging to previous revision
  $0 production               # Rollback production to previous revision
  $0 production --to-revision=3  # Rollback production to revision 3
  $0 staging --list-revisions    # List available revisions for staging
  $0 production --confirm        # Rollback production without confirmation

EOF
}

# Parse arguments
ENVIRONMENT="${1:-$DEFAULT_ENVIRONMENT}"
TO_REVISION=""
CONFIRM=false
LIST_REVISIONS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --to-revision=*)
            TO_REVISION="${1#*=}"
            shift
            ;;
        --confirm)
            CONFIRM=true
            shift
            ;;
        --list-revisions)
            LIST_REVISIONS=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        staging|production)
            ENVIRONMENT="$1"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(staging|production)$ ]]; then
    log_error "Invalid environment: $ENVIRONMENT"
    usage
    exit 1
fi

# Configuration based on environment
if [[ "$ENVIRONMENT" == "production" ]]; then
    NAMESPACE="fastapi-production"
    DEPLOYMENT="fastapi-deployment"
else
    NAMESPACE="fastapi-staging"
    DEPLOYMENT="fastapi-deployment"
fi

log_info "Rollback script for $ENVIRONMENT environment"
log_info "Namespace: $NAMESPACE"
log_info "Deployment: $DEPLOYMENT"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if deployment exists
    if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
        log_error "Deployment $DEPLOYMENT not found in namespace $NAMESPACE"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# List available revisions
list_revisions() {
    log_info "Available rollout revisions for $DEPLOYMENT in $NAMESPACE:"
    echo "============================================================"
    
    kubectl rollout history deployment/"$DEPLOYMENT" -n "$NAMESPACE"
    
    echo
    log_info "Current revision details:"
    kubectl rollout history deployment/"$DEPLOYMENT" -n "$NAMESPACE" --revision=0
}

# Get current deployment info
get_current_info() {
    log_info "Current deployment information:"
    
    local current_revision=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')
    local current_image=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
    local current_replicas=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
    local ready_replicas=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    
    echo "Current Revision: $current_revision"
    echo "Current Image: $current_image"
    echo "Replicas: $ready_replicas/$current_replicas"
    
    # Get pods status
    echo "Pod Status:"
    kubectl get pods -n "$NAMESPACE" -l app=fastapi-service --no-headers | while read -r line; do
        echo "  $line"
    done
}

# Backup current state before rollback
backup_current_state() {
    log_info "Creating backup of current state..."
    
    local backup_dir="$PROJECT_ROOT/backups/rollback-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup deployment
    kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o yaml > "$backup_dir/deployment-before-rollback.yaml"
    
    # Backup pods info
    kubectl get pods -n "$NAMESPACE" -l app=fastapi-service -o yaml > "$backup_dir/pods-before-rollback.yaml"
    
    # Save current state info
    cat << EOF > "$backup_dir/rollback-info.txt"
Rollback Information
===================
Environment: $ENVIRONMENT
Namespace: $NAMESPACE
Deployment: $DEPLOYMENT
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Rollback Reason: Manual rollback initiated
$(get_current_info)
EOF
    
    log_success "Backup created: $backup_dir"
}

# Confirm rollback
confirm_rollback() {
    if [[ "$CONFIRM" == false ]]; then
        echo
        log_warning "You are about to rollback the $ENVIRONMENT deployment!"
        log_warning "Environment: $ENVIRONMENT"
        log_warning "Namespace: $NAMESPACE"
        log_warning "Deployment: $DEPLOYMENT"
        
        if [[ -n "$TO_REVISION" ]]; then
            log_warning "Target Revision: $TO_REVISION"
        else
            log_warning "Target: Previous revision"
        fi
        
        echo
        read -p "Are you sure you want to continue? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Rollback cancelled"
            exit 0
        fi
    fi
}

perform_rollback() {
    log_info "Starting rollback process..."
    
    local rollback_cmd="kubectl rollout undo deployment/$DEPLOYMENT -n $NAMESPACE"
    
    if [[ -n "$TO_REVISION" ]]; then
        rollback_cmd="$rollback_cmd --to-revision=$TO_REVISION"
        log_info "Rolling back to revision $TO_REVISION..."
    else
        log_info "Rolling back to previous revision..."
    fi
    
    # Execute rollback
    if eval "$rollback_cmd"; then
        log_success "Rollback command executed successfully"
    else
        log_error "Rollback command failed"
        exit 1
    fi
}

wait_for_rollback() {
    log_info "Waiting for rollback to complete..."
    
    local timeout=300  # 5 minutes
    if kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout="${timeout}s"; then
        log_success "Rollback completed successfully"
    else
        log_error "Rollback failed to complete within $timeout seconds"
        return 1
    fi
}

# Verify rollback
verify_rollback() {
    log_info "Verifying rollback..."
    
    # Check pod status
    local ready_replicas=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    local desired_replicas=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
    
    if [[ "$ready_replicas" == "$desired_replicas" && "$ready_replicas" -gt 0 ]]; then
        log_success "All replicas are ready ($ready_replicas/$desired_replicas)"
    else
        log_error "Not all replicas are ready ($ready_replicas/$desired_replicas)"
        return 1
    fi
    
    # Health check
    local service_ip=$(kubectl get service fastapi-service -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    
    if [[ -n "$service_ip" ]]; then
        log_info "Running health checks..."
        
        # Test health endpoint
        if kubectl run rollback-health-test --image=curlimages/curl:latest --rm -i --restart=Never -n "$NAMESPACE" -- \
           curl -f "http://$service_ip/health" --max-time 10 --silent; then
            log_success "Health check passed"
        else
            log_error "Health check failed"
            return 1
        fi
        
        # Test API endpoint
        if kubectl run rollback-api-test --image=curlimages/curl:latest --rm -i --restart=Never -n "$NAMESPACE" -- \
           curl -f "http://$service_ip/items" --max-time 10 --silent; then
            log_success "API check passed"
        else
            log_error "API check failed"
            return 1
        fi
    else
        log_warning "Could not get service IP, skipping health checks"
    fi
}

# Show post-rollback information
show_post_rollback_info() {
    log_info "Post-rollback deployment information:"
    echo "====================================="
    
    get_current_info
    
    echo
    log_info "Recent events:"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -5
    
    echo
    log_info "Pod logs (last 5 lines):"
    kubectl logs -n "$NAMESPACE" -l app=fastapi-service --tail=5 --prefix=true 2>/dev/null || log_warning "No logs available"
}

# Record rollback
record_rollback() {
    local record_file="$PROJECT_ROOT/deployments/rollback-$(date +%Y%m%d-%H%M%S)-$ENVIRONMENT.log"
    
    cat << EOF > "$record_file"
Rollback Record
===============
Environment: $ENVIRONMENT
Namespace: $NAMESPACE
Deployment: $DEPLOYMENT
$(if [[ -n "$TO_REVISION" ]]; then echo "Target Revision: $TO_REVISION"; else echo "Target: Previous revision"; fi)
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Status: SUCCESS
Performed by: $(whoami)

Post-rollback Status:
$(get_current_info)
EOF
    
    log_success "Rollback recorded: $record_file"
}


# Main rollback function
main() {
    # Handle list revisions request
    if [[ "$LIST_REVISIONS" == true ]]; then
        check_prerequisites
        list_revisions
        exit 0
    fi
    
    # Check for emergency mode
    if [[ "${EMERGENCY:-false}" == true ]]; then
        emergency_rollback
        exit 0
    fi
    
    # Normal rollback process
    check_prerequisites
    
    echo
    list_revisions
    echo
    get_current_info
    echo
    
    confirm_rollback
    backup_current_state
    
    if perform_rollback && wait_for_rollback; then
        if verify_rollback; then
            show_post_rollback_info
            record_rollback
            log_success "Rollback completed successfully! ✅"
        else
            log_error "Rollback completed but verification failed ⚠️"
            log_warning "Please check the deployment manually"
            exit 1
        fi
    else
        log_error "Rollback failed ❌"
        log_error "Please check the deployment status and logs"
        exit 1
    fi
}

emergency_handler() {
    log_warning "Emergency rollback triggered!"
    EMERGENCY=true
    emergency_rollback
}

trap 'log_error "Rollback interrupted"; exit 1' INT TERM
trap emergency_handler USR1

# Run main function
main "$@"