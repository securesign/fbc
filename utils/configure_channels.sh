#!/bin/bash
set -euo pipefail

# export BUNDLE_NAME="bundle_name"
# export CHANNELS="channel1,channel2"
# export GRAPH="graph.yaml"

OPERATOR_NAME=$(yq e '.entries[] | select(.schema=="olm.package") | .name' $GRAPH)
IFS=',' read -ra channel_list <<< "$CHANNELS"
for channel in "${channel_list[@]}"; do
  echo "Processing channel: $channel"
  export channel
  CHANNEL_EXISTS=$(yq e '[.entries[] | select(.schema=="olm.channel" and .name==env(channel))] | (length > 0)' $GRAPH)
  
  if [[ "$CHANNEL_EXISTS" == "true" ]]; then
    echo "Channel $channel exists. Updating..."
    
    CURRENT_ENTRIES=$(yq e ".entries[] | select(.schema==\"olm.channel\" and .name==\"$channel\").entries[].name" $GRAPH || true)
    FILTERED_ENTRIES=$(echo "$CURRENT_ENTRIES" | grep -v "^${BUNDLE_NAME}$" || true)
    
    if [[ -n "$FILTERED_ENTRIES" ]]; then
      export OLDEST=$(echo "$FILTERED_ENTRIES" | sort -V | head -n 1)
      export SKIPS=$(echo "$FILTERED_ENTRIES" | awk '{print "\"" $0 "\""}' | paste -sd, - | sed 's/^/[/' | sed 's/$/]/')
      
      yq -i -P eval --indent=1 "
        (.entries[] | select(.schema == \"olm.channel\" and .name == \"$channel\").entries) |=
          (map(select(.name != env(BUNDLE_NAME))) + [{
            \"name\": env(BUNDLE_NAME),
            \"replaces\": env(OLDEST),
            \"skips\": (strenv(SKIPS) | fromjson)
          }])
      " $GRAPH
    else
      yq -i -P eval --indent=1 "
        (.entries[] | select(.schema == \"olm.channel\" and .name == \"$channel\").entries) = [{
          \"name\": env(BUNDLE_NAME)
        }]
      " $GRAPH
    fi
  else
    echo "Channel $channel does not exist. Creating..."
    yq -i -P eval --indent=1 "
      .entries += [{
        \"schema\": \"olm.channel\",
        \"package\": \"$OPERATOR_NAME\",
        \"name\": \"$channel\",
        \"entries\": [{
          \"name\": env(BUNDLE_NAME)
        }]
      }]
    " $GRAPH
  fi
done
