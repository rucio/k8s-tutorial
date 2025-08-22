#!/usr/bin/env bash
set -e

echo "┌──────────────────────────────┐"
echo "⟾ Cleanup Rucio tutorial setup │"
echo "└──────────────────────────────┘"

read -rp "Delete all resources in rucio-tutorial namespace? (y/N): " CONFIRM
[[ "${CONFIRM,,}" == "y" ]] || exit 0

# Simple namespace deletion handles everything
kubectl delete namespace rucio-tutorial --ignore-not-found=true
echo "✓ Cleanup complete!"