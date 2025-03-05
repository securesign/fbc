#!/usr/bin/env bash
set -euo pipefail

# export BUNDLE_IMAGE="quay.io/securesign/rhtas-operator-bundle@sha256:a1c9dc1bbe50e2bff631ab0a9a9c06dfdbf45f42202d5e74e43c9ea571a8fc56"
# export BUNDLE_NAME="rhtas-operator.v1.2.0"
# export GRAPH="v4.13/graph.yaml"

BUNDLE="$(yq e '(.entries[] | select(.schema=="olm.bundle" and .name=="'"$BUNDLE_NAME"'"))' $GRAPH)"
if [[ -n "$BUNDLE" ]]; then
  echo "Bundle '$BUNDLE_NAME' found. Updating image..."
  yq e '(.entries[] | select(.schema=="olm.bundle" and .name=="'"$BUNDLE_NAME"'")).image = "'"$BUNDLE_IMAGE"'"' -i $GRAPH
else
  echo "Bundle '$BUNDLE_NAME' not found. Adding new entry..."
  yq e '.entries += [{"image": "'"$BUNDLE_IMAGE"'", "name": "'"$BUNDLE_NAME"'", "schema": "olm.bundle"}]' -i $GRAPH
fi
