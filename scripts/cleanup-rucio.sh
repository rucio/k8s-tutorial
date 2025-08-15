#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

echo "# --------------------------------------"
echo "# Rucio Cleanup Script"
echo "# --------------------------------------"

echo "┌──────────────────────────────────────┐"
echo "⟾ Check current resources in namespace │"
echo "└──────────────────────────────────────┘"

echo "Current resources in default namespace:"
kubectl get all -o wide

echo ""
echo "Current PVCs:"
kubectl get pvc

echo ""
echo "Current secrets (rucio-related):"
kubectl get secrets | grep -E "(hostcert|ca-cert|rucio)" || echo "No rucio-related secrets found"

echo ""
read -rp "Do you want to proceed with cleanup? This will delete ALL Rucio resources! (y/N): " CONFIRM_CLEANUP
CONFIRM_CLEANUP=$(echo "${CONFIRM_CLEANUP}" | tr '[:upper:]' '[:lower:]')

if [[ "${CONFIRM_CLEANUP}" != "y" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "┌────────────────────────────────────┐"
echo "⟾ Starting Rucio resource cleanup... │"
echo "└────────────────────────────────────┘"

# Function to safely delete resources
safe_delete() {
    local resource_type="$1"
    local resource_name="$2"
    local extra_args="${3:-}"
    
    echo "⤑ Deleting $resource_type $resource_name..."
    kubectl delete $resource_type $resource_name $extra_args 2>/dev/null || echo "  ⚠ $resource_type $resource_name not found or already deleted"
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local timeout="${3:-60}"
    
    echo "⤑ Waiting for $resource_type $resource_name to be deleted..."
    kubectl wait --for=delete $resource_type/$resource_name --timeout=${timeout}s 2>/dev/null || echo "  ⚠ Timeout or resource already deleted"
}

echo "┌─────────────────────────┐"
echo "⟾ Uninstall Helm releases │"
echo "└─────────────────────────┘"
helm uninstall daemons --debug 2>/dev/null || echo "  ⚠ helm release daemons not found or already deleted"
helm uninstall server --debug 2>/dev/null || echo "  ⚠ helm release server not found or already deleted"
helm uninstall postgres --debug 2>/dev/null || echo "  ⚠ helm release postgres not found or already deleted"

echo ""
echo "┌──────────────────────────────┐"
echo "⟾ Delete Kubernetes resources │"
echo "└──────────────────────────────┘"

# Delete jobs
safe_delete "job" "daemons-renew-fts-proxy-on-helm-install"

# Delete FTS resources
echo "⤑ Deleting FTS resources..."
kubectl delete -f ../manifests/fts.yaml --all=true --recursive=true 2>/dev/null || echo "  ⚠ FTS manifest not found or already deleted"
kubectl delete -f ../manifests/ftsdb.yaml --all=true --recursive=true 2>/dev/null || echo "  ⚠ FTS DB manifest not found or already deleted"

# Delete XRootD resources
echo "⤑ Deleting XRootD resources..."
kubectl delete -f ../manifests/xrd.yaml --all=true --recursive=true 2>/dev/null || echo "  ⚠ XRD manifest not found or already deleted"

# Delete individual XRootD pods if they exist (from your custom deployment)
XRD_PODS=("xrd1" "xrd2" "xrd3")
for pod in "${XRD_PODS[@]}"; do
    safe_delete "pod" "$pod"
    safe_delete "service" "$pod"
done

# Delete client resources
echo "⤑ Deleting client resources..."
kubectl delete -f ../manifests/client.yaml --all=true --recursive=true 2>/dev/null || echo "  ⚠ Client manifest not found or already deleted"

# Delete init pod
safe_delete "pod" "init"
kubectl delete -f ../manifests/init-pod.yaml --all=true --recursive=true 2>/dev/null || echo "  ⚠ Init pod manifest not found or already deleted"

echo ""
echo "┌─────────────────────────┐"
echo "⟾ Delete PVCs and storage │"
echo "└─────────────────────────┘"
echo "⤑ Deleting pvc data-postgres-postgresql-0..."
kubectl delete pvc data-postgres-postgresql-0 --timeout=60s 2>/dev/null || {
    echo "  ⚠ PVC deletion timed out, trying force delete..."
    kubectl patch pvc data-postgres-postgresql-0 -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
    kubectl delete pvc data-postgres-postgresql-0 --force --grace-period=0 2>/dev/null || true
}

echo ""
echo "┌──────────────────────┐"
echo "⟾ Delete secrets       │"
echo "└──────────────────────┘"
echo "⤑ Deleting secrets..."
kubectl delete -k ../secrets 2>/dev/null || echo "  ⚠ Secrets not found or already deleted"

# Delete individual secrets if they exist
SECRETS=("hostcert-xrd1" "hostcert-xrd2" "hostcert-xrd3" "ca-cert")
for secret in "${SECRETS[@]}"; do
    safe_delete "secret" "$secret"
done

echo ""
echo "┌─────────────────────────────────────┐"
echo "⟾ Wait for resources to be cleaned up │"
echo "└─────────────────────────────────────┘"

# Wait a bit for resources to be deleted
echo "⤑ Waiting for resources to be fully cleaned up..."
sleep 5

# Check for any remaining pods
echo ""
echo "┌────────────────────────────────────────────┐"
echo "⟾ Force delete any remaining stubborn pods   │"
echo "└────────────────────────────────────────────┘"

REMAINING_PODS=$(kubectl get pods --no-headers -o custom-columns=NAME:metadata.name | grep -E "(rucio|postgres|fts|xrd|init)" || true)
if [[ -n "$REMAINING_PODS" ]]; then
    echo "⤑ Found remaining pods, force deleting..."
    for pod in $REMAINING_PODS; do
        echo "  ⤑ Force deleting pod: $pod"
        kubectl delete pod "$pod" --force --grace-period=0 2>/dev/null || echo "    ⚠ Could not force delete $pod"
    done
fi

echo ""
echo "┌─────────────────────────────────────────────┐"
echo "⟾ Final cleanup - remove any stuck resources │"
echo "└─────────────────────────────────────────────┘"

# Remove finalizers from stuck resources if any
echo "⤑ Checking for resources with finalizers..."
STUCK_PVCS=$(kubectl get pvc --no-headers -o custom-columns=NAME:metadata.name | grep -E "(postgres|rucio)" || true)
if [[ -n "$STUCK_PVCS" ]]; then
    echo "⚠ Found stuck PVCs, attempting to remove finalizers..."
    for pvc in $STUCK_PVCS; do
        echo "  ⤑ Removing finalizers from PVC: $pvc"
        kubectl patch pvc "$pvc" -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
        kubectl delete pvc "$pvc" --force --grace-period=0 2>/dev/null || true
    done
fi

STUCK_RESOURCES=$(kubectl get all --no-headers -o custom-columns=NAME:metadata.name,KIND:kind | grep -E "(rucio|postgres|fts|xrd)" || true)
if [[ -n "$STUCK_RESOURCES" ]]; then
    echo "⚠ Found potentially stuck resources. You may need to manually remove finalizers."
    echo "$STUCK_RESOURCES"
fi

echo ""
echo "┌───────────────────────────────┐"
echo "⟾ Cleanup verification         │"
echo "└───────────────────────────────┘"

echo "Current resources after cleanup:"
kubectl get all

echo ""
echo "Current PVCs after cleanup:"
kubectl get pvc

echo ""
echo "Current secrets after cleanup:"
kubectl get secrets | grep -E "(hostcert|ca-cert|rucio)" || echo "✓ No rucio-related secrets found"

echo ""
echo "*** Rucio cleanup complete! ***"
echo ""
echo "If you see any remaining resources above that should have been deleted,"
echo "you may need to manually delete them or check for finalizers blocking deletion."