#!/usr/bin/env bash
set -euo pipefail

# export BUNDLE_IMAGE="bundle_image"
# export BUNDLE_NAME="bundle_name"
# export GRAPH="graph.yaml"

BUNDLE="$(yq e '(.entries[] | select(.schema=="olm.bundle" and .name=="'"$BUNDLE_NAME"'"))' $GRAPH)"
if [[ -n "$BUNDLE" ]]; then
  echo "Bundle '$BUNDLE_NAME' found. Updating image..."
  yq e '(.entries[] | select(.schema=="olm.bundle" and .name=="'"$BUNDLE_NAME"'")).image = "'"$BUNDLE_IMAGE"'"' -i $GRAPH
else
  echo "Bundle '$BUNDLE_NAME' not found. Adding new entry..."
  yq e '.entries += [{"schema": "olm.bundle", "name": "'"$BUNDLE_NAME"'", "image": "'"$BUNDLE_IMAGE"'"}]' -i $GRAPH
fi
