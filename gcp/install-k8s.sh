#!/usr/bin/env bash
set -euo pipefail

metadata_value() {
	curl --fail --silent --show-error \
		--header 'Metadata-Flavor: Google' \
		"http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1"
}

RANCHER_SERVER="${RANCHER_SERVER:-$(metadata_value rancher-server)}"
RANCHER_TOKEN="${RANCHER_TOKEN:-$(metadata_value rancher-token)}"
RANCHER_CA_CHECKSUM="${RANCHER_CA_CHECKSUM:-$(metadata_value rancher-ca-checksum)}"

: "${RANCHER_SERVER:?RANCHER_SERVER or metadata rancher-server is required}"
: "${RANCHER_TOKEN:?RANCHER_TOKEN or metadata rancher-token is required}"
: "${RANCHER_CA_CHECKSUM:?RANCHER_CA_CHECKSUM or metadata rancher-ca-checksum is required}"

curl --insecure --fail --location "https://${RANCHER_SERVER}/system-agent-install.sh" | sudo sh -s - \
	--server "https://${RANCHER_SERVER}" \
	--label 'cattle.io/os=linux' \
	--token "${RANCHER_TOKEN}" \
	--ca-checksum "${RANCHER_CA_CHECKSUM}" \
	--etcd \
	--controlplane \
	--worker
