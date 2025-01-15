#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

echo "┌─────────────────────────────────────────────────────────────────┐"
echo "⟾ kubectl: Rucio - Start client container pod for interactive use │"
echo "└─────────────────────────────────────────────────────────────────┘"
kubectl apply -f ../manifests/client.yaml
kubectl wait --timeout=120s --for=condition=Ready pod/client

echo "┌─────────────────────────────────┐"
echo "⟾ kubectl: Check client container │"
echo "└─────────────────────────────────┘"
kubectl exec client -it -- /etc/profile.d/rucio_init.sh
kubectl exec client -it -- rucio whoami

echo "┌────────────────┐"
echo "⟾ Run Rucio init │"
echo "└────────────────┘"
kubectl exec client -it -- /etc/profile.d/rucio_init.sh

echo "┌─────────────────┐"
echo "⟾ Create the RSEs │"
echo "└─────────────────┘"
kubectl exec client -it -- rucio rse add --rse XRD1
kubectl exec client -it -- rucio rse add --rse XRD2
kubectl exec client -it -- rucio rse add --rse XRD3

echo "┌──────────────────────────────────────────────────────┐"
echo "⟾ Add the protocol definitions for the storage servers │"
echo "└──────────────────────────────────────────────────────┘"
kubectl exec client -it -- rucio rse protocol add --host xrd1 --rse XRD1 --scheme root --prefix //rucio --port 1094 --impl rucio.rse.protocols.gfal.Default --domain-json '{"wan": {"read": 1, "write": 1, "delete": 1, "third_party_copy_read": 1, "third_party_copy_write": 1}, "lan": {"read": 1, "write": 1, "delete": 1}}'
kubectl exec client -it -- rucio rse protocol add --host xrd2 --rse XRD2 --scheme root --prefix //rucio --port 1094 --impl rucio.rse.protocols.gfal.Default --domain-json '{"wan": {"read": 1, "write": 1, "delete": 1, "third_party_copy_read": 1, "third_party_copy_write": 1}, "lan": {"read": 1, "write": 1, "delete": 1}}'
kubectl exec client -it -- rucio rse protocol add --host xrd3 --rse XRD3 --scheme root --prefix //rucio --port 1094 --impl rucio.rse.protocols.gfal.Default --domain-json '{"wan": {"read": 1, "write": 1, "delete": 1, "third_party_copy_read": 1, "third_party_copy_write": 1}, "lan": {"read": 1, "write": 1, "delete": 1}}'

echo "┌────────────┐"
echo "⟾ Enable FTS │"
echo "└────────────┘"
kubectl exec client -it -- rucio rse attribute add --rse XRD1 --key fts --value https://fts:8446
kubectl exec client -it -- rucio rse attribute add --rse XRD2 --key fts --value https://fts:8446
kubectl exec client -it -- rucio rse attribute add --rse XRD3 --key fts --value https://fts:8446

echo "┌──────────────────────────┐"
echo "⟾ Fake a full mesh network │"
echo "└──────────────────────────┘"
kubectl exec client -it -- rucio rse distance add --source XRD1 --destination XRD2 --distance 1
kubectl exec client -it -- rucio rse distance add --source XRD1 --destination XRD3 --distance 1
kubectl exec client -it -- rucio rse distance add --source XRD2 --destination XRD1 --distance 1
kubectl exec client -it -- rucio rse distance add --source XRD2 --destination XRD3 --distance 1
kubectl exec client -it -- rucio rse distance add --source XRD3 --destination XRD1 --distance 1
kubectl exec client -it -- rucio rse distance add --source XRD3 --destination XRD2 --distance 1

echo "┌───────────────────────────────────┐"
echo "⟾ Indefinite storage quota for root │"
echo "└───────────────────────────────────┘"
kubectl exec client -it -- rucio account limit add --account root --rses XRD1 --bytes infinity
kubectl exec client -it -- rucio account limit add --account root --rses XRD2 --bytes infinity
kubectl exec client -it -- rucio account limit add --account root --rses XRD3 --bytes infinity

echo "┌────────────────────────────────────┐"
echo "⟾ Create a default scope for testing │"
echo "└────────────────────────────────────┘"
kubectl exec client -it -- rucio scope add --account root --scope test

echo "┌──────────────────────────────────────┐"
echo "⟾ Create initial transfer testing data │"
echo "└──────────────────────────────────────┘"
kubectl exec client -it -- dd if=/dev/urandom of=file1 bs=10M count=1
kubectl exec client -it -- dd if=/dev/urandom of=file2 bs=10M count=1
kubectl exec client -it -- dd if=/dev/urandom of=file3 bs=10M count=1
kubectl exec client -it -- dd if=/dev/urandom of=file4 bs=10M count=1

echo "┌──────────────────┐"
echo "⟾ Upload the files │"
echo "└──────────────────┘"
kubectl exec client -it -- rucio upload --rse XRD1 --scope test --files file1 file2
kubectl exec client -it -- rucio upload --rse XRD2 --scope test --files file3 file4

echo "┌──────────────────────────────────────┐"
echo "⟾ Create a few datasets and containers │"
echo "└──────────────────────────────────────┘"
kubectl exec client -it -- rucio did add --type dataset --did test:dataset1
kubectl exec client -it -- rucio did content add --to test:dataset1 --did test:file1 test:file2
kubectl exec client -it -- rucio did add --type dataset --did test:dataset2
kubectl exec client -it -- rucio did content add --to test:dataset2 --did test:file3 test:file4
kubectl exec client -it -- rucio did add --type container --did test:container
kubectl exec client -it -- rucio did content add --to test:container --did test:dataset1 test:dataset2
kubectl exec client -it -- rucio did add --type dataset --did test:dataset3
kubectl exec client -it -- rucio did content add --to test:dataset3 --did test:file4

echo "┌─────────────────────────────────────────────┐"
echo "⟾ Create a rule and remember returned rule ID │"
echo "└─────────────────────────────────────────────┘"
kubectl exec client -it -- rucio rule add --did test:container --rses XRD3 --copies 1

echo "┌────────────────────────────────────────────────────┐"
echo "⟾ Query the status of the rule until it is completed │"
echo "└────────────────────────────────────────────────────┘"
echo "⤑ It will wait for 90 seconds."
sleep 90
RULE_ID=$(kubectl exec client -it -- rucio rule list --did test:container | tail -n 1 | awk '{print $1}')
echo "RULE_ID: ${RULE_ID}"
kubectl exec client -it -- rucio rule show --rule-id "${RULE_ID}"

echo""
echo""
echo""
echo "*** Rucio usage showcase complete. ***"
