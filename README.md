# Rucio Kubernetes Tutorial

## Preliminaries

* Clone this repo to your local machine

```sh
git clone https://github.com/rucio/k8s-tutorial/
```

* Install kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl/

* Install helm: https://helm.sh/docs/intro/install/

* Install minikube: https://kubernetes.io/docs/tasks/tools/install-minikube/

* Start minikube with extra RAM:

```sh
minikube start --memory='4000mb'
```

* Add Helm chart repositories:

```sh
helm repo add stable https://charts.helm.sh/stable
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add rucio https://rucio.github.io/helm-charts
```

## Installation of Rucio + FTS + Storage

_NOTE: Before executing the following commands, please change directory to the cloned `k8s-tutorial` repo location_

_NOTE: Replace the pod IDs with the ones from your instance, they change every time_

_NOTE: You can execute this shell script for easier installation and understanding:
[./automation/01-install-rucio.bash](./automation/01-install-rucio.bash)._

* Install secrets:

```sh
kubectl apply -k ./secrets
```

* Check if you have previously done this before and want to reset from scratch. In that case, check if there's an old PostgreSQL database lying around, and find and remove it with `kubectl describe pvc` && `kubectl delete pvc data-postgres-postgresql-0`

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

* Install a fresh new Rucio database (PostgreSQL).

```sh
helm install postgres bitnami/postgresql -f values-postgres.yaml
```

* Wait for PostgreSQL to finish starting. Output should be `STATUS:Running`.

```sh
kubectl get pods
```

On bash/fish/zsh shells, you can also get the status of the job updated in real-time via:

```sh
(TOWATCH=postgres; watch "kubectl get pods --all-namespaces --no-headers |  awk '{if (\$2 ~ \"$TOWATCH\") print \$0}'")
```
Here the fourth column represents the status.

Tip: To watch the status any other install, just change value of `TOWATCH` from `postgres` to the name of your current install.


* Run init container once to setup the Rucio database once the PostgreSQL container is running:

```sh
kubectl apply -f init-pod.yaml
```

* Watch the output of the init container to check if everything is fine. Pod should finish with `STATUS:Completed`

```sh
kubectl logs -f init
```

or on bash/fish/zsh shells via:

```sh
(TOWATCH=init; watch "kubectl get pods --all-namespaces --no-headers |  awk '{if (\$2 ~ \"$TOWATCH\") print \$0}'")
```

* Install the Rucio server and wait for it to come online:

```sh
helm install server rucio/rucio-server -f values-server.yaml
kubectl logs -f deployment/server-rucio-server -c rucio-server
```

* Prepare a client container for interactive use:

```sh
kubectl apply -f client.yaml
```

* Once the client container is in `STATUS:Running`, you can jump into it and check if the clients are working:

```sh
kubectl exec -it client -- /bin/bash
rucio whoami
```

* Install the XRootD storage systems. This will start three instances of them.

```sh
kubectl apply -f xrd.yaml
```

* Install the FTS database (MySQL).

```sh
kubectl apply -f ftsdb.yaml
```

* Wait for the FTS database to come online.

For Linux/MacOS:

```sh
kubectl logs -f $(kubectl get pods -o NAME | grep fts-mysql | cut -d '/' -f 2)
```

For Windows:

```sh
kubectl logs -f $(kubectl get pods -o name | findstr /c:"fts-mysql" | sed "s/^pod\///")
```

* Install FTS, once the FTS database container is up and running:

```sh
kubectl apply -f fts.yaml
```

* Wait for FTS to come online.

For Linux/MacOS:

```sh
kubectl logs -f $(kubectl get pods -o NAME | grep fts-server | cut -d '/' -f 2)
```

For Windows:

```sh
kubectl logs -f $(kubectl get pods -o name | findstr /c:"fts-server" | sed "s/^pod\///")
```

* Install the Rucio daemons:

```sh
helm install daemons rucio/rucio-daemons -f values-daemons.yaml
```

* Run FTS storage authentication delegation once:

```sh
kubectl create job renew-manual-1 --from=cronjob/daemons-renew-fts-proxy
```

## Rucio usage

_NOTE: You can execute this shell script for easier set up and understanding:
[./automation/02-set-up-rucio.bash](./automation/02-set-up-rucio.bash)._

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