#!/bin/bash
curl -fL https://${RANCHER_SERVER}/system-agent-install.sh | sudo sh -s - \
  --server https://${RANCHER_SERVER} \
  --label 'cattle.io/os=linux' \
  --token ${RANCHER_TOKEN} \
  --ca-checksum ${RANCHER_CA_CHECKSUM} \
  --etcd --controlplane --worker