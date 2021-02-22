# Rucio Kubernetes Tutorial

## Preliminaries

* Clone this repo to your local machine

* Install kubectl

      https://kubernetes.io/docs/tasks/tools/install-kubectl/

* Install helm

      https://helm.sh/docs/intro/install/

* Install minikube

      https://kubernetes.io/docs/tasks/tools/install-minikube/
	  https://minikube.sigs.k8s.io/docs/start/

* Start minikube with extra RAM:

      minikube start --memory='4000mb'

* Add Helm chart repositories:

      helm repo add stable https://charts.helm.sh/stable
      helm repo add bitnami https://charts.bitnami.com/bitnami
      helm repo add rucio https://rucio.github.io/helm-charts

## Some helpful commands

* Activate kubectl bash completion:

      source <(kubectl completion bash)

* View all containers:

      kubectl get pods

* View/Tail logfiles of pod:

      kubectl logs <NAME>

      kubectl logs -f <NAME>

* Update helm repositories:

      helm repo update

* Shut down minikube:

      minikube stop

## Installation of Rucio + FTS + Storage

* Install the main Rucio database (PostgreSQL):

      helm install postgres bitnami/postgresql -f postgres_values.yaml

* Run init container once to setup the Rucio database once the PostgreSQL container is running:

      kubectl apply -f init-pod.yaml

* Install the Rucio server:

      helm install server rucio/rucio-server -f server.yaml

* Prepare a client container for interactive use:

      kubectl apply -f client.yaml

* Jump into the client container and check if the clients are working:

      kubectl exec -it client /bin/bash

      rucio whoami

* Install the XRootD storage systems:

      kubectl apply -f xrd.yaml

* Install the FTS database (MySQL):

      kubectl apply -f ftsdb.yaml

* Install FTS, once the FTS database container is up and running:

      kubectl apply -f fts.yaml

* Install the Rucio daemons:

      helm install daemons rucio/rucio-daemons -f daemons.yaml

* Run FTS storage authentication delegation once:

      kubectl create job renew-manual-1 --from=cronjob/daemons-renew-fts-proxy

## Rucio usage

* Jump into the client container

      kubectl exec -it client /bin/bash

* Create the RSEs

      rucio-admin rse add XRD1
      rucio-admin rse add XRD2
      rucio-admin rse add XRD3

* Add the protocol definitions for the storage servers

      rucio-admin rse add-protocol --hostname xrd1 --scheme root --prefix //rucio --port 1094 --impl rucio.rse.protocols.gfal.Default --domain-json '{"wan": {"read": 1, "write": 1, "delete": 1, "third_party_copy": 1}, "lan": {"read": 1, "write": 1, "delete": 1}}' XRD1
      rucio-admin rse add-protocol --hostname xrd2 --scheme root --prefix //rucio --port 1094 --impl rucio.rse.protocols.gfal.Default --domain-json '{"wan": {"read": 1, "write": 1, "delete": 1, "third_party_copy": 1}, "lan": {"read": 1, "write": 1, "delete": 1}}' XRD2
      rucio-admin rse add-protocol --hostname xrd3 --scheme root --prefix //rucio --port 1094 --impl rucio.rse.protocols.gfal.Default --domain-json '{"wan": {"read": 1, "write": 1, "delete": 1, "third_party_copy": 1}, "lan": {"read": 1, "write": 1, "delete": 1}}' XRD3

* Enable FTS

      rucio-admin rse set-attribute --rse XRD1 --key fts --value https://fts:8446
      rucio-admin rse set-attribute --rse XRD2 --key fts --value https://fts:8446
      rucio-admin rse set-attribute --rse XRD3 --key fts --value https://fts:8446

* Fake a full mesh network

      rucio-admin rse add-distance --distance 1 --ranking 1 XRD1 XRD2
      rucio-admin rse add-distance --distance 1 --ranking 1 XRD1 XRD3
      rucio-admin rse add-distance --distance 1 --ranking 1 XRD2 XRD1
      rucio-admin rse add-distance --distance 1 --ranking 1 XRD2 XRD3
      rucio-admin rse add-distance --distance 1 --ranking 1 XRD3 XRD1
      rucio-admin rse add-distance --distance 1 --ranking 1 XRD3 XRD2

* Indefinite storage quota for root

      rucio-admin account set-limits root XRD1 -1
      rucio-admin account set-limits root XRD2 -1
      rucio-admin account set-limits root XRD3 -1

* Create a default scope for testing

      rucio-admin scope add --account root --scope test

* Create initial transfer testing data

      dd if=/dev/urandom of=file1 bs=10M count=1
      dd if=/dev/urandom of=file2 bs=10M count=1
      dd if=/dev/urandom of=file3 bs=10M count=1
      dd if=/dev/urandom of=file4 bs=10M count=1

* Upload the files

      rucio upload --rse XRD1 --scope test file1
      rucio upload --rse XRD1 --scope test file2
      rucio upload --rse XRD2 --scope test file3
      rucio upload --rse XRD2 --scope test file4

* Create a few datasets and containers

      rucio add-dataset test:dataset1
      rucio attach test:dataset1 test:file1 test:file2

      rucio add-dataset test:dataset2
      rucio attach test:dataset2 test:file3 test:file4

      rucio add-container test:container
      rucio attach test:container test:dataset1 test:dataset2

* Create a rule and remember returned rule ID

      rucio add-rule test:container 1 XRD3

* Query the status of the rule

      rucio rule-info <rule_id>

* Add some more complications

      rucio add-dataset test:dataset3
      rucio attach test:dataset3 test:file4
