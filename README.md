# Rucio Kubernetes Tutorial

## Preliminaries

* Clone this repo to your local machine

```sh
git clone https://github.com/rucio/k8s-tutorial/
```

* Install `kubectl`: https://kubernetes.io/docs/tasks/tools/install-kubectl/
* Install `helm`: https://helm.sh/docs/intro/install/
* (Optional) Install `minikube` if you do not have a pre-existing Kubernetes cluster: https://kubernetes.io/docs/tasks/tools/install-minikube/

_NOTE: All following commands should be run from the parent directory of this repository._

## Set up a Kubernetes cluster

You can skip this step if you have already set up a Kubernetes cluster.

* Run the `minikube` setup script:

```sh
./scripts/setup-minikube.sh
```

## Deploy Rucio, FTS and storage

You can perform either an automatic deployment or a manual deployment, as documented below.

### Automatic deployment

* Run the Rucio deployment script:

```sh
./scripts/deploy-rucio.sh
```

### Manual deployment

#### Add repositories to Helm

```sh
helm repo add stable https://charts.helm.sh/stable
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add rucio https://rucio.github.io/helm-charts
```

#### Apply secrets

```sh
kubectl apply -k ./secrets
```

#### (Optional) Delete existing Postgres volume claim

If you have done this step in a previous script run, the existing Postgres PersistentVolumeClaim must be deleted.

1. Verify if the PVC exists via:

```sh
kubectl get pvc data-postgres-postgresql-0
```

If the PVC exists, the command will return the following message:

```
NAME                         STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
data-postgres-postgresql-0   Bound    ...   8Gi        RWO            standard       <unset>                 4s
```

If the PVC does not exist, the command will return this message:

```
Error from server (NotFound): persistentvolumeclaims "data-postgres-postgresql-0" not found
```

You can skip to the next section if the PVC does not exist.

2. If the PVC exists, patch it to allow deletion:

```sh
kubectl patch pvc data-postgres-postgresql-0 -p '{"metadata":{"finalizers":null}}'
```

3. Delete the PVC:

```sh
kubectl delete pvc data-postgres-postgresql-0
```

4. You might also need to uninstall `postgres` if it is installed:

```sh
helm uninstall postgres
```

#### Install Postgres

```sh
helm install postgres bitnami/postgresql -f values-postgres.yaml
```

#### Verify that Postgres is running

```sh
kubectl get pod postgres-postgresql-0
```

Once the Postgres setup is complete, you should see `STATUS: Running`.

#### Start init container pod

* Once Postgres is running, start the init container pod to set up the Rucio database:

```sh
kubectl apply -f init-pod.yaml
```

* This command will take some time to complete. You can follow the relevant logs via: 

```sh
kubectl logs -f init
```

#### Verify that the init container pod setup is complete

```sh
kubectl get pod init
```

Once the init container pod setup is complete, you should see `STATUS: Completed`.


#### Deploy the Rucio server

```sh
helm install server rucio/rucio-server -f values-server.yaml
```

* You can check the deployment status via:

```sh
kubectl rollout status deployment server-rucio-server
```

#### Start the XRootD (XRD) storage container pods

* This command will deploy three XRD storage container pods.

```sh
kubectl apply -f xrd.yaml
```

#### Deploy the FTS database (MySQL)

```sh
kubectl apply -f ftsdb.yaml
```

* You can check the deployment status via:

```
kubectl rollout status deployment fts-mysql
```

#### Deploy the FTS server

* Once the FTS database deployment is complete, Install the FTS server:

```sh
kubectl apply -f fts.yaml
```

* You can check the deployment status via:

```sh
kubectl rollout status deployment fts-server
```

#### Deploy the Rucio daemons

```sh
helm install daemons rucio/rucio-daemons -f values-daemons.yaml
```

This command might take a few minutes.


#### Run FTS storage authentication delegation once
```sh
kubectl create job renew-manual-1 --from=cronjob/daemons-renew-fts-proxy
```

#### Troubleshooting
* If at any point `helm` fails to install, before re-installing, remove the previous failed installation:

```sh
helm list # list all helm installations
helm delete $installation
```

* You might also get errors that a `job` also exists. You can easily remove this:

```sh
kubectl get jobs # get all jobs
kubectl delete jobs/$jobname
```

## Use Rucio

Once the setup is complete, you can use Rucio by interacting with it via a client.

You can either run the provided script to showcase the usage of Rucio,
or you can run the Rucio commands directly

#### Script client usage showcase

* Run the Rucio usage script:

```sh
./scripts/use-rucio.sh
```

#### Manual client usage


### Start client container pod for interactive use

```sh
kubectl apply -f client.yaml
```

* You can verify that the client container is running via:

```sh
kubectl get pod client
```

Once the client container pod setup is complete, you should see `STATUS: Running`.

* You can verify that the client works by running a shell inside the container:

```sh
kubectl exec -it client -- /bin/bash
rucio whoami
```

#### Rest
_NOTE: You can execute this shell script for easier set up and understanding:
[./scripts/02-set-up-rucio.bash](./scripts/02-set-up-rucio.bash)._

