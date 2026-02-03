#!/bin/bash
set -euo pipefail

#export BUNDLE_NAME="rhtas-operator.v1.2.1"
#export CHANNELS="stable,stable-v1.2"
#export GRAPH="v4.19/rhtas-operator/graph.yaml"

version_lt() {
  [[ "$1" != "$2" ]] && [[ "$(printf '%s\n%s' "$1" "$2" | sort -V | head -1)" == "$1" ]]
}

get_version() {
  echo "$1" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo ""
}

export PACKAGE_NAME=$(yq e '.entries[] | select(.schema=="olm.package") | .name' $GRAPH)
BUNDLE_VERSION=$(get_version "$BUNDLE_NAME")
BUNDLE_MINOR=$(echo "$BUNDLE_NAME" | grep -oE 'v[0-9]+\.[0-9]+')

IFS=',' read -ra channel_list <<< "$CHANNELS"
for channel in "${channel_list[@]}"; do
  echo "Processing channel: $channel"
  export channel
  CHANNEL_EXISTS=$(yq e '[.entries[] | select(.schema=="olm.channel" and .name==env(channel))] | (length > 0)' $GRAPH)

  if [[ "$CHANNEL_EXISTS" == "true" ]]; then
    echo "Channel $channel exists. Updating..."
    
    REPLACES="" REPLACES_FALLBACK="" SKIPS="" GREATER=""
    for entry in $(yq e ".entries[] | select(.schema==\"olm.channel\" and .name==\"$channel\").entries[].name" $GRAPH); do
      [[ "$entry" == "$BUNDLE_NAME" ]] && continue
      ENTRY_VERSION=$(get_version "$entry")
      [[ -z "$ENTRY_VERSION" ]] && continue
      if version_lt "$ENTRY_VERSION" "$BUNDLE_VERSION"; then
        ENTRY_MINOR=$(echo "$entry" | grep -oE 'v[0-9]+\.[0-9]+')
        if [[ "$ENTRY_MINOR" == "$BUNDLE_MINOR" ]]; then
          [[ -z "$REPLACES" || $(version_lt "$(get_version "$REPLACES")" "$ENTRY_VERSION" && echo 1) ]] && REPLACES="$entry"
        elif [[ "$entry" == *".0" ]]; then
          [[ -z "$REPLACES_FALLBACK" || $(version_lt "$(get_version "$REPLACES_FALLBACK")" "$ENTRY_VERSION" && echo 1) ]] && REPLACES_FALLBACK="$entry"
        fi
        SKIPS="${SKIPS:+$SKIPS,}$entry"
      elif version_lt "$BUNDLE_VERSION" "$ENTRY_VERSION"; then
        GREATER="${GREATER:+$GREATER }$entry"
      fi
    done
    [[ -z "$REPLACES" ]] && REPLACES="$REPLACES_FALLBACK"
    [[ -n "$REPLACES" ]] && SKIPS=$(echo "$SKIPS" | tr ',' '\n' | { grep -v "^${REPLACES}$" || true; } | paste -sd ',' -)

    # Add bundle with replaces/skips
    export REPLACES SKIPS
    if [[ -n "$REPLACES" && -n "$SKIPS" ]]; then
      yq -i -P eval "(.entries[] | select(.schema == \"olm.channel\" and .name == env(channel)).entries) |=
        (map(select(.name != env(BUNDLE_NAME))) + [{\"name\": env(BUNDLE_NAME), \"replaces\": env(REPLACES), \"skips\": (env(SKIPS) | split(\",\"))}])" $GRAPH
    elif [[ -n "$REPLACES" ]]; then
      yq -i -P eval "(.entries[] | select(.schema == \"olm.channel\" and .name == env(channel)).entries) |=
        (map(select(.name != env(BUNDLE_NAME))) + [{\"name\": env(BUNDLE_NAME), \"replaces\": env(REPLACES)}])" $GRAPH
    else
      yq -i -P eval "(.entries[] | select(.schema == \"olm.channel\" and .name == env(channel)).entries) |=
        (map(select(.name != env(BUNDLE_NAME))) + [{\"name\": env(BUNDLE_NAME)}])" $GRAPH
    fi

    # Add bundle to skips for greater versions
    for entry in $GREATER; do
      export entry
      yq -i -P eval "(.entries[] | select(.schema == \"olm.channel\" and .name == env(channel)).entries[] |
        select(.name == env(entry)).skips) |= ((. // []) + [env(BUNDLE_NAME)] | unique)" $GRAPH
    done
  else
    yq -i -P eval '
      (.entries) |= (.[0:1] + [{
        "entries": [{"name": env(BUNDLE_NAME)}],
        "name": env(channel),
        "package": env(PACKAGE_NAME),
        "schema": "olm.channel"
      }] + .[1:])
    ' $GRAPH
  fi
done
