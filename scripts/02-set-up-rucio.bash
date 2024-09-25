#!/usr/bin/env bash
set -e

echo "┌─────────────────────────────────────────────────────────────────┐"
echo "⟾ kubectl: Rucio - Start client container pod for interactive use │"
echo "└────────────────────────────────────────────git a─────────────────────┘"
kubectl apply -f ../client.yaml
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
kubectl exec client -it -- rucio-admin rse add XRD1
kubectl exec client -it -- rucio-admin rse add XRD2
kubectl exec client -it -- rucio-admin rse add XRD3

echo "┌──────────────────────────────────────────────────────┐"
echo "⟾ Add the protocol definitions for the storage servers │"
echo "└──────────────────────────────────────────────────────┘"
kubectl exec client -it -- rucio-admin rse add-protocol --hostname xrd1 --scheme root --prefix //rucio --port 1094 --impl rucio.rse.protocols.gfal.Default --domain-json '{"wan": {"read": 1, "write": 1, "delete": 1, "third_party_copy_read": 1, "third_party_copy_write": 1}, "lan": {"read": 1, "write": 1, "delete": 1}}' XRD1
kubectl exec client -it -- rucio-admin rse add-protocol --hostname xrd2 --scheme root --prefix //rucio --port 1094 --impl rucio.rse.protocols.gfal.Default --domain-json '{"wan": {"read": 1, "write": 1, "delete": 1, "third_party_copy_read": 1, "third_party_copy_write": 1}, "lan": {"read": 1, "write": 1, "delete": 1}}' XRD2
kubectl exec client -it -- rucio-admin rse add-protocol --hostname xrd3 --scheme root --prefix //rucio --port 1094 --impl rucio.rse.protocols.gfal.Default --domain-json '{"wan": {"read": 1, "write": 1, "delete": 1, "third_party_copy_read": 1, "third_party_copy_write": 1}, "lan": {"read": 1, "write": 1, "delete": 1}}' XRD3

echo "┌────────────┐"
echo "⟾ Enable FTS │"
echo "└────────────┘"
kubectl exec client -it -- rucio-admin rse set-attribute --rse XRD1 --key fts --value https://fts:8446
kubectl exec client -it -- rucio-admin rse set-attribute --rse XRD2 --key fts --value https://fts:8446
kubectl exec client -it -- rucio-admin rse set-attribute --rse XRD3 --key fts --value https://fts:8446

echo "┌──────────────────────────┐"
echo "⟾ Fake a full mesh network │"
echo "└──────────────────────────┘"
kubectl exec client -it -- rucio-admin rse add-distance --distance 1 --ranking 1 XRD1 XRD2
kubectl exec client -it -- rucio-admin rse add-distance --distance 1 --ranking 1 XRD1 XRD3
kubectl exec client -it -- rucio-admin rse add-distance --distance 1 --ranking 1 XRD2 XRD1
kubectl exec client -it -- rucio-admin rse add-distance --distance 1 --ranking 1 XRD2 XRD3
kubectl exec client -it -- rucio-admin rse add-distance --distance 1 --ranking 1 XRD3 XRD1
kubectl exec client -it -- rucio-admin rse add-distance --distance 1 --ranking 1 XRD3 XRD2

echo "┌───────────────────────────────────┐"
echo "⟾ Indefinite storage quota for root │"
echo "└───────────────────────────────────┘"
kubectl exec client -it -- rucio-admin account set-limits root XRD1 -1
kubectl exec client -it -- rucio-admin account set-limits root XRD2 -1
kubectl exec client -it -- rucio-admin account set-limits root XRD3 -1

echo "┌────────────────────────────────────┐"
echo "⟾ Create a default scope for testing │"
echo "└────────────────────────────────────┘"
kubectl exec client -it -- rucio-admin scope add --account root --scope test

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
kubectl exec client -it -- rucio upload --rse XRD1 --scope test file1
kubectl exec client -it -- rucio upload --rse XRD1 --scope test file2
kubectl exec client -it -- rucio upload --rse XRD2 --scope test file3
kubectl exec client -it -- rucio upload --rse XRD2 --scope test file4

echo "┌──────────────────────────────────────┐"
echo "⟾ Create a few datasets and containers │"
echo "└──────────────────────────────────────┘"
kubectl exec client -it -- rucio add-dataset test:dataset1
kubectl exec client -it -- rucio attach test:dataset1 test:file1 test:file2
kubectl exec client -it -- rucio add-dataset test:dataset2
kubectl exec client -it -- rucio attach test:dataset2 test:file3 test:file4
kubectl exec client -it -- rucio add-container test:container
kubectl exec client -it -- rucio attach test:container test:dataset1 test:dataset2

echo "┌─────────────────────────────────────────────┐"
echo "⟾ Create a rule and remember returned rule ID │"
echo "└─────────────────────────────────────────────┘"
kubectl exec client -it -- rucio add-rule test:container 1 XRD3

echo "┌────────────────────────────────────────────────────┐"
echo "⟾ Query the status of the rule until it is completed │"
echo "└────────────────────────────────────────────────────┘"
echo "⤑ It will wait for 90 seconds."
sleep 90
RULE_ID=$(kubectl exec client -it -- rucio list-rules test:container | tail -n 1 | awk '{print $1}')
echo "RULE_ID: ${RULE_ID}"
kubectl exec client -it -- rucio rule-info "${RULE_ID}"

echo "┌─────────────────────────────┐"
echo "⟾ Add some more complications │"
echo "└─────────────────────────────┘"
kubectl exec client -it -- rucio add-dataset test:dataset3
kubectl exec client -it -- rucio attach test:dataset3 test:file4
