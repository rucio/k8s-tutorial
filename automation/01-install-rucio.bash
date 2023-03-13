#!/usr/bin/env bash
set -e

# Minikube
# Possible values for memory: max | format: <number>[<unit>], where unit = b, k, m or g, e.g., 4000mb
MINIKUBE_MEMORY_RAM=8000mb
# Possible values for CPUs: max | 1, 2, 3, 4, 5, ...
MINIKUBE_CPU=4

echo "# --------------------------------------"
echo "# Check installed packages"
echo "# --------------------------------------"
KUBECTL_SUCCESS="The kubectl package is installed."
KUBECTL_ERROR="The kubectl package is not installed. Please, follow this guide https://kubernetes.io/docs/tasks/tools/install-kubectl/"
type kubectl &>/dev/null && echo "${KUBECTL_SUCCESS}" || echo "${KUBECTL_ERROR}"

MINIKUBE_SUCCESS="The minikube package is installed."
MINIKUBE_ERROR="The minikube package is not installed. Please, follow this guide https://minikube.sigs.k8s.io/docs/start/"
type minikube &>/dev/null && echo "${MINIKUBE_SUCCESS}" || echo "${MINIKUBE_ERROR}"

HELM_SUCCESS="The helm package is installed."
HELM_ERROR="The helm package is not installed. Please, follow this guide https://helm.sh/docs/intro/install/"
type helm &>/dev/null && echo "${HELM_SUCCESS}" || echo "${HELM_ERROR}"

echo ""
echo "# --------------------------------------"
echo "# Celan local environment"
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

MINIKUBE_HAS_NOT_PROFILE="The minikube not has profile. It will create a new one."
minikube status | grep "not found" &>/dev/null && {
  echo "${MINIKUBE_HAS_NOT_PROFILE}"
  minikube status || true
  minikube start --memory="${MINIKUBE_MEMORY_RAM}" --cpus="${MINIKUBE_CPU}"
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
  minikube start --memory="${MINIKUBE_MEMORY_RAM}" --cpus="${MINIKUBE_CPU}"
}

echo "┌────────────────────────┐"
echo "⟾ Helm: Install Postgres │"
echo "└────────────────────────┘"
KUBECTL_HAS_PVC="The kubectl has the Postgres PVC. It will delete."
kubectl get pvc data-postgres-postgresql-0 &>/dev/null || false && {
  echo "${KUBECTL_HAS_PVC}"
  kubectl delete pvc data-postgres-postgresql-0
}
helm delete postgres 2>/dev/null || true
helm install postgres bitnami/postgresql -f ../postgres_values.yaml

echo "┌──────────────────────────┐"
echo "⟾ kubectl: Postgres set up │"
echo "└──────────────────────────┘"
echo "⤑ It will wait until the Postgres is set up. It could take several seconds or minutes."
while [[ "$(kubectl get pods postgres-postgresql-0 -o custom-columns=STATUS:.status.containerStatuses[*].ready --no-headers || false)" != true ]]; do
  echo ""
  kubectl get pods postgres-postgresql-0 || true
  sleep 4
done
echo ""
kubectl get pods postgres-postgresql-0 || true

echo "┌─────────────────────────────────┐"
echo "⟾ kubectl: Rucio - Init Container │"
echo "└─────────────────────────────────┘"
kubectl delete pod init 2>/dev/null || true
kubectl apply -f ../init-pod.yaml
echo "⤑ It will wait until the Rucio Init Container is set up. It could take several seconds or minutes."
while [[ "$(kubectl get pods init -o custom-columns=STATUS:.status.containerStatuses[*].ready --no-headers)" != true ]]; do
  echo ""
  kubectl get pods init
  if [[ "$(kubectl get pods init -o custom-columns=STATUS:.status.containerStatuses[*].state.terminated.reason --no-headers)" == "Error" ]]; then
    echo ""
    echo "ERROR: The Init Container has an error. Verify that the postgres container is finished and ready."
    exit 1
  fi
  sleep 3
done
echo ""
kubectl get pods init

echo "┌──────────────────────────────────────────┐"
echo "⟾ kubectl: Logs for Rucio - Init Container │"
echo "└──────────────────────────────────────────┘"
kubectl logs init

echo "┌────────────────────────────┐"
echo "⟾ helm: Install Rucio server │"
echo "└────────────────────────────┘"
helm delete server 2>/dev/null || true
helm install server rucio/rucio-server -f ../server.yaml
RUCIO_SERVER_POD=$(kubectl get pods | grep ^server-rucio-server- | grep -v auth- | awk '{print $1}')
echo "RUCIO_SERVER_POD: ${RUCIO_SERVER_POD}"
while [[ "$(kubectl get pods "${RUCIO_SERVER_POD}" -o custom-columns=STATUS:.status.containerStatuses[*].ready --no-headers)" != true,true ]]; do
  echo ""
  kubectl get pods "${RUCIO_SERVER_POD}"
  sleep 4
