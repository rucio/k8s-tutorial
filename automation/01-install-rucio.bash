#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

# Minikube
MINIKUBE_ARGS=()
if [[ -n "${MINIKUBE_MEMORY}" ]]; then
  MINIKUBE_ARGS+=("--memory=${MINIKUBE_MEMORY}")
fi
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
  echo >&2 "Minikube accepts two parameters, the amount of memory and the number of CPUs."
  echo >&2 "  Memory:"
  echo >&2 "    - max"
  echo >&2 "    - format: <number>[<unit>], where unit = b, k, m or g, e.g., 4000mb"
  echo >&2 "  CPUs:"
  echo >&2 "    - max"
  echo >&2 "    - 1, 2, 3, 4, 5, …, e.g., 8"
  echo >&2 ""
  echo >&2 "  Usage"
  echo >&2 "  ━━━━━"
  echo >&2 "  To set up these parameters, need to use environment variables: MINIKUBE_MEMORY or MINIKUBE_CPU."
  echo >&2 "  Usage ▶ export MINIKUBE_MEMORY=5000mb MINIKUBE_CPU=3; $0"
  echo >&2 "  Usage ▶ export MINIKUBE_CPU=max; $0"
  echo >&2 "  Usage ▶ export MINIKUBE_MEMORY=max; $0"
  echo >&2 ""
  echo >&2 "  Clean environment variables"
  echo >&2 "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo >&2 "  The unset command, removes the environment variable"
  echo >&2 "  Usage ▶ unset MINIKUBE_MEMORY MINIKUBE_CPU"
  echo >&2 ""
  echo >&2 "  Actual value for environment variables"
  echo >&2 "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo >&2 "  Currently, these are the parameters which will set in the minikube. Blank means not arguments."
  echo >&2 "  ▶ minikube start ${MINIKUBE_ARGS[*]}"
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

echo "# --------------------------------------"
echo "# Check installed packages"
echo "# --------------------------------------"
KUBECTL_SUCCESS="The kubectl package is installed."
KUBECTL_ERROR="The kubectl package is not installed. Please follow this guide https://kubernetes.io/docs/tasks/tools/install-kubectl/"
type kubectl &>/dev/null && echo "${KUBECTL_SUCCESS}" || echo "${KUBECTL_ERROR}"

MINIKUBE_SUCCESS="The minikube package is installed."
MINIKUBE_ERROR="The minikube package is not installed. Please follow this guide https://minikube.sigs.k8s.io/docs/start/"
type minikube &>/dev/null && echo "${MINIKUBE_SUCCESS}" || echo "${MINIKUBE_ERROR}"

HELM_SUCCESS="The helm package is installed."
HELM_ERROR="The helm package is not installed. Please follow this guide https://helm.sh/docs/intro/install/"
type helm &>/dev/null && echo "${HELM_SUCCESS}" || echo "${HELM_ERROR}"

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

echo "┌─────────────────────────────────────┐"
echo "⟾ Check default namespace for kubectl │"
echo "└─────────────────────────────────────┘"
WILL_STOP_PODS="n"
KUBECTL_PODS="The default namespace is running elements in kubectl."
if [[ "$(kubectl get all -o custom-columns=NAME:metadata.name --no-headers | wc -l)" -gt 1 ]]; then
  echo "${KUBECTL_PODS}"
  kubectl get all
  read -rp "Do you want to stop all of these pods, services, etc? (y/N): " WILL_STOP_PODS
fi
if [[ "${WILL_STOP_PODS,,}" == "y" ]]; then
  while true; do
    echo ""
    echo "⤑ It will stop all the pods. It could take several seconds or minutes."
    helm uninstall daemons --debug 2>/dev/null || true
    helm uninstall server --debug 2>/dev/null || true
    helm uninstall postgres --debug 2>/dev/null || true
    kubectl delete job daemons-renew-fts-proxy-on-helm-install 2>/dev/null || true
    kubectl delete pvc data-postgres-postgresql-0 2>/dev/null || true
    kubectl delete -f ../fts.yaml --all=true --recursive=true
    kubectl delete -f ../ftsdb.yaml --all=true --recursive=true
    kubectl delete -f ../xrd.yaml --all=true --recursive=true
    kubectl delete -f ../client.yaml --all=true --recursive=true
    kubectl delete -f ../init-pod.yaml --all=true --recursive=true
    kubectl delete -k ../secrets
    kubectl get all
    if [[ "$(kubectl get all -o custom-columns=NAME:metadata.name --no-headers | wc -l)" -le 1 ]]; then
      break
    fi
    sleep 4
  done
fi

echo ""
echo "# --------------------------------------"
echo "# Start local environment"
echo "# --------------------------------------"

echo "┌──────────────────────────┐"
echo "⟾ Add repositories to helm │"
echo "└──────────────────────────┘"
helm repo add stable https://charts.helm.sh/stable
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add rucio https://rucio.github.io/helm-charts
helm repo update

