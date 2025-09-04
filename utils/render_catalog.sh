#!/usr/bin/env bash
set -euo pipefail

#OCP_VERSION="v4.19"
#FBC_DIR="rhtas-operator"
#CATALOG_FILE="v4.19/${FBC_DIR}/catalog/rhtas-operator/catalog.json"

minor=${OCP_VERSION#v4.}
minor=${minor%%.*}

# Anything related to related_images can be removed once we deprecate 1.1.x
related_images=$(jq -s '
reduce .[] as $item ({}; 
    if ($item.schema == "olm.bundle" and 
        $item.name != "rhtas-operator.v1.2.0" and 
        (
        ($item.name | contains("v1.0.0")) or 
        ($item.name | contains("v1.0.1")) or 
        ($item.name | contains("v1.0.2")) or 
        ($item.name | contains("v1.1.0")) or 
        ($item.name | contains("v1.1.1")) or
        ($item.name | contains("v1.1.2"))
        )
    ) 
    then .[$item.name] = $item.relatedImages 
    else . 
    end
)' "$CATALOG_FILE")

migrate_flag=""
if (( minor >= 17 )); then
    migrate_flag="--migrate-level=bundle-object-to-csv-metadata"
fi

opm alpha render-template $migrate_flag basic "${OCP_VERSION}/${FBC_DIR}/graph.yaml" > "$CATALOG_FILE"

jq -s --indent 4 --argjson related_images "$related_images" '
    map(
        if .schema == "olm.bundle" then
            . + { relatedImages: ($related_images[.name] // .relatedImages) }
        else
            .
        end
    ) | .[]
' "$CATALOG_FILE" > "${CATALOG_FILE}.tmp" && mv "${CATALOG_FILE}.tmp" "$CATALOG_FILE"