done
echo ""
kubectl get pods "${RUCIO_SERVER_POD}"

echo "┌────────────────────────────────┐"
echo "⟾ kubectl: Logs for Rucio server │"
echo "└────────────────────────────────┘"
kubectl logs "${RUCIO_SERVER_POD}" rucio-server

echo "┌───────────────────────────────────┐"
echo "⟾ kubectl: Install client container │"
echo "└───────────────────────────────────┘"
kubectl apply -f ../client.yaml
while [[ "$(kubectl get pods client -o custom-columns=STATUS:.status.containerStatuses[*].ready --no-headers)" != true ]]; do
  echo ""
  kubectl get pods client
  sleep 2
done
echo ""
kubectl get pods client

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
  echo ""
  echo "XRD_CONTAINER: ${XRD_CONTAINER}"
  while [[ "$(kubectl get pods "${XRD_CONTAINER}" -o custom-columns=STATUS:.status.containerStatuses[*].ready --no-headers)" != true ]]; do
    echo ""
    kubectl get pods "${XRD_CONTAINER}"
    sleep 2
  done
  echo ""
  kubectl get pods "${XRD_CONTAINER}"
done

echo "┌───────────────────────────────────────┐"
echo "⟾ kubectl: Install FTS database (MySQL) │"
echo "└───────────────────────────────────────┘"
kubectl apply -f ../ftsdb.yaml
FTS_MYSQL_POD=$(kubectl get pods | grep ^fts-mysql- | awk '{print $1}')
echo "FTS_MYSQL_POD: ${FTS_MYSQL_POD}"
while [[ "$(kubectl get pods "${FTS_MYSQL_POD}" -o custom-columns=STATUS:.status.containerStatuses[*].ready --no-headers)" != true ]]; do
  echo ""
  kubectl get pods "${FTS_MYSQL_POD}"
  sleep 1
done
echo ""
kubectl get pods "${FTS_MYSQL_POD}"

echo "┌────────────────────────────────────────┐"
echo "⟾ kubectl: Logs for FTS database (MySQL) │"
echo "└────────────────────────────────────────┘"
kubectl logs "${FTS_MYSQL_POD}"

echo "┌──────────────────────┐"
echo "⟾ kubectl: Install FTS │"
echo "└──────────────────────┘"
kubectl apply -f ../fts.yaml
FTS_SERVER_POD=$(kubectl get pods | grep ^fts-server- | awk '{print $1}')
echo "FTS_SERVER_POD: ${FTS_SERVER_POD}"
while [[ "$(kubectl get pods "${FTS_SERVER_POD}" -o custom-columns=STATUS:.status.containerStatuses[*].ready --no-headers)" != true ]]; do
  echo ""
  kubectl get pods "${FTS_SERVER_POD}"
  sleep 1
done
echo ""
kubectl get pods "${FTS_SERVER_POD}"

echo "┌───────────────────────┐"
echo "⟾ kubectl: Logs for FTS │"
echo "└───────────────────────┘"
kubectl logs "${FTS_SERVER_POD}"

echo "┌───────────────────────┐"
echo "⟾ helm: Install Daemons │"
echo "└───────────────────────┘"
echo "⤑ It will wait until the Daemons are set up. It could take several seconds or minutes."
helm delete daemons 2>/dev/null || true
helm install daemons rucio/rucio-daemons -f ../daemons.yaml
mapfile -t DAEMONS_PODS < <(kubectl get pods | grep ^daemons- | awk '{print $1}')
echo "DAEMONS_PODS: ${DAEMONS_PODS[*]}"
for DAEMON_POD in "${DAEMONS_PODS[@]}"; do
  echo ""
  echo "DAEMON_POD: ${DAEMON_POD}"
  while [[ "$(kubectl get pods "${DAEMON_POD}" -o custom-columns=STATUS:.status.containerStatuses[*].ready --no-headers)" != true ]]; do
    echo ""
    kubectl get pods "${DAEMON_POD}"
    sleep 1
  done
  echo ""
  kubectl get pods "${DAEMON_POD}"
done

echo "┌────────────────────────────────────────────────────┐"
echo "⟾ kubectl: Run FTS storage authentication delegation │"
echo "└────────────────────────────────────────────────────┘"
kubectl create job renew-manual-1 --from=cronjob/daemons-renew-fts-proxy

echo""
echo""
echo""
echo "*** Finished! ***"
