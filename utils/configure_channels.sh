#!/bin/bash
set -euo pipefail

#export BUNDLE_NAME="rhtas-operator.v1.2.1"
#export CHANNELS="stable,stable-v1.2"
#export GRAPH="v4.19/rhtas-operator/graph.yaml"

# Returns true if version $1 <= version $2
version_lte() {
  [[ "$(printf '%s\n%s' "$1" "$2" | sort -V | head -1)" == "$1" ]]
}

export PACKAGE_NAME=$(yq e '.entries[] | select(.schema=="olm.package") | .name' $GRAPH)
IFS=',' read -ra channel_list <<< "$CHANNELS"
for channel in "${channel_list[@]}"; do
  echo "Processing channel: $channel"
  export channel
  CHANNEL_EXISTS=$(yq e '[.entries[] | select(.schema=="olm.channel" and .name==env(channel))] | (length > 0)' $GRAPH)
  
  if [[ "$CHANNEL_EXISTS" == "true" ]]; then
    echo "Channel $channel exists. Updating..."
    
    CURRENT_ENTRIES=$(yq e ".entries[] | select(.schema==\"olm.channel\" and .name==\"$channel\").entries[].name" $GRAPH || true)
    ENTRIES_WO_BUNDLE=$(echo "$CURRENT_ENTRIES" | grep -v "^${BUNDLE_NAME}$" || true)
    
    if [[ -n "$ENTRIES_WO_BUNDLE" ]]; then
      # Extract the minor version from the bundle name (e.g., "1.2" from "rhtas-operator.v1.2.1")
      BUNDLE_MINOR=$(echo "$BUNDLE_NAME" | grep -oE 'v[0-9]+\.[0-9]+' | sed 's/^v//')

      # Filter entries to only include versions in the same or earlier minor series
      ELIGIBLE_ENTRIES=$(echo "$ENTRIES_WO_BUNDLE" | tr ' ' '\n' | while read -r entry; do
        ENTRY_MINOR=$(echo "$entry" | grep -oE 'v[0-9]+\.[0-9]+' | sed 's/^v//')
        if [[ -n "$ENTRY_MINOR" ]] && version_lte "$ENTRY_MINOR" "$BUNDLE_MINOR"; then
          echo "$entry"
        fi
      done)

      export MAJOR_VERSIONS=$(echo "$ELIGIBLE_ENTRIES" | grep -E '\.0$')
      export REPLACES=$(echo "$MAJOR_VERSIONS" | sort -V | tail -n 1)

      SKIPS_ENTRIES=$(echo "$ELIGIBLE_ENTRIES" | grep -v -E '\.v1\.(0|1)\.[0-9]+')
      export SKIPS=$(echo "$SKIPS_ENTRIES" \
        | awk 'NF {print "\"" $0 "\""}' \
        | paste -sd, - \
        | sed 's/^/[/' | sed 's/$/]/'
      )

      yq -i -P eval "
        (.entries[] | select(.schema == \"olm.channel\" and .name == \"$channel\").entries) |=
          (map(select(.name != env(BUNDLE_NAME))) + [{
            \"name\": env(BUNDLE_NAME),
            \"replaces\": env(REPLACES),
            \"skips\": (strenv(SKIPS) | fromjson)
          }])
      " $GRAPH
    else
      yq -i -P eval "
        (.entries[] | select(.schema == \"olm.channel\" and .name == \"$channel\").entries) = [{
          \"name\": env(BUNDLE_NAME)
        }]
      " $GRAPH
    fi
  else
    echo "Channel $channel does not exist. Creating..."
    yq -i -P eval '
      (.entries) |= (.[0:1] + [{
        "entries": [{
          "name": env(BUNDLE_NAME)
        }],
        "name": env(channel),
        "package": env(PACKAGE_NAME),
        "schema": "olm.channel"
      }] + .[1:])
  ' $GRAPH
  fi
done
