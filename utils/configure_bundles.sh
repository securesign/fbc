#!/usr/bin/env bash
set -euo pipefail

#export BUNDLE_IMAGE="registry.redhat.io/rhtas/rhtas-operator-bundle@sha256:7c4e739622f68cd924afcb41cc788cdadc34c725283a097e564d620f39637bac"
#export BUNDLE_NAME="rhtas-operator.v1.2.1"
#export GRAPH="v4.19/rhtas-operator/graph.yaml"

BUNDLE="$(yq e '(.entries[] | select(.schema=="olm.bundle" and .name=="'"$BUNDLE_NAME"'"))' $GRAPH)"
if [[ -n "$BUNDLE" ]]; then
  echo "Bundle '$BUNDLE_NAME' found. Updating image..."
  yq e '(.entries[] | select(.schema=="olm.bundle" and .name=="'"$BUNDLE_NAME"'")).image = "'"$BUNDLE_IMAGE"'"' -i $GRAPH
else
  echo "Bundle '$BUNDLE_NAME' not found. Adding new entry..."
  yq e '.entries += [{"image": "'"$BUNDLE_IMAGE"'", "name": "'"$BUNDLE_NAME"'", "schema": "olm.bundle"}]' -i $GRAPH
fi
