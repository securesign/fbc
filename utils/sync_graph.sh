#!/usr/bin/env bash
set -euo pipefail

#PACKAGE_NAME="rhtas-operator"
#OCP_VERSION="v4.20"
#RELEASED_CATALOG="/tmp/raw-catalog.yaml"

path=$OCP_VERSION/$PACKAGE_NAME

yq eval-all 'select(.package == "'"$PACKAGE_NAME"'" or .name == "'"$PACKAGE_NAME"'")' "$RELEASED_CATALOG" | \
yq eval-all '[.] | .[0] = {"entries": ., "schema": "olm.template.basic"} | .[0] |
  .entries[] |= (select(.schema == "olm.bundle") | {"schema": .schema, "image": .image, "name": .name}) |
  .entries[] |= (select(.schema == "olm.package") | {"schema": .schema, "name": .name, "defaultChannel": .defaultChannel, "icon": .icon}) |
  .entries[] |= (select(.schema == "olm.channel") | {"schema": .schema, "name": .name, "package": .package, "entries": .entries})'  > "${path}"/graph.yaml