echo "┌────────────────┐"
echo "⟾ Start minikube │"
echo "└────────────────┘"
minikube status | grep "Stopped" &>/dev/null && {
  echo "${MINIKUBE_HAS_KUBERNETES}"
  minikube status || true
  minikube start "${MINIKUBE_ARGS[@]}"
}

echo "┌────────────────┐"
echo "⟾ Secrets        │"
echo "└────────────────┘"
kubectl apply -k ../secrets

echo "┌────────────────────────┐"
echo "⟾ Helm: Install Postgres │"
echo "└────────────────────────┘"
KUBECTL_HAS_PVC="The kubectl has the Postgres PVC. Deleting."
kubectl get pvc data-postgres-postgresql-0 &>/dev/null || false && {
  echo "${KUBECTL_HAS_PVC}"
  kubectl delete pvc data-postgres-postgresql-0
}
helm delete postgres 2>/dev/null || true
helm install postgres bitnami/postgresql -f ../values-postgres.yaml

echo "┌──────────────────────────┐"
echo "⟾ kubectl: Postgres set up │"
echo "└──────────────────────────┘"
echo "⤑ Waiting until the Postgres is set up. It could take several seconds or minutes."
kubectl rollout status statefulset postgres-postgresql

echo "┌─────────────────────────────────┐"
echo "⟾ kubectl: Rucio - Init Container │"
echo "└─────────────────────────────────┘"
kubectl delete pod init 2>/dev/null || true
kubectl apply -f ../init-pod.yaml
echo "⤑ Waiting until the Rucio Init Container is set up. It could take several seconds or minutes."
kubectl wait --timeout=120s --for=condition=Ready pod/init

echo "┌──────────────────────────────────────────┐"
echo "⟾ kubectl: Logs for Rucio - Init Container │"
echo "└──────────────────────────────────────────┘"
kubectl logs init

echo "┌────────────────────────────┐"
echo "⟾ helm: Install Rucio server │"
echo "└────────────────────────────┘"
helm delete server 2>/dev/null || true
helm install server rucio/rucio-server -f ../values-server.yaml
kubectl rollout status deployment server-rucio-server

echo "┌────────────────────────────────┐"
echo "⟾ kubectl: Logs for Rucio server │"
echo "└────────────────────────────────┘"
kubectl logs deployment/server-rucio-server -c rucio-server

echo "┌───────────────────────────────────┐"
echo "⟾ kubectl: Install client container │"
echo "└───────────────────────────────────┘"
kubectl apply -f ../client.yaml
kubectl wait --timeout=120s --for=condition=Ready pod/client

echo "┌─────────────────────────────────┐"
echo "⟾ kubectl: Check client container │"
echo "└─────────────────────────────────┘"
kubectl exec client -it -- /etc/profile.d/rucio_init.sh
kubectl exec client -it -- rucio whoami

echo "┌─────────────────────────────────────────┐"
echo "⟾ kubectl: Install XRootD storage systems │"
echo "└─────────────────────────────────────────┘"
kubectl apply -f ../xrd.yaml
XRD_CONTAINERS=(xrd1 xrd2 xrd3)
echo "XRD_CONTAINERS: ${XRD_CONTAINERS[*]}"
for XRD_CONTAINER in "${XRD_CONTAINERS[@]}"; do
  kubectl --timeout=120s wait --for=condition=Ready pod/$XRD_CONTAINER
done

echo "┌───────────────────────────────────────┐"
echo "⟾ kubectl: Install FTS database (MySQL) │"
echo "└───────────────────────────────────────┘"
kubectl apply -f ../ftsdb.yaml
kubectl rollout status deployment fts-mysql

echo "┌────────────────────────────────────────┐"
echo "⟾ kubectl: Logs for FTS database (MySQL) │"
echo "└────────────────────────────────────────┘"
kubectl logs deployment/fts-mysql

echo "┌──────────────────────┐"
echo "⟾ kubectl: Install FTS │"
echo "└──────────────────────┘"
kubectl apply -f ../fts.yaml
kubectl rollout status deployment fts-server

echo "┌───────────────────────┐"
echo "⟾ kubectl: Logs for FTS │"
echo "└───────────────────────┘"
kubectl logs deployment/fts-server

echo "┌───────────────────────┐"
echo "⟾ helm: Install Daemons │"
echo "└───────────────────────┘"
helm delete daemons 2>/dev/null || true
echo "⤑ Waiting until the Daemons are set up. It could take several seconds or minutes."
helm install daemons rucio/rucio-daemons -f ../values-daemons.yaml
for DAEMON in $(kubectl get deployment -l='app-group=rucio-daemons' -o name); do
    kubectl rollout status $DAEMON
done

echo""
echo""
echo""
echo "*** Finished! ***"
