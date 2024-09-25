#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

# Minikube
MINIKUBE_ARGS=()

# Set default MINIKUBE_MEMORY to 4000mb if it is not specified
if [[ -z "${MINIKUBE_MEMORY}" ]]; then
  MINIKUBE_MEMORY="4000mb"
fi
MINIKUBE_ARGS+=("--memory=${MINIKUBE_MEMORY}")

if [[ -n "${MINIKUBE_CPU}" ]]; then
  MINIKUBE_ARGS+=("--cpus=${MINIKUBE_CPU}")
fi

display_help() {
  echo >&2 "▄▄▄▄▄▄▄▄▄▄▄▄"
  echo >&2 "█   HELP   █"
  echo >&2 "▀▀▀▀▀▀▀▀▀▀▀▀"
  echo >&2 ""
  echo >&2 "Usage ▶ $0"
  echo >&2 ""
  echo >&2 "Minikube"
  echo >&2 "════════"
  echo >&2 "Minikube accepts two parameters: the amount of memory and the number of CPUs."
  echo >&2 "  Memory:"
  echo >&2 "    - max"
  echo >&2 "    - format: <number>[<unit>], where unit = b, k, m or g, e.g., 4000mb"
  echo >&2 "  CPUs:"
  echo >&2 "    - max"
  echo >&2 "    - 1, 2, 3, 4, 5, …, e.g., 8"
  echo >&2 ""
  echo >&2 "  Usage"
  echo >&2 "  ━━━━━"
  echo >&2 "  These parameters can be set via the environment variables MINIKUBE_MEMORY and MINIKUBE_CPU."
  echo >&2 "  Usage ▶ export MINIKUBE_MEMORY=5000mb MINIKUBE_CPU=3; $0"
  echo >&2 "  Usage ▶ export MINIKUBE_CPU=max; $0"
  echo >&2 "  Usage ▶ export MINIKUBE_MEMORY=max; $0"
}

case "$1" in
-h | --help)
  display_help
  exit 0
  ;;
--) # End of all options
  shift
  ;;
-*) # Error
  echo "Error: Unknown option: $1" >&2
  echo "Help ▶ $0 --help" >&2
  exit 1
  ;;
esac

MINIKUBE_SUCCESS="The minikube package is installed."
MINIKUBE_ERROR="The minikube package is not installed. Please install it here: https://kubernetes.io/docs/tasks/tools/install-minikube/"
type minikube &>/dev/null && echo "${MINIKUBE_SUCCESS}" || echo "${MINIKUBE_ERROR}"

echo ""
echo "# --------------------------------------"
echo "# Clean local environment"
echo "# --------------------------------------"

echo "┌──────────────────────────────────────────────┐"
echo "⟾ Check local Kubernetes clusters for minikube │"
echo "└──────────────────────────────────────────────┘"
WILL_STOP_MINIKUBE="n"
MINIKUBE_RUNNING_KUBERNETES="The minikube is running local Kubernetes clusters."
minikube status | grep "Running" &>/dev/null && {
  echo "${MINIKUBE_RUNNING_KUBERNETES}"
  minikube status
  read -rp "Do you want to stop the local Kubernetes clusters? (y/N): " WILL_STOP_MINIKUBE
}
if [[ "${WILL_STOP_MINIKUBE,,}" == "y" ]]; then
  minikube stop
fi

WILL_DELETE_MINIKUBE="n"
MINIKUBE_HAS_KUBERNETES="The minikube has local Kubernetes clusters."
minikube status | grep "Stopped" &>/dev/null && {
  echo "${MINIKUBE_HAS_KUBERNETES}"
  minikube status || true
  read -rp "Do you want to delete the local Kubernetes clusters? (y/N): " WILL_DELETE_MINIKUBE
}
if [[ "${WILL_DELETE_MINIKUBE,,}" == "y" ]]; then
  minikube delete --all=true
fi

MINIKUBE_HAS_NOT_PROFILE="The minikube does not have a profile. It will create a new one."
minikube status | grep "not found" &>/dev/null && {
  echo "${MINIKUBE_HAS_NOT_PROFILE}"
  minikube status || true
  minikube start "${MINIKUBE_ARGS[@]}"
}

echo "┌────────────────┐"
echo "⟾ Start minikube │"
echo "└────────────────┘"
minikube status | grep "Stopped" &>/dev/null && {
  echo "${MINIKUBE_HAS_KUBERNETES}"
  minikube status || true
  minikube start "${MINIKUBE_ARGS[@]}"
}

echo""
echo""
echo""
echo "*** Minikube setup complete. ***"