* Jump into the client container

```sh
kubectl exec -it client /bin/bash
```

* Create the Rucio Storage Elements (RSEs) by

```sh
rucio-admin rse add XRD1
rucio-admin rse add XRD2
rucio-admin rse add XRD3
```

* Add the protocol definitions for the storage servers

```sh
rucio-admin rse add-protocol --hostname xrd1 --scheme root --prefix //rucio --port 1094 --impl rucio.rse.protocols.gfal.Default --domain-json '{"wan": {"read": 1, "write": 1, "delete": 1, "third_party_copy_read": 1, "third_party_copy_write": 1}, "lan": {"read": 1, "write": 1, "delete": 1}}' XRD1
rucio-admin rse add-protocol --hostname xrd2 --scheme root --prefix //rucio --port 1094 --impl rucio.rse.protocols.gfal.Default --domain-json '{"wan": {"read": 1, "write": 1, "delete": 1, "third_party_copy_read": 1, "third_party_copy_write": 1}, "lan": {"read": 1, "write": 1, "delete": 1}}' XRD2
rucio-admin rse add-protocol --hostname xrd3 --scheme root --prefix //rucio --port 1094 --impl rucio.rse.protocols.gfal.Default --domain-json '{"wan": {"read": 1, "write": 1, "delete": 1, "third_party_copy_read": 1, "third_party_copy_write": 1}, "lan": {"read": 1, "write": 1, "delete": 1}}' XRD3
```

* Enable FTS

```sh
rucio-admin rse set-attribute --rse XRD1 --key fts --value https://fts:8446
rucio-admin rse set-attribute --rse XRD2 --key fts --value https://fts:8446
rucio-admin rse set-attribute --rse XRD3 --key fts --value https://fts:8446
```

Note that `8446` is the port exposed by the `fts-server` pod. You can easily view ports opened by a pod by `kubectl describe pod PODNAME`.

* Fake a full mesh network

```sh
rucio-admin rse add-distance --distance 1 --ranking 1 XRD1 XRD2
rucio-admin rse add-distance --distance 1 --ranking 1 XRD1 XRD3
rucio-admin rse add-distance --distance 1 --ranking 1 XRD2 XRD1
rucio-admin rse add-distance --distance 1 --ranking 1 XRD2 XRD3
rucio-admin rse add-distance --distance 1 --ranking 1 XRD3 XRD1
rucio-admin rse add-distance --distance 1 --ranking 1 XRD3 XRD2
```

* Indefinite storage quota for root

```sh
rucio-admin account set-limits root XRD1 -1
rucio-admin account set-limits root XRD2 -1
rucio-admin account set-limits root XRD3 -1
```

* Create a default scope for testing

```sh
rucio-admin scope add --account root --scope test
```

* Create initial transfer testing data

```sh
dd if=/dev/urandom of=file1 bs=10M count=1
dd if=/dev/urandom of=file2 bs=10M count=1
dd if=/dev/urandom of=file3 bs=10M count=1
dd if=/dev/urandom of=file4 bs=10M count=1
```

* Upload the files

```sh
rucio upload --rse XRD1 --scope test file1
rucio upload --rse XRD1 --scope test file2
rucio upload --rse XRD2 --scope test file3
rucio upload --rse XRD2 --scope test file4
```

* Create a few datasets and containers

```sh
rucio add-dataset test:dataset1
rucio attach test:dataset1 test:file1 test:file2

rucio add-dataset test:dataset2
rucio attach test:dataset2 test:file3 test:file4

rucio add-container test:container
rucio attach test:container test:dataset1 test:dataset2
```

* Create a rule and remember returned rule ID

```sh
rucio add-rule test:container 1 XRD3
```

* Query the status of the rule until it is completed. Note that the daemons are running with long sleep cycles (e.g. 30 seconds, 60 seconds) by default, so this will take a bit. You can always watch the output of the daemon containers to see what they are doing.

```sh
rucio rule-info <rule_id>
```

`rule_id` can be obtained via:

```sh
rucio list-rules test:container
```

* Add some more complications

```sh
rucio add-dataset test:dataset3
rucio attach test:dataset3 test:file4
```

## Some helpful commands

* Activate `kubectl` completion:

Bash:

```bash
source <(kubectl completion bash)
```

Zsh:

```zsh
source <(kubectl completion zsh)
```

* View all containers:

```sh
kubectl get pods 
kubectl get pods --all-namespaces
```

* View logfiles of a pod:

```sh
kubectl logs <NAME>
```

* Tail logfiles of a pod:

```sh
kubectl logs -f <NAME>
```

* Update helm repositories:

```sh
helm repo update
```

* Shut down minikube:

```sh
minikube stop
```

* Command references:
1. `kubectl` : [https://kubernetes.io/docs/reference/kubectl/cheatsheet/](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
2. `helm` : [https://helm.sh/docs/helm/](https://helm.sh/docs/helm/)
3. `minikube` : [https://cheatsheet.dennyzhang.com/cheatsheet-minikube-a4](https://cheatsheet.dennyzhang.com/cheatsheet-minikube-a4)